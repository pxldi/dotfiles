--!nonstrict
-- present bar widget: presentation mode at a glance, and one click away.
--
-- All the real work already lives in the `present` script; this only reflects
-- its state and drives it. State is read straight from the file the script
-- writes rather than from `present status`, which shells out to
-- `niri msg outputs` and is far too heavy to poll.
--
-- The widget deliberately stays visible when no external screen is attached
-- (dimmed), because "is anything plugged in yet" is the question you actually
-- have while setting up in a meeting room.
--
-- Click mapping:
--   Left click:  present toggle (start, or stop if already live)
--   Right click: present mirror, or whatever `right_click_action` names
-- Middle click is left alone; the host binds it to this widget's settings.

local PROBE = "sh -c 'cat \"${XDG_STATE_HOME:-$HOME/.local/state}/present.state\" 2>/dev/null; "
    .. "pgrep -x wl-mirror >/dev/null && echo mirror=1; "
    .. "echo tv=$(av-detect output 2>/dev/null)'"
local PROBE_TIMEOUT_MS = 5000
local ACTION_TIMEOUT_MS = 20000

local tv = "" -- external output name, "" when nothing is attached
local mode = nil -- "window" | "desk" | "mirror" while live, nil when idle
local mirroring = false
local lastPoll = 0
local polling = false
local busy = false
local failure = nil
local wasLive = false

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

local function live()
    return mode ~= nil
end

local function render()
    local attached = tv ~= ""

    if failure ~= nil then
        barWidget.setVisible(true)
        barWidget.setGlyph("presentation-off")
        barWidget.setGlyphColor("error")
        barWidget.setText("")
        barWidget.setTooltip({ { key = tr("error"), value = failure } })
        return
    end

    if not attached and not live() then
        barWidget.setVisible(cfg("hide_without_display", false) ~= true)
        barWidget.setGlyph("device-desktop-off")
        barWidget.setGlyphColor("on_surface_variant")
        barWidget.setText("")
        barWidget.setTooltip({
            { key = tr("tooltip.state"), value = tr("state.no_display") },
            { key = "", value = tr("tooltip.hint_idle") },
        })
        return
    end

    barWidget.setVisible(true)

    if live() then
        barWidget.setGlyph(mirroring and "copy" or "broadcast")
        barWidget.setGlyphColor("error")
    else
        barWidget.setGlyph("presentation")
        barWidget.setGlyphColor("on_surface")
    end

    local label = ""
    if live() then
        label = tr("mode." .. mode)
    elseif cfg("show_output_name", false) == true then
        label = tv
    end
    barWidget.setText(busy and tr("working") or label)

    local rows = {
        { key = tr("tooltip.state"), value = live() and tr("state.live") or tr("state.ready") },
        { key = tr("tooltip.display"), value = tv ~= "" and tv or tr("state.no_display") },
    }
    if live() then
        table.insert(rows, { key = tr("tooltip.mode"), value = tr("mode." .. mode) })
    end
    if mirroring then
        table.insert(rows, { key = tr("tooltip.mirror"), value = tr("state.mirroring") })
    end
    table.insert(rows, { key = "", value = live() and tr("tooltip.hint_live") or tr("tooltip.hint_ready") })
    barWidget.setTooltip(rows)
end

local function poll(force)
    local now = os.time()
    if polling then
        return
    end
    if not force and now - lastPoll < cfg("poll_seconds", 3) then
        return
    end
    polling = true
    lastPoll = now

    local started = noctalia.runAsync(PROBE, function(result)
        polling = false
        if result.timedOut then
            failure = tr("error.timeout")
            render()
            return
        end

        failure = nil
        local out = result.stdout or ""
        tv = out:match("tv=([%w%-_]+)") or ""
        mirroring = out:match("mirror=1") ~= nil
        -- The state file only exists while a presentation is running, so a
        -- missing mode is the idle case rather than an error.
        mode = out:match("mode=([%a]+)")

        if cfg("notify", true) == true then
            if live() and not wasLive then
                noctalia.notify(tr("notify.on.title"), tr("notify.on.body", {
                    output = tv ~= "" and tv or "?",
                    mode = tr("mode." .. mode),
                }))
            elseif not live() and wasLive then
                noctalia.notify(tr("notify.off.title"), tr("notify.off.body"))
            end
        end
        wasLive = live()

        render()
    end, PROBE_TIMEOUT_MS)

    if not started then
        polling = false
        failure = tr("error.spawn")
        render()
    end
end

-- Every action goes through the script, so the widget never has to know how
-- presenting is actually performed - and the two stay in step if it changes.
local function run(action)
    if busy then
        return
    end
    busy = true
    render()
    local started = noctalia.runAsync("present " .. action, function(result)
        busy = false
        if result.timedOut or result.exitCode ~= 0 then
            local why = noctalia.string.trim(result.stdout or "")
            if why == "" then
                why = noctalia.string.trim(result.stderr or "")
            end
            failure = (why ~= "") and why or ("exit " .. tostring(result.exitCode))
        end
        poll(true)
    end, ACTION_TIMEOUT_MS)

    if not started then
        busy = false
        failure = tr("error.spawn")
        render()
    end
end

function update()
    poll(false)
    render()
end

function onClick()
    run("toggle")
end

-- Mirroring is its own mode rather than a variant of presenting, so it gets
-- its own gesture: right click starts it, and stops the presentation if one
-- is already running in mirror mode.
function onRightClick()
    local action = cfg("right_click_action", "mirror")
    if live() and mode == action then
        run("off")
    else
        run(action)
    end
end

-- Same actions over IPC, for keybinds:
--   noctalia msg plugin sappler/present:present all mirror
function onIpc(event, _payload)
    if event == "toggle" or event == "on" or event == "off"
        or event == "mirror" or event == "desk" then
        run(event)
    elseif event == "refresh" then
        poll(true)
    end
end

noctalia.setUpdateInterval(1000)
poll(true)
render()
