local Config = require('config')

require('events.left-status').setup()
require('events.right-status').setup({ date_format = '%a %H:%M:%S' })
require('events.tab-title').setup({
    hide_active_tab_unseen = true,
    unseen_icon = 'numbered_box',
    show_progress = true,
})
require('events.new-tab-button').setup()
require('events.gui-startup').setup()
require('events.bell').setup()

return Config:init()
    :append(require('config.appearance'))
    :append(require('config.bindings'))
    :append(require('config.domains'))
    :append(require('config.fonts'))
    :append(require('config.general'))
    :append(require('config.launch')).options
