--!nonstrict
-- posture bar widget: alternate sitting and standing on a timer.
--
-- The bar is the primary channel here, not the notification. A glanceable
-- "how long is left in this phase" costs nothing to ignore, which is what
-- makes it survivable long-term; the notification fires once per switch and
-- is the exception rather than the mechanism. A nudge that interrupts on a
-- fixed timer regardless of what you are doing gets dismissed reflexively
-- within a week and then ignored entirely.
--
-- Two things keep it from firing at a useless moment:
--   * a switch due during a meeting is held until the call ends (capped), so
--     the popup does not land mid screen-share
--   * a gap between ticks longer than `away_resets_minutes` means suspend or
--     a long absence, so the phase restarts instead of firing stale
--
-- Click mapping:
--   Left click:  switch posture now and restart the phase
--   Right click: pause / resume
-- Middle click is left alone; the host binds it to this widget's settings.

local STATE_FILE = "/state.json"
local MEETING_POLL_SECONDS = 60
local FETCH_TIMEOUT_MS = 10000
local MAX_TICK_CREDIT = 5 -- seconds; a scheduling hiccup must not inflate the daily total

local state = nil -- loaded on first use
local lastTick = os.time()
local meetingUntil = 0 -- epoch at which the running meeting ends; 0 when none
local lastMeetingPoll = 0
local deferredSince = nil

local function tr(key, args)
    return noctalia.tr(key, args)
end

local function cfg(key, fallback)
    local value = noctalia.getConfig(key)
    if value == nil then
        return fallback
    end
    return value
end

local function today()
    return os.date("%Y-%m-%d")
end

local function statePath()
    local dir = noctalia.pluginDataDir()
    if dir == nil then
        return nil
    end
    return dir .. STATE_FILE
end

local function defaults()
    return {
        phase = "sit",
        startedAt = os.time(),
        paused = false,
        day = today(),
        standSeconds = 0,
    }
end

-- The cycle should survive a shell restart: coming back from a Noctalia
-- reload to "you have been sitting 0 minutes" would quietly reset the day.
local function load()
    state = defaults()
    local path = statePath()
    if path == nil then
        return
    end
    local body = noctalia.readFile(path)
    if body == nil or noctalia.string.trim(body) == "" then
        return
    end
    local ok, saved = pcall(noctalia.json.decode, body)
    if not ok or type(saved) ~= "table" then
        return
    end
    if saved.phase == "sit" or saved.phase == "stand" then
        state.phase = saved.phase
    end
    state.startedAt = tonumber(saved.startedAt) or state.startedAt
    state.paused = saved.paused == true
    state.day = saved.day or state.day
    state.standSeconds = tonumber(saved.standSeconds) or 0
    if state.day ~= today() then
        state.day = today()
        state.standSeconds = 0
    end
end

local function save()
    local path = statePath()
    if path == nil then
        return
    end
    local ok, body = pcall(noctalia.json.encode, state)
    if ok then
        noctalia.writeFile(path, body)
    end
end

local function phaseSeconds()
    if state.phase == "stand" then
        return cfg("stand_minutes", 20) * 60
    end
    return cfg("sit_minutes", 30) * 60
end

-- "12m", "1h05m", "now" -- short enough to live in a bar.
local function short(seconds)
    if seconds < 60 then
        return tr("now")
    end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then
        return minutes .. "m"
    end
    return string.format("%dh%02dm", math.floor(minutes / 60), minutes % 60)
end

local function switchTo(phase, now)
    state.phase = phase
    state.startedAt = now
    deferredSince = nil
    save()
end

local function notifySwitch()
    if cfg("notify", true) ~= true then
        return
    end
    if state.phase == "stand" then
        noctalia.notify(tr("notify.stand.title"), tr("notify.stand.body", {
            minutes = tostring(cfg("stand_minutes", 20)),
        }))
    else
        noctalia.notify(tr("notify.sit.title"), tr("notify.sit.body", {
            minutes = tostring(cfg("sit_minutes", 30)),
        }))
    end
end

local function inMeeting(now)
    return cfg("defer_during_meetings", true) == true and meetingUntil > now
end

local function pollMeeting(now)
    if cfg("defer_during_meetings", true) ~= true then
        meetingUntil = 0
        return
    end
    if now - lastMeetingPoll < MEETING_POLL_SECONDS then
        return
    end
    lastMeetingPoll = now

    -- Best effort: the helper belongs to the next-meeting plugin. Without it
    -- there is simply no deferral, which is a worse widget but not a broken one.
    noctalia.runAsync("next-event --raw", function(result)
        if result.timedOut or result.exitCode ~= 0 then
            meetingUntil = 0
            return
        end
        local ok, payload = pcall(noctalia.json.decode, result.stdout or "")
        if not ok or type(payload) ~= "table" or type(payload.events) ~= "table" then
            meetingUntil = 0
            return
        end
        local at = os.time()
        local running = 0
        for _, raw in ipairs(payload.events) do
            local startsAt = tonumber(raw.start)
            local endsAt = tonumber(raw["end"])
            if startsAt ~= nil and endsAt ~= nil and startsAt <= at and endsAt > at then
                if endsAt > running then
                    running = endsAt
                end
            end
        end
        meetingUntil = running
    end, FETCH_TIMEOUT_MS)
end

local function render(now)
    local standing = state.phase == "stand"
    local elapsed = now - state.startedAt
    local remaining = phaseSeconds() - elapsed
    local goal = cfg("stand_goal_minutes", 120) * 60

    if state.paused then
        barWidget.setVisible(true)
        barWidget.setGlyph("player-pause")
        barWidget.setGlyphColor("on_surface_variant")
        barWidget.setText(cfg("show_remaining", true) and tr("paused") or "")
        barWidget.setTooltip({
            { key = tr("tooltip.state"), value = tr("tooltip.paused") },
            { key = tr("tooltip.standing_today"), value = short(state.standSeconds) },
            { key = "", value = tr("tooltip.hint") },
        })
        return
    end

    local held = deferredSince ~= nil
    local urgent = held or remaining <= (cfg("warn_minutes", 2) * 60)

    barWidget.setVisible(true)
    barWidget.setGlyph(standing and "walk" or "armchair")
    barWidget.setGlyphColor(urgent and "error" or "on_surface")
    if cfg("show_remaining", true) == true then
        barWidget.setText(held and tr("held") or short(math.max(remaining, 0)))
    else
        barWidget.setText("")
    end

    local rows = {
        { key = tr("tooltip.state"), value = standing and tr("standing") or tr("sitting") },
        { key = tr("tooltip.switch_in"), value = short(math.max(remaining, 0)) },
    }
    if held then
        table.insert(rows, { key = tr("tooltip.held"), value = tr("tooltip.held_reason") })
    end
    local total = { key = tr("tooltip.standing_today"), value = short(state.standSeconds) }
    if goal > 0 then
        total.value = total.value .. " / " .. short(goal)
            .. string.format("  (%d%%)", math.floor(state.standSeconds / goal * 100))
    end
    table.insert(rows, total)
    table.insert(rows, { key = "", value = tr("tooltip.hint") })
    barWidget.setTooltip(rows)
end

function update()
    if state == nil then
        load()
    end

    local now = os.time()
    local gap = now - lastTick
    lastTick = now

    -- A long gap means the machine slept or was locked, not that you stood
    -- for an hour. Restart the phase rather than firing a switch for time
    -- that was never spent at the desk.
    local awayLimit = cfg("away_resets_minutes", 20) * 60
    if awayLimit > 0 and gap > awayLimit then
        state.startedAt = now
        deferredSince = nil
        save()
        render(now)
        return
    end

    if state.day ~= today() then
        state.day = today()
        state.standSeconds = 0
        save()
    end

    if state.phase == "stand" and not state.paused and gap > 0 then
        state.standSeconds = state.standSeconds + math.min(gap, MAX_TICK_CREDIT)
    end

    pollMeeting(now)

    if not state.paused and (now - state.startedAt) >= phaseSeconds() then
        if inMeeting(now) then
            deferredSince = deferredSince or now
            local cap = cfg("max_defer_minutes", 15) * 60
            if cap <= 0 or (now - deferredSince) < cap then
                render(now)
                return
            end
        end
        switchTo(state.phase == "sit" and "stand" or "sit", now)
        notifySwitch()
    end

    render(now)
end

-- Switching by hand is the common case: you stood up early, or you sat back
-- down because a call ran long. Clicking should agree with reality rather
-- than argue with it, so it restarts the phase from now.
function onClick()
    if state == nil then
        load()
    end
    local now = os.time()
    state.paused = false
    switchTo(state.phase == "sit" and "stand" or "sit", now)
    render(now)
end

function onRightClick()
    if state == nil then
        load()
    end
    local now = os.time()
    if state.paused then
        state.paused = false
        state.startedAt = now
    else
        state.paused = true
    end
    deferredSince = nil
    save()
    render(now)
end

-- Same two actions over IPC, so they can sit on a keybind next to the rest of
-- the `noctalia msg` bindings:
--   noctalia msg plugin sappler/posture:posture all switch
--   noctalia msg plugin sappler/posture:posture all pause
function onIpc(event, _payload)
    if event == "switch" then
        onClick()
    elseif event == "pause" then
        onRightClick()
    end
end

noctalia.setUpdateInterval(1000)
load()
render(os.time())
