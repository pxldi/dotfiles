--!nonstrict
-- Teams unread count in the bar.
--
-- The count comes from the tray item's tooltip via teams-unread. The tray
-- icon itself is not trustworthy - it shows its attention dot with nothing
-- actually waiting - but the tooltip text carries the real number.
--
-- -1 means no tray item at all, i.e. Teams is not running.

local CHECK_TIMEOUT_MS = 5000

local count = -1
local lastCheck = 0
local checking = false

local function cfg(key, fallback)
    local value = noctalia.getConfig(key)
    if value == nil then
        return fallback
    end
    return value
end

local function render()
    local running = count >= 0
    local waiting = count > 0

    barWidget.setVisible(not (cfg("hide_when_empty", false) == true and not waiting))
    barWidget.setGlyph("brand-teams")
    barWidget.setGlyphColor(waiting and "primary" or (running and "on_surface" or "on_surface_variant"))
    barWidget.setText((waiting and cfg("show_count", true) == true) and tostring(count) or "")

    local tip
    if not running then
        tip = noctalia.tr("closed")
    elseif waiting then
        tip = noctalia.trp("unread", count, { count = tostring(count) })
    else
        tip = noctalia.tr("clear")
    end
    barWidget.setTooltip({ { key = "", value = tip }, { key = "", value = noctalia.tr("hint") } })
end

local function check()
    if checking then
        return
    end
    checking = true
    lastCheck = os.time()
    local started = noctalia.runAsync("teams-unread", function(result)
        checking = false
        if result.exitCode == 0 and not result.timedOut then
            count = tonumber(noctalia.string.trim(result.stdout or "")) or -1
        end
        render()
    end, CHECK_TIMEOUT_MS)
    if not started then
        checking = false
    end
end

function update()
    if os.time() - lastCheck >= cfg("poll_seconds", 5) then
        check()
    end
end

function onClick()
    -- Raise the existing window rather than starting a second Teams.
    noctalia.runAsync("teams-focus", function() end, CHECK_TIMEOUT_MS)
end

noctalia.setUpdateInterval(1000)
check()
render()
