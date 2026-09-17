--!nonstrict
-- next-meeting bar widget: countdown to the next calendar event.
--
-- The `next-event` helper does the talking to evolution-data-server and hands
-- back plain JSON, so this file only has to format and colour it. The calendar
-- is polled every `refresh_seconds`, while the countdown is recomputed on every
-- 1s tick from the cached start time -- a lookup per second would be wasteful.
--
-- Click mapping:
--   Left click:  join the meeting, or open the calendar app when there is none
--   Right click: refresh now
-- Middle click is left alone; the host binds it to this widget's settings.

local FETCH_TIMEOUT_MS = 15000
local PANEL_ID = "sappler/next-meeting:agenda"

local events = nil -- nil until the first fetch lands
local lastFetchAt = 0
local fetching = false
local failure = nil
local notifiedKey = nil

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

-- The soonest event that has not ended yet; running events win over upcoming.
local function current()
    if type(events) ~= "table" then
        return nil
    end
    local now = os.time()
    for _, ev in ipairs(events) do
        if ev.endsAt == nil or ev.endsAt > now then
            return ev
        end
    end
    return nil
end

local function truncate(text, limit)
    if utf8.len(text) == nil or utf8.len(text) <= limit then
        return text
    end
    return string.sub(text, 1, utf8.offset(text, limit) - 1) .. "…"
end

-- "now", "7m", "2h15m", "3d" -- short enough to live in a bar.
local function countdown(seconds)
    if seconds < 60 then
        return tr("now")
    end
    local minutes = math.floor(seconds / 60)
    if minutes < 60 then
        return minutes .. "m"
    end
    local hours = math.floor(minutes / 60)
    minutes = minutes % 60
    if hours < 24 then
        if minutes > 0 then
            return string.format("%dh%02dm", hours, minutes)
        end
        return hours .. "h"
    end
    return math.floor(hours / 24) .. "d"
end

local function clock(at)
    return os.date("%H:%M", at)
end

local function when(ev, now)
    local sameDay = os.date("%Y%m%d", ev.startsAt) == os.date("%Y%m%d", now)
    if sameDay then
        return clock(ev.startsAt)
    end
    return os.date("%a %d %b %H:%M", ev.startsAt)
end

local function render()
    local now = os.time()
    local ev = current()

    if failure ~= nil then
        barWidget.setVisible(true)
        barWidget.setGlyph("calendar-off")
        barWidget.setGlyphColor("error")
        barWidget.setText("")
        barWidget.setTooltip({ { key = tr("error"), value = failure } })
        return
    end

    if ev == nil then
        barWidget.setVisible(cfg("hide_when_empty", false) ~= true)
        barWidget.setGlyph("calendar-check")
        barWidget.setGlyphColor("on_surface")
        barWidget.setText("")
        barWidget.setTooltip({ { key = "", value = tr("none") } })
        return
    end

    local running = ev.startsAt <= now
    local untilStart = ev.startsAt - now
    local imminent = running or untilStart <= (cfg("imminent_minutes", 5) * 60)

    -- One nudge per meeting, a configurable number of minutes ahead. Waiting
    -- for the start is too late to walk anywhere or find the right window.
    local lead = cfg("notify_minutes_before", 2) * 60
    if cfg("notify_at_start", true) == true and untilStart <= lead then
        local key = tostring(ev.startsAt) .. ev.summary
        if notifiedKey ~= key then
            notifiedKey = key
            local when = running and tr("notify.now")
                or tr("notify.soon", { minutes = tostring(math.max(math.floor(untilStart / 60), 1)) })
            local body = clock(ev.startsAt) .. " · " .. when
            if ev.location ~= nil and ev.location ~= "" then
                body = body .. "\n" .. ev.location
            end
            if ev.url ~= nil then
                body = body .. "\n" .. tr("notify.join")
            end
            noctalia.notify(ev.summary, body)
        end
    end

    barWidget.setVisible(true)
    barWidget.setGlyph(ev.url ~= nil and "video" or "calendar-event")
    barWidget.setGlyphColor(imminent and "error" or "on_surface")
    barWidget.setText(countdown(untilStart) .. " · " .. truncate(ev.summary, cfg("max_title_length", 28)))

    local rows = {
        { key = tr("tooltip.event"), value = ev.summary },
        { key = tr("tooltip.when"), value = when(ev, now) },
        { key = tr("tooltip.calendar"), value = ev.calendar or "" },
    }
    if ev.location ~= nil and ev.location ~= "" then
        table.insert(rows, { key = tr("tooltip.location"), value = ev.location })
    end
    if ev.url ~= nil then
        table.insert(rows, { key = tr("tooltip.join"), value = tr("join_hint") })
    end
    local seen = false
    for _, nxt in ipairs(events) do
        if nxt ~= ev and (nxt.endsAt == nil or nxt.endsAt > now) and not seen then
            table.insert(rows, { key = tr("tooltip.next"), value = when(nxt, now) .. "  " .. nxt.summary })
            seen = true
        end
    end
    table.insert(rows, { key = "", value = tr("tooltip.hint") })
    barWidget.setTooltip(rows)
end

local function fetch()
    if fetching then
        return
    end
    fetching = true
    lastFetchAt = os.time()

    local started = noctalia.runAsync("next-event --raw", function(result)
        fetching = false
        if result.timedOut or result.exitCode ~= 0 then
            failure = noctalia.string.trim(result.stderr or "") 
            if failure == "" then
                failure = "exit " .. tostring(result.exitCode)
            end
            render()
            return
        end

        local ok, payload = pcall(noctalia.json.decode, result.stdout or "")
        if not ok or type(payload) ~= "table" or type(payload.events) ~= "table" then
            failure = "bad output"
            render()
            return
        end

        failure = nil
        events = {}
        for _, raw in ipairs(payload.events) do
            table.insert(events, {
                startsAt = tonumber(raw.start),
                endsAt = tonumber(raw["end"]),
                summary = raw.summary or "",
                location = raw.location,
                url = raw.url,
                calendar = raw.calendar,
            })
        end
        render()
    end, FETCH_TIMEOUT_MS)

    if not started then
        fetching = false
        failure = "could not start next-event"
        render()
    end
end

function update()
    if os.time() - lastFetchAt >= cfg("refresh_seconds", 60) then
        fetch()
    end
    render()
end

-- Clicking should do the thing that is useful right now: join the meeting
-- you are about to walk into, browse the agenda the rest of the time.
-- Joining tomorrow's standup because you clicked at lunchtime is not useful.
function onClick()
    local ev = current()
    local window = cfg("join_window_minutes", 10) * 60
    if ev ~= nil and ev.url ~= nil and (ev.startsAt - os.time()) <= window then
        noctalia.runAsync("next-event --join", function() end, FETCH_TIMEOUT_MS)
        return
    end
    noctalia.togglePanel(PANEL_ID)
end

function onRightClick()
    lastFetchAt = 0
    fetch()
end

noctalia.setUpdateInterval(1000)
fetch()
render()
