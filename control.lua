__rq_debug = false

local migrationlib = require('__flib__.migration')

local gui = require('scripts.gui.index')
local queue = require('scripts.queue')
local rqtech = require('scripts.rqtech')

local CURRENT_VERSION = script.active_mods[script.mod_name]

local migrations = {
  ['0.4.0'] = function()
    storage.forces = {}

    for _, player in pairs(game.players) do
      storage.players[player.index].queue = nil
      storage.players[player.index].queue_paused = nil
    end
  end,
  ['0.4.17'] = function()
    if storage.__flib ~= nil then
      storage.__flib.gui = nil
    end
  end,
}

local queue_saves = {
  {
    version = '0.3.3',
    save = function(force)
      for _, player in pairs(force.players) do
        if storage.players[player.index] == nil then return end
        local player_data = storage.players[player.index]
        local tech_ids = {}
        for _, tech in ipairs(player_data.queue) do
          if tech.valid then
            table.insert(tech_ids, tech.name)
          end
        end
        local paused = player_data.queue_paused
        return tech_ids, paused
      end
    end,
  },
  {
    version = '0.4.10',
    save = function(force)
      if storage.forces[force.index] == nil then return end
      local force_data = storage.forces[force.index]
      local tech_ids = {}
      for _, tech in ipairs(force_data.queue) do
        if tech.valid then
          table.insert(tech_ids, tech.name)
        end
      end
      local paused = force_data.queue_paused
      return tech_ids, paused
    end,
  },
}

function lookup_queue_save(version)
  log('looking up queue save fn for v'..version)
  for _, qs in ipairs(queue_saves) do
    if
      qs.version == version or
      migrationlib.is_newer_version(version, qs.version)
    then
      log('using queue save fn v'..qs.version)
      return qs.save
    end
  end
  log('using current queue save fn')
  return function(force)
    if storage.forces[force.index] == nil then return end
    local tech_ids = {}
    for tech in queue.iter(force) do
      if tech.tech.valid then
        table.insert(tech_ids, tech.id)
      end
    end
    local paused = queue.is_paused(force)
    return tech_ids, paused
  end
end

function init_player(player)
  storage.players[player.index] = {}

  gui.actions.init(player)
end

function deinit_player(player)
  gui.actions.deinit(player)
  storage.players[player.index] = nil
end

function init_force(force, saved_queue, queue_paused)
  if storage.forces[force.index] ~= nil then return end

  rqtech.init_force(force)

  storage.forces[force.index] = {}

  if saved_queue == nil then saved_queue = {} end
  if queue_paused == nil then queue_paused = true end

  queue.new(force, queue_paused)
  for _, tech_id in ipairs(saved_queue) do
    local tech = rqtech.from_id(force, tech_id)
    if tech ~= nil then
      queue.enqueue(force, tech)
    end
  end
end

function deinit_force(force)
  rqtech.deinit_force(force)
  storage.forces[force.index] = nil
end

script.on_init(function()
  rqtech.init()

  storage.forces = {}
  for _, force in pairs(game.forces) do
    init_force(force)
  end

  storage.players = {}
  for _, player in pairs(game.players) do
    init_player(player)
  end
end)

script.on_load(function()
end)

script.on_configuration_changed(function(event)
  local saved_queues = {}
  local saved_queue_paused = {}

  local function save_queues(old_version)
    local version = old_version or CURRENT_VERSION
    local queue_save = lookup_queue_save(version)

    for _, force in pairs(game.forces) do
      log('saving queue for '..force.name)
      local saved_queue, paused = queue_save(force)
      log('saved queue for '..force.name..': '..serpent.line({ queue = saved_queue, paused = paused }))
      saved_queues[force.index] = saved_queue
      saved_queue_paused[force.index] = paused
    end
  end

  local init = true
  local changes = event.mod_changes[script.mod_name]
  if changes then
    local old_version = changes.old_version
    if old_version then
      save_queues(old_version)
      migrationlib.run(old_version, migrations)
    else
      save_queues()
      init = false
    end
  else
    save_queues()
  end

  rqtech.init()

  for _, force in pairs(game.forces) do
    deinit_force(force)
    init_force(
      force,
      saved_queues[force.index],
      saved_queue_paused[force.index])
  end

  for _, player in pairs(game.players) do
    deinit_player(player)
    init_player(player)
  end
end)

script.on_event(defines.events.on_force_created, function(event)
  local force = event.force
  init_force(force)
end)

script.on_event(defines.events.on_forces_merging, function(event)
  local force = event.source
  deinit_force(force)
end)

script.on_event(defines.events.on_force_reset, function(event)
  local force = event.force
  deinit_force(force)
  init_force(force)
  for _, player in pairs(force.players) do
    if storage.players[player.index] ~= nil then
      gui.actions.update_all(player)
    end
  end
end)

script.on_event(defines.events.on_player_created, function(event)
  local player = game.players[event.player_index]
  init_player(player)
end)

script.on_event(defines.events.on_pre_player_removed, function(event)
  local player = game.players[event.player_index]
  deinit_player(player)
end)

script.on_event(defines.events.on_player_changed_force, function(event)
  local player = game.players[event.player_index]
  if player ~= nil then
    gui.actions.update_all(player)
  end
end)

script.on_event(defines.events.on_player_display_scale_changed, function(event)
  local player = game.players[event.player_index]
  gui.actions.update_tech_list_ingredients(player)
end)

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name == 'factorio-research-queue' then
    local player = game.players[event.player_index]
    if player.is_shortcut_toggled('factorio-research-queue') then
      gui.actions.close_window(player)
    else
      gui.actions.open_window(player)
    end
  end
end)

script.on_event('rq-toggle-main-window', function(event)
  local player = game.players[event.player_index]
  if storage.players[player.index] ~= nil then
    gui.actions.toggle_window(player)
  end
end)

script.on_event('rq-focus-search', function(event)
  local player = game.players[event.player_index]
  if storage.players[player.index] ~= nil then
    gui.actions.focus_search(player)
  end
end)

script.on_event(defines.events.on_research_started, function(event)
  local force = event.research.force
  if storage.forces[force.index] ~= nil then
    gui.actions.on_research_started(force, event.research)
  end
end)

script.on_event(defines.events.on_research_finished, function(event)
  local force = event.research.force
  if storage.forces[force.index] ~= nil then
    gui.actions.on_research_finished(force, event.research)
  end
end)

-- GUI event handling
local GUI_EVENTS = {
  defines.events.on_gui_click,
  defines.events.on_gui_text_changed,
  defines.events.on_gui_checked_state_changed,
  defines.events.on_gui_elem_changed,
  defines.events.on_gui_value_changed,
  defines.events.on_gui_selection_state_changed,
  defines.events.on_gui_closed,
  defines.events.on_gui_opened,
}

local GUI_EVENT_TAG_KEYS = {
  [defines.events.on_gui_click]                   = 'on_click',
  [defines.events.on_gui_checked_state_changed]   = 'on_checked_state_changed',
  [defines.events.on_gui_text_changed]             = 'on_text_changed',
  [defines.events.on_gui_elem_changed]             = 'on_elem_changed',
  [defines.events.on_gui_value_changed]            = 'on_value_changed',
  [defines.events.on_gui_selection_state_changed]  = 'on_selection_state_changed',
  [defines.events.on_gui_closed]                   = 'on_closed',
  [defines.events.on_gui_opened]                   = 'on_opened',
}

local function on_gui_event(event)
  local player = game.players[event.player_index]
  if storage.players[player.index] ~= nil then
    local action
    if event.element and event.element.valid then
      local tags = event.element.tags
      if tags then
        local key = GUI_EVENT_TAG_KEYS[event.name]
        action = key and tags[key]
      end
    end
    if action then
      gui.handle_event(player, action, event)
    elseif
      event.name == defines.events.on_gui_opened and
      event.gui_type == defines.gui_type.research
    then
      gui.actions.on_technology_gui_opened(player)
    elseif
      event.name == defines.events.on_gui_closed and
      event.gui_type == defines.gui_type.research
    then
      gui.actions.on_technology_gui_closed(player)
    end
  end
end

script.on_event(GUI_EVENTS, on_gui_event)

local research_speed_period = 60
local research_progress_sample_count = 3
local research_progress_samples_by_force = {}

script.on_nth_tick(research_speed_period, function(event)
  for _, force in pairs(game.forces) do
    local tech = force.current_research
    local speed_estimate = 0
    if tech ~= nil then
      local progress_samples = research_progress_samples_by_force[force.index]
      if progress_samples == nil then
        progress_samples = {}
        research_progress_samples_by_force[force.index] = progress_samples
      end
      table.insert(progress_samples, {
        tech = tech,
        progress = force.research_progress,
      })
      if #progress_samples > 1+research_progress_sample_count then
        table.remove(progress_samples, 1)
      end
      if #progress_samples > 1 then
        local num_samples = 0
        for i = 2,#progress_samples do
          local prev_sample = progress_samples[i-1]
          local curr_sample = progress_samples[i]
          if prev_sample.tech.name == curr_sample.tech.name then
            local t = prev_sample.tech
            local diff = curr_sample.progress - prev_sample.progress
            speed_estimate = speed_estimate + diff /
              (research_speed_period/60) *
              ((t.research_unit_energy or 0)/60) *
              (t.research_unit_count or 0)
            num_samples = num_samples + 1
          end
        end
        if num_samples > 0 then
          speed_estimate = speed_estimate / num_samples
        end
      end
    end
    gui.actions.on_research_speed_estimate(force, speed_estimate)
  end
end)
