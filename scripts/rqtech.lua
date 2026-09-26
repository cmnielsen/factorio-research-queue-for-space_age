local util = require('.util')

local rqtech = {}

function rqtech.init()
  storage.rqtechs = {}
end

function rqtech.init_force(force)
  storage.rqtechs[force.index] = {}
end

function rqtech.deinit_force(force)
  storage.rqtechs[force.index] = nil
end

-- Return the object that makes a technology with a research trigger available.
-- Technologies using a research trigger do not have a lab science-pack cost.
function rqtech.research_trigger(tech)
  local trigger = tech.tech.prototype.research_trigger
  if trigger == nil then
    return nil
  end

  local function default_description(trigger_type)
    local locale_key = ({
      ['capture-spawner'] = 'tech-button-trigger-capture-spawner-any',
      ['create-space-platform'] = 'tech-button-trigger-create-space-platform',
      ['scripted'] = 'tech-button-trigger-scripted',
    })[trigger_type] or 'tech-button-trigger-generic'
    return {'factorio-research-queue.'..locale_key}
  end

  local function filter_name(value)
    if type(value) == 'string' then
      return value
    elseif type(value) == 'table' then
      return value.name
    end
    return nil
  end

  local target_type
  local target_name
  if trigger.type == 'craft-item' or trigger.type == 'send-item-to-orbit' then
    target_type = 'item'
    target_name = filter_name(trigger.item)
  elseif trigger.type == 'craft-fluid' then
    target_type = 'fluid'
    target_name = filter_name(trigger.fluid)
  elseif
    trigger.type == 'mine-entity' or
    trigger.type == 'capture-spawner' or
    trigger.type == 'build-entity'
  then
    target_type = 'entity'
    target_name = filter_name(trigger.entity)
  end

  if type(target_name) ~= 'string' then
    if trigger.type == 'capture-spawner' then
      return {
        type = trigger.type,
        target_type = 'entity',
        name = 'biter-spawner',
        sprite = 'entity/biter-spawner',
        localised_name = {'factorio-research-queue.tech-button-trigger-capture-spawner-any'},
      }
    end

    return {
      type = trigger.type,
      description = trigger.trigger_description or default_description(trigger.type),
    }
  end

  local prototype
  if target_type == 'item' then
    prototype = prototypes.item[target_name]
  elseif target_type == 'fluid' then
    prototype = prototypes.fluid[target_name]
  elseif target_type == 'entity' then
    prototype = prototypes.entity[target_name]
  end
  return {
    type = trigger.type,
    target_type = target_type,
    name = target_name,
    sprite = target_type..'/'..target_name,
    localised_name = prototype and prototype.localised_name or target_name,
    count = trigger.count,
    amount = trigger.amount,
  }
end

function rqtech.has_research_trigger(tech)
  return tech.tech.prototype.research_trigger ~= nil
end

-- create rqtech struct: id, tech, level, upgradegroup, infinite, unitcount, prerequisites
function rqtech.new(tech, level, offset)
  if offset == nil then offset = 0 end
  local infinite = tech.research_unit_count_formula ~= nil

  local level_from_name = string.match(tech.name, '-(%d+)$')
  if level_from_name ~= nil then
    level_from_name = tonumber(level_from_name)
  elseif infinite then
    level_from_name = 1
  end
  if level == nil then
    level = level_from_name
  elseif level == 'current' or level == 'previous' or level == 'max' then
    if infinite then
      if level == 'current' then
        level = tech.level + offset
      elseif level == 'previous' then
        if tech.researched then
          level = tech.level + offset
        else
          level = tech.level - 1 + offset
        end
      elseif level == 'max' then
        level = tech.prototype.max_level
      else
        error(string.format('unknown infinite level spec %s', level))
      end
    else
      level = level_from_name
    end
  end
  if level ~= nil then
    if level_from_name == nil then
      error(string.format('%s: level (%d) given with no level in name', tech.name, level))
    end
    assert(level >= level_from_name, string.format('%s: level (%d) < level from name (%d)', tech.name, level, level_from_name))
    assert(level <= tech.prototype.max_level, string.format('%s: level (%d) > max level (%d)', tech.name, level, tech.prototype.max_level))
  else
    if level_from_name ~= nil then
      error(string.format('%s: no level given with level in name (%d)', tech.name, level_from_name))
    end
  end

  local id
  if level == nil then
    id = tech.name
  else
    id = string.format('%s:%s', tech.name, level)
  end

  local cached_rqtech = storage.rqtechs[tech.force.index][id]
  if cached_rqtech ~= nil then
    return cached_rqtech
  end

  local upgrade_group
  do
    local level_tail = string.find(tech.name, '-%d+$')
    if level_tail ~= nil then
      upgrade_group = string.sub(tech.name, 1, level_tail - 1)
    else
      upgrade_group = tech.name
    end
  end

  local research_unit_count
  if infinite then
    -- helpers.evaluate_expression replaces game.evaluate_expression in Factorio 2.0
    research_unit_count = helpers.evaluate_expression(tech.research_unit_count_formula, { L = level, l = level })
    if not tech.prototype.ignore_tech_cost_multiplier then
      research_unit_count = math.ceil(
        research_unit_count * game.difficulty_settings.technology_price_multiplier)
    end
  else
    research_unit_count = tech.research_unit_count
  end

  local prerequisites
  if level ~= level_from_name then
    prerequisites = { [tech.name] = rqtech.new(tech, level - 1) }
  else
    prerequisites = {}
    for name, prerequisite in pairs(tech.prerequisites) do
      if
        prerequisite.research_unit_count_formula ~= nil and
        prerequisite.prototype.max_level == 4294967295
      then
        log(string.format('WARNING: %s is unresearchable! It has %s as a prerequisite, which is infinite with no max level. The prerequisite will be ignored in Improved Research Queue.', tech.name, prerequisite.name))
      else
        prerequisites[name] = rqtech.new(prerequisite, 'max')
      end
    end
  end

  local t = {
    id = id,
    tech = tech,
    level = level,
    upgrade_group = upgrade_group,
    infinite = infinite,
    research_unit_count = research_unit_count,
    prerequisites = prerequisites,
  }
  storage.rqtechs[tech.force.index][id] = t
  return t
end

-- rqtech struct from tech id
function rqtech.from_id(force, id)
  local cached_rqtech = storage.rqtechs[force.index][id]
  if cached_rqtech ~= nil then
    return cached_rqtech
  end
  local tech, level = string.match(id, '^(.+):(%d+)$')
  if tech ~= nil then
    tech = force.technologies[tech]
    level = tonumber(level)
  else
    tech = force.technologies[id]
    level = nil
  end
  if tech == nil then return nil end
  return rqtech.new(tech, level)
end

-- iterate over all rqtechs
function rqtech.iter(force)
  return util.iter_map(
    util.iter_values(force.technologies),
    rqtech.new)
end

-- progress from rqtech
function rqtech.progress(tech)
  local force = tech.tech.force
  if
    force.current_research ~= nil and
    force.current_research.name == tech.tech.name and
    (tech.level == nil or force.current_research.level == tech.level)
  then
    return force.research_progress
  elseif not tech.infinite or tech.tech.level == tech.level then
    return tech.tech.saved_progress or 0
  else
    return 0
  end
end

-- status from rqtech
function rqtech.is_researched(tech)
  if tech.tech.researched then
    return true
  end
  if tech.infinite then
    if tech.tech.level > tech.level then
      return true
    end
  end
  return false
end

return rqtech
