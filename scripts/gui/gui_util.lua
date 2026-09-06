-- Build a GUI element tree using native Factorio API.
-- Replaces flib's gui.add which changed API in flib 2.0.
-- def: element definition table (same structure as flib gui.add used)
-- refs: optional table to collect named refs into
-- Returns: the refs table
local function build_gui(parent, def, refs)
  refs = refs or {}

  local spec = {}
  for k, v in pairs(def) do
    if k ~= 'ref' and k ~= 'children' and k ~= 'elem_mods' and k ~= 'style_mods' then
      spec[k] = v
    end
  end

  local elem = parent.add(spec)

  if def.elem_mods then
    for k, v in pairs(def.elem_mods) do
      elem[k] = v
    end
  end

  if def.style_mods then
    for k, v in pairs(def.style_mods) do
      elem.style[k] = v
    end
  end

  if def.ref then
    refs[def.ref] = elem
  end

  if def.children then
    for _, child_def in ipairs(def.children) do
      build_gui(elem, child_def, refs)
    end
  end

  return refs
end

return { build_gui = build_gui }
