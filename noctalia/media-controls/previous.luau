--!nonstrict
-- previous track. Static glyph: the action never changes meaning.

local function render()
    barWidget.setGlyph("player-skip-back")
    barWidget.setText("")
    barWidget.setTooltip({ { key = "", value = noctalia.tr("previous") } })
end

function update()
    render()
end

function onClick()
    noctalia.runAsync("noctalia msg media previous", function() end, 3000)
end

noctalia.setUpdateInterval(5000)
render()
