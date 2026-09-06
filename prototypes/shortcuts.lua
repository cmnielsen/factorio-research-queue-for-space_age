local data_util = require('__flib__.data-util')

local path = '__factorio-research-queue-for-space_age__/graphics/icons.png'

data:extend{
  {
    type = 'shortcut',
    name = 'factorio-research-queue',
    order = 'r[research-queue]',
    associated_control_input = 'rq-toggle-main-window',
    action = 'lua',
    toggleable = true,
    icon = '__factorio-research-queue-for-space_age__/graphics/icons.png',
    icon_size = 32,
    small_icon = '__factorio-research-queue-for-space_age__/graphics/icons.png',
    small_icon_size = 32,
  },
}
