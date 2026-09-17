--!nonstrict
-- next track. Static glyph: the action never changes meaning.

local function render()
    barWidget.setGlyph("player-skip-forward")
    barWidget.setText("")
    barWidget.setTooltip({ { key = "", value = noctalia.tr("next") } })
end

function update()
    render()
end

function onClick()
    noctalia.runAsync("noctalia msg media next", function() end, 3000)
end

noctalia.setUpdateInterval(5000)
render()
