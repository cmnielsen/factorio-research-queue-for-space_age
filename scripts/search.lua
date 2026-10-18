-- Technology name search in the player's own language.
-- Technology names are translated through request_translation; each request
-- carries the technology's internal name so the answer can be matched back.

local util = require('scripts.util')

local search = {}

local MARKER = 'rqtn'

-- Requests translations of all technology names if the player's language
-- changed (or was never requested). Answers arrive later as events.
function search.request(player)
  local pdata = storage.players[player.index]
  if pdata.locale == player.locale then
    return
  end
  pdata.locale = player.locale
  pdata.names = {}
  for name, tech in pairs(player.force.technologies) do
    player.request_translation{'', MARKER .. '|' .. name .. '|', tech.localised_name}
  end
end

-- Forces a new request the next time the window opens.
function search.invalidate(player_data)
  player_data.locale = nil
end

function search.on_string_translated(event)
  if not event.translated or type(event.result) ~= 'string' then
    return
  end
  local name, text = string.match(event.result, '^' .. MARKER .. '|([^|]*)|(.*)$')
  if not name then
    return -- a translation requested by another mod
  end
  local pdata = storage.players[event.player_index]
  if pdata then
    pdata.names[name] = util.to_lower(text)
  end
end

return search
