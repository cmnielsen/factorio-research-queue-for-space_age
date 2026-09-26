local rqtech = require('scripts.rqtech')
local gui_util = require('.gui_util')
local build_gui = gui_util.build_gui

local function try_localise(str)
  local ok, result = pcall(function() return helpers.localise_string(str) end)
  if ok and type(result) == 'string' then
    return result
  elseif type(str) == 'string' then
    return str
  end
  return ''
end

local function update_tech_button_tooltip(player, gui_data, tech)
  local description_str = try_localise(tech.tech.localised_description)
  local has_description = description_str ~= nil and description_str ~= ''

  local tooltip_lines = {}
  table.insert(tooltip_lines, {'',
    '[font=heading-2]',
    tech.tech.localised_name,
    '[/font]'})
  if has_description then
    table.insert(tooltip_lines, tech.tech.localised_description)
  end

  local research_trigger = rqtech.research_trigger(tech)
  if research_trigger ~= nil then
    if research_trigger.sprite ~= nil then
      local trigger_locale_key = 'factorio-research-queue.tech-button-trigger'
      if research_trigger.type == 'craft-item' then
        trigger_locale_key = trigger_locale_key..'-craft-item'
      elseif research_trigger.type == 'mine-entity' then
        trigger_locale_key = trigger_locale_key..'-mine-entity'
      elseif research_trigger.type == 'craft-fluid' then
        trigger_locale_key = trigger_locale_key..'-craft-fluid'
      elseif research_trigger.type == 'send-item-to-orbit' then
        trigger_locale_key = trigger_locale_key..'-send-item-to-orbit'
      elseif research_trigger.type == 'capture-spawner' then
        trigger_locale_key = trigger_locale_key..'-capture-spawner'
      elseif research_trigger.type == 'build-entity' then
        trigger_locale_key = trigger_locale_key..'-build-entity'
      end

      local trigger_count = research_trigger.count or research_trigger.amount
      if trigger_count ~= nil and
          (research_trigger.type == 'craft-item' or
           research_trigger.type == 'craft-fluid' or
           research_trigger.type == 'send-item-to-orbit')
      then
        table.insert(tooltip_lines, {
          trigger_locale_key..'-with-count',
          research_trigger.sprite,
          research_trigger.localised_name,
          trigger_count,
        })
      else
        table.insert(tooltip_lines, {
          trigger_locale_key,
          research_trigger.sprite,
          research_trigger.localised_name,
        })
      end
    elseif research_trigger.description ~= nil then
      table.insert(tooltip_lines, {
        'factorio-research-queue.tech-button-trigger-description',
        research_trigger.description,
      })
    end
  else
    local cost = '[[font=count-font]'
    for _, ingredient in ipairs(tech.tech.research_unit_ingredients or {}) do
      local ingredient_type = ingredient.type or 'item'
      cost = cost .. string.format(
        '[img=%s/%s]%d ',
        ingredient_type,
        ingredient.name,
        ingredient.amount)
    end
    cost = cost .. string.format(
      '[img=quantity-time]%d[/font]][font=count-font][img=quantity-multiplier]%d[/font]',
      (tech.tech.research_unit_energy or 0) / 60,
      tech.research_unit_count or 0)
    table.insert(tooltip_lines, cost)
  end

  local prerequisite_texts = {}
  for _, prereq in pairs(tech.prerequisites) do
    table.insert(prerequisite_texts, '[technology=' .. prereq.tech.name .. '] ' .. try_localise(prereq.tech.localised_name))
  end
  if #prerequisite_texts > 0 then
    table.insert(tooltip_lines, {'factorio-research-queue.tech-button-requires', table.concat(prerequisite_texts, ', ')})
  end
  table.insert(tooltip_lines, {'factorio-research-queue.tech-button-enqueue-last'})
  table.insert(tooltip_lines, {'factorio-research-queue.tech-button-enqueue-second'})
  table.insert(tooltip_lines, {'factorio-research-queue.tech-button-dequeue'})
  table.insert(tooltip_lines, {'factorio-research-queue.tech-button-open'})

  local tooltip = {''}
  do
    local first = true
    for _, line in ipairs(tooltip_lines) do
      if not first then
        table.insert(tooltip, '\n')
      end
      table.insert(tooltip, line)
      first = false
    end
  end

  gui_data.button.tooltip = tooltip
end

local function build(player, parent, tech, list_type)
  local refs = build_gui(parent, {
    type = 'flow',
    style = 'rq_tech_button_container_'..list_type,
    direction = 'vertical',
    children = {
      {
        ref = 'button',
        type = 'sprite-button',
        tags = {
          on_click = { type = 'on_click_tech_button', tech = tech.id },
        },
        sprite = 'technology/'..tech.tech.name,
        number = tech.level,
        mouse_button_filter = {'left', 'right'},
      },
      {
        ref = 'progressbar',
        type = 'progressbar',
        style = 'rq_tech_button_progressbar_'..list_type,
      },
    },
  })

  update_tech_button_tooltip(player, refs, tech)

  return refs
end

return {
  build = build,
  update_tech_button_tooltip = update_tech_button_tooltip,
}
