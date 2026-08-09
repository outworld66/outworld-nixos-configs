local wezterm = require('wezterm')

local M = {}

function M.setup()
    wezterm.on('bell', function(window, pane)
        local title = pane:get_title()
        if title == '' then
            title = 'Терминал ожидает ответа'
        end

        window:toast_notification(
            'Codex',
            title,
            nil,
            10000
        )
    end)
end

return M
