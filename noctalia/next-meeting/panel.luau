--!nonstrict
-- The agenda panel: what is coming up, with a join button on each meeting.
--
-- Reads the same cache the bar widget does, so opening this never waits on
-- Teams. Refresh re-runs the sync and then re-reads.

local FETCH_TIMEOUT_MS = 15000
local SYNC_TIMEOUT_MS = 30000
local STALE_SECS = 30 * 60

local events = {}
local fetchedAt = 0
local busy = false
local render

local function baseFont()
    local size = noctalia.getConfig("panel_font_size")
    return (type(size) == "number" and size >= 9) and size or 13
end

local function tr(key, args)
    return noctalia.tr(key, args)
end

local function dayLabel(stamp)
    local today = os.date("%Y%m%d", os.time())
    local tomorrow = os.date("%Y%m%d", os.time() + 86400)
    local day = os.date("%Y%m%d", stamp)
    if day == today then
        return tr("agenda.today")
    elseif day == tomorrow then
        return tr("agenda.tomorrow")
    end
    return os.date("%a %d %b", stamp)
end

local function load(callback)
    noctalia.runAsync("next-event --raw", function(result)
        if result.exitCode == 0 and not result.timedOut then
            local ok, payload = pcall(noctalia.json.decode, result.stdout or "")
            if ok and type(payload) == "table" and type(payload.events) == "table" then
                events = {}
                for _, raw in ipairs(payload.events) do
                    table.insert(events, {
                        startsAt = tonumber(raw.start),
                        endsAt = tonumber(raw["end"]),
                        summary = raw.summary or "",
                        location = raw.location or "",
                        url = raw.url,
                    })
                end
                fetchedAt = tonumber(payload.fetched) or 0
            end
        end
        if callback ~= nil then
            callback()
        end
    end, FETCH_TIMEOUT_MS)
end

local function eventRow(ev, now)
    local running = ev.startsAt <= now
    local children = {
        ui.label({
            text = os.date("%H:%M", ev.startsAt),
            fontSize = baseFont(),
            fontWeight = "bold",
            color = running and "error" or "on_surface",
        }),
        ui.column({ gap = 2, flexGrow = 1 }, {
            ui.label({ text = ev.summary, fontSize = baseFont(), color = "on_surface" }),
            ui.label({ text = ev.location, fontSize = baseFont() - 2, color = "on_surface_variant" }),
        }),
    }

    if ev.url ~= nil then
        table.insert(children, ui.button({
            key = "join-" .. tostring(ev.startsAt),
            label = tr("agenda.join"),
            glyph = "video",
            -- The meeting you are about to be late for is the prominent one.
            variant = running and "primary" or "ghost",
            onClick = function()
                noctalia.runAsync("setsid xdg-open '" .. ev.url .. "' >/dev/null 2>&1 &", function() end, FETCH_TIMEOUT_MS)
                panel.close()
            end,
        }))
    end

    return ui.row({ gap = 10, align = "center" }, children)
end

render = function()
    local now = os.time()

    local header = ui.row({ gap = 8, align = "center" }, {
        ui.label({ text = tr("agenda.title"), fontSize = baseFont() + 3, fontWeight = "bold", color = "on_surface", flexGrow = 1 }),
        ui.button({
            key = "refresh" .. (busy and "-off" or ""),
            glyph = "refresh",
            variant = "ghost",
            enabled = not busy,
            tooltip = tr("agenda.refresh"),
            onClick = function()
                busy = true
                render()
                noctalia.runAsync("teams-calendar-sync --quiet", function()
                    load(function()
                        busy = false
                        render()
                    end)
                end, SYNC_TIMEOUT_MS)
            end,
        }),
    })

    local rows = {}
    local lastDay = nil
    for _, ev in ipairs(events) do
        local day = dayLabel(ev.startsAt)
        if day ~= lastDay then
            if lastDay ~= nil then
                table.insert(rows, ui.separator({}))
            end
            table.insert(rows, ui.label({ text = day, fontSize = baseFont() - 2, fontWeight = "bold", color = "primary" }))
            lastDay = day
        end
        table.insert(rows, eventRow(ev, now))
    end

    if #rows == 0 then
        table.insert(rows, ui.label({ text = tr("agenda.empty"), fontSize = baseFont(), color = "on_surface_variant" }))
    end

    local children = { header, ui.scroll({ flexGrow = 1 }, { ui.column({ gap = 8 }, rows) }) }

    -- A stale cache means Teams is closed; say so rather than quietly ageing.
    if fetchedAt > 0 and (now - fetchedAt) > STALE_SECS then
        table.insert(children, ui.label({ text = tr("agenda.stale"), fontSize = baseFont() - 2, color = "error" }))
    end

    table.insert(children, ui.button({
        key = "open-calendar",
        label = tr("agenda.open_calendar"),
        glyph = "calendar",
        variant = "ghost",
        onClick = function()
            local app = noctalia.getConfig("calendar_app")
            if app == nil or app == "" then
                app = "gnome-calendar"
            end
            noctalia.runAsync("setsid " .. app .. " >/dev/null 2>&1 &", function() end, FETCH_TIMEOUT_MS)
            panel.close()
        end,
    }))

    panel.render(ui.column({ flexGrow = 1, gap = 10, align = "stretch" }, children))
end

function onOpen()
    load(render)
    render()
end

load(render)
render()
