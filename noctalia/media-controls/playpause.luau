--!nonstrict
-- Play/pause button whose glyph follows the actual MPRIS state, so it shows
-- a pause icon while music plays and a play icon while it is stopped.

-- A file read, not a poll: mpris-follow keeps the file correct, so this only
-- controls how quickly the bar notices, and costs nothing per tick.
local TICK_MS = 500
local ACTION_TIMEOUT_MS = 3000
local state = "None"

local function render()
    local playing = state == "Playing"
    local idle = state == "None"

    barWidget.setVisible(not (idle and noctalia.getConfig("hide_when_idle") ~= false))
    barWidget.setGlyph(playing and "player-pause" or "player-play")
    barWidget.setGlyphColor(idle and "on_surface_variant" or "on_surface")
    barWidget.setText("")

    local tip = idle and noctalia.tr("idle")
        or (playing and noctalia.tr("playing") or noctalia.tr("paused"))
    barWidget.setTooltip({ { key = "", value = tip } })
end

-- os.getenv is not available in the plugin sandbox, so the path comes from
-- the host. mpris-follow writes the same file.
local function readState()
    local dir = noctalia.pluginDataDir()
    if dir == nil then
        return "None"
    end
    local body = noctalia.readFile(dir .. "/state")
    local value = (body ~= nil) and noctalia.string.trim(body) or ""
    return (value ~= "") and value or "None"
end

local function poll()
    local now = readState()
    if now ~= state then
        state = now
        render()
    end
end

function update()
    poll()
end

function onClick()
    -- Flip immediately so the glyph does not wait for the next poll.
    state = (state == "Playing") and "Paused" or "Playing"
    render()
    noctalia.runAsync("noctalia msg media toggle", function() poll() end, ACTION_TIMEOUT_MS)
end

noctalia.setUpdateInterval(TICK_MS)
poll()
render()
