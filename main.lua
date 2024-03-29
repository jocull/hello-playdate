-- Name this file `main.lua`. Your game can use multiple source files if you wish
-- (use the `import "myFilename"` command), but the simplest games can be written
-- with just `main.lua`.

-- You'll want to import these in just about every project you'll work on.
import "CoreLibs/object"
import "CoreLibs/graphics"
import "CoreLibs/sprites"
import "CoreLibs/timer"
import "CoreLibs/ui"

-- Declaring this "gfx" shorthand will make your life easier. Instead of having
-- to preface all graphics calls with "playdate.graphics", just use "gfx."
-- Performance will be slightly enhanced, too.
-- NOTE: Because it's local, you'll have to do it in every .lua source file.
local gfx <const> = playdate.graphics
local geo <const> = playdate.geometry
local ui <const> = playdate.ui

-- Helpful vars
local SCREEN <const> = {}
local SPRITE_TAG <const> = {
    wall = 1,
    player = 2,
    tootie = 3,
    gloober = 4,
}
(function()
    SCREEN.origin = geo.point.new(0, 0)
    SCREEN.rect = geo.rect.new(SCREEN.origin.x, SCREEN.origin.y, 400, 240)
    SCREEN.height = SCREEN.rect.height
    SCREEN.width = SCREEN.rect.width
    SCREEN.center = geo.point.new(
        SCREEN.rect.width / 2,
        SCREEN.rect.height / 2)
    SCREEN.offscreen = geo.point.new(
        SCREEN.width * -3,
        SCREEN.height * -3)
    SCREEN.sprites = {}
end)()

-- Here's our player sprite declaration. We'll scope it to this file because
-- several functions need to access it.
local playerSprite = nil
local arrowSprite = nil

-- Sound vars
local fartSoundPools = nil
local giggleSoundPools = nil

-- Crank vars
local crankState = {
    changed = true,
    docked = playdate.isCrankDocked(),
    dockedRecently = playdate.isCrankDocked(),
    angle = playdate.getCrankPosition(),
}

local SoundPool = {}
function SoundPool.new(path, size)
    if size == nil then
        size = 8
    end
    assert(size > 0, "Invalid sound pool size")
    local obj = setmetatable({}, { __index = SoundPool })
    obj.idx = 1
    obj.path = path
    obj.pool = {}
    for i = 1, size, 1 do
        table.insert(obj.pool, playdate.sound.sampleplayer.new(path))
    end
    return obj
end

function SoundPool:play()
    self.pool[self.idx]:play()
    self.idx = self.idx + 1
    if not self.pool[self.idx] then
        self.idx = 1
    end
end

local function getAngleDegrees(fromX, fromY, toX, toY)
    -- Calculate the difference between the x- and y-coordinates
    local deltaX = fromX - toX
    local deltaY = fromY - toY
    -- Calculate the arctangent of the ratio of the y- and x-coordinates
    local radians = math.atan(deltaY, deltaX)
    -- Convert radians to degrees by multiplying by 180 / Math.PI
    local degrees = (radians * 180) / math.pi
    degrees = degrees - 90 -- Adjust for drawing
    -- If the angle is negative, add 360 degrees to make it positive
    if degrees < 0 then
        degrees = (degrees + 360) % 360
    end
    -- Return the angle in degrees
    return degrees
end

-- A function to set up our game environment.
-- After this runs (it just runs once), nearly everything will be
-- controlled by the OS calling `playdate.update()` 30 times a second.
(function()
    -- Set up the player sprite.
    -- The :setCenter() call specifies that the sprite will be anchored at its center.
    -- The :moveTo() call moves our sprite to the center of the display.
    local playerImg = assert(
        gfx.image.new("Images/playerImage"),
        "Player image not found")
    playerSprite = gfx.sprite.new(playerImg)
    playerSprite:setCollideRect(0, 0, playerSprite:getSize())

    -- Beware, weird syntax for method implementation of child object
    -- Don't use playerSprite.collisionResponse = function(other) ...
    function playerSprite:collisionResponse(other)
        if other:getTag() == SPRITE_TAG.wall then
            return gfx.sprite.kCollisionTypeSlide
        elseif other:getTag() == SPRITE_TAG.gloober then
            return gfx.sprite.kCollisionTypeBounce
        end
        return gfx.sprite.kCollisionTypeOverlap
    end

    playerSprite:setZIndex(32767) -- always on top
    playerSprite:moveTo(SCREEN.center:unpack())
    playerSprite:setTag(SPRITE_TAG.player)
    playerSprite:add()

    local arrowImg = assert(
        gfx.image.new("Images/arrow"),
        "Arrow image not found")
    arrowSprite = gfx.sprite.new(arrowImg)
    arrowSprite:moveTo(SCREEN.offscreen:unpack())
    arrowSprite:add()

    local function genWallSprite(x, y, w, h)
        local sprite = gfx.sprite.new()
        sprite:setCollideRect(0, 0, w, h)
        sprite:moveTo(x, y)
        sprite:setTag(SPRITE_TAG.wall)
        sprite:add()
        -- print("Generated new sprite", x, y, w, h)
        return sprite
    end

    -- In order to use boundary collisions we have to generate boxes
    -- that cover the outer edges. I can't seem to get collisions to work
    -- for an "interior" area of a rectangle (e.g. the screen boundary).
    --
    -- We add the player buffer into this as well so that the character is
    -- allowed to go off screen, but not endlessly.
    local outerBuffer = playerSprite.width * 1.5
    local outerBuffer2 = outerBuffer * 2
    SCREEN.sprites.top = genWallSprite(
        SCREEN.origin.x - SCREEN.width,
        SCREEN.origin.y - outerBuffer2,
        SCREEN.width * 3,
        outerBuffer)

    SCREEN.sprites.right = genWallSprite(
        SCREEN.origin.x + SCREEN.width + outerBuffer,
        SCREEN.origin.y - SCREEN.height,
        outerBuffer2,
        SCREEN.height * 3)

    SCREEN.sprites.bottom = genWallSprite(
        SCREEN.origin.x - SCREEN.width,
        SCREEN.origin.y + SCREEN.height + outerBuffer,
        SCREEN.width * 3,
        outerBuffer2)

    SCREEN.sprites.left = genWallSprite(
        SCREEN.origin.x - outerBuffer2,
        SCREEN.origin.y - SCREEN.height,
        outerBuffer,
        SCREEN.height * 3)

    local tootieImg = gfx.image.new('Images/tootie')
    local glooberImg = gfx.image.new('Images/gloober')

    local function genThing1()
        local t = gfx.sprite.new(glooberImg)
        t:setImageFlip(gfx.kImageUnflipped)
        t:setScale(2)
        t:setCollideRect(0, 0, t:getSize())
        t:setTag(SPRITE_TAG.gloober)
        t:moveTo(SCREEN.center.x - (SCREEN.center.x / 2), SCREEN.center.y)
        t:add()
        local a = gfx.animator.new(
            1000,
            geo.point.new(t.x, t.y),
            geo.point.new(0, SCREEN.center.y - (SCREEN.center.y / 2)),
            playdate.easingFunctions.inOutCubic)
        a.repeatCount = -1 -- forever
        a.reverses = true
        t:setAnimator(a, true)
        return t
    end

    local function genThing2()
        local t = gfx.sprite.new(tootieImg)
        t:setImageFlip(gfx.kImageFlippedX)
        t:setCollideRect(0, 0, t:getSize())
        t:setTag(SPRITE_TAG.tootie)
        t:moveTo(SCREEN.center.x + (SCREEN.center.x / 2), SCREEN.center.y)
        t:add()

        local a = gfx.animator.new(
            1000,
            geo.point.new(t.x, t.y),
            geo.point.new(SCREEN.width, SCREEN.center.y + (SCREEN.center.y / 2)),
            playdate.easingFunctions.inOutCubic)
        a.repeatCount = -1 -- forever
        a.reverses = true
        t:setAnimator(a, true)
        return t
    end

    local thing1 = genThing1()
    local thing2 = genThing2()

    -- We want an environment displayed behind our sprite.
    -- There are generally two ways to do this:
    -- 1) Use setBackgroundDrawingCallback() to draw a background image. (This is what we're doing below.)
    -- 2) Use a tilemap, assign it to a sprite with sprite:setTilemap(tilemap),
    --       and call :setZIndex() with some low number so the background stays behind
    --       your other sprites.
    local backgroundImg = assert(
        gfx.image.new("Images/background"),
        "Background image not found")

    gfx.sprite.setBackgroundDrawingCallback(
        function(x, y, width, height)
            -- x,y,width,height is the updated area in sprite-local coordinates
            -- The clip rect is already set to this area, so we don't need to set it ourselves
            backgroundImg:draw(SCREEN.origin:unpack())
        end
    )

    -- Setup game sounds
    fartSoundPools = {
        SoundPool.new("Sounds/fart-1"),
        SoundPool.new("Sounds/fart-2"),
        SoundPool.new("Sounds/fart-3"),
        SoundPool.new("Sounds/fart-4"),
    }
    giggleSoundPools = {
        SoundPool.new("Sounds/giggle-1"),
        SoundPool.new("Sounds/giggle-2"),
        SoundPool.new("Sounds/giggle-3"),
    }
end)()

-- `playdate.update()` is the heart of every Playdate game.
-- This function is called right before every frame is drawn onscreen.
-- Use this function to poll input, run game logic, and move sprites.
local function playRandomSound(soundPoolTable)
    -- Get a random index from the table
    local index = math.random(#soundPoolTable)

    -- Play the sound at that index
    soundPoolTable[index]:play()
end

playdate.display.setRefreshRate(50)

local function onCrankChange(docked, angle)
    playerSprite:setRotation(angle)
    playerSprite:setCollideRect(0, 0, playerSprite:getSize())
    playerSprite:moveWithCollisions(playerSprite.x, playerSprite.y)

    crankState.changed = false
    if docked then
        --[[
        "As your game calls playdate.ui.crankIndicator:draw() on successive frames,
        the Playdate screen will display a "Use the Crank" message for ~0.7 seconds,
        then an animation of a rotating crank for ~1.4 seconds. (The direction of
        animation is specified by .clockwise.)"
        --]]
        crankState.dockedRecently = true
        playdate.timer.performAfterDelay((1400 + 700) * 3, function()
            crankState.dockedRecently = false
        end)
    end
end

function playdate.update()
    -- Poll the d-pad and move our player accordingly.
    -- (There are multiple ways to read the d-pad; this is the simplest.)
    -- Note that it is possible for more than one of these directions
    -- to be pressed at once, if the user is pressing diagonally.
    local moveSpeed = 5
    local goalX, goalY = playerSprite.x, playerSprite.y
    local buttonIsPressed = false
    if playdate.buttonIsPressed(playdate.kButtonUp) then
        goalY = goalY - moveSpeed
        buttonIsPressed = true
    end
    if playdate.buttonIsPressed(playdate.kButtonRight) then
        goalX = goalX + moveSpeed
        buttonIsPressed = true
    end
    if playdate.buttonIsPressed(playdate.kButtonDown) then
        goalY = goalY + moveSpeed
        buttonIsPressed = true
    end
    if playdate.buttonIsPressed(playdate.kButtonLeft) then
        goalX = goalX - moveSpeed
        buttonIsPressed = true
    end

    -- Remember to use :moveWithCollisions(), and not :moveTo() or :moveBy(), or collisions won't happen!
    -- To do a "moveBy" operation, sprite:moveBy(5, 5) == sprite:moveWithCollisions(sprite.x + 5, sprite.y + 5)
    if buttonIsPressed then
        local actualX, actualY, collisions, numberOfCollisions = playerSprite:moveWithCollisions(goalX, goalY)
        -- print(actualX, actualY, collisions, numberOfCollisions)
        -- printTable(playerSprite)

        -- Did the player move off screen?
        if not SCREEN.rect:intersects(playerSprite:getBoundsRect()) then
            local sx, sy = playerSprite.x, playerSprite.y
            local aw, ah = arrowSprite.width / 2, arrowSprite.height / 2
            local ax = math.max(aw, math.min(SCREEN.width - aw, sx))
            local ay = math.max(ah, math.min(SCREEN.height - ah, sy))
            arrowSprite:moveTo(ax, ay)

            local pointerRotation = getAngleDegrees(ax, ay, sx, sy)
            arrowSprite:setRotation(pointerRotation)
        else
            arrowSprite:moveTo(SCREEN.offscreen:unpack())
        end
    end

    -- Rotate the player sprite related to how the crank is positioned
    local crankDocked = playdate.isCrankDocked()
    if crankState.docked ~= crankDocked then
        crankState.changed = true
        crankState.docked = crankDocked
    end
    local crankAngle = playdate.getCrankPosition()
    if crankState.angle ~= crankAngle then
        crankState.changed = true
        crankState.angle = crankAngle
    end
    if crankState.changed then
        -- print('crank changed!', crankDocked, crankAngle)
        -- printTable(playerSprite)
        onCrankChange(crankDocked, crankAngle)
    end

    -- Play sounds when we use buttons
    if playdate.buttonJustPressed(playdate.kButtonA) then
        playRandomSound(fartSoundPools)
    end
    if playdate.buttonJustPressed(playdate.kButtonB) then
        playRandomSound(giggleSoundPools)
    end

    -- Call the functions below in playdate.update() to draw sprites and keep
    -- timers updated. (We aren't using timers in this example, but in most
    -- average-complexity games, you will.)
    gfx.sprite.update()

    -- "Note that if sprites are being used, this call should usually happen after playdate.graphics.sprite.update()"
    if crankState.dockedRecently then
        ui.crankIndicator:draw()
    end

    playdate.timer.updateTimers()
end
