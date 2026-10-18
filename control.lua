-- Extended Research Queue: event wiring, setup and migration.
-- The logic lives in scripts/ (queue, rqtech, speed, search) and scripts/gui/.

local queue = require('scripts.queue')
local rqtech = require('scripts.rqtech')
local search = require('scripts.search')
local speed = require('scripts.speed')
local controller = require('scripts.gui.controller')

local SHORTCUT = 'factorio-research-queue'

---------------------------------------------------------------------------
-- Setup and migration
---------------------------------------------------------------------------

local function is_older_version(version, than)
  local function parts(text)
    local list = {}
    for number in string.gmatch(text, '%d+') do
      list[#list + 1] = tonumber(number)
    end
    return list
  end
  local a, b = parts(version), parts(than)
  for i = 1, math.max(#a, #b) do
    local x, y = a[i] or 0, b[i] or 0
    if x ~= y then
      return x < y
    end
  end
  return false
end

-- Makes sure data exists for every force and player and drops all windows so
-- they are rebuilt with current data the next time they are opened.
local function setup()
  storage.forces = storage.forces or {}
  storage.players = storage.players or {}
  rqtech.reset_cache()

  for _, force in pairs(game.forces) do
    if queue.has_force(force) then
      queue.pull(force)
      queue.normalize(force)
      queue.push(force)
    else
      queue.init_force(force)
    end
  end

  for _, player in pairs(game.players) do
    if not storage.players[player.index] then
      storage.players[player.index] = controller.new_player_data()
    end
    controller.destroy(player)
    search.invalidate(storage.players[player.index])
  end
end

script.on_init(setup)

script.on_configuration_changed(function(event)
  local change = event.mod_changes and event.mod_changes[script.mod_name]
  if change and change.old_version and is_older_version(change.old_version, '1.0.0') then
    -- Saves from versions before 1.0.0 stored data in another format; start over
    storage.forces = nil
    storage.players = nil
    storage.rqtechs = nil
  end
  setup()
end)

---------------------------------------------------------------------------
-- Forces and players
---------------------------------------------------------------------------

script.on_event(defines.events.on_force_created, function(event)
  queue.init_force(event.force)
end)

script.on_event(defines.events.on_forces_merging, function(event)
  queue.remove_force(event.source.index)
end)

script.on_event(defines.events.on_force_reset, function(event)
  queue.init_force(event.force)
  controller.refresh_force(event.force)
end)

script.on_event(defines.events.on_player_created, function(event)
  storage.players[event.player_index] = controller.new_player_data()
end)

script.on_event(defines.events.on_player_removed, function(event)
  storage.players[event.player_index] = nil
end)

script.on_event(defines.events.on_player_changed_force, function(event)
  controller.refresh_player(game.get_player(event.player_index))
end)

script.on_event(defines.events.on_player_joined_game, function(event)
  local pdata = storage.players[event.player_index]
  if pdata then
    search.invalidate(pdata)
  end
end)

script.on_event(defines.events.on_string_translated, search.on_string_translated)

---------------------------------------------------------------------------
-- Opening the window
---------------------------------------------------------------------------

script.on_event(defines.events.on_lua_shortcut, function(event)
  if event.prototype_name == SHORTCUT then
    controller.toggle(game.get_player(event.player_index))
  end
end)

script.on_event('rq-toggle-main-window', function(event)
  controller.toggle(game.get_player(event.player_index))
end)

script.on_event('rq-focus-search', function(event)
  controller.focus_search(game.get_player(event.player_index))
end)

---------------------------------------------------------------------------
-- GUI events
---------------------------------------------------------------------------

script.on_event({
  defines.events.on_gui_click,
  defines.events.on_gui_text_changed,
  defines.events.on_gui_checked_state_changed,
}, controller.on_gui_event)

script.on_event(defines.events.on_gui_opened, controller.on_gui_opened)

script.on_event(defines.events.on_gui_closed, function(event)
  if not controller.on_gui_closed(event) then
    controller.on_gui_event(event)
  end
end)

---------------------------------------------------------------------------
-- Research events
---------------------------------------------------------------------------

local function force_of(event)
  if event.force then
    return event.force
  end
  local research = event.research
  if research and research.object_name == 'LuaTechnology' then
    return research.force
  end
  return nil
end

-- A player changed the vanilla research queue (or research started): adopt it.
local function on_vanilla_queue_changed(event)
  local force = force_of(event)
  local forces = force and {force} or game.forces
  for _, candidate in pairs(forces) do
    if queue.has_force(candidate) and queue.sync(candidate) then
      controller.refresh_force(candidate)
    end
  end
end

script.on_event({
  defines.events.on_research_started,
  defines.events.on_research_queued,
  defines.events.on_research_cancelled,
  defines.events.on_research_moved,
}, on_vanilla_queue_changed)

-- A technology was completed (or its research reversed): drop it from the
-- queue and refill the vanilla queue.
local function on_research_state_changed(event)
  local force = force_of(event)
  if not (force and queue.has_force(force)) then return end
  queue.pull(force)
  queue.normalize(force)
  queue.push(force)
  controller.refresh_force(force, nil, true)
end

script.on_event({
  defines.events.on_research_finished,
  defines.events.on_research_reversed,
}, on_research_state_changed)

---------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if event.setting ~= 'rq-mirror-vanilla-queue' then return end
  for _, force in pairs(game.forces) do
    if queue.has_force(force) then
      storage.forces[force.index].mirrored = {}
      queue.pull(force)
      queue.normalize(force)
      queue.push(force)
      controller.refresh_force(force)
    end
  end
end)

---------------------------------------------------------------------------
-- Once a second: research speed estimate and open windows
---------------------------------------------------------------------------

script.on_nth_tick(60, function()
  for _, force in pairs(game.forces) do
    if queue.has_force(force) then
      speed.sample(force)
    end
  end
  controller.on_tick()
end)
