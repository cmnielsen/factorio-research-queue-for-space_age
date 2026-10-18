-- Wrapper around LuaTechnology ("rqtech"). One rqtech describes one researchable
-- unit: a normal technology, one level of a leveled technology ("name-3"), or one
-- level of an infinite technology. Instances are cached per force in storage and
-- identified by an id string: "name" or "name:level".
--
-- An rqtech has the fields:
--   id, tech (LuaTechnology), level (number or nil), upgrade_group, infinite,
--   research_unit_count, prerequisites (name -> rqtech), has_trigger

local rqtech = {}

local INFINITE_MAX_LEVEL = 4294967295

---------------------------------------------------------------------------
-- Cache
---------------------------------------------------------------------------

function rqtech.reset_cache()
  storage.rqtechs = {}
end

function rqtech.drop_force(force_index)
  if storage.rqtechs then
    storage.rqtechs[force_index] = nil
  end
end

local function cache_of(force)
  local all = storage.rqtechs
  if not all then
    all = {}
    storage.rqtechs = all
  end
  local cache = all[force.index]
  if not cache then
    cache = {}
    all[force.index] = cache
  end
  return cache
end

---------------------------------------------------------------------------
-- Construction
---------------------------------------------------------------------------

local function is_infinite(tech)
  return tech.research_unit_count_formula ~= nil
end

-- Lowest level of a technology: the number in its name, 1 for infinite
-- technologies without a number, nil for technologies without levels.
local function base_level(tech)
  local from_name = string.match(tech.name, '-(%d+)$')
  if from_name then
    return tonumber(from_name)
  end
  if is_infinite(tech) then
    return 1
  end
  return nil
end

-- Level that has to be reached for the technology to count as done.
local function top_level(tech)
  local base = base_level(tech)
  if base == nil then
    return nil
  end
  if is_infinite(tech) then
    return tech.prototype.max_level
  end
  return base
end

local function upgrade_group_of(tech)
  local tail = string.find(tech.name, '-%d+$')
  if tail then
    return string.sub(tech.name, 1, tail - 1)
  end
  return tech.name
end

local function unit_count_of(tech, level)
  if not is_infinite(tech) then
    return tech.research_unit_count
  end
  local count = helpers.evaluate_expression(tech.research_unit_count_formula, {L = level, l = level})
  if not tech.prototype.ignore_tech_cost_multiplier then
    count = math.ceil(count * game.difficulty_settings.technology_price_multiplier)
  end
  return count
end

-- Returns the rqtech for a technology at the given level (nil = lowest level).
function rqtech.get(tech, level)
  local base = base_level(tech)
  if base == nil then
    level = nil
  else
    -- Only infinite technologies have more than one level to choose from
    local highest = is_infinite(tech) and tech.prototype.max_level or base
    level = math.min(math.max(level or base, base), highest)
  end

  local id = level and string.format('%s:%d', tech.name, level) or tech.name
  local cache = cache_of(tech.force)
  if cache[id] then
    return cache[id]
  end

  local prerequisites = {}
  if base ~= nil and level > base then
    -- Higher levels only require the level below
    prerequisites[tech.name] = rqtech.get(tech, level - 1)
  else
    for name, prerequisite in pairs(tech.prerequisites) do
      if is_infinite(prerequisite) and prerequisite.prototype.max_level == INFINITE_MAX_LEVEL then
        -- Can never be completed, so it cannot be a real requirement
        log(string.format('WARNING: %s requires infinite technology %s; ignoring it as a prerequisite.', tech.name, name))
      else
        prerequisites[name] = rqtech.get(prerequisite, top_level(prerequisite))
      end
    end
  end

  local result = {
    id = id,
    tech = tech,
    level = level,
    upgrade_group = upgrade_group_of(tech),
    infinite = is_infinite(tech),
    research_unit_count = unit_count_of(tech, level),
    prerequisites = prerequisites,
    has_trigger = tech.prototype.research_trigger ~= nil,
  }
  cache[id] = result
  return result
end

-- Returns the rqtech for an id, or nil if the technology no longer exists.
function rqtech.from_id(force, id)
  local cached = cache_of(force)[id]
  if cached then
    return cached
  end
  local name, level = string.match(id, '^(.+):(%d+)$')
  local tech = force.technologies[name or id]
  if not tech then
    return nil
  end
  return rqtech.get(tech, level and tonumber(level) or nil)
end

-- The rqtech a technology currently stands at. For infinite technologies an
-- offset selects a later level (used for repeated entries in the vanilla queue).
function rqtech.current(tech, offset)
  if is_infinite(tech) then
    return rqtech.get(tech, tech.level + (offset or 0))
  end
  return rqtech.get(tech)
end

-- Prerequisites in a stable order (technology order, then id).
function rqtech.sorted_prerequisites(rt)
  local list = {}
  for _, prerequisite in pairs(rt.prerequisites) do
    list[#list + 1] = prerequisite
  end
  table.sort(list, function(a, b)
    if a.tech.order ~= b.tech.order then
      return a.tech.order < b.tech.order
    end
    return a.id < b.id
  end)
  return list
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------

function rqtech.is_researched(rt)
  if rt.tech.researched then
    return true
  end
  return rt.infinite and rt.tech.level > rt.level
end

-- Can still be researched at some point (visible, enabled and not done).
function rqtech.is_researchable(rt)
  return not rt.tech.prototype.hidden and rt.tech.enabled and not rqtech.is_researched(rt)
end

-- Can be put into the research queue right now or later: researchable, not
-- unlocked by a research trigger, and with a queueable chain of prerequisites.
-- `memo` caches results while many technologies are checked in a row.
function rqtech.is_queueable(rt, memo)
  memo = memo or {}
  local known = memo[rt.id]
  if known ~= nil then
    return known
  end
  local result = rqtech.is_researchable(rt) and not rt.has_trigger
  if result then
    for _, prerequisite in pairs(rt.prerequisites) do
      if rqtech.is_researchable(prerequisite) and not rqtech.is_queueable(prerequisite, memo) then
        result = false
        break
      end
    end
  end
  memo[rt.id] = result
  return result
end

-- Research progress from 0 to 1.
function rqtech.progress(rt)
  local tech = rt.tech
  local force = tech.force
  local current = force.current_research
  if current and current.name == tech.name and (rt.level == nil or current.level == rt.level) then
    return force.research_progress
  elseif not rt.infinite or tech.level == rt.level then
    return tech.saved_progress or 0
  end
  return 0
end

---------------------------------------------------------------------------
-- Research triggers
---------------------------------------------------------------------------

local TRIGGER_TARGETS = {
  ['craft-item'] = {kind = 'item', field = 'item'},
  ['send-item-to-orbit'] = {kind = 'item', field = 'item'},
  ['craft-fluid'] = {kind = 'fluid', field = 'fluid'},
  ['mine-entity'] = {kind = 'entity', field = 'entity'},
  ['capture-spawner'] = {kind = 'entity', field = 'entity'},
  ['build-entity'] = {kind = 'entity', field = 'entity'},
}

local function filter_name(value)
  if type(value) == 'string' then
    return value
  elseif type(value) == 'table' then
    return value.name
  end
  return nil
end

local function trigger_target(trigger, target)
  local value = trigger[target.field]
  if value == nil and target.kind == 'entity' and trigger.entities then
    value = trigger.entities[1] -- newer game versions list several entities
  end
  return filter_name(value)
end

-- Describes the research trigger of a technology for display, or returns nil if
-- the technology has none. The result has either `line` (a complete
-- LocalisedString) or `sprite`, `name` (LocalisedString) and an optional `count`.
function rqtech.trigger_info(rt)
  local trigger = rt.tech.prototype.research_trigger
  if trigger == nil then
    return nil
  end

  local target = TRIGGER_TARGETS[trigger.type]
  if target then
    local name = trigger_target(trigger, target)
    local prototype = name and prototypes[target.kind][name]
    if prototype then
      return {
        type = trigger.type,
        sprite = target.kind .. '/' .. name,
        name = prototype.localised_name,
        count = trigger.count or trigger.amount,
      }
    end
    if trigger.type == 'capture-spawner' and prototypes.entity['biter-spawner'] then
      return {
        type = trigger.type,
        sprite = 'entity/biter-spawner',
        name = {'factorio-research-queue.trigger-any-spawner'},
      }
    end
  end

  local line
  if trigger.trigger_description then
    line = {'factorio-research-queue.trigger-scripted', trigger.trigger_description}
  elseif trigger.type == 'create-space-platform' then
    line = {'factorio-research-queue.trigger-create-space-platform'}
  else
    line = {'factorio-research-queue.trigger-generic'}
  end
  return {type = trigger.type, line = line}
end

return rqtech
