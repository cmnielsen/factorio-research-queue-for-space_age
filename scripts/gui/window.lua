-- Construction of the research queue window and its parts.
--
-- build() returns a table of element references ("gui") that is kept in
-- storage.players[index].gui:
--   window, main, filter          the outer frame and the two inner frames
--   search, pause_button          titlebar widgets
--   pause_container, head_container, queue_list    queue area
--   tech_table                    table holding the technology list
--   items        tech id -> refs of a row in the technology list
--   base_ids     ids of the rows built with the window (list order)
--   extra        tech id -> refs of rows added for later infinite levels
--   queue_items  tech id -> refs of the rows in the queue (rebuilt on update)
--   packs        science pack names, pack_buttons   pack name -> filter button
--   researched_checkbox, upgrades_checkbox

local builder = require('scripts.gui.builder')
local tooltips = require('scripts.gui.tooltips')
local rqtech = require('scripts.rqtech')
local util = require('scripts.util')

local window = {}

local TECH_COLUMNS = 7
local ICON_SIZE = 16 -- size of the science pack icons under a technology
local ICON_AREA_WIDTH = 80 -- width available for those icons

---------------------------------------------------------------------------
-- Technology and science pack lists
---------------------------------------------------------------------------

-- Names of all science packs (research ingredients) used by the force's
-- technologies, in prototype order.
local function collect_packs(force)
  local set = {}
  for _, tech in pairs(force.technologies) do
    for _, ingredient in ipairs(tech.research_unit_ingredients or {}) do
      if prototypes.item[ingredient.name] then
        set[ingredient.name] = true
      end
    end
  end
  local packs = {}
  for name in pairs(set) do
    packs[#packs + 1] = name
  end
  table.sort(packs, function(a, b)
    local order_a, order_b = prototypes.item[a].order, prototypes.item[b].order
    if order_a ~= order_b then
      return order_a < order_b
    end
    return a < b
  end)
  return packs
end

local function compare_values(a, b)
  if type(a) == 'boolean' then a = a and 1 or 0 end
  if type(b) == 'boolean' then b = b and 1 or 0 end
  if a == b then return 0 end
  return a < b and -1 or 1
end

-- Sort order of the technology list: lab technologies before trigger
-- technologies, then by the most advanced science pack, pack count, cost,
-- technology order, name and level.
local function sort_key(rt, packs)
  local has_pack = {}
  for i, pack in ipairs(packs) do
    local has = false
    for _, ingredient in ipairs(rt.tech.research_unit_ingredients or {}) do
      if ingredient.name == pack then
        has = true
        break
      end
    end
    has_pack[#packs + 1 - i] = has
  end
  return {rt.has_trigger and 1 or 0, has_pack, rt.research_unit_count or 0, rt.tech.order, rt.tech.name, rt.level or 0}
end

local function compare_keys(a, b)
  for i = 1, #a do
    local x, y = a[i], b[i]
    if type(x) == 'table' then
      for j = 1, #x do
        local result = compare_values(x[j], y[j])
        if result ~= 0 then return result < 0 end
      end
    else
      local result = compare_values(x, y)
      if result ~= 0 then return result < 0 end
    end
  end
  return false
end

---------------------------------------------------------------------------
-- Technology buttons
---------------------------------------------------------------------------

-- Technology icon with a progress bar underneath. list_type is 'tech_list' or 'tech_queue'.
function window.build_tech_button(container, rt, list_type)
  return builder.build(container, {
    type = 'flow',
    style = 'rq_tech_button_container_' .. list_type,
    direction = 'vertical',
    children = {
      {
        ref = 'button',
        type = 'sprite-button',
        tags = {rq = 'tech_click', tech = rt.id},
        sprite = 'technology/' .. rt.tech.name,
        number = rt.level,
        mouse_button_filter = {'left', 'right'},
        tooltip = tooltips.for_tech(rt),
      },
      {ref = 'progressbar', type = 'progressbar', style = 'rq_tech_button_progressbar_' .. list_type},
    },
  })
end

-- Science pack icons (or the trigger icon) shown under a technology
local function build_ingredient_icons(container, rt)
  local icons = {}
  local trigger = rqtech.trigger_info(rt)
  if trigger then
    if trigger.sprite then
      icons[1] = {
        type = 'sprite',
        style = 'rq_tech_list_item_ingredient',
        sprite = trigger.sprite,
        tooltip = trigger.name,
      }
    end
  else
    for _, ingredient in ipairs(rt.tech.research_unit_ingredients or {}) do
      icons[#icons + 1] = {
        type = 'sprite',
        style = 'rq_tech_list_item_ingredient',
        sprite = string.format('%s/%s', ingredient.type or 'item', ingredient.name),
      }
    end
  end

  -- Overlap the icons when there are too many to fit side by side
  local spacing = nil
  if #icons >= 2 then
    spacing = math.min(0, math.floor((ICON_AREA_WIDTH - #icons * ICON_SIZE) / (#icons - 1)))
  end
  builder.build(container, {
    type = 'flow',
    style = 'horizontal_flow',
    direction = 'horizontal',
    style_mods = {horizontal_spacing = spacing},
    children = icons,
  })
end

-- One cell of the technology list. `index` places the cell inside the table.
function window.build_tech_item(container, rt, index)
  local function tool_button(position, sprite)
    return builder.tool_button{
      style = 'rq_tech_list_item_tool_button',
      tags = {rq = 'enqueue', pos = position, tech = rt.id},
      sprite = sprite,
      tooltip = {'factorio-research-queue.enqueue-' .. position .. '-tooltip', rt.tech.localised_name},
    }
  end

  local refs = builder.build(container, {
    ref = 'item',
    type = 'flow',
    style = 'rq_tech_list_item',
    direction = 'vertical',
    index = index,
    children = {
      {ref = 'button_container', type = 'flow', direction = 'vertical'},
      {ref = 'ingredients_bar', type = 'frame', direction = 'horizontal'},
      {
        ref = 'tool_bar',
        type = 'frame',
        direction = 'horizontal',
        children = {
          tool_button('last', 'rq-enqueue-last-black'),
          tool_button('next', 'rq-enqueue-second-black'),
          tool_button('first', 'rq-enqueue-first-black'),
        },
      },
    },
  })
  refs.tech_button = window.build_tech_button(refs.button_container, rt, 'tech_list')
  build_ingredient_icons(refs.ingredients_bar, rt)
  return refs
end

-- One row of the queue.
function window.build_queue_item(container, rt, can_shift_up, can_shift_down)
  local function shift_button(direction, enabled)
    return {
      type = 'button',
      style = 'rq_tech_queue_item_shift_' .. direction .. '_button',
      tags = {rq = 'queue_shift', dir = direction, tech = rt.id},
      tooltip = enabled and {'factorio-research-queue.shift-' .. direction .. '-tooltip', rt.tech.localised_name} or nil,
      enabled = enabled,
      mouse_button_filter = {'left'},
    }
  end

  local refs = builder.build(container, {
    ref = 'item',
    type = 'frame',
    style = 'rq_tech_queue_item',
    direction = 'horizontal',
    children = {
      {
        type = 'flow',
        style = 'rq_tech_queue_item_inner_flow',
        direction = 'vertical',
        children = {
          {ref = 'button_container', type = 'flow'},
          {
            ref = 'etc_label',
            type = 'label',
            style = 'rq_etc_label',
            caption = '[img=quantity-time][img=infinity]',
          },
        },
      },
      {
        type = 'flow',
        style = 'rq_tech_queue_item_buttons',
        direction = 'vertical',
        children = {
          shift_button('up', can_shift_up),
          builder.pusher(),
          builder.tool_button{
            style = 'rq_tech_queue_item_close_button',
            tags = {rq = 'dequeue', tech = rt.id},
            sprite = 'utility/close',
            tooltip = {'factorio-research-queue.dequeue-tooltip', rt.tech.localised_name},
          },
          builder.pusher(),
          shift_button('down', can_shift_down),
        },
      },
    },
  })
  refs.tech_button = window.build_tech_button(refs.button_container, rt, 'tech_queue')
  return refs
end

---------------------------------------------------------------------------
-- Main frame (queue and technology list)
---------------------------------------------------------------------------

local function main_frame_definition()
  return {
    ref = 'main',
    type = 'frame',
    style = 'rq_main_window',
    direction = 'vertical',
    children = {
      {
        ref = 'titlebar',
        type = 'flow',
        children = {
          builder.frame_title{'factorio-research-queue.window-title'},
          builder.drag_handle(),
          {
            ref = 'search',
            type = 'textfield',
            tags = {rq = 'search'},
            clear_and_focus_on_right_click = true,
            tooltip = {'factorio-research-queue.search-tooltip'},
            style_mods = {width = 150},
          },
          builder.frame_action_button{ref = 'pause_button', tags = {rq = 'toggle_pause'}},
          builder.frame_action_button{
            style = 'rq_frame_action_button_red',
            tags = {rq = 'clear_queue'},
            sprite = 'utility/trash',
            hovered_sprite = 'utility/trash',
            clicked_sprite = 'utility/trash',
            tooltip = {'factorio-research-queue.clear-tooltip'},
          },
          builder.frame_action_button{
            tags = {rq = 'close_window'},
            sprite = 'utility/close',
            hovered_sprite = 'utility/close',
            clicked_sprite = 'utility/close',
            tooltip = {'factorio-research-queue.close-tooltip'},
          },
        },
      },
      {
        type = 'flow',
        style = 'horizontal_flow',
        direction = 'horizontal',
        style_mods = {horizontal_spacing = 12},
        children = {
          {
            type = 'flow',
            style = 'vertical_flow',
            direction = 'vertical',
            style_mods = {vertical_spacing = 8},
            children = {
              {
                type = 'frame',
                style = 'rq_tech_queue_head_frame',
                children = {
                  {
                    ref = 'pause_container',
                    type = 'flow',
                    style = 'rq_tech_queue_item_paused',
                    children = {
                      {
                        type = 'sprite-button',
                        style = 'rq_tech_queue_item_paused_unpause_button',
                        tags = {rq = 'toggle_pause'},
                        sprite = 'rq-play-black',
                        tooltip = {'factorio-research-queue.play-tooltip'},
                        mouse_button_filter = {'left'},
                      },
                    },
                  },
                  {ref = 'head_container', type = 'flow'},
                },
              },
              {
                ref = 'queue_list',
                type = 'scroll-pane',
                style = 'rq_tech_queue_list_box',
                vertical_scroll_policy = 'always',
                horizontal_scroll_policy = 'never',
              },
            },
          },
          {
            type = 'scroll-pane',
            style = 'rq_tech_list_list_box',
            vertical_scroll_policy = 'always',
            horizontal_scroll_policy = 'never',
            children = {
              {ref = 'tech_table', type = 'table', style = 'rq_tech_list_table', column_count = TECH_COLUMNS},
            },
          },
        },
      },
    },
  }
end

---------------------------------------------------------------------------
-- Filter frame (checkboxes and science pack filter)
---------------------------------------------------------------------------

local function filter_frame_definition()
  return {
    ref = 'filter',
    type = 'frame',
    style = 'rq_settings_window',
    direction = 'vertical',
    children = {
      {
        ref = 'filter_titlebar',
        type = 'flow',
        children = {
          builder.frame_title{'factorio-research-queue.filter-title'},
          builder.drag_handle(),
        },
      },
      {
        type = 'flow',
        style = 'vertical_flow',
        direction = 'vertical',
        style_mods = {vertical_spacing = 12},
        children = {
          {
            ref = 'researched_checkbox',
            type = 'checkbox',
            tags = {rq = 'filter_researched'},
            caption = {'factorio-research-queue.filter-researched'},
            state = false,
          },
          {
            ref = 'upgrades_checkbox',
            type = 'checkbox',
            tags = {rq = 'filter_upgrades'},
            caption = {'factorio-research-queue.filter-upgrades'},
            state = false,
          },
          {
            type = 'frame',
            style = 'rq_settings_section',
            direction = 'vertical',
            children = {
              {type = 'label', style = 'caption_label', caption = {'factorio-research-queue.filter-packs'}},
              {
                type = 'scroll-pane',
                style = 'rq_tech_ingredient_filter_scroll_pane',
                children = {{ref = 'pack_table', type = 'table', column_count = 4}},
              },
            },
          },
        },
      },
    },
  }
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------

-- Creates the whole window (hidden) and returns its references.
function window.build(player)
  local old = player.gui.screen['rq_window']
  if old then
    old.destroy()
  end

  local gui = builder.build(player.gui.screen, {
    ref = 'window',
    type = 'frame',
    name = 'rq_window',
    direction = 'horizontal',
    tags = {rq = 'close_window'},
    elem_mods = {visible = false},
    children = {main_frame_definition(), filter_frame_definition()},
  })
  gui.titlebar.drag_target = gui.window
  gui.filter_titlebar.drag_target = gui.window
  gui.window.force_auto_center()

  -- Science pack filter buttons
  gui.packs = collect_packs(player.force)
  gui.pack_buttons = {}
  for _, pack in ipairs(gui.packs) do
    gui.pack_buttons[pack] = builder.build(gui.pack_table, {
      ref = 'button',
      type = 'sprite-button',
      tags = {rq = 'filter_pack', pack = pack},
      sprite = 'item/' .. pack,
      mouse_button_filter = {'left'},
    }).button
  end

  -- Technology list: one row per visible technology (hidden ones are skipped)
  local techs = {}
  for _, tech in pairs(player.force.technologies) do
    if not tech.prototype.hidden then
      local rt = rqtech.get(tech)
      techs[#techs + 1] = {rt = rt, key = sort_key(rt, gui.packs)}
    end
  end
  table.sort(techs, function(a, b)
    return compare_keys(a.key, b.key)
  end)

  gui.items = {}
  gui.base_ids = {}
  gui.extra = {}
  gui.queue_items = {}
  for _, entry in ipairs(techs) do
    gui.items[entry.rt.id] = window.build_tech_item(gui.tech_table, entry.rt)
    gui.base_ids[#gui.base_ids + 1] = entry.rt.id
  end
  return gui
end

return window
