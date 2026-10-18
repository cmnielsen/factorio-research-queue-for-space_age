-- Builds a GUI element tree from a nested table description.
-- Special keys in a description: ref (store the element in the refs table under
-- this name), children, elem_mods (properties set after creation) and
-- style_mods (style properties set after creation). All other keys are passed
-- to LuaGuiElement.add.

local builder = {}

function builder.build(parent, definition, refs)
  refs = refs or {}

  local spec = {}
  for key, value in pairs(definition) do
    if key ~= 'ref' and key ~= 'children' and key ~= 'elem_mods' and key ~= 'style_mods' then
      spec[key] = value
    end
  end

  local element = parent.add(spec)
  for key, value in pairs(definition.elem_mods or {}) do
    element[key] = value
  end
  for key, value in pairs(definition.style_mods or {}) do
    element.style[key] = value
  end
  if definition.ref then
    refs[definition.ref] = element
  end
  for _, child in ipairs(definition.children or {}) do
    builder.build(element, child, refs)
  end
  return refs
end

---------------------------------------------------------------------------
-- Element templates
---------------------------------------------------------------------------

-- Copies `defaults` and overrides it with `props`.
local function with(defaults, props)
  for key, value in pairs(props or {}) do
    defaults[key] = value
  end
  return defaults
end

function builder.frame_title(caption)
  return {
    type = 'label',
    style = 'frame_title',
    caption = caption,
    elem_mods = {ignored_by_interaction = true},
  }
end

-- Stretches to fill the titlebar so the window can be dragged by it.
function builder.drag_handle()
  return {
    type = 'empty-widget',
    style = 'draggable_space_header',
    style_mods = {horizontally_stretchable = true, height = 24, right_margin = 4},
    elem_mods = {ignored_by_interaction = true},
  }
end

function builder.pusher()
  return {type = 'empty-widget', style_mods = {vertically_stretchable = true}}
end

function builder.frame_action_button(props)
  return with({type = 'sprite-button', style = 'frame_action_button', mouse_button_filter = {'left'}}, props)
end

function builder.tool_button(props)
  return with({type = 'sprite-button', style = 'tool_button', mouse_button_filter = {'left'}}, props)
end

return builder
