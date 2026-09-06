local rqtech = require('scripts.rqtech')
local util = require('scripts.util')
local tech_button = require('.tech_button')
local templates = require('.templates')
local gui_util = require('.gui_util')
local build_gui = gui_util.build_gui

local function build(player, window)
  local force = player.force
  local player_data = storage.players[player.index]
  local tech_ingredients = player_data.tech_ingredients

  local refs = build_gui(window, {
    type = 'frame',
    style = 'rq_settings_window',
    direction = 'vertical',
    children = {
      {
        ref = 'titlebar',
        type = 'flow',
        children = {
          templates.frame_title{'factorio-research-queue.settings-title'},
          templates.titlebar_drag_handle(),
        },
      },
      {
        type = 'flow',
        style = 'vertical_flow',
        style_mods = {
          vertical_spacing = 12,
        },
        direction = 'vertical',
        children = {
          {
            ref = 'researched_techs_checkbox',
            type = 'checkbox',
             tags = {
               on_checked_state_changed = 'set_researched_filter',
             },
            caption = {'factorio-research-queue.researched-techs-checkbox'},
            state = false,
          },
          {
            ref = 'upgrade_techs_checkbox',
            type = 'checkbox',
             tags = {
               on_checked_state_changed = 'set_upgrades_filter',
             },
            caption = {'factorio-research-queue.upgrade-techs-checkbox'},
            state = false,
          },
          {
            type = 'frame',
            style = 'rq_settings_section',
            direction = 'vertical',
            children = {
              {
                type = 'label',
                style = 'caption_label',
                caption = {'factorio-research-queue.tech-ingredient-filter-table'},
              },
              {
                type = 'scroll-pane',
                style = 'rq_tech_ingredient_filter_table_scroll_box',
                children = {
                  {
                    ref = 'tech_ingredient_filter_table',
                    type = 'table',
                    column_count = 4,
                  },
                },
              },
            },
          },
        },
      },
    },
  })

  refs.tech_ingredient_filter = {
    table = refs.tech_ingredient_filter_table,
  }

  local items_gui_data = {}
  for _, tech_ingredient in ipairs(tech_ingredients) do
    local item_refs = build_gui(refs.tech_ingredient_filter.table, {
      ref = 'button',
      type = 'sprite-button',
      tags = {
        on_click = { type = 'toggle_tech_ingredient_filter', tech_ingredient = tech_ingredient.name },
      },
      sprite = string.format('%s/%s', 'item', tech_ingredient.name),
      mouse_button_filter = {'left'},
    })
    items_gui_data[tech_ingredient.name] = item_refs
  end
  refs.tech_ingredient_filter.items = items_gui_data

  refs.titlebar.drag_target = window

  return refs
end

return {
  build = build,
}
