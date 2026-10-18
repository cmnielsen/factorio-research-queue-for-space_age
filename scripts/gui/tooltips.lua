-- Tooltip for technology buttons.

local rqtech = require('scripts.rqtech')
local util = require('scripts.util')

local tooltips = {}

-- "[[ pack amounts, time ]] x count" line for technologies researched in labs
local function cost_line(rt)
  local text = '[[font=count-font]'
  for _, ingredient in ipairs(rt.tech.research_unit_ingredients or {}) do
    text = text .. string.format('[img=%s/%s]%d ', ingredient.type or 'item', ingredient.name, ingredient.amount)
  end
  text = text .. string.format(
    '[img=quantity-time]%g[/font]][font=count-font][img=quantity-multiplier]%d[/font]',
    (rt.tech.research_unit_energy or 0) / 60,
    rt.research_unit_count or 0)
  return text
end

local function trigger_line(trigger)
  if trigger.line then
    return trigger.line
  end
  local count = trigger.count and string.format('x%g', trigger.count) or ''
  return {'factorio-research-queue.trigger-' .. trigger.type, trigger.sprite, trigger.name, count}
end

local function prerequisites_line(rt)
  local parts = {}
  for _, prerequisite in ipairs(rqtech.sorted_prerequisites(rt)) do
    if #parts > 0 then
      parts[#parts + 1] = ', '
    end
    parts[#parts + 1] = '[technology=' .. prerequisite.tech.name .. '] '
    parts[#parts + 1] = prerequisite.tech.localised_name
  end
  if #parts == 0 then
    return nil
  end
  return {'factorio-research-queue.requires', util.concat(parts)}
end

function tooltips.for_tech(rt)
  local lines = {{'', '[font=heading-2]', rt.tech.localised_name, '[/font]'}}

  local trigger = rqtech.trigger_info(rt)
  lines[#lines + 1] = trigger and trigger_line(trigger) or cost_line(rt)

  local prerequisites = prerequisites_line(rt)
  if prerequisites then
    lines[#lines + 1] = prerequisites
  end
  lines[#lines + 1] = {'factorio-research-queue.tech-hints'}

  local parts = {}
  for i, line in ipairs(lines) do
    if i > 1 then
      parts[#parts + 1] = '\n'
    end
    parts[#parts + 1] = line
  end
  return util.concat(parts)
end

return tooltips
