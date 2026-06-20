local M = {}

local VALID_DIRECTIONS = {
    right = true,
    left = true,
    down = true,
    up = true,
}

local VALID_TILING_MODES = {
    split = true,
    ajuste = true,
}

local VALID_INSERT_MODES = {
    last = true,
    first = true,
    view = true,
    after_focused = true,
    before_focused = true,
}

M.raw_config = {
    default = {
        allowed_dimensions = {
            { 1.0, 1.0 },
            { 0.5, 1.0 },
            { 0.5, 0.5 },
        },
        scroll_direction = "right",
        tiling_mode = "split",
        insert_mode = "view",
    },
    displays = {},
}

local function copy_array(values)
    local out = {}
    for i, value in ipairs(values or {}) do
        out[i] = value
    end
    return out
end

local function format_number(value)
    if math.abs(value - math.floor(value)) < 0.0000001 then
        return string.format("%.1f", value)
    end

    local formatted = string.format("%.6f", value)
    formatted = formatted:gsub("0+$", ""):gsub("%.$", "")
    return formatted
end

function M.dimension_key(dimension)
    return format_number(dimension.w) .. "x" .. format_number(dimension.h)
end

local function dimension_value(raw_dimension)
    if type(raw_dimension) ~= "table" then
        return nil, nil
    end

    return raw_dimension.w or raw_dimension[1], raw_dimension.h or raw_dimension[2]
end

local function normalize_dimension(raw_dimension, display_id, index)
    local w, h = dimension_value(raw_dimension)
    local path = "display " .. tostring(display_id) .. " allowed_dimensions[" .. tostring(index) .. "]"

    if type(w) ~= "number" or w <= 0 or w > 1 then
        return nil, "fit-scroller: " .. path .. ".w must be > 0 and <= 1"
    end

    if type(h) ~= "number" or h <= 0 or h > 1 then
        return nil, "fit-scroller: " .. path .. ".h must be > 0 and <= 1"
    end

    local dimension = { w = w, h = h }
    dimension.key = M.dimension_key(dimension)
    return dimension
end

local function normalize(raw_display_config, display_id)
    if type(raw_display_config) ~= "table" then
        return nil, "fit-scroller: missing configuration for display " .. tostring(display_id)
    end

    local raw_dimensions = raw_display_config.allowed_dimensions
    if type(raw_dimensions) ~= "table" or #raw_dimensions == 0 then
        return nil, "fit-scroller: display " .. tostring(display_id) .. " allowed_dimensions must be a non-empty list"
    end

    local direction = raw_display_config.scroll_direction
    if not VALID_DIRECTIONS[direction] then
        return nil, "fit-scroller: display " .. tostring(display_id) .. " scroll_direction must be one of right, left, down, up"
    end

    local tiling_mode = raw_display_config.tiling_mode or "split"
    if not VALID_TILING_MODES[tiling_mode] then
        return nil, "fit-scroller: display " .. tostring(display_id) .. " tiling_mode must be one of split, ajuste"
    end

    local insert_mode = raw_display_config.insert_mode or "view"
    if not VALID_INSERT_MODES[insert_mode] then
        return nil, "fit-scroller: display " .. tostring(display_id) .. " insert_mode must be one of last, first, view, after_focused, before_focused"
    end

    local dimensions = {}
    local by_key = {}

    for i, raw_dimension in ipairs(raw_dimensions) do
        local dimension, err = normalize_dimension(raw_dimension, display_id, i)
        if not dimension then
            return nil, err
        end

        if by_key[dimension.key] then
            return nil, "fit-scroller: duplicate allowed dimension for display " .. tostring(display_id) .. ": " .. dimension.key
        end

        by_key[dimension.key] = dimension
        table.insert(dimensions, dimension)
    end

    table.sort(dimensions, function(a, b)
        local area_a = a.w * a.h
        local area_b = b.w * b.h
        if area_a ~= area_b then
            return area_a > area_b
        end
        if a.w ~= b.w then
            return a.w > b.w
        end
        return a.h > b.h
    end)

    local cycle = {}
    for i, dimension in ipairs(dimensions) do
        cycle[i] = dimension.key
    end

    return {
        display_id = display_id,
        allowed_dimensions = dimensions,
        dimensions_by_key = by_key,
        toggle_cycle = cycle,
        scroll_direction = direction,
        tiling_mode = tiling_mode,
        insert_mode = insert_mode,
    }
end

function M.resolve_display(raw_config, display_id)
    if type(raw_config) ~= "table" then
        return nil, "fit-scroller: config must be a table"
    end

    if type(raw_config.default) ~= "table" then
        return nil, "fit-scroller: config.default must be a table"
    end

    local effective = {
        allowed_dimensions = copy_array(raw_config.default.allowed_dimensions),
        scroll_direction = raw_config.default.scroll_direction,
        tiling_mode = raw_config.default.tiling_mode,
        insert_mode = raw_config.default.insert_mode,
    }

    local displays = raw_config.displays
    local override = type(displays) == "table" and displays[display_id] or nil
    if override then
        if override.allowed_dimensions ~= nil then
            effective.allowed_dimensions = copy_array(override.allowed_dimensions)
        end
        if override.scroll_direction ~= nil then
            effective.scroll_direction = override.scroll_direction
        end
        if override.tiling_mode ~= nil then
            effective.tiling_mode = override.tiling_mode
        end
        if override.insert_mode ~= nil then
            effective.insert_mode = override.insert_mode
        end
    end

    return effective
end

function M.validate(raw_config)
    local effective, err = M.resolve_display(raw_config, "default")
    if not effective then
        return nil, err
    end

    return normalize(effective, "default")
end

function M.get_for_display(display_id, raw_config)
    local source = raw_config or M.raw_config
    local resolved, err = M.resolve_display(source, display_id or "default")
    if not resolved then
        return nil, err
    end

    return normalize(resolved, display_id or "default")
end

function M.is_allowed_dimension_key(config, key)
    return type(config) == "table"
        and type(config.dimensions_by_key) == "table"
        and config.dimensions_by_key[key] ~= nil
end

local function mode_key(mode)
    if type(mode) == "table" then
        if mode.kind == "auto" then
            return nil
        end
        return mode.key
    end

    if mode == "auto" then
        return nil
    end

    return mode
end

function M.next_dimension_mode(config, current_mode)
    if type(config) ~= "table" or type(config.toggle_cycle) ~= "table" then
        return nil, "fit-scroller: missing normalized configuration"
    end

    local key = mode_key(current_mode)
    if not key then
        return { kind = "forced", key = config.toggle_cycle[1] }
    end

    for i, cycle_key in ipairs(config.toggle_cycle) do
        if cycle_key == key then
            local next_key = config.toggle_cycle[i + 1]
            if next_key then
                return { kind = "forced", key = next_key }
            end

            return { kind = "auto" }
        end
    end

    return nil, "fit-scroller: invalid forced dimension mode: " .. tostring(key)
end

return M
