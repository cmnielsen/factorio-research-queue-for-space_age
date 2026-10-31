-- Shared helpers: formatting, text search, LocalisedString joining and science pack availability.

local util = {}

---------------------------------------------------------------------------
-- Formatting
---------------------------------------------------------------------------

-- Formats a number of seconds as e.g. "1h2m3s".
function util.format_duration(seconds)
  local negative = seconds < 0
  if negative then seconds = -seconds end
  local s = math.floor(seconds % 60)
  local m = math.floor((seconds / 60) % 60)
  local h = math.floor(seconds / 3600)
  local text = ''
  if h > 0 then text = text .. string.format('%dh', h) end
  if m > 0 then text = text .. string.format('%dm', m) end
  text = text .. string.format('%ds', s)
  return negative and ('-' .. text) or text
end

-- Joins LocalisedString parts into one string. Factorio allows at most 20
-- parameters per LocalisedString, so long lists are split into nested groups.
function util.concat(parts)
  while #parts > 20 do
    local grouped = {}
    for first = 1, #parts, 20 do
      local group = {''}
      for i = first, math.min(first + 19, #parts) do
        group[#group + 1] = parts[i]
      end
      grouped[#grouped + 1] = group
    end
    parts = grouped
  end
  local result = {''}
  for _, part in ipairs(parts) do
    result[#result + 1] = part
  end
  return result
end

---------------------------------------------------------------------------
-- Text search
---------------------------------------------------------------------------

-- Lowercases text; uses the multilingual variant when the game provides it.
function util.to_lower(text)
  if helpers.multilingual_to_lower then
    return helpers.multilingual_to_lower(text)
  end
  return string.lower(text)
end

-- Splits a search string into lowercase words (letters and digits of any language).
function util.search_terms(text)
  local terms = {}
  for word in string.gmatch(util.to_lower(text or ''), '[^%c%s%p]+') do
    terms[#terms + 1] = word
  end
  return terms
end

-- True if every search term occurs somewhere in the (lowercase) haystack.
function util.matches_terms(haystack, terms)
  for _, term in ipairs(terms) do
    if not string.find(haystack, term, 1, true) then
      return false
    end
  end
  return true
end

---------------------------------------------------------------------------
-- Science pack availability
---------------------------------------------------------------------------

local function has_enabled_recipe(force, item_name)
  local recipes = prototypes.get_recipe_filtered{
    {filter = 'has-product-item', elem_filters = {{filter = 'name', name = item_name}}},
  }
  for recipe_name in pairs(recipes) do
    local recipe = force.recipes[recipe_name]
    if recipe and recipe.enabled then
      return true
    end
  end
  return false
end

local function is_rocket_silo_available(force)
  for _, silo in pairs(prototypes.get_entity_filtered{{filter = 'type', type = 'rocket-silo'}}) do
    for _, stack in pairs(silo.items_to_place_this or {}) do
      if has_enabled_recipe(force, stack.name) then
        return true
      end
    end
  end
  return false
end

-- True if the force can currently produce the item: either an unlocked recipe
-- makes it, or it is a rocket launch product of an item the force can craft.
local function check_item_available(force, item_name)
  if has_enabled_recipe(force, item_name) then
    return true
  end
  if not is_rocket_silo_available(force) then
    return false
  end
  for _, item in pairs(prototypes.get_item_filtered{{filter = 'has-rocket-launch-products'}}) do
    if has_enabled_recipe(force, item.name) then
      for _, product in pairs(item.rocket_launch_products) do
        if product.type == 'item' and product.name == item_name then
          return true
        end
      end
    end
  end
  return false
end

-- If the check itself fails the pack is treated as available, so technologies
-- are shown rather than hidden.
function util.is_item_available(force, item_name)
  local ok, available = pcall(check_item_available, force, item_name)
  if ok then
    return available
  end
  return true
end

---------------------------------------------------------------------------
-- Misc
---------------------------------------------------------------------------

-- The game can only be paused in single player (and not in the map editor),
-- and only if the player wants it.
function util.can_pause_game(player)
  if game.is_multiplayer() or player.controller_type == defines.controllers.editor then
    return false
  end
  return settings.get_player_settings(player)['rq-pause-game'].value
end

return util
