-- The extended research queue.
--
-- Per force, storage.forces[force.index] holds:
--   queue    array of rqtech ids; dependencies always come before dependents
--   paused   true while the queue is not driving research
--   mirrored ids that were last seen in the vanilla research queue
--   samples, speed   research speed estimate (see scripts/speed.lua)
--
-- With "mirror" enabled the first MIRROR_SIZE queue entries are copied into the
-- vanilla research queue, and changes made in the vanilla queue are read back.
-- With mirror disabled the queue is only a planning list and vanilla is untouched.

local rqtech = require('scripts.rqtech')

local queue = {}

local MIRROR_SIZE = 4 -- queue entries mirrored into the vanilla queue
local pushing = false -- true while this mod writes the vanilla queue

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

local function data_of(force)
  return storage.forces[force.index]
end

local function mirror_enabled()
  return settings.global['rq-mirror-vanilla-queue'].value
end

local function index_of(list, id)
  for i, value in ipairs(list) do
    if value == id then
      return i
    end
  end
  return nil
end

local function to_set(list)
  local set = {}
  for _, value in ipairs(list) do
    set[value] = true
  end
  return set
end

local function same_list(a, b)
  if #a ~= #b then
    return false
  end
  for i = 1, #a do
    if a[i] ~= b[i] then
      return false
    end
  end
  return true
end

-- True if the item `dependent` directly requires the item `dependency`.
local function depends_on(force, dependent_id, dependency_id)
  local dependent = rqtech.from_id(force, dependent_id)
  local dependency = rqtech.from_id(force, dependency_id)
  if not dependent or not dependency then
    return false
  end
  local prerequisite = dependent.prerequisites[dependency.tech.name]
  return prerequisite ~= nil and prerequisite.id == dependency.id
end

-- Moves list[from] to position `to`; the items in between shift by one.
local function rotate(list, from, to)
  table.insert(list, to, table.remove(list, from))
end

-- Collects an rqtech and its unresearched prerequisites, dependencies first.
local function collect(rt, block, seen)
  if seen[rt.id] then
    return
  end
  seen[rt.id] = true
  for _, prerequisite in ipairs(rqtech.sorted_prerequisites(rt)) do
    if rqtech.is_researchable(prerequisite) then
      collect(prerequisite, block, seen)
    end
  end
  block[#block + 1] = rt.id
end

---------------------------------------------------------------------------
-- Force data
---------------------------------------------------------------------------

function queue.init_force(force)
  storage.forces[force.index] = {queue = {}, paused = true, mirrored = {}, samples = {}, speed = 0}
  queue.pull(force) -- adopt research that is already queued in the vanilla queue
end

function queue.remove_force(force_index)
  storage.forces[force_index] = nil
  rqtech.drop_force(force_index)
end

function queue.has_force(force)
  return storage.forces[force.index] ~= nil
end

---------------------------------------------------------------------------
-- Queries
---------------------------------------------------------------------------

function queue.ids(force)
  return data_of(force).queue
end

function queue.contains(force, id)
  return index_of(data_of(force).queue, id) ~= nil
end

function queue.is_paused(force)
  return data_of(force).paused and mirror_enabled()
end

-- The head of the queue is the active research, unless the queue is paused.
function queue.is_head(force, id)
  return not queue.is_paused(force) and data_of(force).queue[1] == id
end

function queue.set_paused(force, paused)
  data_of(force).paused = paused
end

---------------------------------------------------------------------------
-- Moving items (a move never separates an item from its prerequisites)
---------------------------------------------------------------------------

-- Position of the item that swaps with list[index] when moving it earlier.
local function earlier_pivot(force, list, index, first)
  local pivot = index - 1
  while pivot >= first do
    local blocked = false
    for i = pivot + 1, index do
      if depends_on(force, list[i], list[pivot]) then
        blocked = true
        break
      end
    end
    if not blocked then
      return pivot
    end
    pivot = pivot - 1
  end
  return nil
end

-- Position of the item that swaps with list[index] when moving it later.
local function later_pivot(force, list, index)
  local pivot = index + 1
  while pivot <= #list do
    local blocked = false
    for i = index, pivot - 1 do
      if depends_on(force, list[pivot], list[i]) then
        blocked = true
        break
      end
    end
    if not blocked then
      return pivot
    end
    pivot = pivot + 1
  end
  return nil
end

function queue.can_shift(force, id, direction)
  local list = data_of(force).queue
  local index = index_of(list, id)
  if not index then
    return false
  end
  if direction == 'up' then
    return earlier_pivot(force, list, index, 1) ~= nil
  end
  return later_pivot(force, list, index) ~= nil
end

-- Moves an item one step (or as far as possible when `far` is set) up or down.
-- Moving far up leaves the active research in place.
function queue.shift(force, id, direction, far)
  local list = data_of(force).queue
  local first = far and (queue.is_paused(force) and 1 or 2) or 1
  repeat
    local index = index_of(list, id)
    if not index then
      return
    end
    local pivot
    if direction == 'up' then
      pivot = earlier_pivot(force, list, index, first)
    else
      pivot = later_pivot(force, list, index)
    end
    if pivot then
      rotate(list, pivot, index)
    end
  until not far or not pivot
end

---------------------------------------------------------------------------
-- Adding and removing
---------------------------------------------------------------------------

-- Adds a technology (with missing prerequisites) at the end of the queue.
function queue.enqueue_last(force, rt)
  local data = data_of(force)
  local list = data.queue
  local present = to_set(list)
  local block = {}
  collect(rt, block, {})
  for _, id in ipairs(block) do
    if not present[id] then
      list[#list + 1] = id
    end
  end
  queue.shift(force, rt.id, 'down', true)
  data.paused = false
end

-- Puts a technology and its prerequisites at the front of the queue. With
-- `after_head` the active research stays first; otherwise the technology is
-- researched as soon as possible.
function queue.enqueue_front(force, rt, after_head)
  local data = data_of(force)
  local list = data.queue
  local first = (after_head and not queue.is_paused(force)) and 2 or 1

  local block, in_block = {}, {}
  collect(rt, block, in_block)

  -- Entries before `first` (the active research) are never moved
  local protected = {}
  for i = 1, math.min(first - 1, #list) do
    protected[list[i]] = true
  end
  data.paused = false
  if protected[rt.id] then
    return
  end

  local rest = {}
  for i, id in ipairs(list) do
    if i < first or not in_block[id] then
      rest[#rest + 1] = id
    end
  end
  local position = math.min(first, #rest + 1)
  for _, id in ipairs(block) do
    if not protected[id] then
      table.insert(rest, position, id)
      position = position + 1
    end
  end
  data.queue = rest
end

-- Removes a technology and everything in the queue that depends on it.
function queue.dequeue(force, id)
  local data = data_of(force)
  local removed = {[id] = true}
  local result = {}
  for _, queued_id in ipairs(data.queue) do
    local keep = not removed[queued_id]
    if keep then
      local rt = rqtech.from_id(force, queued_id)
      keep = rt ~= nil
      if rt then
        for _, prerequisite in pairs(rt.prerequisites) do
          if removed[prerequisite.id] then
            keep = false
            break
          end
        end
      end
    end
    if keep then
      result[#result + 1] = queued_id
    else
      removed[queued_id] = true
    end
  end
  data.queue = result
end

-- Empties the queue; the active research is kept unless the queue is paused.
function queue.clear(force)
  local data = data_of(force)
  if queue.is_paused(force) or #data.queue == 0 then
    data.queue = {}
  else
    data.queue = {data.queue[1]}
  end
end

-- Drops everything that cannot or no longer needs to be researched and makes
-- sure every item comes after its unresearched prerequisites.
function queue.normalize(force)
  local data = data_of(force)
  local memo, kept, result = {}, {}, {}
  for _, id in ipairs(data.queue) do
    local rt = rqtech.from_id(force, id)
    if rt and not kept[id] and rqtech.is_queueable(rt, memo) then
      local ready = true
      for _, prerequisite in pairs(rt.prerequisites) do
        if rqtech.is_researchable(prerequisite) and not kept[prerequisite.id] then
          ready = false
          break
        end
      end
      if ready then
        kept[id] = true
        result[#result + 1] = id
      end
    end
  end
  data.queue = result
end

---------------------------------------------------------------------------
-- Vanilla research queue
---------------------------------------------------------------------------

-- Ids of the vanilla queue. Repeated entries of an infinite technology are
-- consecutive levels.
local function read_vanilla(force)
  local ids = {}
  local seen = {}
  for _, tech in ipairs(force.research_queue) do
    local offset = seen[tech.name] or 0
    seen[tech.name] = offset + 1
    local rt = rqtech.current(tech, offset)
    if rt then
      ids[#ids + 1] = rt.id
    end
  end
  return ids
end

local function write_vanilla(force, ids)
  local techs = {}
  for _, id in ipairs(ids) do
    local rt = rqtech.from_id(force, id)
    if rt then
      techs[#techs + 1] = rt.tech
    end
  end
  force.research_queue = techs
end

-- Copies the head of the queue into the vanilla queue (empty while paused).
function queue.push(force)
  if not mirror_enabled() then
    return
  end
  local data = data_of(force)
  local window = {}
  if not data.paused then
    for i = 1, math.min(MIRROR_SIZE, #data.queue) do
      window[i] = data.queue[i]
    end
  end

  if not same_list(window, read_vanilla(force)) then
    pushing = true
    local ok, err = pcall(write_vanilla, force, window)
    pushing = false
    if not ok then
      error(err)
    end
  end
  data.mirrored = read_vanilla(force)
end

-- Adopts changes a player made in the vanilla queue. Returns true if the queue
-- changed. Entries the player added or reordered become the head of the queue,
-- entries the player removed are dropped, and emptying the vanilla queue pauses.
function queue.pull(force)
  if pushing or not mirror_enabled() then
    return false
  end
  local data = data_of(force)
  local vanilla = read_vanilla(force)
  if same_list(vanilla, data.mirrored) then
    return false
  end

  local in_vanilla = to_set(vanilla)
  local was_mirrored = to_set(data.mirrored)
  local merged = {}
  for _, id in ipairs(vanilla) do
    merged[#merged + 1] = id
  end
  for _, id in ipairs(data.queue) do
    if not in_vanilla[id] and not was_mirrored[id] then
      merged[#merged + 1] = id
    end
  end
  data.queue = merged

  if #vanilla > 0 then
    data.paused = false
  elseif #data.mirrored > 0 then
    data.paused = true
  end
  data.mirrored = vanilla
  return true
end

-- Pull, then restore a valid queue and mirror it again. Returns true if
-- anything was adopted from the vanilla queue.
function queue.sync(force)
  local changed = queue.pull(force)
  if changed then
    queue.normalize(force)
    queue.push(force)
  end
  return changed
end

return queue
