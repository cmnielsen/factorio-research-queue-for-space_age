local rqtech = require('scripts.rqtech')
local queue = require('scripts.queue')
local util = require('scripts.util')

local main_gui = require('.main')
local settings_gui = require('.settings')
local tech_button = require('.tech_button')
local templates = require('.templates')
local gui_util = require('.gui_util')
local build_gui = gui_util.build_gui

local actions = {}

function actions.init(player)
  local force = player.force
  local player_data = storage.players[player.index]

  local tech_ingredients = {}
  for _, item in pairs(prototypes.get_item_filtered{{filter='tool'}}) do
    local is_tech_ingredient = (function()
      for _, tech in pairs(force.technologies) do
        if tech.enabled then
          for _, ingredient in pairs(tech.research_unit_ingredients or {}) do
            if (ingredient.type == nil or ingredient.type == 'item') and ingredient.name == item.name then
              return true
            end
          end
        end
      end
      return false
    end)()
    if is_tech_ingredient then
      table.insert(tech_ingredients, item)
    end
  end
  table.sort(tech_ingredients, function(a, b) return a.order < b.order end)
  player_data.tech_ingredients = tech_ingredients

  local filter_data = {
    researched = false,
    upgrades = false,
    ingredients = {},
    search_terms = {},
  }
  player_data.filter = filter_data

  local gui_data = build_gui(player.gui.screen, {
    ref = 'window',
    type = 'frame',
    tags = {
      on_closed = 'close_window',
    },
    elem_mods = {
      visible = false,
    },
  })
  gui_data.window.force_auto_center()

  gui_data.main = main_gui.build(player, gui_data.window)
  gui_data.settings = settings_gui.build(player, gui_data.window)

  player_data.gui = gui_data

  actions.auto_select_tech_ingredients(player)
  actions.update_techs(player)
  actions.update_queue(player)
end

function actions.deinit(player)
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui

  gui_data.window.destroy()

  player_data.gui = nil
end

function actions.open_window(player)
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui

  if not gui_data.window.valid then
    actions.init(player)
    gui_data = player_data.gui
  end

  gui_data.window.visible = true
  player.opened = gui_data.window
  player.set_shortcut_toggled('factorio-research-queue', true)
  if gui_data.main.search.visible then
    gui_data.main.search.focus()
    gui_data.main.search.select_all()
  end
  if util.can_pause_game(player) then
    game.tick_paused = true
  end

  actions.update_search(player)
  actions.update_queue(player)
  actions.update_techs(player)
end

function actions.close_window(player)
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui

  if gui_data.window.valid then
    gui_data.window.visible = false
    if player.opened == gui_data.window then
      player.opened = nil
    end
    player_data.closed_tick = game.tick
    if util.can_pause_game(player) then
      game.tick_paused = false
    end
  end
  player.set_shortcut_toggled('factorio-research-queue', false)
end

function actions.toggle_window(player)
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui

  if gui_data.window.valid and gui_data.window.visible then
    actions.close_window(player)
  else
    actions.open_window(player)
  end
end

function actions.update_all(player)
  actions.update_queue(player)
  actions.update_techs(player)
  actions.update_progressbars(player)
end

function actions.update_techs(player)
  local force = player.force
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui
  local filter_data = player_data.filter
  local tech_ingredients = player_data.tech_ingredients

  if not gui_data.window.valid then return end

  gui_data.settings.researched_techs_checkbox.state = filter_data.researched
  gui_data.settings.upgrade_techs_checkbox.state = filter_data.upgrades
  for _, tech_ingredient in ipairs(tech_ingredients) do
    local button = gui_data.settings.tech_ingredient_filter.items[tech_ingredient.name].button
    local enabled = filter_data.ingredients[tech_ingredient.name]
    button.style = 'rq_tech_ingredient_filter_button_'..(enabled and 'enabled' or 'disabled')
    button.tooltip = {
      'factorio-research-queue.tech-ingredient-filter-button-'..(enabled and 'enabled' or 'disabled'),
      tech_ingredient.localised_name,
    }
  end

  local function is_tech_visible(tech)
    if tech.tech.prototype.hidden or not tech.tech.enabled then
      return false
    end

    if not filter_data.researched and rqtech.is_researched(tech) then
      return false
    end

    if tech.tech.upgrade or tech.infinite then
      local has_significant_dependency = (function()
        for _, dependency in pairs(tech.prerequisites) do
          local is_significant_dependency = (function()
            if #tech.prerequisites == 0 and tech.level and tech.level < 2 then
              return true
            end

            if not (dependency.tech.upgrade or dependency.infinite) then
              return true
            end

            if tech.upgrade_group ~= dependency.upgrade_group then
              return true
            end

            if rqtech.is_researched(dependency) then
              return true
            end

            if queue.in_queue(force, dependency) then
              return true
            end

            return false
          end)()
          if is_significant_dependency then return true end
        end
        return false
      end)()
      if not has_significant_dependency then
        if not filter_data.upgrades then
          return false
        end

        if tech.infinite then
          return false
        end
      end
    end

    local ingredients_filter = filter_data.ingredients
    for _, ingredient in pairs(tech.tech.research_unit_ingredients or {}) do
      if not ingredients_filter[ingredient.name] then
        return false
      end
    end

    local search_terms = filter_data.search_terms
    local search_matches = (function()
      if #search_terms == 0 then
        return true
      end

      local function try_localise(str)
        local ok, result = pcall(function() return helpers.localise_string(str) end)
        if ok and type(result) == 'string' then
          return result
        elseif type(str) == 'string' then
          return str
        end
        return tech.tech.name
      end
      local tech_name = try_localise(tech.tech.localised_name)
      local tech_desc = try_localise(tech.tech.localised_description)

      if util.fuzzy_search(tech_name, search_terms) then
        return true
      end
      if util.fuzzy_search(tech_desc, search_terms) then
        return true
      end

      return false
    end)()
    if not search_matches then
      return false
    end

    return true
  end

  local function update_item(item_gui_data, tech)
    local researchable = queue.is_researchable(force, tech)
    local queued = queue.in_queue(force, tech)
    local queued_head = not queue.is_paused(force) and queue.is_head(force, tech)
    local researched = rqtech.is_researched(tech)
    local available = (function()
      for _, prereq in pairs(tech.prerequisites) do
        if not rqtech.is_researched(prereq) then
          return false
        end
      end
      return true
    end)()
    local style_prefix =
      'rq_tech_list_item' ..
        (queued_head and '_queued_head' or
        queued and '_queued' or
        researched and '_researched' or
        available and '_available' or
        '_unavailable')

    item_gui_data.ingredients_bar.style = style_prefix..'_ingredients_bar'
    item_gui_data.tool_bar.style = style_prefix..'_tool_bar'
    for _, button in pairs(item_gui_data.tool_bar.children) do
      button.enabled = researchable
    end
    actions.update_tech_button(
      player,
      item_gui_data.tech_button,
      tech,
      style_prefix..'_tech_button')
  end

  local items_gui_data = gui_data.main.techs.items
  local upgrade_items_gui_data = gui_data.main.techs.upgrade_items or {}

  for tech_id, item_gui_data in pairs(upgrade_items_gui_data) do
    item_gui_data.item.destroy()
    items_gui_data[tech_id] = nil
  end
  upgrade_items_gui_data = {}
  gui_data.main.techs.upgrade_items = upgrade_items_gui_data

  for tech in rqtech.iter(force) do
    if not tech.tech.prototype.hidden then
      local item_gui_data = items_gui_data[tech.id]

      local visible = is_tech_visible(tech)
      if visible then
        update_item(item_gui_data, tech)
        item_gui_data.item.visible = true
      else
        item_gui_data.item.visible = false
      end

      local index = item_gui_data.item.get_index_in_parent() + 1

      while true do
        if
          not (visible or rqtech.is_researched(tech)) or
          not tech.infinite or
          tech.level + 1 > tech.tech.prototype.max_level
        then
          break
        end
        local next_level_tech = rqtech.new(tech.tech, tech.level + 1)
        tech = next_level_tech
        visible = is_tech_visible(tech)
        if visible then
          local item_gui_data = main_gui.build_tech_item(
            player,
            gui_data.main.techs.table,
            tech,
            index)

          update_item(item_gui_data, tech)

          index = item_gui_data.item.get_index_in_parent() + 1

          items_gui_data[tech.id] = item_gui_data
          upgrade_items_gui_data[tech.id] = item_gui_data
        end
      end
    end
  end
end

function actions.update_tech_list_ingredients(player)
  local force = player.force
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui
  local items_gui_data = gui_data.main.techs.items
  for tech_id, item_gui_data in pairs(items_gui_data) do
    local tech = rqtech.from_id(force, tech_id)
    item_gui_data.ingredients_bar.clear()
    item_gui_data.ingredients_bar_flow = main_gui.build_tech_item_ingredients_flow(
      player,
      item_gui_data.ingredients_bar,
      tech)
  end
end

function actions.update_queue(player, new_tech)
  local force = player.force
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui

  local is_head = true
  do
    local queue_pause_toggle_button = gui_data.main.queue_pause_toggle_button
    local pause_button_container = gui_data.main.queue.pause_button_container
    local head_item_container = gui_data.main.queue.head_item_container
    if queue.is_paused(force) then
      queue_pause_toggle_button.style = 'rq_frame_action_button_green'
      queue_pause_toggle_button.sprite = 'rq-play-white'
      queue_pause_toggle_button.hovered_sprite = 'rq-play-black'
      queue_pause_toggle_button.clicked_sprite = 'rq-play-black'
      queue_pause_toggle_button.tooltip = {'factorio-research-queue.queue-play-button-tooltip'}

      pause_button_container.visible = true
      head_item_container.visible = false

      is_head = false
    else
      queue_pause_toggle_button.style = 'rq_frame_action_button_red'
      queue_pause_toggle_button.sprite = 'rq-pause-white'
      queue_pause_toggle_button.hovered_sprite = 'rq-pause-black'
      queue_pause_toggle_button.clicked_sprite = 'rq-pause-black'
      queue_pause_toggle_button.tooltip = {'factorio-research-queue.queue-pause-button-tooltip'}

      pause_button_container.visible = false
      head_item_container.visible = true
    end
  end

  gui_data.main.queue.head_item_container.clear()
  gui_data.main.queue.list.clear()
  local new_tech_element = nil
  local items_gui_data = {}
  for tech in queue.iter(force) do
    local shift_up_enabled = queue.can_shift_earlier(force, tech)
    local shift_down_enabled = queue.can_shift_later(force, tech)
    local container = gui_data.main.queue[is_head and 'head_item_container' or 'list']
    local item_gui_data = build_gui(container, {
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
            {
              ref = 'tech_button_container',
              type = 'flow',
            },
            {
              ref = 'etc_label',
              type = 'label',
              style = 'rq_etc_label',
              caption = '[img=quantity-time][img=infinity]',
              tooltip = {'factorio-research-queue.etc-label-tooltip'},
            },
          },
        },
        {
          type = 'flow',
          style = 'rq_tech_queue_item_buttons',
          direction = 'vertical',
          children = {
            {
              type = 'button',
              style = 'rq_tech_queue_item_shift_up_button',
              tags = {
                on_click = { type = 'queue_shift', dir = 'up', tech = tech.id },
              },
              tooltip =
                shift_up_enabled and
                  {'factorio-research-queue.shift-up-button-tooltip', tech.tech.localised_name} or
                  nil,
              enabled = shift_up_enabled,
              mouse_button_filter = {'left'},
            },
            {
              type = 'empty-widget',
              style = 'flib_vertical_pusher',
            },
            templates.tool_button{
              style = 'rq_tech_queue_item_close_button',
              tags = {
                on_click = { type = 'dequeue', tech = tech.id },
              },
              sprite = 'utility/close',
              tooltip = {'factorio-research-queue.dequeue-button-tooltip', tech.tech.localised_name},
            },
            {
              type = 'empty-widget',
              style = 'flib_vertical_pusher',
            },
            {
              type = 'button',
              style = 'rq_tech_queue_item_shift_down_button',
              tags = {
                on_click = { type = 'queue_shift', dir = 'down', tech = tech.id },
              },
              tooltip =
                shift_down_enabled and
                  {'factorio-research-queue.shift-down-button-tooltip', tech.tech.localised_name} or
                  nil,
              enabled = shift_down_enabled,
              mouse_button_filter = {'left'},
            },
          },
        },
      },
    })

    local tech_button_gui_data = tech_button.build(
      player,
      item_gui_data.tech_button_container,
      tech,
      'tech_queue')
    actions.update_tech_button(
      player,
      tech_button_gui_data,
      tech,
      'rq_tech_queue'..(is_head and '_head' or '')..'_item_tech_button')
    item_gui_data.tech_button = tech_button_gui_data

    items_gui_data[tech.id] = item_gui_data

    if new_tech ~= nil and new_tech.id == tech.id then
      if is_head then
        new_tech_element = 'head'
      else
        new_tech_element = item_gui_data.item
      end
    end

    is_head = false
  end
  gui_data.main.queue.items = items_gui_data

  if new_tech_element ~= nil then
    if new_tech_element == 'head' then
      gui_data.main.queue.list.scroll_to_top()
    else
      gui_data.main.queue.list.scroll_to_element(new_tech_element, 'top-third')
    end
  end

  actions.update_etcs(player)
end

function actions.update_etcs(player)
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui
  local force = player.force

  if not gui_data.window.valid then return end

  local speed = player_data.last_research_speed_estimate or 0
  local etc = 0
  local tech_ingredient_totals = {}
  for tech in queue.iter(force) do
    local etc_label = gui_data.main.queue.items[tech.id].etc_label
    local research_unit_energy = tech.tech.research_unit_energy or 0
    local research_unit_count = tech.research_unit_count or 0

    local progress = rqtech.progress(tech)

    local etc_text = ''
    if speed == 0 then
      etc_text = etc_text..'[img=infinity]'
    else
      etc = etc +
        (1-progress) *
        (research_unit_energy/60) *
        research_unit_count /
        speed
      etc_text = etc_text..util.format_duration(etc)
    end
    etc_label.caption = etc_text

    for _, ingredient in ipairs(tech.tech.research_unit_ingredients or {}) do
      tech_ingredient_totals[ingredient.name] =
        (tech_ingredient_totals[ingredient.name] or 0) +
        (1-progress) *
        tech.research_unit_count *
        ingredient.amount
    end

    local tech_ingredient_totals_text = '[font=count-font]'
    for _, ingredient in ipairs(player_data.tech_ingredients) do
      local amount = tech_ingredient_totals[ingredient.name]
      if amount ~= nil and amount ~= 0 then
        tech_ingredient_totals_text = tech_ingredient_totals_text ..
          string.format(
            '[img=%s/%s]%d ',
            'item',
            ingredient.name,
            amount)
      end
    end
    tech_ingredient_totals_text = tech_ingredient_totals_text..'[/font]'
    etc_label.tooltip = {'',
      {'factorio-research-queue.etc-label-tooltip', etc_text},
      '\n',
      {'factorio-research-queue.tech-ingredient-totals-tooltip',
        tech_ingredient_totals_text}}
  end
end

function actions.update_progressbars(player)
  local force = player.force
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui

  for tech_id, item_gui_data in pairs(gui_data.main.techs.items) do
    local tech = rqtech.from_id(force, tech_id)

    if item_gui_data.item.visible then
      actions.update_tech_button_progressbar(
        player,
        item_gui_data.tech_button,
        tech)
    end
  end

  for tech_id, item_gui_data in pairs(gui_data.main.queue.items or {}) do
    local tech = rqtech.from_id(force, tech_id)
    actions.update_tech_button_progressbar(
      player,
      item_gui_data.tech_button,
      tech)
  end
end

function actions.update_tech_button(player, gui_data, tech, style)
  gui_data.button.style = style
  tech_button.update_tech_button_tooltip(player, gui_data, tech)
  actions.update_tech_button_progressbar(player, gui_data, tech)
end

function actions.update_tech_button_progressbar(player, gui_data, tech)
  local researched = rqtech.is_researched(tech)
  local progress
  if researched then
    progress = 0
  else
    progress = rqtech.progress(tech)
  end

  gui_data.progressbar.value = progress
  gui_data.progressbar.visible = progress > 0
end

function actions.update_search(player)
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui
  local filter_data = player_data.filter

  if not gui_data.window.valid then return end

  local search_text = gui_data.main.search.text
  filter_data.search_terms = util.prepare_search_terms(search_text)
end

function actions.focus_search(player)
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui

  if not gui_data.window.valid then return end

  if gui_data.window.visible then
    local search = gui_data.main.search
    local search_toggle_button = gui_data.main.search_toggle_button
    if not search.visible then
      search_toggle_button.style = 'flib_selected_frame_action_button'
      search.visible = true
    end
    search.focus()
    search.select_all()
  end
end

function actions.toggle_search(player)
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui

  if not gui_data.window.valid then return end

  if gui_data.window.visible then
    local search = gui_data.main.search
    local search_toggle_button = gui_data.main.search_toggle_button
    if not search.visible then
      search_toggle_button.style = 'flib_selected_frame_action_button'
      search.visible = true
      search.focus()
      search.select_all()
    else
      search_toggle_button.style = 'frame_action_button'
      search.visible = false
      search.text = ''
      actions.update_search(player)
      actions.update_techs(player)
    end
  end
end

function actions.set_researched_filter(player, state)
  local player_data = storage.players[player.index]
  local filter_data = player_data.filter

  filter_data.researched = state
end

function actions.set_upgrades_filter(player, state)
  local player_data = storage.players[player.index]
  local filter_data = player_data.filter

  filter_data.upgrades = state
end

function actions.auto_select_tech_ingredients(player)
  local force = player.force
  local player_data = storage.players[player.index]
  local filter_data = player_data.filter
  local tech_ingredients = player_data.tech_ingredients

  for _, tech_ingredient in ipairs(tech_ingredients) do
    filter_data.ingredients[tech_ingredient.name] =
      util.is_item_available(force, tech_ingredient.name)
  end
end

function actions.toggle_tech_ingredient_filter(player, tech_ingredient)
  local player_data = storage.players[player.index]
  local filter_data = player_data.filter

  local enabled = filter_data.ingredients[tech_ingredient.name]
  filter_data.ingredients[tech_ingredient.name] = not enabled
end

function actions.on_technology_gui_opened(player)
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui

  if gui_data.window.valid and player_data.closed_tick == game.tick then
    gui_data.window.visible = true
  end
end

function actions.on_technology_gui_closed(player)
  local force = player.force
  local player_data = storage.players[player.index]
  local gui_data = player_data.gui

  if gui_data.window.valid and gui_data.window.visible then
    player.opened = gui_data.window
  end

  queue.update(force, 3)
  for _, p in pairs(force.players) do
    if storage.players[p.index] ~= nil then
      actions.update_queue(p)
      actions.update_techs(p)
    end
  end
end

function actions.on_research_started(force, research)
  queue.update(force, 2)
  for _, player in pairs(force.players) do
    if storage.players[player.index] ~= nil then
      actions.update_queue(player)
      actions.update_techs(player)
      actions.update_progressbars(player)
    end
  end
end

function actions.on_research_finished(force, research)
  rqtech.init_force(force)
  queue.update(force, 1)
  for _, player in pairs(force.players) do
    if storage.players[player.index] ~= nil then
      actions.update_queue(player)
      actions.update_techs(player)
    end
  end
end

function actions.on_research_speed_estimate(force, speed_estimate)
  for _, player in pairs(force.players) do
    if storage.players[player.index] ~= nil then
      local player_data = storage.players[player.index]
      player_data.last_research_speed_estimate = speed_estimate
      if player_data.gui.window.valid and player_data.gui.window.visible then
        actions.update_etcs(player)
      end
    end
  end
end

-- No-op in Factorio 2.0: translations are synchronous via helpers.localise_string
function actions.register_translation_handler()
end

return actions
