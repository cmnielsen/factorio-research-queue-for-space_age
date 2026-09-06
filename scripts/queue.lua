local rqtech = require('.rqtech')
local util = require('.util')

-- initialisation
local function new(force, paused)
  local queue = {}
  storage.forces[force.index].queue = queue
  storage.forces[force.index].queue_paused = paused
end

-- move q[i] to [j] and shift intervening items
local function rotate(force, queue, i, j)
  if i == j then return end
  local dir = i < j and 1 or -1
  local tmp = queue[i]
  local k = i
  while k*dir < j*dir do
    queue[k] = queue[k+dir]
    k = k+dir
  end
  queue[j] = tmp
end

local function is_researchable(force, queue, tech)
  return
    not tech.tech.prototype.hidden and
    tech.tech.enabled and
    not rqtech.is_researched(tech)
end

local function is_dependency(force, queue, dependency, tech)
  return is_researchable(force, queue, dependency) and tech.prerequisites[dependency.tech.name] ~= nil
end

local function is_dependent(force, queue, dependent, tech)
  return is_researchable(force, queue, dependent) and is_dependency(force, queue, tech, dependent)
end

-- returns all dependencies
local function tech_dependencies(force, queue, tech)
  return util.iter_filter(
    util.iter_values(tech.prerequisites),
    function(dependency)
      return is_researchable(force, queue, dependency)
    end)
end

-- returns all techs that depend on <tech>
local function tech_dependents(force, queue, tech)
  local deps
  if tech.infinite and tech.level < tech.tech.prototype.max_level then
    deps = util.iter_once(rqtech.new(tech.tech, tech.level + 1))
  else
    deps = rqtech.iter(force)
  end
  return util.iter_filter(
    deps,
    function(depdendent)
      return is_dependent(force, queue, depdendent, tech)
    end)
end

-- where is a tech in queue
local function queue_pos(force, queue, tech)
  for idx, queued_tech in ipairs(queue) do
    if queued_tech.id == tech.id then
      return idx
    end
  end
  return nil
end

-- is tech first item in queue
local function is_head(force, queue, tech, ignore_level)
  if queue[1] == nil then
    return false
  end
  if ignore_level then
    return queue[1].tech.name == tech.tech.name
  else
    return queue[1].id == tech.id
  end
end

local function get_head(force, queue)
  return queue[1]
end

local function in_queue(force, queue, tech)
  for _, queued_tech in ipairs(queue) do
    if queued_tech.id == tech.id then
      return true
    end
  end
  return false
end

-- enqueue all necessary techs
local function enqueue(force, queue, tech)
  if not in_queue(force, queue, tech) then
    for dependency in tech_dependencies(force, queue, tech) do
      enqueue(force, queue, dependency)
    end

    table.insert(queue, tech)
    return true
  end
  return false
end

-- dequeue tech and all dependents
local function dequeue(force, queue, tech)
  if in_queue(force, queue, tech) then
    for dependent in tech_dependents(force, queue, tech) do
      dequeue(force, queue, dependent)
    end

    for idx, queued_tech in ipairs(queue) do
      if queued_tech.id == tech.id then
        table.remove(queue, idx)
        break
      end
    end
  end
end

-- is tech dependency of queue[from...to]
local function is_depdendency_of_any(force, queue, tech, from_pos, to_pos)
  for i = from_pos,to_pos do
    if is_dependency(force, queue, tech, queue[i]) then
      return true
    end
  end
  return false
end

-- is tech dependent of queue[from...to]
local function is_depdendent_of_any(force, queue, tech, from_pos, to_pos)
  for i = from_pos,to_pos do
    if is_dependent(force, queue, tech, queue[i]) then
      return true
    end
  end
  return false
end

-- search for a tech that could be moved before <tech>
local function try_shift_later(force, queue, tech)
  local tech_pos = queue_pos(force, queue, tech)
  local pivot_pos = tech_pos + 1
  if pivot_pos > #queue then
    return nil
  end
  while is_depdendent_of_any(force, queue, queue[pivot_pos], tech_pos, pivot_pos) do
    pivot_pos = pivot_pos + 1
    if pivot_pos > #queue then
      return nil
    end
  end
  return pivot_pos, tech_pos
end

-- move earliest independent tech in front of <tech>
local function shift_later(force, queue, tech)
  local pivot_pos, tech_pos = try_shift_later(force, queue, tech)
  if pivot_pos ~= nil then
    rotate(force, queue, pivot_pos, tech_pos)
    return true
  end
  return false
end

-- search for latest independent tech that could be moved behind <tech>
local function try_shift_earlier(force, queue, tech, head)
  head = head or 1
  local tech_pos = queue_pos(force, queue, tech)
  local pivot_pos = tech_pos - 1
  if pivot_pos < head then
    return nil
  end
  while is_depdendency_of_any(force, queue, queue[pivot_pos], pivot_pos, tech_pos) do
    pivot_pos = pivot_pos - 1
    if pivot_pos < head then
      return nil
    end
  end
  return pivot_pos, tech_pos
end

-- move latest independent tech behind <tech>
local function shift_earlier(force, queue, tech, head)
  local pivot_pos, tech_pos = try_shift_earlier(force, queue, tech, head)
  if pivot_pos ~= nil then
    rotate(force, queue, pivot_pos, tech_pos)
    return true
  end
  return false
end

-- move to the right as far as possible
local function shift_latest(force, queue, tech)
  while shift_later(force, queue, tech) do end
end

-- move to the left as far as possible
local function shift_earliest(force, queue, tech)
  while shift_earlier(force, queue, tech) do end
end

-- move to the left as far as possible, but keep current
local function shift_before_earliest(force, queue, paused, tech)
  while shift_earlier(force, queue, tech, paused and 1 or 2) do end
end

-- enqueue and move to the right
local function enqueue_tail(force, queue, tech)
  enqueue(force, queue, tech)
  shift_latest(force, queue, tech)
end

-- enqueue and move to the left
local function enqueue_head(force, queue, tech)
  local ret = enqueue(force, queue, tech)
  shift_earliest(force, queue, tech)
  return ret
end

-- enqueue and move to the left, ignoring current research
local function enqueue_before_head(force, queue, paused, tech)
  enqueue(force, queue, tech)
  shift_before_earliest(force, queue, paused, tech)
end

-- queue iterator
local function iter(force, queue)
  return util.iter_list(queue)
end

-- clear all after current research
local function clear(force, force_data)
  if force_data.queue_paused then
    force_data.queue = {}
  else
    local head = force_data.queue[1]
    force_data.queue = {head}
  end
  return force_data.queue
end

local function set_queue(force, target)
  force.research_queue = target
end

local function count_prev(rq, id)
  local j = 0
  for k=1, id-1 do
    if rq[id].name == rq[k].name then
      j = j+1
    end
  end
  return j
end

local function count_after(rq, id)
  local j = 0
  for k=#rq,id+1,-1 do
    if rq[id].name == rq[k].name then
      j=j+1
    end
  end
  return j
end

local function queues_identical(force, queue, n)
  if n == nil then n = 7 end
  local rq = force.research_queue
  local flag = true
  for i=1, n do
    if force.research_queue[i] ~= nil and queue[i] ~= nil then
      if force.research_queue[i].name ~= queue[i].tech.name then
        flag = false
        break
      end
    elseif force.research_queue[i] ~= nil or queue[i] ~= nil then
      flag = false
      break
    else
      break
    end
  end
  return flag
end

local function update(force, queue, paused, mode)
  if mode == nil then
    mode = 0
  end
  -- remove invalid/researched techs
  local to_dequeue = {}
  for _, tech in ipairs(queue) do
    if not is_researchable(force, queue, tech) then
      table.insert(to_dequeue, tech)
    end
  end
  for _, tech in ipairs(to_dequeue) do
    dequeue(force, queue, tech)
  end
  -- process newly started tech
  if mode==2 then
    storage.forces[force.index].queue_paused = false
    local tech = rqtech.new(force.research_queue[1], "current")
    enqueue_head(force, queue, tech)
  end

  -- research_queue_enabled removed in Factorio 2.0; queue is always enabled
  if true then
    if settings.global['rq-sync'].value == 'disabled' then
      return
    end
    if settings.global['rq-sync'].value == 'sync' then
      if mode == 0 then
        local rq = {}
        for i=1,7 do
          if queue[i] == nil then break end
          table.insert(rq, queue[i].tech)
        end
        set_queue(force, rq)
      elseif mode == 1 then
        local rq = force.research_queue
        if queues_identical(force, queue, #rq) and queue[7] then
          table.insert(rq, queue[7].tech)
          set_queue(force, rq)
        end
      elseif mode == 2 and paused then
        local rq = {}
        for i=1,7 do
          if queue[i] == nil then break end
          table.insert(rq, queue[i].tech)
        end
        set_queue(force, rq)
      elseif mode == 3 then
        if #queue > 7 then
          local rq = force.research_queue
          if queues_identical(force, queue) then return end
          local removed = {}
          if #force.research_queue < 7 and #force.research_queue < #queue then
            for i=1,7 do
              if queue[i] == nil then break end
              local present = false
              for j=1,#force.research_queue do
                if queue[i].tech.name == force.research_queue[j].name then
                  present = true
                  break
                end
              end
              if not present then table.insert(removed, queue[i]) end
            end
          end
          local new = 0
          for i=#rq, 1, -1 do
            new = new + (enqueue_head(force, queue, rqtech.new(rq[i], 'current', count_prev(rq, i))) and 1 or 0)
          end
          if new == 0 then
            for _,tech in ipairs(removed) do
              dequeue(force, queue, tech)
            end
          end
          rq = {}
          for i=1,7 do
            if queue[i] == nil then break end
            table.insert(rq, queue[i].tech)
          end
          set_queue(force, rq)
        else
          queue = clear(force, storage.forces[force.index])
          local rq = force.research_queue
          for i=1, #rq do
            enqueue_tail(force, queue, rqtech.new(rq[i], 'current', count_prev(rq, i)))
          end
        end
      elseif mode == 4 then
        if paused then
          set_queue(force, {})
        else
          local rq = {}
          for i=1,7 do
            if queue[i] == nil then break end
            table.insert(rq, queue[i].tech)
          end
          set_queue(force, rq)
        end
      end
    elseif settings.global['rq-sync'].value == 'hybrid' then
      if mode==0 or mode==1 or (mode==2 and paused) then
        local rq={}
        for i=1,4 do
          if queue[i] == nil then break end
          table.insert(rq, queue[i].tech)
        end
        set_queue(force, rq)
      elseif mode==3 then
        local old4 = {}
        for i=1,4 do
          if queue[i] == nil then break end
          table.insert(old4, queue[i])
        end
        local rq = force.research_queue
        for i=#rq,1,-1 do
          enqueue_head(force, queue, rqtech.new(rq[i], "current", count_prev(rq, i)))
        end
        local dq = {}
        for i=1,#old4 do
          local found = false
          for j=1, #rq do
            if old4[i].tech.name == rq[j].name then
              found = true
              break
            end
          end
          if not found then table.insert(dq, old4[i]) end
        end
        for _, tech in ipairs(dq) do
          dequeue(force, queue, tech)
        end
        for i=#rq,5,-1 do
          table.remove(rq)
        end
        set_queue(force, rq)
      elseif mode==4 then
        if paused then
          set_queue(force, {})
        else
          local rq = {}
          for i=1,4 do
            if queue[i] == nil then break end
            table.insert(rq, queue[i].tech)
          end
          set_queue(force, rq)
        end
      end
    elseif settings.global['rq-sync'].value == 'wait' then
      if #force.research_queue == 0 and not paused and next(queue) ~= nil then
        set_queue(force, {queue[1].tech})
      end
    elseif settings.global['rq-sync'].value == 'freeze' then
      if #queue == 0 or paused then return end
      if mode == 0 then
        local rq = force.research_queue
        rq[1] = queue[1].tech
        set_queue(force, rq)
      elseif mode==1 then
        if queue[1].tech.name ~= force.research_queue[1].name then
          local rq = {queue[1].tech}
          for _,tech in ipairs(force.research_queue) do
            table.insert(rq, tech)
          end
          set_queue(force, rq)
        end
      end
    elseif settings.global['rq-sync'].value == 'move-head' or settings.global['rq-sync'].value == 'move-tail' then
      if mode==2 then return end
      local rq = force.research_queue
      if mode == 3 and #rq > 1 then
        if settings.global['rq-sync'].value == 'move-head' then
          for i=#rq,1,-1 do
            enqueue_head(force, queue, rqtech.new(rq[i], 'current', count_prev(rq, i)))
          end
        else
          for i=1, #rq do
            enqueue_tail(force, queue, rqtech.new(rq[i], 'current', count_prev(rq, i)))
          end
        end
      end
      if not paused and next(queue) ~= nil then
        set_queue(force, {queue[1].tech})
      else
        set_queue(force, {})
      end
    end
  end
end

return {
  new = new,
  is_paused = function(force)
    local force_data = storage.forces[force.index]
    return force_data.queue_paused
  end,
  set_paused = function(force, paused)
    local force_data = storage.forces[force.index]
    force_data.queue_paused = paused
  end,
  toggle_paused = function(force, paused)
    local force_data = storage.forces[force.index]
    force_data.queue_paused = not force_data.queue_paused
  end,
  is_researchable = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return is_researchable(force, queue, tech)
  end,
  in_queue = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return in_queue(force, queue, tech)
  end,
  is_head = function(force, tech, ignore_level)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return is_head(force, queue, tech, ignore_level)
  end,
  get_head = function(force)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return get_head(force, queue)
  end,
  queue_pos = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return queue_pos(force, queue, tech)
  end,
  enqueue = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return enqueue(force, queue, tech)
  end,
  enqueue_tail = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return enqueue_tail(force, queue, tech)
  end,
  enqueue_head = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    force_data.queue_paused = false
    return enqueue_head(force, queue, tech)
  end,
  enqueue_before_head = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    local paused = force_data.queue_paused
    return enqueue_before_head(force, queue, paused, tech)
  end,
  shift_earlier = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return shift_earlier(force, queue, tech)
  end,
  shift_earliest = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return shift_earliest(force, queue, tech)
  end,
  can_shift_earlier = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return try_shift_earlier(force, queue, tech) ~= nil
  end,
  shift_before_earliest = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    local paused = force_data.queue_paused
    return shift_before_earliest(force, queue, paused, tech)
  end,
  shift_later = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return shift_later(force, queue, tech)
  end,
  shift_latest = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return shift_latest(force, queue, tech)
  end,
  can_shift_later = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return try_shift_later(force, queue, tech) ~= nil
  end,
  dequeue = function(force, tech)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return dequeue(force, queue, tech)
  end,
  clear = function(force)
    local force_data = storage.forces[force.index]
    return clear(force, force_data)
  end,
  iter = function(force)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    return iter(force, queue)
  end,
  update = function(force, mode)
    local force_data = storage.forces[force.index]
    local queue = force_data.queue
    local paused = force_data.queue_paused
    return update(force, queue, paused, mode)
  end
}
