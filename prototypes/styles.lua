-- GUI styles for the research queue window.
-- Layout constants and the tech button states below are shared by many styles.

local util = require('util')

local styles = data.raw['gui-style'].default

local TECH_LIST_BUTTON_SIZE = 64 + 8 * 2 + 8
local TECH_QUEUE_BUTTON_SIZE = 64 * 4 / 4 + 8

---------------------------------------------------------------------------
-- Tech state graphics (cut from the core gui sprite sheet)
---------------------------------------------------------------------------

local STATES = {
  {name = 'available', style = 'available'},
  {name = 'unavailable', style = 'unavailable'},
  {name = 'queued', style = 'conditionally_available'},
  {name = 'queued_head', style = 'conditionally_available', highlighted = true},
  {name = 'researched', style = 'researched'},
}

local STATE_ROW = {
  available = 136,
  conditionally_available = 153,
  unavailable = 170,
  researched = 187,
}

local function tech_graphical_set(kind, state)
  local y = STATE_ROW[state.style]
  local function base(x)
    return {base = {position = {x, y}, corner_size = 8}, shadow = default_shadow}
  end

  if kind == 'button' then
    local default_set = base(state.highlighted and 330 or 296)
    local other_set = base(312)
    return {
      default_graphical_set = default_set,
      hovered_graphical_set = other_set,
      clicked_graphical_set = other_set,
      selected_graphical_set = other_set,
      selected_hovered_graphical_set = other_set,
      selected_clicked_graphical_set = other_set,
    }
  elseif kind == 'ingredients' then
    return base(state.highlighted and 364 or 347)
  elseif kind == 'level' then
    return base(397)
  end
  error('unknown tech graphical set: ' .. tostring(kind))
end

---------------------------------------------------------------------------
-- Windows and containers
---------------------------------------------------------------------------

styles.rq_main_window = {
  type = 'frame_style',
  parent = 'inside_shallow_frame_with_padding',
  height = 770,
}

styles.rq_settings_window = {
  type = 'frame_style',
  parent = 'inside_shallow_frame_with_padding',
  height = 770,
}

styles.rq_settings_section = {
  type = 'frame_style',
  parent = 'inside_shallow_frame_with_padding',
}

styles.rq_list_box = {
  type = 'scroll_pane_style',
  vertically_stretchable = 'on',
  extra_padding_when_activated = 0,
  graphical_set = {
    base = {position = {34, 0}, corner_size = 8},
    shadow = default_inner_shadow,
  },
}

styles.rq_tech_ingredient_filter_scroll_pane = {
  type = 'scroll_pane_style',
}

---------------------------------------------------------------------------
-- Science pack filter buttons
---------------------------------------------------------------------------

styles.rq_tech_ingredient_filter_button_enabled = {
  type = 'button_style',
  parent = 'green_slot',
}

styles.rq_tech_ingredient_filter_button_disabled = {
  type = 'button_style',
  parent = 'slot',
}

---------------------------------------------------------------------------
-- Technology list (right side of the window)
---------------------------------------------------------------------------

styles.rq_tech_list_list_box = {
  type = 'scroll_pane_style',
  parent = 'rq_list_box',
  width = 4 + 7 * TECH_LIST_BUTTON_SIZE + 4 + 12,
  background_graphical_set = {
    position = {282, 17},
    corner_size = 8,
    overall_tiling_horizontal_size = TECH_LIST_BUTTON_SIZE - 8,
    overall_tiling_horizontal_padding = 8 / 2,
    overall_tiling_horizontal_spacing = 8,
    overall_tiling_vertical_size = TECH_LIST_BUTTON_SIZE + 4 + 16 + 4 + 40 - 8,
    overall_tiling_vertical_padding = 8 / 2,
    overall_tiling_vertical_spacing = 8,
  },
}

styles.rq_tech_list_table = {
  type = 'table_style',
  horizontally_stretchable = 'off',
  horizontal_spacing = 0,
  vertical_spacing = 0,
}

-- Every cell has a fixed width so no content can widen a column of the table
styles.rq_tech_list_item = {
  type = 'vertical_flow_style',
  vertical_spacing = 0,
  width = TECH_LIST_BUTTON_SIZE,
  maximal_width = TECH_LIST_BUTTON_SIZE,
}

styles.rq_tech_list_item_ingredient = {
  type = 'image_style',
  width = 16,
  height = 16,
  stretch_image_to_widget_size = true,
}

styles.rq_tech_list_item_tool_button = {
  type = 'button_style',
  parent = 'tool_button',
  size = 24,
  padding = 0,
}

-- Bars shared by all tech states; the state variants only change the graphics
styles.rq_tech_list_item_ingredients_bar = {
  type = 'frame_style',
  padding = 0,
  maximal_width = TECH_LIST_BUTTON_SIZE,
  horizontal_flow_style = {
    type = 'horizontal_flow_style',
    horizontally_stretchable = 'on',
    horizontal_align = 'left',
  },
}

styles.rq_tech_list_item_tool_bar = {
  type = 'frame_style',
  padding = 0,
  maximal_width = TECH_LIST_BUTTON_SIZE,
  top_padding = 4,
  bottom_padding = 4,
  horizontal_flow_style = {
    type = 'horizontal_flow_style',
    horizontally_stretchable = 'on',
    horizontal_align = 'center',
  },
}

-- One variant of button / ingredients bar / tool bar per tech state
for _, state in ipairs(STATES) do
  local prefix = 'rq_tech_list_item_' .. state.name

  styles[prefix .. '_tech_button'] = util.merge{
    {type = 'button_style', size = TECH_LIST_BUTTON_SIZE},
    tech_graphical_set('button', state),
  }

  styles[prefix .. '_ingredients_bar'] = {
    type = 'frame_style',
    parent = 'rq_tech_list_item_ingredients_bar',
    graphical_set = tech_graphical_set('level', state),
  }

  styles[prefix .. '_tool_bar'] = {
    type = 'frame_style',
    parent = 'rq_tech_list_item_tool_bar',
    graphical_set = tech_graphical_set('ingredients', state),
  }
end

---------------------------------------------------------------------------
-- Queue (left side of the window)
---------------------------------------------------------------------------

local QUEUE_ITEM_INNER_WIDTH = TECH_QUEUE_BUTTON_SIZE + 8 + 16
local QUEUE_ITEM_WIDTH = 2 + 4 + QUEUE_ITEM_INNER_WIDTH + 4 + 2
local QUEUE_ITEM_INNER_HEIGHT = TECH_QUEUE_BUTTON_SIZE + 4 + 20
local QUEUE_ITEM_HEIGHT = 2 + 4 + QUEUE_ITEM_INNER_HEIGHT + 4 + 2

styles.rq_tech_queue_head_frame = {
  type = 'frame_style',
  width = 4 + QUEUE_ITEM_WIDTH + 4,
  height = 4 + QUEUE_ITEM_HEIGHT + 4,
  padding = 0,
  horizontal_flow_style = {
    type = 'horizontal_flow_style',
    padding = 0,
  },
  graphical_set = {
    base = {position = {34, 0}, corner_size = 8},
    shadow = default_inner_shadow,
  },
  background_graphical_set = {
    position = {282, 17},
    corner_size = 8,
    overall_tiling_horizontal_size = QUEUE_ITEM_WIDTH,
    overall_tiling_horizontal_padding = 4,
    overall_tiling_vertical_size = QUEUE_ITEM_HEIGHT,
    overall_tiling_vertical_padding = 4,
    overall_tiling_vertical_spacing = 4,
  },
}

styles.rq_tech_queue_item_paused = {
  type = 'horizontal_flow_style',
  horizontally_stretchable = 'on',
  height = QUEUE_ITEM_HEIGHT,
  horizontal_align = 'center',
  vertical_align = 'center',
}

styles.rq_tech_queue_item_paused_unpause_button = {
  type = 'button_style',
  parent = 'tool_button_green',
}

styles.rq_tech_queue_list_box = {
  type = 'scroll_pane_style',
  parent = 'rq_list_box',
  width = 4 + QUEUE_ITEM_WIDTH + 4 + 12,
  background_graphical_set = {
    position = {282, 17},
    corner_size = 8,
    overall_tiling_horizontal_size = QUEUE_ITEM_WIDTH,
    overall_tiling_vertical_size = QUEUE_ITEM_HEIGHT,
    overall_tiling_vertical_spacing = 4,
  },
}

styles.rq_tech_queue_item = {
  type = 'frame_style',
  parent = 'inside_shallow_frame',
  padding = 2,
  horizontal_flow_style = {
    type = 'horizontal_flow_style',
    vertically_stretchable = 'off',
    horizontal_spacing = 8,
  },
}

styles.rq_tech_queue_item_inner_flow = {
  type = 'vertical_flow_style',
}

styles.rq_tech_queue_item_tech_button = util.merge{
  {type = 'button_style', size = TECH_QUEUE_BUTTON_SIZE, padding = 0},
  tech_graphical_set('button', STATES[3]),
}

styles.rq_tech_queue_head_item_tech_button = util.merge{
  {type = 'button_style', size = TECH_QUEUE_BUTTON_SIZE, padding = 0},
  tech_graphical_set('button', STATES[4]),
}

styles.rq_tech_queue_item_buttons = {
  type = 'vertical_flow_style',
  horizontal_align = 'center',
  vertical_spacing = 0,
  top_padding = 4,
  bottom_padding = 4,
}

styles.rq_tech_queue_item_close_button = {
  type = 'button_style',
  parent = 'mini_button',
}

-- Small arrow buttons that move a technology up or down in the queue
local function arrow_button(direction)
  local path = '__core__/graphics/arrows/table-header-sort-arrow-' .. direction
  local function sprite(suffix)
    return {filename = path .. suffix .. '.png', size = {16, 16}, scale = 0.5}
  end
  return {
    type = 'button_style',
    size = {8, 8},
    padding = 0,
    default_graphical_set = sprite('-active'),
    hovered_graphical_set = sprite('-hover'),
    clicked_graphical_set = sprite('-active'),
    disabled_graphical_set = util.empty_sprite(),
  }
end

styles.rq_tech_queue_item_shift_up_button = arrow_button('up')
styles.rq_tech_queue_item_shift_down_button = arrow_button('down')

styles.rq_etc_label = {
  type = 'label_style',
  parent = 'label',
  font = 'count-font',
  maximal_width = TECH_QUEUE_BUTTON_SIZE,
}

---------------------------------------------------------------------------
-- Tech button containers and progress bars (list and queue variants)
---------------------------------------------------------------------------

styles.rq_tech_button_container = {
  type = 'vertical_flow_style',
  vertical_spacing = 0,
  padding = 0,
  margin = 0,
}

styles.rq_tech_button_container_tech_list = {
  type = 'vertical_flow_style',
  parent = 'rq_tech_button_container',
  height = TECH_LIST_BUTTON_SIZE,
}

styles.rq_tech_button_container_tech_queue = {
  type = 'vertical_flow_style',
  parent = 'rq_tech_button_container',
  height = TECH_QUEUE_BUTTON_SIZE,
}

styles.rq_tech_button_progressbar = {
  type = 'progressbar_style',
  horizontally_stretchable = 'on',
  bar_width = 4,
  bar_background = {position = {296, 39}, corner_size = 4},
  bar = {position = {305, 39}, corner_size = 4},
}

styles.rq_tech_button_progressbar_tech_list = {
  type = 'progressbar_style',
  parent = 'rq_tech_button_progressbar',
  top_margin = -TECH_LIST_BUTTON_SIZE,
}

styles.rq_tech_button_progressbar_tech_queue = {
  type = 'progressbar_style',
  parent = 'rq_tech_button_progressbar',
  top_margin = -TECH_QUEUE_BUTTON_SIZE,
}

---------------------------------------------------------------------------
-- Titlebar action buttons
---------------------------------------------------------------------------

local function action_button(row)
  local function set(x)
    return {base = {position = {x, row}, corner_size = 8}, shadow = default_shadow}
  end
  return {
    type = 'button_style',
    parent = 'frame_action_button',
    default_graphical_set = set(272),
    hovered_graphical_set = set(369),
    clicked_graphical_set = set(369),
  }
end

styles.rq_frame_action_button_red = action_button(169)
styles.rq_frame_action_button_green = action_button(186)
