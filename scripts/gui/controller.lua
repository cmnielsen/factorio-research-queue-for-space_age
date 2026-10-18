-- Opening and closing the window, and handling GUI events.

local queue = require('scripts.queue')
local rqtech = require('scripts.rqtech')
local search = require('scripts.search')
local util = require('scripts.util')
local window = require('scripts.gui.window')
local update = require('scripts.gui.update')

local controller = {}

local SHORTCUT = 'factorio-research-queue'
local MAX_WINDOW_HEIGHT = 770

---------------------------------------------------------------------------
-- Player data
---------------------------------------------------------------------------

function controller.new_player_data()
  return {
    filter = {researched = false, upgrades = false, ingredients = {}, manual = {}},
    terms = {},   -- search words
    names = {},   -- tech name -> lowercase translated name
    locale = nil, -- language the names were requested for
    gui = nil,
  }
end

-- Removes every window this mod created (also those of older versions).
function controller.destroy(player)
  for _, child in pairs(player.gui.screen.children) do
    if child.name == 'rq_window' or (child.tags and child.tags.on_closed == 'close_window') then
      child.destroy()
    end
  end
  local pdata = storage.players[player.index]
  if pdata then
    pdata.gui = nil
  end
  player.set_shortcut_toggled(SHORTCUT, false)
end

local function is_open(pdata)
  return pdata and pdata.gui and pdata.gui.window.valid and pdata.gui.window.visible
end

---------------------------------------------------------------------------
-- Opening and closing
---------------------------------------------------------------------------

-- Keeps the window inside small screens.
local function fit_to_screen(player, gui)
  local available = math.floor(player.display_resolution.height / player.display_scale) - 140
  local height = math.max(400, math.min(MAX_WINDOW_HEIGHT, available))
  gui.main.style.height = height
  gui.filter.style.height = height
end

function controller.open(player)
  local pdata = storage.players[player.index]
  if not pdata then return end
  if not queue.has_force(player.force) then
    queue.init_force(player.force)
  end

  if not (pdata.gui and pdata.gui.window.valid) then
    pdata.gui = window.build(player)
    update.auto_filter(player)
  end
  local gui = pdata.gui

  search.request(player)
  queue.sync(player.force)
  fit_to_screen(player, gui)
  update.auto_filter(player)
  update.all(player)

  gui.window.visible = true
  player.opened = gui.window
  player.set_shortcut_toggled(SHORTCUT, true)
  if util.can_pause_game(player) then
    game.tick_paused = true
  end
end

function controller.close(player)
  local pdata = storage.players[player.index]
  if pdata and pdata.gui and pdata.gui.window.valid then
    local gui = pdata.gui
    gui.window.visible = false
    if player.opened == gui.window then
      player.opened = nil
    end
    pdata.closed_tick = game.tick
    if util.can_pause_game(player) then
      game.tick_paused = false
    end
  end
  player.set_shortcut_toggled(SHORTCUT, false)
end

function controller.toggle(player)
  if is_open(storage.players[player.index]) then
    controller.close(player)
  else
    controller.open(player)
  end
end

function controller.focus_search(player)
  local pdata = storage.players[player.index]
  if is_open(pdata) then
    pdata.gui.search.focus()
    pdata.gui.search.select_all()
  end
end

---------------------------------------------------------------------------
-- Refreshing
---------------------------------------------------------------------------

-- Refreshes the open window of one player.
function controller.refresh_player(player, focus_id, auto_filter)
  if is_open(storage.players[player.index]) then
    if auto_filter then
      update.auto_filter(player)
    end
    update.all(player, focus_id)
  end
end

-- Refreshes the open windows of all online players of a force.
function controller.refresh_force(force, focus_id, auto_filter)
  for _, player in pairs(force.connected_players) do
    controller.refresh_player(player, focus_id, auto_filter)
  end
end

-- Once a second: time estimates and progress for open windows.
function controller.on_tick()
  for _, player in pairs(game.connected_players) do
    if is_open(storage.players[player.index]) then
      update.tick(player)
    end
  end
end

---------------------------------------------------------------------------
-- Technology screen interplay
-- Opening the technology screen from our window (alt+click) closes our window
-- in the same tick; it is shown again next to the technology screen and the
-- vanilla queue is read back when the technology screen closes.
---------------------------------------------------------------------------

function controller.on_gui_opened(event)
  if event.gui_type ~= defines.gui_type.research then return end
  local player = game.get_player(event.player_index)
  local pdata = storage.players[event.player_index]
  if pdata and pdata.gui and pdata.gui.window.valid and pdata.closed_tick == game.tick then
    pdata.gui.window.visible = true
    player.set_shortcut_toggled(SHORTCUT, true)
  end
end

function controller.on_gui_closed(event)
  if event.gui_type == defines.gui_type.research then
    local player = game.get_player(event.player_index)
    local pdata = storage.players[event.player_index]
    if is_open(pdata) then
      player.opened = pdata.gui.window
    end
    if queue.sync(player.force) then
      controller.refresh_force(player.force)
    else
      controller.refresh_player(player)
    end
    return true
  end
  return false
end

---------------------------------------------------------------------------
-- Actions (looked up by the "rq" tag of the clicked element)
---------------------------------------------------------------------------

-- Applies a change to the queue: adopt pending vanilla changes first, then
-- change, clean up, mirror to vanilla and refresh every open window.
local function modify(player, change, focus_id)
  local force = player.force
  queue.pull(force)
  change(force)
  queue.normalize(force)
  queue.push(force)
  controller.refresh_force(force, focus_id)
end

local function tech_of(player, tags)
  return rqtech.from_id(player.force, tags.tech)
end

local actions = {}

function actions.close_window(player)
  controller.close(player)
end

function actions.toggle_pause(player)
  modify(player, function(force)
    queue.set_paused(force, not queue.is_paused(force))
  end)
end

function actions.clear_queue(player)
  modify(player, queue.clear)
end

function actions.search(player, event)
  local pdata = storage.players[player.index]
  pdata.terms = util.search_terms(event.element.text)
  update.techs(player)
end

function actions.filter_researched(player, event)
  storage.players[player.index].filter.researched = event.element.state
  update.techs(player)
end

function actions.filter_upgrades(player, event)
  storage.players[player.index].filter.upgrades = event.element.state
  update.techs(player)
end

function actions.filter_pack(player, event, tags)
  local filter = storage.players[player.index].filter
  filter.ingredients[tags.pack] = not filter.ingredients[tags.pack]
  filter.manual[tags.pack] = true
  update.filters(player)
  update.techs(player)
end

local function enqueue(player, rt, position)
  if not rt or not rqtech.is_queueable(rt) then return end
  modify(player, function(force)
    if position == 'last' then
      queue.enqueue_last(force, rt)
    else
      queue.enqueue_front(force, rt, position == 'next')
    end
  end, rt.id)
end

function actions.enqueue(player, event, tags)
  enqueue(player, tech_of(player, tags), tags.pos)
end

function actions.dequeue(player, event, tags)
  modify(player, function(force)
    queue.dequeue(force, tags.tech)
  end)
end

function actions.queue_shift(player, event, tags)
  modify(player, function(force)
    queue.shift(force, tags.tech, tags.dir, event.shift)
  end, tags.tech)
end

-- Click on a technology: left adds to the end, shift+left right after the
-- active research, right removes, alt+left opens the technology screen.
function actions.tech_click(player, event, tags)
  local rt = tech_of(player, tags)
  if not rt or event.control then return end
  if event.button == defines.mouse_button_type.left then
    if event.alt and not event.shift then
      player.open_technology_gui(rt.tech)
    elseif not event.alt then
      enqueue(player, rt, event.shift and 'next' or 'last')
    end
  elseif event.button == defines.mouse_button_type.right and not event.shift and not event.alt then
    modify(player, function(force)
      queue.dequeue(force, rt.id)
    end)
  end
end

-- Handles on_gui_click, on_gui_text_changed, on_gui_checked_state_changed and
-- on_gui_closed for elements of this mod's window.
function controller.on_gui_event(event)
  local element = event.element
  if not (element and element.valid) then return end
  local tags = element.tags
  local action = tags and tags.rq and actions[tags.rq]
  if not action then return end
  local player = game.get_player(event.player_index)
  if not storage.players[player.index] then return end
  action(player, event, tags)
end

return controller
