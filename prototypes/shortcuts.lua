-- Toolbar shortcut (shortcut bar button) that opens the research queue window
local GRAPHICS = '__factorio-research-queue-for-space_age__/graphics/'

data:extend{
  {
    type = 'shortcut',
    name = 'factorio-research-queue',
    order = 'r[research-queue]',
    associated_control_input = 'rq-toggle-main-window',
    action = 'lua',
    toggleable = true,
    icon = GRAPHICS .. 'shortcut-32.png',
    icon_size = 32,
    small_icon = GRAPHICS .. 'shortcut-24.png',
    small_icon_size = 24,
  },
}
