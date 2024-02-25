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
local ui <const> = playdate.ui

-- Helpful vars
local SCREEN <const> = {}
(function ()
    SCREEN.origin = playdate.geometry.point.new(0, 0)
    SCREEN.rect = playdate.geometry.rect.new(SCREEN.origin.x, SCREEN.origin.y, 400, 240)
    SCREEN.height = SCREEN.rect.height
    SCREEN.width = SCREEN.rect.width
    SCREEN.center = playdate.geometry.point.new(
        SCREEN.rect.width / 2,
        SCREEN.rect.height / 2)
    SCREEN.sprites = {}
end)()

-- Here's our player sprite declaration. We'll scope it to this file because
-- several functions need to access it.
local playerSprite = nil

-- Sound vars
local fartSoundPools = nil
local giggleSoundPools = nil

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

-- A function to set up our game environment.
-- After this runs (it just runs once), nearly everything will be
-- controlled by the OS calling `playdate.update()` 30 times a second.
(function ()
    -- Set up the player sprite.
    -- The :setCenter() call specifies that the sprite will be anchored at its center.
    -- The :moveTo() call moves our sprite to the center of the display.
    local playerImg = assert(
        gfx.image.new("Images/playerImage"),
        "Player image not found")
    playerSprite = gfx.sprite.new(playerImg)
    playerSprite:setCollideRect(0, 0, playerSprite:getSize())
    playerSprite:moveTo(SCREEN.center:unpack())
    playerSprite:add()

    local function genSprite(x, y, w, h)
        local sprite = gfx.sprite.new()
        sprite:setCollideRect(0, 0, w, h)
        sprite:moveTo(x, y)
        sprite:add()
        print("Generated new sprite", x, y, w, h)
        return sprite
    end

    -- In order to use boundary collisions we have to generate boxes
    -- that cover the outer edges. I can't seem to get collisions to work
    -- for an "interior" area of a rectangle (e.g. the screen boundary).
    --
    -- We add the player buffer into this as well so that the character is
    -- allowed to go off screen, but not endlessly.
    local playerBoundary1 = playerSprite.width * 2
    local playerBoundary2 = playerBoundary1 * 4
    SCREEN.sprites.top = genSprite(
        SCREEN.origin.x - SCREEN.width,
        SCREEN.origin.y - playerBoundary2,
        SCREEN.width * 3,
        playerBoundary1)

    SCREEN.sprites.right = genSprite(
        SCREEN.origin.x + SCREEN.width + playerBoundary1,
        SCREEN.origin.y - SCREEN.height,
        playerBoundary1,
        SCREEN.height * 3)

    SCREEN.sprites.bottom = genSprite(
        SCREEN.origin.x - SCREEN.width,
        SCREEN.origin.y + SCREEN.height + playerBoundary1,
        SCREEN.width * 3,
        playerBoundary1)

    SCREEN.sprites.left = genSprite(
        SCREEN.origin.x - playerBoundary2,
        SCREEN.origin.y - SCREEN.height,
        playerBoundary1,
        SCREEN.height * 3)

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
    end

    -- Rotate the player sprite related to how the crank is positioned
    if playdate.isCrankDocked() then
        playerSprite:setRotation(0.0)
        ui.crankIndicator:draw()
    else
        local angle = playdate.getCrankPosition()
        playerSprite:setRotation(angle)
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

    playdate.timer.updateTimers()
end
