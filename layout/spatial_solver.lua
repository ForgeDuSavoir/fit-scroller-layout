local M = {}

local spatial_geometry = nil

local LOCAL_EVENTS = {
    window_added = true,
    window_removed = true,
    dimension_forced = true,
    dimension_auto = true,
    move = true,
}

local GLOBAL_EVENTS = {
    initial = true,
    config_changed = true,
}

function M.set_dependencies(dependencies)
    spatial_geometry = dependencies and dependencies.spatial_geometry
end

local function result_error(message)
    return {
        ok = false,
        error = "fit-scroller: spatial: " .. message,
    }
end

local function is_finite_number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function target_ids(targets)
    if type(targets) ~= "table" then
        return nil, "targets must be a list"
    end

    local ids = {}
    local seen = {}
    for i, target in ipairs(targets) do
        if type(target) ~= "table" then
            return nil, "target at index " .. tostring(i) .. " must be a table"
        end

        local id = target.id
        if id == nil or id == "" then
            return nil, "target at index " .. tostring(i) .. " has no id"
        end

        if seen[id] then
            return nil, "duplicate target id: " .. tostring(id)
        end

        seen[id] = true
        table.insert(ids, id)
    end

    return ids
end

local function validate_dimension(dimension)
    return type(dimension) == "table"
        and type(dimension.key) == "string"
        and is_finite_number(dimension.w)
        and is_finite_number(dimension.h)
        and dimension.w > 0
        and dimension.w <= 1
        and dimension.h > 0
        and dimension.h <= 1
end

local function validate_config(config)
    if type(config) ~= "table" then
        return nil, "missing normalized configuration"
    end

    if config.placement_priority ~= "spatial" then
        return nil, "config.placement_priority must be spatial"
    end

    if not spatial_geometry.direction_info(config.scroll_direction) then
        return nil, "unsupported scroll direction: " .. tostring(config.scroll_direction)
    end

    if type(config.allowed_dimensions) ~= "table" or #config.allowed_dimensions == 0 then
        return nil, "config.allowed_dimensions must be non-empty"
    end

    if type(config.dimensions_by_key) ~= "table" then
        return nil, "missing config.dimensions_by_key"
    end

    for _, dimension in ipairs(config.allowed_dimensions) do
        if not validate_dimension(dimension) then
            return nil, "config.allowed_dimensions contains an invalid dimension"
        end
    end

    return true
end

local function event_kind(input)
    local event = type(input.event) == "table" and input.event or { kind = "initial" }
    return event.kind or "initial", event
end

local function validate_last_layout(last_layout)
    if type(last_layout) ~= "table" or type(last_layout.placements_by_id) ~= "table" then
        return nil, "last_layout placements are required for local spatial event"
    end

    for id, rect in pairs(last_layout.placements_by_id) do
        local valid, err = spatial_geometry.validate_rect(rect)
        if not valid then
            return nil, "last_layout placement is invalid for " .. tostring(id) .. ": " .. err
        end
    end

    return true
end

local function mode_for(input, id)
    local mode = input.dimension_mode_by_id[id]
    if mode == nil then
        return { kind = "auto" }
    end

    if type(mode) ~= "table" then
        return nil, "dimension mode for " .. tostring(id) .. " must be a table"
    end

    if mode.kind == "auto" then
        return mode
    end

    if mode.kind == "forced" then
        if type(mode.key) ~= "string" or mode.key == "" then
            return nil, "forced dimension mode for " .. tostring(id) .. " has no key"
        end
        return mode
    end

    return nil, "unsupported dimension mode for " .. tostring(id) .. ": " .. tostring(mode.kind)
end

local function dimension_for(input, id)
    local mode, mode_err = mode_for(input, id)
    if not mode then
        return nil, mode_err
    end

    if mode.kind == "forced" then
        local dimension = input.config.dimensions_by_key[mode.key]
        if not dimension then
            return nil, "forced dimension is not allowed for " .. tostring(id) .. ": " .. tostring(mode.key)
        end
        return dimension
    end

    return input.config.allowed_dimensions[1]
end

local function is_auto(input, id)
    local mode, mode_err = mode_for(input, id)
    if not mode then
        return nil, mode_err
    end

    return mode.kind == "auto"
end

local function placement_for(direction, offset, dimension)
    if direction == "right" then
        return { x = offset, y = 0, w = dimension.w, h = dimension.h }
    end

    if direction == "left" then
        return { x = -(offset + dimension.w), y = 0, w = dimension.w, h = dimension.h }
    end

    if direction == "down" then
        return { x = 0, y = offset, w = dimension.w, h = dimension.h }
    end

    if direction == "up" then
        return { x = 0, y = -(offset + dimension.h), w = dimension.w, h = dimension.h }
    end
end

local function rect_dimension(input, id, rect)
    local previous_dimensions = type(input.last_layout) == "table" and input.last_layout.dimensions_by_id or nil
    local previous_dimension = type(previous_dimensions) == "table" and previous_dimensions[id] or nil
    if validate_dimension(previous_dimension) then
        return {
            key = previous_dimension.key,
            w = previous_dimension.w,
            h = previous_dimension.h,
        }
    end

    for _, dimension in ipairs(input.config.allowed_dimensions) do
        if math.abs(dimension.w - rect.w) <= 0.000001 and math.abs(dimension.h - rect.h) <= 0.000001 then
            return {
                key = dimension.key,
                w = dimension.w,
                h = dimension.h,
            }
        end
    end
end

local function scroll_size(direction, dimension)
    local info = spatial_geometry.direction_info(direction)
    if info.scroll_axis == "x" then
        return dimension.w
    end

    return dimension.h
end

local function workspace_extent_for(direction, placements_by_id)
    local extent = 0
    for _, rect in pairs(placements_by_id or {}) do
        local _, finish = spatial_geometry.scroll_interval(rect, direction)
        if finish and finish > extent then
            extent = finish
        end
    end
    return extent
end

local function copy_previous_layout(input)
    local placements_by_id = {}
    local dimensions_by_id = {}
    local previous = input.last_layout

    for id, rect in pairs(previous.placements_by_id or {}) do
        placements_by_id[id] = {
            x = rect.x,
            y = rect.y,
            w = rect.w,
            h = rect.h,
        }

        local dimension = rect_dimension(input, id, rect)
        if dimension then
            dimensions_by_id[id] = dimension
        end
    end

    return placements_by_id, dimensions_by_id
end

local validate_output_rect

local function validate_layout_rects(placements_by_id, ids, direction)
    for _, id in ipairs(ids) do
        local rect = placements_by_id[id]
        if not rect then
            return nil, "missing placement for " .. tostring(id)
        end

        local valid, err = validate_output_rect(rect, direction)
        if not valid then
            return nil, "invalid placement for " .. tostring(id) .. ": " .. err
        end
    end

    for i = 1, #ids do
        for j = i + 1, #ids do
            local a = placements_by_id[ids[i]]
            local b = placements_by_id[ids[j]]
            if spatial_geometry.overlaps(a, b) then
                return nil, "placements overlap: " .. tostring(ids[i]) .. " and " .. tostring(ids[j])
            end
        end
    end

    return true
end

validate_output_rect = function(rect, direction)
    local valid_rect, rect_err = spatial_geometry.validate_rect(rect)
    if not valid_rect then
        return nil, rect_err
    end

    if not spatial_geometry.is_within_cross_axis(rect, direction) then
        return nil, "placement exceeds cross axis"
    end

    return true
end

local function has_target_id(ids, target_id)
    for _, id in ipairs(ids) do
        if id == target_id then
            return true
        end
    end
    return false
end

local function clone_dimension(dimension)
    return {
        key = dimension.key,
        w = dimension.w,
        h = dimension.h,
    }
end

local function clone_rect(rect)
    return {
        x = rect.x,
        y = rect.y,
        w = rect.w,
        h = rect.h,
    }
end

local function rect_union(a, b)
    local x1 = math.min(a.x, b.x)
    local y1 = math.min(a.y, b.y)
    local x2 = math.max(a.x + a.w, b.x + b.w)
    local y2 = math.max(a.y + a.h, b.y + b.h)

    return {
        x = x1,
        y = y1,
        w = x2 - x1,
        h = y2 - y1,
    }
end

local function matching_dimension(dimensions, rect)
    for _, dimension in ipairs(dimensions) do
        if math.abs(dimension.w - rect.w) <= 0.000001
            and math.abs(dimension.h - rect.h) <= 0.000001 then
            return dimension
        end
    end
end

local function intervals_equal(a_start, a_end, b_start, b_end)
    return math.abs(a_start - b_start) <= 0.000001
        and math.abs(a_end - b_end) <= 0.000001
end

local function spans_full_cross_axis(rect, direction)
    local start, finish = spatial_geometry.cross_interval(rect, direction)
    return start and start <= 0.000001 and finish >= 1 - 0.000001
end

local function rect_with_scroll_interval(rect, direction, scroll_start, scroll_end)
    if direction == "right" or direction == "left" then
        return {
            x = scroll_start,
            y = rect.y,
            w = scroll_end - scroll_start,
            h = rect.h,
        }
    end

    return {
        x = rect.x,
        y = scroll_start,
        w = rect.w,
        h = scroll_end - scroll_start,
    }
end

local function rect_with_intervals(direction, scroll_start, scroll_end, cross_start, cross_end)
    if direction == "right" or direction == "left" then
        return {
            x = scroll_start,
            y = cross_start,
            w = scroll_end - scroll_start,
            h = cross_end - cross_start,
        }
    end

    return {
        x = cross_start,
        y = scroll_start,
        w = cross_end - cross_start,
        h = scroll_end - scroll_start,
    }
end

local function scroll_axis_size(rect, direction)
    local info = spatial_geometry.direction_info(direction)
    return spatial_geometry.axis_size(rect, info.scroll_axis)
end

local function dimension_scroll_size(dimension, direction)
    local info = spatial_geometry.direction_info(direction)
    if info.scroll_axis == "x" then
        return dimension.w
    end
    return dimension.h
end

local function dimension_cross_size(dimension, direction)
    local info = spatial_geometry.direction_info(direction)
    if info.cross_axis == "x" then
        return dimension.w
    end
    return dimension.h
end

local function shift_rect_on_scroll_axis(rect, direction, amount)
    if direction == "right" then
        return { x = rect.x - amount, y = rect.y, w = rect.w, h = rect.h }
    end

    if direction == "left" then
        return { x = rect.x + amount, y = rect.y, w = rect.w, h = rect.h }
    end

    if direction == "down" then
        return { x = rect.x, y = rect.y - amount, w = rect.w, h = rect.h }
    end

    if direction == "up" then
        return { x = rect.x, y = rect.y + amount, w = rect.w, h = rect.h }
    end
end

local function is_after_scroll_hole(rect, hole, direction)
    if direction == "right" then
        return rect.x >= hole.x + hole.w - 0.000001
    end

    if direction == "left" then
        return rect.x + rect.w <= hole.x + 0.000001
    end

    if direction == "down" then
        return rect.y >= hole.y + hole.h - 0.000001
    end

    if direction == "up" then
        return rect.y + rect.h <= hole.y + 0.000001
    end
end

local function freed_scroll_axis_holes(previous_rect, next_rect, direction)
    local holes = {}
    if not previous_rect or not next_rect then
        return holes
    end

    local previous_cross_start, previous_cross_end = spatial_geometry.cross_interval(previous_rect, direction)
    local next_cross_start, next_cross_end = spatial_geometry.cross_interval(next_rect, direction)
    if not intervals_equal(previous_cross_start, previous_cross_end, next_cross_start, next_cross_end) then
        return holes
    end

    local info = spatial_geometry.direction_info(direction)
    local previous_start, previous_end = spatial_geometry.interval(previous_rect, info.scroll_axis)
    local next_start, next_end = spatial_geometry.interval(next_rect, info.scroll_axis)

    if next_start > previous_start + 0.000001 then
        table.insert(holes, rect_with_scroll_interval(previous_rect, direction, previous_start, next_start))
    end

    if next_end < previous_end - 0.000001 then
        table.insert(holes, rect_with_scroll_interval(previous_rect, direction, next_end, previous_end))
    end

    return holes
end

local function resized_top_left(rect, dimension)
    return {
        x = rect.x,
        y = rect.y,
        w = dimension.w,
        h = dimension.h,
    }
end

local function resized_center(rect, dimension)
    local center = spatial_geometry.center(rect)
    return {
        x = center.x - dimension.w / 2,
        y = center.y - dimension.h / 2,
        w = dimension.w,
        h = dimension.h,
    }
end

local function best_append_dimension(input, target_id)
    local mode, mode_err = mode_for(input, target_id)
    if not mode then
        return nil, mode_err
    end

    if mode.kind == "forced" then
        local dimension = input.config.dimensions_by_key[mode.key]
        if not dimension then
            return nil, "forced dimension is not allowed for " .. tostring(target_id) .. ": " .. tostring(mode.key)
        end
        return dimension
    end

    local best = nil
    local direction = input.config.scroll_direction
    for _, dimension in ipairs(input.config.allowed_dimensions) do
        if not best then
            best = dimension
        else
            local size = scroll_size(direction, dimension)
            local best_size = scroll_size(direction, best)
            local area = dimension.w * dimension.h
            local best_area = best.w * best.h
            if size < best_size or (size == best_size and area > best_area) then
                best = dimension
            end
        end
    end

    return best
end

local function candidate_dimensions(input, target_id)
    local mode, mode_err = mode_for(input, target_id)
    if not mode then
        return nil, mode_err
    end

    if mode.kind == "forced" then
        local dimension = input.config.dimensions_by_key[mode.key]
        if not dimension then
            return nil, "forced dimension is not allowed for " .. tostring(target_id) .. ": " .. tostring(mode.key)
        end
        return { dimension }
    end

    return input.config.allowed_dimensions
end

local function split_rects(source_rect, existing_dimension, new_dimension)
    local candidates = {}

    if existing_dimension.w + new_dimension.w <= source_rect.w + 0.000001
        and existing_dimension.h <= source_rect.h + 0.000001
        and new_dimension.h <= source_rect.h + 0.000001 then
        table.insert(candidates, {
            existing_rect = {
                x = source_rect.x,
                y = source_rect.y,
                w = existing_dimension.w,
                h = existing_dimension.h,
            },
            new_rect = {
                x = source_rect.x + existing_dimension.w,
                y = source_rect.y,
                w = new_dimension.w,
                h = new_dimension.h,
            },
            uncovered_area = source_rect.w * source_rect.h - (existing_dimension.w * existing_dimension.h + new_dimension.w * new_dimension.h),
        })
    end

    if existing_dimension.h + new_dimension.h <= source_rect.h + 0.000001
        and existing_dimension.w <= source_rect.w + 0.000001
        and new_dimension.w <= source_rect.w + 0.000001 then
        table.insert(candidates, {
            existing_rect = {
                x = source_rect.x,
                y = source_rect.y,
                w = existing_dimension.w,
                h = existing_dimension.h,
            },
            new_rect = {
                x = source_rect.x,
                y = source_rect.y + existing_dimension.h,
                w = new_dimension.w,
                h = new_dimension.h,
            },
            uncovered_area = source_rect.w * source_rect.h - (existing_dimension.w * existing_dimension.h + new_dimension.w * new_dimension.h),
        })
    end

    return candidates
end

local function compare_split_candidates(a, b)
    if a.visible ~= b.visible then
        return a.visible
    end

    if a.source_area ~= b.source_area then
        return a.source_area > b.source_area
    end

    if a.uncovered_area ~= b.uncovered_area then
        return a.uncovered_area < b.uncovered_area
    end

    if a.workspace_extent ~= b.workspace_extent then
        return a.workspace_extent < b.workspace_extent
    end

    if tostring(a.source_id) ~= tostring(b.source_id) then
        return tostring(a.source_id) < tostring(b.source_id)
    end

    return tostring(a.new_dimension.key) < tostring(b.new_dimension.key)
end

local function make_layout(input, ids, placements_by_id, dimensions_by_id, strategy, changed_ids)
    local direction = input.config.scroll_direction
    local valid, validation_err = validate_layout_rects(placements_by_id, ids, direction)
    if not valid then
        return nil, validation_err
    end

    for _, id in ipairs(ids) do
        if not dimensions_by_id[id] then
            local dimension = rect_dimension(input, id, placements_by_id[id])
            if not dimension then
                return nil, "missing dimension for " .. tostring(id)
            end
            dimensions_by_id[id] = dimension
        end
    end

    return {
        placements_by_id = placements_by_id,
        dimensions_by_id = dimensions_by_id,
        workspace_extent = workspace_extent_for(direction, placements_by_id),
        diagnostics = {
            strategy = strategy,
            changed_ids = changed_ids or {},
        },
    }
end

local function append_window(input, ids, target_id)
    local placements_by_id, dimensions_by_id = copy_previous_layout(input)
    local dimension, dimension_err = best_append_dimension(input, target_id)
    if not dimension then
        return nil, dimension_err or "no append dimension available"
    end

    local offset = workspace_extent_for(input.config.scroll_direction, placements_by_id)
    local rect = placement_for(input.config.scroll_direction, offset, dimension)

    placements_by_id[target_id] = rect
    dimensions_by_id[target_id] = {
        key = dimension.key,
        w = dimension.w,
        h = dimension.h,
    }

    return make_layout(input, ids, placements_by_id, dimensions_by_id, "local_append", { target_id })
end

local function window_added(input, ids, event)
    local target_id = event.target_id
    if not target_id then
        return nil, "window_added event requires target_id"
    end

    if not has_target_id(ids, target_id) then
        return nil, "event target is not present: " .. tostring(target_id)
    end

    if input.last_layout.placements_by_id[target_id] then
        return nil, "window_added target already has a previous placement: " .. tostring(target_id)
    end

    local target_dimensions, target_dimensions_err = candidate_dimensions(input, target_id)
    if not target_dimensions then
        return nil, target_dimensions_err
    end

    local candidates = {}
    for _, source_id in ipairs(ids) do
        if source_id ~= target_id then
            local source_rect = input.last_layout.placements_by_id[source_id]
            local source_auto, source_mode_err = is_auto(input, source_id)
            if source_auto == nil then
                return nil, source_mode_err
            end

            if source_rect and source_auto then
                for _, existing_dimension in ipairs(input.config.allowed_dimensions) do
                    for _, target_dimension in ipairs(target_dimensions) do
                        for _, split in ipairs(split_rects(source_rect, existing_dimension, target_dimension)) do
                            local placements_by_id, dimensions_by_id = copy_previous_layout(input)
                            placements_by_id[source_id] = split.existing_rect
                            placements_by_id[target_id] = split.new_rect
                            dimensions_by_id[source_id] = {
                                key = existing_dimension.key,
                                w = existing_dimension.w,
                                h = existing_dimension.h,
                            }
                            dimensions_by_id[target_id] = {
                                key = target_dimension.key,
                                w = target_dimension.w,
                                h = target_dimension.h,
                            }

                            local layout = make_layout(input, ids, placements_by_id, dimensions_by_id, "local_split", { source_id, target_id })
                            if layout then
                                table.insert(candidates, {
                                    layout = layout,
                                    source_id = source_id,
                                    source_area = source_rect.w * source_rect.h,
                                    visible = spatial_geometry.is_visible(source_rect, input.viewport_offset, input.config.scroll_direction),
                                    uncovered_area = split.uncovered_area,
                                    workspace_extent = layout.workspace_extent,
                                    new_dimension = target_dimension,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    if #candidates > 0 then
        table.sort(candidates, compare_split_candidates)
        return candidates[1].layout
    end

    return append_window(input, ids, target_id)
end

local global_rebuild

local function compare_expansion_candidates(a, b)
    if a.visible ~= b.visible then
        return a.visible
    end

    if a.priority ~= b.priority then
        return (a.priority or 1) < (b.priority or 1)
    end

    if a.area_gain ~= b.area_gain then
        return a.area_gain > b.area_gain
    end

    if a.workspace_extent ~= b.workspace_extent then
        return a.workspace_extent < b.workspace_extent
    end

    if tostring(a.target_id) ~= tostring(b.target_id) then
        return tostring(a.target_id) < tostring(b.target_id)
    end

    return tostring(a.dimension.key) < tostring(b.dimension.key)
end

local function copy_rects_by_id(placements_by_id)
    local copy = {}
    for id, rect in pairs(placements_by_id or {}) do
        copy[id] = clone_rect(rect)
    end
    return copy
end

local function copy_dimensions_by_id(dimensions_by_id)
    local copy = {}
    for id, dimension in pairs(dimensions_by_id or {}) do
        copy[id] = clone_dimension(dimension)
    end
    return copy
end

local function add_unique_id(ids, id)
    for _, existing in ipairs(ids) do
        if existing == id then
            return
        end
    end
    table.insert(ids, id)
end

local function full_cross_compaction_layout_candidates(input, ids, placements_by_id, dimensions_by_id, holes, strategy, changed_ids)
    local candidates = {}
    local direction = input.config.scroll_direction

    for _, hole in ipairs(holes) do
        if spans_full_cross_axis(hole, direction) then
            local next_placements_by_id = copy_rects_by_id(placements_by_id)
            local next_dimensions_by_id = copy_dimensions_by_id(dimensions_by_id)
            local next_changed_ids = {}
            local changed = false
            local amount = scroll_axis_size(hole, direction)

            for _, id in ipairs(changed_ids or {}) do
                add_unique_id(next_changed_ids, id)
            end

            for _, id in ipairs(ids) do
                local rect = next_placements_by_id[id]
                if rect and is_after_scroll_hole(rect, hole, direction) then
                    next_placements_by_id[id] = shift_rect_on_scroll_axis(rect, direction, amount)
                    add_unique_id(next_changed_ids, id)
                    changed = true
                end
            end

            if changed then
                local layout = make_layout(input, ids, next_placements_by_id, next_dimensions_by_id, strategy, next_changed_ids)
                if layout then
                    table.insert(candidates, {
                        layout = layout,
                        target_id = "full_cross_compaction",
                        visible = spatial_geometry.is_visible(hole, input.viewport_offset, direction),
                        area_gain = spatial_geometry.area(hole),
                        workspace_extent = layout.workspace_extent,
                        dimension = { key = "full_cross_compaction" },
                    })
                end
            end
        end
    end

    return candidates
end

local function partial_cross_fill_layout_candidates(input, ids, placements_by_id, dimensions_by_id, holes, strategy, changed_ids)
    local candidates = {}
    local direction = input.config.scroll_direction
    local info = spatial_geometry.direction_info(direction)

    for _, hole in ipairs(holes) do
        if not spans_full_cross_axis(hole, direction) then
            local hole_scroll_start, hole_scroll_end = spatial_geometry.interval(hole, info.scroll_axis)
            local hole_cross_start, hole_cross_end = spatial_geometry.cross_interval(hole, direction)

            for _, id in ipairs(ids) do
                local rect = placements_by_id[id]
                local auto, mode_err = is_auto(input, id)
                if auto == nil then
                    return nil, mode_err
                end

                if rect and auto then
                    local rect_scroll_start, rect_scroll_end = spatial_geometry.interval(rect, info.scroll_axis)
                    local rect_cross_start, rect_cross_end = spatial_geometry.cross_interval(rect, direction)
                    local same_column = intervals_equal(rect_scroll_start, rect_scroll_end, hole_scroll_start, hole_scroll_end)
                    local cross_adjacent = math.abs(rect_cross_end - hole_cross_start) <= 0.000001
                        or math.abs(rect_cross_start - hole_cross_end) <= 0.000001

                    if same_column and cross_adjacent then
                        local dimensions, dimensions_err = candidate_dimensions(input, id)
                        if not dimensions then
                            return nil, dimensions_err
                        end

                        local union_cross_start = math.min(rect_cross_start, hole_cross_start)
                        local union_cross_end = math.max(rect_cross_end, hole_cross_end)
                        local union_cross_size = union_cross_end - union_cross_start
                        local current_scroll_size = rect_scroll_end - rect_scroll_start

                        local dimension_candidates = {}
                        for _, dimension in ipairs(dimensions) do
                            local dimension_cross = dimension_cross_size(dimension, direction)
                            if math.abs(dimension_cross - union_cross_size) <= 0.000001 then
                                local dimension_scroll = dimension_scroll_size(dimension, direction)
                                local priority = 3
                                if math.abs(dimension_scroll - current_scroll_size) <= 0.000001 then
                                    priority = 1
                                elseif dimension_scroll < current_scroll_size then
                                    priority = 2
                                end

                                table.insert(dimension_candidates, {
                                    dimension = dimension,
                                    scroll_size = dimension_scroll,
                                    priority = priority,
                                })
                            end
                        end

                        table.sort(dimension_candidates, function(a, b)
                            if a.priority ~= b.priority then
                                return a.priority < b.priority
                            end

                            if a.priority == 2 and a.scroll_size ~= b.scroll_size then
                                return a.scroll_size > b.scroll_size
                            end

                            if a.scroll_size ~= b.scroll_size then
                                return a.scroll_size < b.scroll_size
                            end

                            return tostring(a.dimension.key) < tostring(b.dimension.key)
                        end)

                        for _, item in ipairs(dimension_candidates) do
                            local next_placements_by_id = copy_rects_by_id(placements_by_id)
                            local next_dimensions_by_id = copy_dimensions_by_id(dimensions_by_id)
                            local next_changed_ids = {}
                            for _, changed_id in ipairs(changed_ids or {}) do
                                add_unique_id(next_changed_ids, changed_id)
                            end

                            local next_scroll_start = rect_scroll_start
                            local next_scroll_end = rect_scroll_start + item.scroll_size
                            if direction == "left" or direction == "up" then
                                next_scroll_start = rect_scroll_end - item.scroll_size
                                next_scroll_end = rect_scroll_end
                            end

                            next_placements_by_id[id] = rect_with_intervals(direction, next_scroll_start, next_scroll_end, union_cross_start, union_cross_end)
                            next_dimensions_by_id[id] = clone_dimension(item.dimension)
                            add_unique_id(next_changed_ids, id)

                            local delta = item.scroll_size - current_scroll_size
                            if math.abs(delta) > 0.000001 then
                                local column_rect = rect_with_scroll_interval(rect, direction, rect_scroll_start, rect_scroll_end)
                                for _, other_id in ipairs(ids) do
                                    if other_id ~= id and is_after_scroll_hole(next_placements_by_id[other_id], column_rect, direction) then
                                        next_placements_by_id[other_id] = shift_rect_on_scroll_axis(next_placements_by_id[other_id], direction, -delta)
                                        add_unique_id(next_changed_ids, other_id)
                                    end
                                end
                            end

                            local layout = make_layout(input, ids, next_placements_by_id, next_dimensions_by_id, strategy, next_changed_ids)
                            if layout then
                                table.insert(candidates, {
                                    layout = layout,
                                    target_id = id,
                                    visible = spatial_geometry.is_visible(hole, input.viewport_offset, direction),
                                    area_gain = spatial_geometry.area(hole),
                                    workspace_extent = layout.workspace_extent,
                                    dimension = item.dimension,
                                    priority = item.priority,
                                })
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(candidates, function(a, b)
        if a.visible ~= b.visible then
            return a.visible
        end
        if a.priority ~= b.priority then
            return a.priority < b.priority
        end
        if a.workspace_extent ~= b.workspace_extent then
            return a.workspace_extent < b.workspace_extent
        end
        if a.area_gain ~= b.area_gain then
            return a.area_gain > b.area_gain
        end
        return tostring(a.target_id) < tostring(b.target_id)
    end)

    return candidates
end

local function pruned_previous_layout(input, ids, removed_id)
    local placements_by_id, dimensions_by_id = copy_previous_layout(input)
    local keep = {}
    for _, id in ipairs(ids) do
        keep[id] = true
    end

    for id in pairs(placements_by_id) do
        if id == removed_id or not keep[id] then
            placements_by_id[id] = nil
            dimensions_by_id[id] = nil
        end
    end

    return placements_by_id, dimensions_by_id
end

local function window_removed(input, ids, event)
    local target_id = event.target_id
    if not target_id then
        return nil, "window_removed event requires target_id"
    end

    if has_target_id(ids, target_id) then
        return nil, "window_removed target is still present: " .. tostring(target_id)
    end

    local removed_rect = event.previous_rect or input.last_layout.placements_by_id[target_id]
    if not removed_rect then
        return global_rebuild(input, ids, "global_rebuild")
    end

    local valid_rect, rect_err = spatial_geometry.validate_rect(removed_rect)
    if not valid_rect then
        return nil, "window_removed previous_rect is invalid: " .. rect_err
    end

    local candidates = {}
    if not spans_full_cross_axis(removed_rect, input.config.scroll_direction) then
        for _, id in ipairs(ids) do
            local rect = input.last_layout.placements_by_id[id]
            local auto, mode_err = is_auto(input, id)
            if auto == nil then
                return nil, mode_err
            end

            if rect and auto and spatial_geometry.is_adjacent(rect, removed_rect) then
                local dimensions, dimensions_err = candidate_dimensions(input, id)
                if not dimensions then
                    return nil, dimensions_err
                end

                local expanded = rect_union(rect, removed_rect)
                local dimension = matching_dimension(dimensions, expanded)
                if dimension then
                    local placements_by_id, dimensions_by_id = pruned_previous_layout(input, ids, target_id)
                    placements_by_id[id] = expanded
                    dimensions_by_id[id] = clone_dimension(dimension)

                    local layout = make_layout(input, ids, placements_by_id, dimensions_by_id, "local_expand", { id })
                    if layout then
                        table.insert(candidates, {
                            layout = layout,
                            target_id = id,
                            visible = spatial_geometry.is_visible(removed_rect, input.viewport_offset, input.config.scroll_direction),
                            area_gain = spatial_geometry.area(removed_rect),
                            workspace_extent = layout.workspace_extent,
                            dimension = dimension,
                        })
                    end
                end
            end
        end
    end

    local placements_by_id, dimensions_by_id = pruned_previous_layout(input, ids, target_id)
    local compaction_candidates, compaction_err = full_cross_compaction_layout_candidates(input, ids, placements_by_id, dimensions_by_id, { removed_rect }, "local_compact_full_cross_hole", {})
    if not compaction_candidates then
        return nil, compaction_err
    end
    for _, candidate in ipairs(compaction_candidates) do
        table.insert(candidates, candidate)
    end

    local partial_candidates, partial_err = partial_cross_fill_layout_candidates(input, ids, placements_by_id, dimensions_by_id, { removed_rect }, "local_cross_fill", {})
    if not partial_candidates then
        return nil, partial_err
    end
    for _, candidate in ipairs(partial_candidates) do
        table.insert(candidates, candidate)
    end

    if #candidates > 0 then
        table.sort(candidates, compare_expansion_candidates)
        return candidates[1].layout
    end

    local layout, layout_err = make_layout(input, ids, placements_by_id, dimensions_by_id, "local_preserve", {})
    if not layout then
        return global_rebuild(input, ids, "global_rebuild")
    end

    return layout, layout_err
end

local function push_rect_after(anchor, rect, direction)
    if direction == "right" then
        return { x = anchor.x + anchor.w, y = rect.y, w = rect.w, h = rect.h }
    end

    if direction == "left" then
        return { x = anchor.x - rect.w, y = rect.y, w = rect.w, h = rect.h }
    end

    if direction == "down" then
        return { x = rect.x, y = anchor.y + anchor.h, w = rect.w, h = rect.h }
    end

    if direction == "up" then
        return { x = rect.x, y = anchor.y - rect.h, w = rect.w, h = rect.h }
    end
end

local function rect_with_scroll_start(rect, direction, offset)
    if direction == "right" then
        return { x = offset, y = rect.y, w = rect.w, h = rect.h }
    end

    if direction == "left" then
        return { x = -(offset + rect.w), y = rect.y, w = rect.w, h = rect.h }
    end

    if direction == "down" then
        return { x = rect.x, y = offset, w = rect.w, h = rect.h }
    end

    if direction == "up" then
        return { x = rect.x, y = -(offset + rect.h), w = rect.w, h = rect.h }
    end
end

local function resolve_auto_pushes(input, ids, placements_by_id, target_id)
    local direction = input.config.scroll_direction
    local pushed = {}
    local changed = true
    local guard = 0

    while changed do
        changed = false
        guard = guard + 1
        if guard > #ids * #ids + 1 then
            return nil, "could not resolve local forced-dimension overlaps"
        end

        for _, id in ipairs(ids) do
            if id ~= target_id then
                local rect = placements_by_id[id]
                for _, other_id in ipairs(ids) do
                    if other_id ~= id and spatial_geometry.overlaps(rect, placements_by_id[other_id]) then
                        local auto, mode_err = is_auto(input, id)
                        if auto == nil then
                            return nil, mode_err
                        end
                        if not auto then
                            return nil, "forced window blocks local forced-dimension resize: " .. tostring(id)
                        end

                        placements_by_id[id] = push_rect_after(placements_by_id[other_id], rect, direction)
                        pushed[id] = true
                        changed = true
                        break
                    end
                end
            end
        end
    end

    local changed_ids = { target_id }
    for _, id in ipairs(ids) do
        if pushed[id] then
            table.insert(changed_ids, id)
        end
    end

    return changed_ids
end

local function compact_auto_scroll_gaps(input, ids, placements_by_id, changed_by_id)
    local direction = input.config.scroll_direction
    local sorted = {}
    for _, id in ipairs(ids) do
        local start, finish = spatial_geometry.scroll_interval(placements_by_id[id], direction)
        table.insert(sorted, {
            id = id,
            start = start,
            finish = finish,
        })
    end

    table.sort(sorted, function(a, b)
        if a.start ~= b.start then
            return a.start < b.start
        end
        return tostring(a.id) < tostring(b.id)
    end)

    local extent = 0
    for _, item in ipairs(sorted) do
        local rect = placements_by_id[item.id]
        local auto, mode_err = is_auto(input, item.id)
        if auto == nil then
            return nil, mode_err
        end

        if auto and item.start > extent + 0.000001 then
            placements_by_id[item.id] = rect_with_scroll_start(rect, direction, extent)
            changed_by_id[item.id] = true
        end

        local _, finish = spatial_geometry.scroll_interval(placements_by_id[item.id], direction)
        if finish > extent then
            extent = finish
        end
    end

    return true
end

local function changed_ids_from_map(ids, changed_by_id, target_id)
    local out = { target_id }
    for _, id in ipairs(ids) do
        if id ~= target_id and changed_by_id[id] then
            table.insert(out, id)
        end
    end
    return out
end

local function compare_forced_candidates(a, b)
    if a.resolves_scroll_hole ~= b.resolves_scroll_hole then
        return a.resolves_scroll_hole
    end

    if a.pushed_count ~= b.pushed_count then
        return a.pushed_count < b.pushed_count
    end

    if a.rank ~= b.rank then
        return a.rank < b.rank
    end

    if a.movement_distance ~= b.movement_distance then
        return a.movement_distance < b.movement_distance
    end

    if a.workspace_extent ~= b.workspace_extent then
        return a.workspace_extent < b.workspace_extent
    end

    return false
end

local function compare_auto_candidates(a, b)
    if a.reduces_extent ~= b.reduces_extent then
        return a.reduces_extent
    end

    if a.reduces_extent and a.workspace_extent ~= b.workspace_extent then
        return a.workspace_extent < b.workspace_extent
    end

    if a.target_area ~= b.target_area then
        return a.target_area > b.target_area
    end

    if a.workspace_extent ~= b.workspace_extent then
        return a.workspace_extent < b.workspace_extent
    end

    if a.movement_distance ~= b.movement_distance then
        return a.movement_distance < b.movement_distance
    end

    return tostring(a.dimension.key) < tostring(b.dimension.key)
end

local function compare_move_candidates(a, b)
    if a.strategy_rank ~= b.strategy_rank then
        return a.strategy_rank < b.strategy_rank
    end

    if a.perpendicular_overlap ~= b.perpendicular_overlap then
        return a.perpendicular_overlap > b.perpendicular_overlap
    end

    if a.directional_distance ~= b.directional_distance then
        return a.directional_distance < b.directional_distance
    end

    if a.workspace_extent ~= b.workspace_extent then
        return a.workspace_extent < b.workspace_extent
    end

    if a.movement_distance ~= b.movement_distance then
        return a.movement_distance < b.movement_distance
    end

    return tostring(a.tie_breaker) < tostring(b.tie_breaker)
end

local function move_metrics(source_rect, candidate_rect, direction)
    local source_center = spatial_geometry.center(source_rect)
    local candidate_center = spatial_geometry.center(candidate_rect)
    local directional_distance
    local perpendicular_overlap

    if direction == "left" then
        directional_distance = source_center.x - candidate_center.x
        perpendicular_overlap = spatial_geometry.interval_overlap(source_rect.y, source_rect.y + source_rect.h, candidate_rect.y, candidate_rect.y + candidate_rect.h)
    elseif direction == "right" then
        directional_distance = candidate_center.x - source_center.x
        perpendicular_overlap = spatial_geometry.interval_overlap(source_rect.y, source_rect.y + source_rect.h, candidate_rect.y, candidate_rect.y + candidate_rect.h)
    elseif direction == "up" then
        directional_distance = source_center.y - candidate_center.y
        perpendicular_overlap = spatial_geometry.interval_overlap(source_rect.x, source_rect.x + source_rect.w, candidate_rect.x, candidate_rect.x + candidate_rect.w)
    elseif direction == "down" then
        directional_distance = candidate_center.y - source_center.y
        perpendicular_overlap = spatial_geometry.interval_overlap(source_rect.x, source_rect.x + source_rect.w, candidate_rect.x, candidate_rect.x + candidate_rect.w)
    end

    return {
        directional_distance = directional_distance or 0,
        perpendicular_overlap = perpendicular_overlap or 0,
    }
end

local function forced_candidate(input, ids, target_id, dimension, target_rect, rank, allow_push)
    local placements_by_id, dimensions_by_id = copy_previous_layout(input)
    placements_by_id[target_id] = target_rect
    dimensions_by_id[target_id] = clone_dimension(dimension)

    local changed_ids = { target_id }
    if allow_push then
        local pushed_ids = resolve_auto_pushes(input, ids, placements_by_id, target_id)
        if not pushed_ids then
            return nil
        end
        changed_ids = pushed_ids
    end

    local layout
    local previous_rect = input.last_layout.placements_by_id[target_id]
    local holes = freed_scroll_axis_holes(previous_rect, target_rect, input.config.scroll_direction)
    local compaction_strategy = allow_push and "local_push_compact_full_cross_hole" or "local_compact_full_cross_hole"
    local compaction_candidates, compaction_err = full_cross_compaction_layout_candidates(input, ids, placements_by_id, dimensions_by_id, holes, compaction_strategy, changed_ids)
    if compaction_err then
        return nil
    end

    if compaction_candidates and #compaction_candidates > 0 then
        table.sort(compaction_candidates, compare_expansion_candidates)
        layout = compaction_candidates[1].layout
    else
        local fill_strategy = allow_push and "local_push_cross_fill" or "local_cross_fill"
        local fill_candidates, fill_err = partial_cross_fill_layout_candidates(input, ids, placements_by_id, dimensions_by_id, holes, fill_strategy, changed_ids)
        if fill_err then
            return nil
        end

        if fill_candidates and #fill_candidates > 0 then
            table.sort(fill_candidates, compare_expansion_candidates)
            layout = fill_candidates[1].layout
        else
            layout = make_layout(input, ids, placements_by_id, dimensions_by_id, allow_push and "local_push" or "local_resize", changed_ids)
        end
    end

    if not layout then
        return nil
    end

    local movement = 0
    local pushed_count = 0
    for _, id in ipairs(ids) do
        local previous = input.last_layout.placements_by_id[id]
        local next_rect = layout.placements_by_id[id]
        if previous and next_rect then
            movement = movement + spatial_geometry.movement_distance(previous, next_rect)
            if id ~= target_id and spatial_geometry.is_moved(previous, next_rect) then
                pushed_count = pushed_count + 1
            end
        end
    end

    return {
        layout = layout,
        pushed_count = pushed_count,
        movement_distance = movement,
        workspace_extent = layout.workspace_extent,
        rank = rank,
        resolves_scroll_hole = layout.diagnostics.strategy == "local_compact_full_cross_hole"
            or layout.diagnostics.strategy == "local_push_compact_full_cross_hole"
            or layout.diagnostics.strategy == "local_cross_fill"
            or layout.diagnostics.strategy == "local_push_cross_fill",
    }
end

local function dimension_forced(input, ids, event)
    local target_id = event.target_id
    if not target_id then
        return nil, "dimension_forced event requires target_id"
    end

    if not has_target_id(ids, target_id) then
        return nil, "event target is not present: " .. tostring(target_id)
    end

    local mode, mode_err = mode_for(input, target_id)
    if not mode then
        return nil, mode_err
    end
    if mode.kind ~= "forced" then
        return nil, "dimension_forced target is not forced: " .. tostring(target_id)
    end

    local key = event.key or mode.key
    if key ~= mode.key then
        return nil, "dimension_forced key does not match target mode: " .. tostring(key)
    end

    local dimension = input.config.dimensions_by_key[key]
    if not dimension then
        return nil, "forced dimension is not allowed for " .. tostring(target_id) .. ": " .. tostring(key)
    end

    local previous_rect = input.last_layout.placements_by_id[target_id]
    if not previous_rect then
        return global_rebuild(input, ids, "global_rebuild")
    end

    local target_rects = {
        resized_top_left(previous_rect, dimension),
        resized_center(previous_rect, dimension),
    }
    local candidates = {}

    for i, target_rect in ipairs(target_rects) do
        local direct = forced_candidate(input, ids, target_id, dimension, clone_rect(target_rect), i, false)
        if direct then
            table.insert(candidates, direct)
        end

        local pushed = forced_candidate(input, ids, target_id, dimension, clone_rect(target_rect), i + #target_rects, true)
        if pushed then
            table.insert(candidates, pushed)
        end
    end

    if #candidates > 0 then
        table.sort(candidates, compare_forced_candidates)
        return candidates[1].layout
    end

    return global_rebuild(input, ids, "global_rebuild")
end

local function auto_candidate(input, ids, target_id, dimension, target_rect, compact)
    local placements_by_id, dimensions_by_id = copy_previous_layout(input)
    local changed_by_id = {}

    placements_by_id[target_id] = target_rect
    dimensions_by_id[target_id] = clone_dimension(dimension)
    changed_by_id[target_id] = true

    if compact then
        local compacted, compact_err = compact_auto_scroll_gaps(input, ids, placements_by_id, changed_by_id)
        if not compacted then
            return nil, compact_err
        end
    end

    local strategy = compact and "local_auto_compact" or "local_auto_resize"
    local layout = make_layout(input, ids, placements_by_id, dimensions_by_id, strategy, changed_ids_from_map(ids, changed_by_id, target_id))
    if not layout then
        return nil
    end

    local previous_extent = workspace_extent_for(input.config.scroll_direction, input.last_layout.placements_by_id)
    local movement = 0
    for _, id in ipairs(ids) do
        local previous = input.last_layout.placements_by_id[id]
        local next_rect = layout.placements_by_id[id]
        if previous and next_rect then
            movement = movement + spatial_geometry.movement_distance(previous, next_rect)
        end
    end

    return {
        layout = layout,
        dimension = dimension,
        target_area = dimension.w * dimension.h,
        workspace_extent = layout.workspace_extent,
        reduces_extent = layout.workspace_extent < previous_extent - 0.000001,
        movement_distance = movement,
    }
end

local function dimension_auto(input, ids, event)
    local target_id = event.target_id
    if not target_id then
        return nil, "dimension_auto event requires target_id"
    end

    if not has_target_id(ids, target_id) then
        return nil, "event target is not present: " .. tostring(target_id)
    end

    local mode, mode_err = mode_for(input, target_id)
    if not mode then
        return nil, mode_err
    end
    if mode.kind ~= "auto" then
        return nil, "dimension_auto target is not auto: " .. tostring(target_id)
    end

    local previous_rect = input.last_layout.placements_by_id[target_id]
    if not previous_rect then
        return global_rebuild(input, ids, "global_rebuild")
    end

    local candidates = {}
    for _, dimension in ipairs(input.config.allowed_dimensions) do
        local target_rects = {
            resized_top_left(previous_rect, dimension),
            resized_center(previous_rect, dimension),
        }

        for _, target_rect in ipairs(target_rects) do
            local direct = auto_candidate(input, ids, target_id, dimension, clone_rect(target_rect), false)
            if direct then
                table.insert(candidates, direct)
            end

            local compacted = auto_candidate(input, ids, target_id, dimension, clone_rect(target_rect), true)
            if compacted then
                table.insert(candidates, compacted)
            end
        end
    end

    if #candidates > 0 then
        table.sort(candidates, compare_auto_candidates)
        return candidates[1].layout
    end

    return global_rebuild(input, ids, "global_rebuild")
end

local function dimension_for_rect(input, id, rect)
    local dimensions, dimensions_err = candidate_dimensions(input, id)
    if not dimensions then
        return nil, dimensions_err
    end

    local dimension = matching_dimension(dimensions, rect)
    if not dimension then
        return nil, "no allowed dimension matches placement for " .. tostring(id)
    end

    return dimension
end

local function movement_for_layout(input, ids, placements_by_id)
    local movement = 0
    for _, id in ipairs(ids) do
        local previous = input.last_layout and input.last_layout.placements_by_id[id]
        local next_rect = placements_by_id[id]
        if previous and next_rect then
            movement = movement + spatial_geometry.movement_distance(previous, next_rect)
        end
    end
    return movement
end

local function resize_count_for_layout(input, ids, placements_by_id)
    local count = 0
    if type(input.last_layout) ~= "table" then
        return count
    end

    for _, id in ipairs(ids) do
        local previous = input.last_layout.placements_by_id[id]
        local next_rect = placements_by_id[id]
        if previous and next_rect and spatial_geometry.is_resized(previous, next_rect) then
            count = count + 1
        end
    end

    return count
end

local function visible_preserved_count(input, ids, placements_by_id)
    local count = 0
    if type(input.last_layout) ~= "table" then
        return count
    end

    for _, id in ipairs(ids) do
        local previous = input.last_layout.placements_by_id[id]
        local next_rect = placements_by_id[id]
        if previous and next_rect
            and spatial_geometry.is_visible(previous, input.viewport_offset, input.config.scroll_direction)
            and not spatial_geometry.is_moved(previous, next_rect)
            and not spatial_geometry.is_resized(previous, next_rect) then
            count = count + 1
        end
    end

    return count
end

local function fill_quality(direction, placements_by_id)
    local extent = workspace_extent_for(direction, placements_by_id)
    if extent <= 0 then
        return 0
    end

    local area = 0
    for _, rect in pairs(placements_by_id or {}) do
        area = area + spatial_geometry.area(rect)
    end

    return area / extent
end

local function move_candidate(input, ids, target_id, direction, placements_by_id, dimensions_by_id, strategy, changed_ids, strategy_rank, tie_breaker, metrics)
    local previous_rect = input.last_layout.placements_by_id[target_id]
    local target_rect = placements_by_id[target_id]
    if not spatial_geometry.directional_progress(previous_rect, target_rect, direction) then
        return nil
    end

    local layout = make_layout(input, ids, placements_by_id, dimensions_by_id, strategy, changed_ids)
    if not layout then
        return nil
    end

    return {
        layout = layout,
        strategy_rank = strategy_rank,
        perpendicular_overlap = metrics and metrics.perpendicular_overlap or 0,
        directional_distance = metrics and metrics.directional_distance or math.huge,
        workspace_extent = layout.workspace_extent,
        movement_distance = movement_for_layout(input, ids, placements_by_id),
        tie_breaker = tie_breaker or strategy,
    }
end

local function split_neighbor_rects(neighbor_rect, target_dimension, neighbor_dimension, direction)
    if direction == "right" then
        if target_dimension.w + neighbor_dimension.w <= neighbor_rect.w + 0.000001
            and target_dimension.h <= neighbor_rect.h + 0.000001
            and neighbor_dimension.h <= neighbor_rect.h + 0.000001 then
            return {
                target_rect = { x = neighbor_rect.x, y = neighbor_rect.y, w = target_dimension.w, h = target_dimension.h },
                neighbor_rect = { x = neighbor_rect.x + target_dimension.w, y = neighbor_rect.y, w = neighbor_dimension.w, h = neighbor_dimension.h },
            }
        end
    elseif direction == "left" then
        if target_dimension.w + neighbor_dimension.w <= neighbor_rect.w + 0.000001
            and target_dimension.h <= neighbor_rect.h + 0.000001
            and neighbor_dimension.h <= neighbor_rect.h + 0.000001 then
            return {
                neighbor_rect = { x = neighbor_rect.x, y = neighbor_rect.y, w = neighbor_dimension.w, h = neighbor_dimension.h },
                target_rect = { x = neighbor_rect.x + neighbor_dimension.w, y = neighbor_rect.y, w = target_dimension.w, h = target_dimension.h },
            }
        end
    elseif direction == "down" then
        if target_dimension.h + neighbor_dimension.h <= neighbor_rect.h + 0.000001
            and target_dimension.w <= neighbor_rect.w + 0.000001
            and neighbor_dimension.w <= neighbor_rect.w + 0.000001 then
            return {
                target_rect = { x = neighbor_rect.x, y = neighbor_rect.y, w = target_dimension.w, h = target_dimension.h },
                neighbor_rect = { x = neighbor_rect.x, y = neighbor_rect.y + target_dimension.h, w = neighbor_dimension.w, h = neighbor_dimension.h },
            }
        end
    elseif direction == "up" then
        if target_dimension.h + neighbor_dimension.h <= neighbor_rect.h + 0.000001
            and target_dimension.w <= neighbor_rect.w + 0.000001
            and neighbor_dimension.w <= neighbor_rect.w + 0.000001 then
            return {
                neighbor_rect = { x = neighbor_rect.x, y = neighbor_rect.y, w = neighbor_dimension.w, h = neighbor_dimension.h },
                target_rect = { x = neighbor_rect.x, y = neighbor_rect.y + neighbor_dimension.h, w = target_dimension.w, h = target_dimension.h },
            }
        end
    end
end

local function current_layout_for_ids(input, ids)
    return pruned_previous_layout(input, ids)
end

local function move_noop(input, ids)
    local placements_by_id, dimensions_by_id = current_layout_for_ids(input, ids)
    return make_layout(input, ids, placements_by_id, dimensions_by_id, "noop", {})
end

local function spatial_move(input, ids, event)
    local target_id = event.target_id
    local direction = event.direction
    if not target_id then
        return nil, "move event requires target_id"
    end

    if not has_target_id(ids, target_id) then
        return nil, "event target is not present: " .. tostring(target_id)
    end

    local valid_direction, direction_err = spatial_geometry.validate_direction(direction)
    if not valid_direction then
        return nil, direction_err
    end

    local target_rect = input.last_layout.placements_by_id[target_id]
    if not target_rect then
        return global_rebuild(input, ids, "global_rebuild")
    end

    local candidates = {}
    for _, neighbor_id in ipairs(ids) do
        if neighbor_id ~= target_id then
            local neighbor_rect = input.last_layout.placements_by_id[neighbor_id]
            if neighbor_rect then
                local metrics = move_metrics(target_rect, neighbor_rect, direction)
                if metrics.directional_distance > 0.000001 then
                    local target_swap_dimension = dimension_for_rect(input, target_id, neighbor_rect)
                    local neighbor_swap_dimension = dimension_for_rect(input, neighbor_id, target_rect)
                    if target_swap_dimension and neighbor_swap_dimension then
                        local placements_by_id, dimensions_by_id = current_layout_for_ids(input, ids)
                        placements_by_id[target_id] = clone_rect(neighbor_rect)
                        placements_by_id[neighbor_id] = clone_rect(target_rect)
                        dimensions_by_id[target_id] = clone_dimension(target_swap_dimension)
                        dimensions_by_id[neighbor_id] = clone_dimension(neighbor_swap_dimension)

                        local candidate = move_candidate(input, ids, target_id, direction, placements_by_id, dimensions_by_id, "local_swap", { target_id, neighbor_id }, 1, neighbor_id, metrics)
                        if candidate then
                            table.insert(candidates, candidate)
                        end
                    end

                    local neighbor_auto, neighbor_mode_err = is_auto(input, neighbor_id)
                    if neighbor_auto == nil then
                        return nil, neighbor_mode_err
                    end

                    if neighbor_auto then
                        local target_dimensions, target_dimensions_err = candidate_dimensions(input, target_id)
                        if not target_dimensions then
                            return nil, target_dimensions_err
                        end

                        for _, target_dimension in ipairs(target_dimensions) do
                            for _, neighbor_dimension in ipairs(input.config.allowed_dimensions) do
                                local split = split_neighbor_rects(neighbor_rect, target_dimension, neighbor_dimension, direction)
                                if split then
                                    local placements_by_id, dimensions_by_id = current_layout_for_ids(input, ids)
                                    placements_by_id[target_id] = split.target_rect
                                    placements_by_id[neighbor_id] = split.neighbor_rect
                                    dimensions_by_id[target_id] = clone_dimension(target_dimension)
                                    dimensions_by_id[neighbor_id] = clone_dimension(neighbor_dimension)

                                    local candidate = move_candidate(input, ids, target_id, direction, placements_by_id, dimensions_by_id, "local_split_move", { target_id, neighbor_id }, 2, neighbor_id .. ":" .. target_dimension.key .. ":" .. neighbor_dimension.key, metrics)
                                    if candidate then
                                        table.insert(candidates, candidate)
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if direction == input.config.scroll_direction then
        local dimension = rect_dimension(input, target_id, target_rect) or dimension_for(input, target_id)
        if dimension then
            local placements_by_id, dimensions_by_id = current_layout_for_ids(input, ids)
            placements_by_id[target_id] = nil
            local offset = workspace_extent_for(input.config.scroll_direction, placements_by_id)
            placements_by_id[target_id] = placement_for(input.config.scroll_direction, offset, dimension)
            dimensions_by_id[target_id] = clone_dimension(dimension)

            local candidate = move_candidate(input, ids, target_id, direction, placements_by_id, dimensions_by_id, "local_scroll_extend", { target_id }, 3, target_id, {
                directional_distance = math.huge,
                perpendicular_overlap = 0,
            })
            if candidate then
                table.insert(candidates, candidate)
            end
        end
    end

    if #candidates > 0 then
        table.sort(candidates, compare_move_candidates)
        return candidates[1].layout
    end

    return move_noop(input, ids)
end

local function dense_global_layout(input, ids, strategy)
    local placements_by_id = {}
    local dimensions_by_id = {}
    local offset = 0
    local direction = input.config.scroll_direction

    for _, id in ipairs(ids) do
        local dimension, dimension_err = dimension_for(input, id)
        if not dimension then
            return nil, dimension_err
        end

        local rect = placement_for(direction, offset, dimension)
        local valid_rect, rect_err = validate_output_rect(rect, direction)
        if not valid_rect then
            return nil, "invalid placement for " .. tostring(id) .. ": " .. rect_err
        end

        placements_by_id[id] = rect
        dimensions_by_id[id] = {
            key = dimension.key,
            w = dimension.w,
            h = dimension.h,
        }

        offset = offset + scroll_size(direction, dimension)
    end

    return {
        placements_by_id = placements_by_id,
        dimensions_by_id = dimensions_by_id,
        workspace_extent = offset,
        diagnostics = {
            strategy = strategy or "global_rebuild",
        },
    }
end

local function global_candidate(input, ids, placements_by_id, dimensions_by_id, strategy, rank)
    local layout = make_layout(input, ids, placements_by_id, dimensions_by_id, strategy, {})
    if not layout then
        return nil
    end

    return {
        layout = layout,
        rank = rank,
        visible_preserved = visible_preserved_count(input, ids, placements_by_id),
        movement_distance = movement_for_layout(input, ids, placements_by_id),
        resize_count = resize_count_for_layout(input, ids, placements_by_id),
        workspace_extent = layout.workspace_extent,
        fill_quality = fill_quality(input.config.scroll_direction, placements_by_id),
    }
end

local function compare_global_candidates(a, b)
    if a.visible_preserved ~= b.visible_preserved then
        return a.visible_preserved > b.visible_preserved
    end

    if a.movement_distance ~= b.movement_distance then
        return a.movement_distance < b.movement_distance
    end

    if a.resize_count ~= b.resize_count then
        return a.resize_count < b.resize_count
    end

    if a.workspace_extent ~= b.workspace_extent then
        return a.workspace_extent < b.workspace_extent
    end

    if a.fill_quality ~= b.fill_quality then
        return a.fill_quality > b.fill_quality
    end

    return a.rank < b.rank
end

local function dimension_for_global_preserve(input, id, rect)
    local mode, mode_err = mode_for(input, id)
    if not mode then
        return nil, mode_err
    end

    if mode.kind == "forced" then
        local dimension = input.config.dimensions_by_key[mode.key]
        if not dimension then
            return nil, "forced dimension is not allowed for " .. tostring(id) .. ": " .. tostring(mode.key)
        end
        if math.abs(dimension.w - rect.w) > 0.000001 or math.abs(dimension.h - rect.h) > 0.000001 then
            return nil, "previous placement does not match forced dimension for " .. tostring(id)
        end
        return dimension
    end

    return matching_dimension(input.config.allowed_dimensions, rect)
end

local function preserved_global_candidate(input, ids, compact, rank)
    if type(input.last_layout) ~= "table" then
        return nil
    end

    local direction = input.config.scroll_direction
    local placements_by_id = {}
    local dimensions_by_id = {}

    for _, id in ipairs(ids) do
        local previous_rect = input.last_layout.placements_by_id[id]
        if previous_rect then
            local dimension = dimension_for_global_preserve(input, id, previous_rect)
            if not dimension then
                return nil
            end

            placements_by_id[id] = clone_rect(previous_rect)
            dimensions_by_id[id] = clone_dimension(dimension)
        end
    end

    for _, id in ipairs(ids) do
        if not placements_by_id[id] then
            local dimension, dimension_err = dimension_for(input, id)
            if not dimension then
                return nil, dimension_err
            end

            local offset = workspace_extent_for(direction, placements_by_id)
            placements_by_id[id] = placement_for(direction, offset, dimension)
            dimensions_by_id[id] = clone_dimension(dimension)
        end
    end

    if compact then
        local changed_by_id = {}
        local compacted = compact_auto_scroll_gaps(input, ids, placements_by_id, changed_by_id)
        if not compacted then
            return nil
        end
    end

    local strategy = compact and "global_preserve_compact" or "global_preserve"
    return global_candidate(input, ids, placements_by_id, dimensions_by_id, strategy, rank)
end

global_rebuild = function(input, ids, strategy)
    local dense_layout, dense_err = dense_global_layout(input, ids, strategy == "initial_global_rebuild" and "initial_global_rebuild" or "global_rebuild")
    if not dense_layout then
        return nil, dense_err
    end

    if type(input.last_layout) ~= "table" or strategy == "initial_global_rebuild" then
        return dense_layout
    end

    local candidates = {}
    local dense_candidate = global_candidate(input, ids, dense_layout.placements_by_id, dense_layout.dimensions_by_id, "global_rebuild", 3)
    if dense_candidate then
        table.insert(candidates, dense_candidate)
    end

    local preserved = preserved_global_candidate(input, ids, false, 1)
    if preserved then
        table.insert(candidates, preserved)
    end

    local compacted = preserved_global_candidate(input, ids, true, 2)
    if compacted then
        table.insert(candidates, compacted)
    end

    table.sort(candidates, compare_global_candidates)
    return candidates[1].layout
end

function M.solve(input)
    if not spatial_geometry then
        return result_error("dependencies are not configured")
    end

    if type(input) ~= "table" then
        return result_error("solver input must be a table")
    end

    local valid_config, config_err = validate_config(input.config)
    if not valid_config then
        return result_error(config_err)
    end

    if not is_finite_number(input.viewport_offset) or input.viewport_offset < 0 then
        return result_error("viewport_offset must be a non-negative finite number")
    end

    input.targets = input.targets or {}
    input.dimension_mode_by_id = input.dimension_mode_by_id or {}

    if type(input.dimension_mode_by_id) ~= "table" then
        return result_error("dimension_mode_by_id must be a table")
    end

    local ids, ids_err = target_ids(input.targets)
    if not ids then
        return result_error(ids_err)
    end

    local kind, event = event_kind(input)
    if not GLOBAL_EVENTS[kind] and not LOCAL_EVENTS[kind] then
        return result_error("unsupported event: " .. tostring(kind))
    end

    if LOCAL_EVENTS[kind] then
        local valid_layout, layout_err = validate_last_layout(input.last_layout)
        if not valid_layout then
            return result_error(layout_err)
        end

        if kind == "window_added" then
            local layout, local_err = window_added(input, ids, event)
            if not layout then
                return result_error(local_err)
            end

            return {
                ok = true,
                layout = layout,
                diagnostics = layout.diagnostics,
            }
        end

        if kind == "window_removed" then
            local layout, local_err = window_removed(input, ids, event)
            if not layout then
                return result_error(local_err)
            end

            return {
                ok = true,
                layout = layout,
                diagnostics = layout.diagnostics,
            }
        end

        if kind == "dimension_forced" then
            local layout, local_err = dimension_forced(input, ids, event)
            if not layout then
                return result_error(local_err)
            end

            return {
                ok = true,
                layout = layout,
                diagnostics = layout.diagnostics,
            }
        end

        if kind == "dimension_auto" then
            local layout, local_err = dimension_auto(input, ids, event)
            if not layout then
                return result_error(local_err)
            end

            return {
                ok = true,
                layout = layout,
                diagnostics = layout.diagnostics,
            }
        end

        if kind == "move" then
            local layout, local_err = spatial_move(input, ids, event)
            if not layout then
                return result_error(local_err)
            end

            return {
                ok = true,
                layout = layout,
                diagnostics = layout.diagnostics,
            }
        end

        return result_error("unsupported local spatial event: " .. tostring(kind))
    end

    if kind == "config_changed" and input.last_layout ~= nil then
        local valid_layout, layout_err = validate_last_layout(input.last_layout)
        if not valid_layout then
            return result_error(layout_err)
        end
    end

    if event.target_id ~= nil then
        local found = false
        for _, id in ipairs(ids) do
            if id == event.target_id then
                found = true
                break
            end
        end
        if not found and kind ~= "config_changed" then
            return result_error("event target is not present: " .. tostring(event.target_id))
        end
    end

    local layout, layout_err = global_rebuild(input, ids, kind == "initial" and "initial_global_rebuild" or "global_rebuild")
    if not layout then
        return result_error(layout_err)
    end

    return {
        ok = true,
        layout = layout,
        diagnostics = layout.diagnostics,
    }
end

return M
