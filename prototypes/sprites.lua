-- Sprites cut out of graphics/icons.png (32x32 cells; black variant left, white variant right)
local ICONS = '__factorio-research-queue-for-space_age__/graphics/icons.png'

local function cell(name, column, row)
  return {
    type = 'sprite',
    name = name,
    filename = ICONS,
    position = {column * 32, row * 32},
    size = 32,
    flags = {'gui-icon'},
  }
end

data:extend{
  cell('rq-enqueue-last-black', 0, 0),
  cell('rq-enqueue-last-white', 1, 0),
  cell('rq-enqueue-second-black', 0, 1),
  cell('rq-enqueue-second-white', 1, 1),
  cell('rq-enqueue-first-black', 0, 2),
  cell('rq-enqueue-first-white', 1, 2),
  cell('rq-pause-black', 0, 3),
  cell('rq-pause-white', 1, 3),
  cell('rq-play-black', 0, 4),
  cell('rq-play-white', 1, 4),
}
