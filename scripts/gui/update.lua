-- Refreshing the contents of the research queue window.

local queue = require('scripts.queue')
local rqtech = require('scripts.rqtech')
local util = require('scripts.util')
local window = require('scripts.gui.window')

local update = {}

---------------------------------------------------------------------------
-- Filters
---------------------------------------------------------------------------

-- Science packs the player has not toggled by hand follow what the force can make.
function update.auto_filter(player)
  local pdata = storage.players[player.index]
  local filter = pdata.filter
  for _, pack in ipairs(pdata.gui.packs) do
    if not filter.manual[pack] then
      filter.ingredients[pack] = util.is_item_available(player.force, pack)
    end
  end
end

function update.filters(player)
  local pdata = storage.players[player.index]
  local gui, filter = pdata.gui, pdata.filter
  gui.researched_checkbox.state = filter.researched
  gui.upgrades_checkbox.state = filter.upgrades
  for pack, button in pairs(gui.pack_buttons) do
    local enabled = filter.ingredients[pack] and true or false
    button.style = 'rq_tech_ingredient_filter_button_' .. (enabled and 'enabled' or 'disabled')
    button.tooltip = {
      'factorio-research-queue.filter-pack-' .. (enabled and 'enabled' or 'disabled'),
      prototypes.item[pack].localised_name,
    }
  end
end

---------------------------------------------------------------------------
-- Technology list
---------------------------------------------------------------------------

-- Later levels of upgrade chains are hidden until the level before them is
-- researched or queued (or the "upgrades" filter is on). Infinite technologies
-- never show levels that are not reachable yet.
local function is_upgrade_level_visible(force, filter, rt)
  if rt.level ~= nil and rt.level < 2 then
    return true
  end
  for _, prerequisite in pairs(rt.prerequisites) do
    if not (prerequisite.tech.upgrade or prerequisite.infinite)
      or prerequisite.upgrade_group ~= rt.upgrade_group
      or rqtech.is_researched(prerequisite)
      or queue.contains(force, prerequisite.id)
    then
      return true
    end
  end
  return filter.upgrades and not rt.infinite
end

local function is_visible(pdata, force, rt)
  local tech, filter = rt.tech, pdata.filter
  if tech.prototype.hidden or not tech.enabled then
    return false
  end
  if not filter.researched and rqtech.is_researched(rt) then
    return false
  end
  if (tech.upgrade or rt.infinite) and not is_upgrade_level_visible(force, filter, rt) then
    return false
  end
  for _, ingredient in ipairs(tech.research_unit_ingredients or {}) do
    if not filter.ingredients[ingredient.name] then
      return false
    end
  end
  if #pdata.terms > 0 then
    local haystack = (pdata.names[tech.name] or '') .. ' ' .. tech.name
    if not util.matches_terms(haystack, pdata.terms) then
      return false
    end
  end
  return true
end

local function update_progress(refs, rt)
  local progress = rqtech.is_researched(rt) and 0 or rqtech.progress(rt)
  refs.progressbar.value = progress
  refs.progressbar.visible = progress > 0
end

-- Sets style, button state and progress of one technology list cell.
local function refresh_item(force, refs, rt, memo)
  local queued = queue.contains(force, rt.id)
  local state
  if queue.is_head(force, rt.id) then
    state = 'queued_head'
  elseif queued then
    state = 'queued'
  elseif rqtech.is_researched(rt) then
    state = 'researched'
  else
    state = 'available'
    for _, prerequisite in pairs(rt.prerequisites) do
      if not rqtech.is_researched(prerequisite) then
        state = 'unavailable'
        break
      end
    end
  end

  local prefix = 'rq_tech_list_item_' .. state
  refs.ingredients_bar.style = prefix .. '_ingredients_bar'
  refs.tool_bar.style = prefix .. '_tool_bar'
  local queueable = rqtech.is_queueable(rt, memo)
  for _, button in pairs(refs.tool_bar.children) do
    button.enabled = queueable
  end
  refs.tech_button.button.style = prefix .. '_tech_button'
  update_progress(refs.tech_button, rt)
end

function update.techs(player)
  local force = player.force
  local pdata = storage.players[player.index]
  local gui = pdata.gui
  local memo = {}

  -- Rows for later infinite levels are recreated every time
  for id, refs in pairs(gui.extra) do
    refs.item.destroy()
    gui.items[id] = nil
  end
  gui.extra = {}

  for _, id in ipairs(gui.base_ids) do
    local rt = rqtech.from_id(force, id)
    local refs = gui.items[id]
    if rt then
      local visible = is_visible(pdata, force, rt)
      refs.item.visible = visible
      if visible then
        refresh_item(force, refs, rt, memo)
      end

      -- Add rows for the next levels of an infinite technology while they are reachable
      local index = refs.item.get_index_in_parent() + 1
      while (visible or rqtech.is_researched(rt)) and rt.infinite and rt.level + 1 <= rt.tech.prototype.max_level do
        rt = rqtech.get(rt.tech, rt.level + 1)
        visible = is_visible(pdata, force, rt)
        if visible then
          local extra = window.build_tech_item(gui.tech_table, rt, index)
          refresh_item(force, extra, rt, memo)
          index = extra.item.get_index_in_parent() + 1
          gui.items[rt.id] = extra
          gui.extra[rt.id] = extra
        end
      end
    end
  end
end

---------------------------------------------------------------------------
-- Queue
---------------------------------------------------------------------------

-- Time estimates and science pack totals, accumulated down the queue.
function update.estimates(player)
  local gui = storage.players[player.index].gui
  local force = player.force
  local speed = storage.forces[force.index].speed

  local elapsed = 0
  local totals = {}
  for _, id in ipairs(queue.ids(force)) do
    local refs = gui.queue_items[id]
    local rt = rqtech.from_id(force, id)
    if refs and rt then
      local unit_count = rt.research_unit_count or 0
      local remaining = 1 - rqtech.progress(rt)

      local text
      if speed == 0 then
        text = '[img=infinity]'
      else
        elapsed = elapsed + remaining * ((rt.tech.research_unit_energy or 0) / 60) * unit_count / speed
        text = util.format_duration(elapsed)
      end
      refs.etc_label.caption = text

      for _, ingredient in ipairs(rt.tech.research_unit_ingredients or {}) do
        totals[ingredient.name] = (totals[ingredient.name] or 0) + remaining * unit_count * ingredient.amount
      end
      local total_text = '[font=count-font]'
      for _, pack in ipairs(gui.packs) do
        if (totals[pack] or 0) > 0 then
          total_text = total_text .. string.format('[img=item/%s]%d ', pack, math.ceil(totals[pack]))
        end
      end
      refs.etc_label.tooltip = {
        '',
        {'factorio-research-queue.etc-tooltip', text},
        '\n',
        {'factorio-research-queue.pack-totals-tooltip', total_text .. '[/font]'},
      }
    end
  end
end

local function update_pause_button(gui, paused, mirrored)
  gui.pause_button.visible = mirrored
  gui.pause_container.visible = mirrored and paused
  gui.head_container.visible = not (mirrored and paused)
  if paused then
    gui.pause_button.style = 'rq_frame_action_button_green'
    gui.pause_button.sprite = 'rq-play-white'
    gui.pause_button.hovered_sprite = 'rq-play-black'
    gui.pause_button.clicked_sprite = 'rq-play-black'
    gui.pause_button.tooltip = {'factorio-research-queue.play-tooltip'}
  else
    gui.pause_button.style = 'rq_frame_action_button_red'
    gui.pause_button.sprite = 'rq-pause-white'
    gui.pause_button.hovered_sprite = 'rq-pause-black'
    gui.pause_button.clicked_sprite = 'rq-pause-black'
    gui.pause_button.tooltip = {'factorio-research-queue.pause-tooltip'}
  end
end

-- Rebuilds the queue column. `focus_id` scrolls the queue to that technology.
function update.queue(player, focus_id)
  local force = player.force
  local gui = storage.players[player.index].gui
  local paused = queue.is_paused(force)
  update_pause_button(gui, paused, settings.global['rq-mirror-vanilla-queue'].value)

  gui.head_container.clear()
  gui.queue_list.clear()
  gui.queue_items = {}

  local focus
  for position, id in ipairs(queue.ids(force)) do
    local rt = rqtech.from_id(force, id)
    if rt then
      local is_head = position == 1 and not paused
      local refs = window.build_queue_item(
        is_head and gui.head_container or gui.queue_list,
        rt,
        queue.can_shift(force, id, 'up'),
        queue.can_shift(force, id, 'down'))
      refs.tech_button.button.style = 'rq_tech_queue' .. (is_head and '_head' or '') .. '_item_tech_button'
      update_progress(refs.tech_button, rt)
      gui.queue_items[id] = refs
      if id == focus_id then
        focus = is_head and 'head' or refs.item
      end
    end
  end

  if focus == 'head' then
    gui.queue_list.scroll_to_top()
  elseif focus then
    gui.queue_list.scroll_to_element(focus, 'top-third')
  end
  update.estimates(player)
end

---------------------------------------------------------------------------
-- Combined updates
---------------------------------------------------------------------------

function update.all(player, focus_id)
  update.filters(player)
  update.queue(player, focus_id)
  update.techs(player)
end

-- Cheap once-a-second refresh of time estimates and the active research bar.
function update.tick(player)
  local force = player.force
  local gui = storage.players[player.index].gui
  update.estimates(player)
  for id, refs in pairs(gui.queue_items) do
    local rt = rqtech.from_id(force, id)
    if rt then update_progress(refs.tech_button, rt) end
  end
  local current = force.current_research
  if current then
    local rt = rqtech.current(current)
    local refs = gui.items[rt.id]
    if refs then update_progress(refs.tech_button, rt) end
  end
end

return update
