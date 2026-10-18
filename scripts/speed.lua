-- Research speed estimate, used for the time estimates in the queue.
-- Once per second the research progress is sampled; the speed is the average
-- amount of lab work (in seconds of research) completed per second.

local rqtech = require('scripts.rqtech')

local speed = {}

local MAX_SAMPLES = 4

function speed.sample(force)
  local data = storage.forces[force.index]
  local tech = force.current_research
  if not tech then
    data.samples = {}
    data.speed = 0
    return
  end

  local samples = data.samples
  samples[#samples + 1] = {name = tech.name, progress = force.research_progress}
  if #samples > MAX_SAMPLES then
    table.remove(samples, 1)
  end

  -- Seconds of lab work needed for the whole technology
  local rt = rqtech.current(tech)
  local total_work = (tech.research_unit_energy / 60) * (rt.research_unit_count or 0)

  local sum, count = 0, 0
  for i = 2, #samples do
    local previous, current = samples[i - 1], samples[i]
    if previous.name == current.name and current.progress >= previous.progress then
      sum = sum + (current.progress - previous.progress) * total_work
      count = count + 1
    end
  end
  data.speed = count > 0 and (sum / count) or 0
end

return speed
