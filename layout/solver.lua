local M = {}

local geometry = nil
local traversal = nil
local unpack_table = table.unpack or unpack

function M.set_dependencies(dependencies)
    geometry = dependencies.geometry
    traversal = dependencies.traversal
end

local function err(message)
    return { ok = false, error = "fit-scroller: " .. message }
end

local function is_finite_number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function target_ids(targets)
    local ids = {}
    local seen = {}
    if type(targets) ~= "table" then
        return nil, "targets must be a list"
    end

    for i, target in ipairs(targets or {}) do
        if type(target) ~= "table" then
            return nil, "target at index " .. tostring(i) .. " must be a table"
        end
        if not target.id then
            return nil, "target at index " .. tostring(i) .. " has no id"
        end
        if seen[target.id] then
            return nil, "duplicate target id: " .. tostring(target.id)
        end
        seen[target.id] = true
        ids[i] = target.id
    end
    return ids
end

local function forced_dimension_for_target(input, target)
    local mode = input.dimension_mode_by_id
        and input.dimension_mode_by_id[target.id]

    if mode and mode.kind == "forced" then
        local dimension = input.config.dimensions_by_key[mode.key]
        if not dimension then
            return nil, "forced dimension " .. tostring(mode.key) .. " is not allowed for target " .. tostring(target.id)
        end
        return dimension
    end
end

local function canonical_dimension(dimension, direction)
    if direction == "down" or direction == "up" then
        return {
            key = dimension.key,
            w = dimension.h,
            h = dimension.w,
        }
    end

    return dimension
end

local function rect_extent(rect)
    return rect.x + rect.w
end

local function layout_extent(placements)
    local extent = 0
    for _, rect in pairs(placements or {}) do
        extent = math.max(extent, rect_extent(rect))
    end
    return extent
end

local function nearly_equal(a, b)
    return math.abs(a - b) <= 0.0000001
end

local function fill_value(value)
    if math.abs(value - 1) <= 0.011 then
        return 1
    end
    return value
end

local function candidate_stable_key(candidate, input)
    local parts = {}
    for i, target in ipairs(input.targets) do
        local rect = candidate.placements_by_id[target.id]
        local dimension = candidate.dimensions_by_id[target.id]
        parts[i] = string.format(
            "%.6f,%.6f,%s",
            rect and rect.x or 0,
            rect and rect.y or 0,
            dimension and dimension.key or ""
        )
    end
    return table.concat(parts, "|")
end

local function is_uniform_full_cross(candidate, input)
    local key = nil
    for _, target in ipairs(input.targets) do
        local dimension = candidate.dimensions_by_id[target.id]
        local rect = candidate.placements_by_id[target.id]
        if not dimension or not rect or math.abs(rect.h - 1) > 0.011 then
            return false
        end
        if key and key ~= dimension.key then
            return false
        end
        key = dimension.key
    end
    return key ~= nil
end

local function column_index_by_target_index(candidate)
    local by_index = {}
    for column_index, column in ipairs(candidate.columns or {}) do
        for index = column.start_index, column.end_index do
            by_index[index] = column_index
        end
    end
    return by_index
end

local function adjacent_forced_split_count(candidate, input)
    local by_index = column_index_by_target_index(candidate)
    local count = 0

    for index = 1, #input.targets - 1 do
        local current = forced_dimension_for_target(input, input.targets[index])
        local next_forced = forced_dimension_for_target(input, input.targets[index + 1])

        if current and next_forced then
            local current_canonical = canonical_dimension(current, input.config.scroll_direction)
            local next_canonical = canonical_dimension(next_forced, input.config.scroll_direction)
            local same_scroll = nearly_equal(current_canonical.w, next_canonical.w)
            local can_share_cross = current_canonical.h + next_canonical.h <= 1 + 0.0000001
            if same_scroll and can_share_cross and by_index[index] ~= by_index[index + 1] then
                count = count + 1
            end
        end
    end

    return count
end

local function is_fullscreen_forced_column(candidate, input, column)
    if column.start_index ~= column.end_index then
        return false
    end

    local target = input.targets[column.start_index]
    local forced = forced_dimension_for_target(input, target)
    if not forced then
        return false
    end

    local canonical = canonical_dimension(forced, input.config.scroll_direction)
    return canonical.w >= 1 - 0.0000001 and canonical.h >= 1 - 0.0000001
end

local function fullscreen_forced_group_metrics(candidate, input)
    local has_fullscreen_anchor = false
    local group_extent = 0
    local group_overflow = 0
    local group_fill_gap = 0

    local function flush_group()
        if group_extent > 0 then
            group_overflow = group_overflow + math.max(0, group_extent - 1)
            if group_extent <= 1 + 0.0000001 then
                group_fill_gap = group_fill_gap + (1 - fill_value(math.min(group_extent, 1)))
            end
            group_extent = 0
        end
    end

    for _, column in ipairs(candidate.columns or {}) do
        if is_fullscreen_forced_column(candidate, input, column) then
            has_fullscreen_anchor = true
            flush_group()
        else
            group_extent = group_extent + column.pattern.scroll_size
        end
    end
    flush_group()

    if not has_fullscreen_anchor then
        return 0, 0
    end

    return group_overflow, group_fill_gap
end

local function rank_candidate(candidate, input)
    local min_area = nil
    local max_area = nil
    local total_area = 0

    for _, target in ipairs(input.targets) do
        local dimension = candidate.dimensions_by_id[target.id]
        local area = geometry.dimension_area(dimension)
        total_area = total_area + area
        min_area = min_area and math.min(min_area, area) or area
        max_area = max_area and math.max(max_area, area) or area
    end

    local min_column_count = nil
    local max_column_count = nil
    local full_columns = 0
    local total_cross_fill = 0
    for _, column in ipairs(candidate.columns or {}) do
        local count = column.end_index - column.start_index + 1
        min_column_count = min_column_count and math.min(min_column_count, count) or count
        max_column_count = max_column_count and math.max(max_column_count, count) or count

        local cross_fill = fill_value(column.pattern.cross_fill)
        total_cross_fill = total_cross_fill + math.min(cross_fill, 1)
        if math.abs(cross_fill - 1) <= 0.0000001 then
            full_columns = full_columns + 1
        end
    end

    local column_count = #(candidate.columns or {})
    local overflow = math.max(0, candidate.workspace_extent - 1)
    local scroll_fill = fill_value(math.min(candidate.workspace_extent, 1))
    local average_cross_fill = column_count > 0 and total_cross_fill / column_count or 0
    local average_scroll_size = column_count > 0 and scroll_fill / column_count or 0
    local group_overflow, group_fill_gap = fullscreen_forced_group_metrics(candidate, input)

    candidate.ranking = {
        fullscreen_group_overflow = group_overflow,
        fullscreen_group_fill_gap = group_fill_gap,
        overflow = overflow,
        scroll_fill_gap = 1 - scroll_fill,
        uniform_full_cross = is_uniform_full_cross(candidate, input) and 0 or 1,
        large_cross_fill_gap = (1 - average_cross_fill) > 0.25 and (1 - average_cross_fill) or 0,
        adjacent_forced_split_count = adjacent_forced_split_count(candidate, input),
        no_scroll_average_scroll_size = overflow <= 0.0000001 and average_scroll_size or 0,
        full_column_gap = column_count - full_columns,
        average_cross_fill_gap = 1 - average_cross_fill,
        balance_range = (max_column_count or 0) - (min_column_count or 0),
        average_area_gap = 1 - (total_area / math.max(#input.targets, 1)),
        area_range = (max_area or 0) - (min_area or 0),
        workspace_extent = candidate.workspace_extent,
        stable_key = candidate_stable_key(candidate, input),
    }
end

local function compare_number(a, b)
    if nearly_equal(a, b) then
        return nil
    end
    return a < b
end

local function compare_candidates(a, b)
    local fields = {
        "fullscreen_group_overflow",
        "fullscreen_group_fill_gap",
        "overflow",
        "scroll_fill_gap",
        "uniform_full_cross",
        "large_cross_fill_gap",
        "adjacent_forced_split_count",
        "balance_range",
        "no_scroll_average_scroll_size",
        "full_column_gap",
        "average_cross_fill_gap",
        "average_area_gap",
        "area_range",
        "workspace_extent",
    }

    for _, field in ipairs(fields) do
        local result = compare_number(a.ranking[field], b.ranking[field])
        if result ~= nil then
            return result
        end
    end

    return a.ranking.stable_key < b.ranking.stable_key
end

local function canonical_dimension_items(config)
    local items = {}
    for _, dimension in ipairs(config.allowed_dimensions or {}) do
        local canonical = canonical_dimension(dimension, config.scroll_direction)
        table.insert(items, {
            dimension = dimension,
            key = dimension.key,
            scroll_size = canonical.w,
            cross_size = canonical.h,
            area = canonical.w * canonical.h,
        })
    end

    table.sort(items, function(a, b)
        if not nearly_equal(a.area, b.area) then
            return a.area > b.area
        end
        if not nearly_equal(a.cross_size, b.cross_size) then
            return a.cross_size > b.cross_size
        end
        if not nearly_equal(a.scroll_size, b.scroll_size) then
            return a.scroll_size < b.scroll_size
        end
        return a.key < b.key
    end)

    return items
end

local function smallest_scroll_size(items)
    local size = nil
    for _, item in ipairs(items) do
        size = size and math.min(size, item.scroll_size) or item.scroll_size
    end
    return size or 1
end

local function append_unique_number(values, value)
    for _, existing in ipairs(values) do
        if nearly_equal(existing, value) then
            return
        end
    end
    table.insert(values, value)
end

local function pattern_cross_range(pattern)
    local min_cross = nil
    local max_cross = nil
    for _, item in ipairs(pattern.items) do
        min_cross = min_cross and math.min(min_cross, item.cross_size) or item.cross_size
        max_cross = max_cross and math.max(max_cross, item.cross_size) or item.cross_size
    end
    return (max_cross or 0) - (min_cross or 0)
end

local function pattern_key(pattern)
    local keys = {}
    for i, item in ipairs(pattern.items) do
        keys[i] = item.key
    end
    return table.concat(keys, "|")
end

local function pattern_area(pattern)
    local area = 0
    for _, item in ipairs(pattern.items) do
        area = area + item.area
    end
    return area
end

local function pattern_fill_value(pattern)
    if math.abs(pattern.cross_fill - 1) <= 0.011 then
        return 1
    end
    return pattern.cross_fill
end

local function compare_column_patterns(a, b)
    local fill_a = pattern_fill_value(a)
    local fill_b = pattern_fill_value(b)
    if not nearly_equal(fill_a, fill_b) then
        return fill_a > fill_b
    end

    local exact_a = math.abs(a.cross_fill - 1) <= 0.011
    local exact_b = math.abs(b.cross_fill - 1) <= 0.011
    if exact_a ~= exact_b then
        return exact_a
    end

    local range_a = pattern_cross_range(a)
    local range_b = pattern_cross_range(b)
    if not nearly_equal(range_a, range_b) then
        return range_a < range_b
    end

    local area_a = pattern_area(a)
    local area_b = pattern_area(b)
    if not nearly_equal(area_a, area_b) then
        return area_a > area_b
    end

    return pattern_key(a) < pattern_key(b)
end

local function append_best_patterns(target, source, limit)
    table.sort(source, compare_column_patterns)
    for i = 1, math.min(limit, #source) do
        table.insert(target, source[i])
    end
end

local function forced_item_for_target(input, target, items_by_key)
    local forced, forced_err = forced_dimension_for_target(input, target)
    if forced_err then
        return nil, forced_err
    end
    if forced then
        local item = items_by_key[forced.key]
        if not item then
            return nil, "forced dimension " .. tostring(forced.key) .. " is not allowed for target " .. tostring(target.id)
        end
        if item.cross_size > 1 + 0.0000001 then
            return nil, "dimension " .. forced.key .. " does not fit on the cross axis for target " .. tostring(target.id)
        end
        return item
    end
end

local function column_scroll_sizes(input, start_index, end_index, items, items_by_key)
    local forced_scroll_size = nil
    local has_forced = false

    for i = start_index, end_index do
        local forced, forced_err = forced_item_for_target(input, input.targets[i], items_by_key)
        if forced_err then
            return nil, forced_err
        end
        if forced then
            has_forced = true
            if forced_scroll_size and not nearly_equal(forced_scroll_size, forced.scroll_size) then
                return {}
            end
            forced_scroll_size = forced.scroll_size
        end
    end

    if has_forced then
        return { forced_scroll_size }
    end

    local sizes = {}
    for _, item in ipairs(items) do
        append_unique_number(sizes, item.scroll_size)
    end
    table.sort(sizes)
    return sizes
end

local function dimension_options_for_target(input, target, scroll_size, items, items_by_key)
    local forced, forced_err = forced_item_for_target(input, target, items_by_key)
    if forced_err then
        return nil, forced_err
    end
    if forced then
        if nearly_equal(forced.scroll_size, scroll_size) then
            return { forced }
        end
        return {}
    end

    local options = {}
    for _, item in ipairs(items) do
        if nearly_equal(item.scroll_size, scroll_size) and item.cross_size <= 1 + 0.0000001 then
            table.insert(options, item)
        end
    end
    return options
end

local function generate_column_patterns(input, start_index, end_index, items, items_by_key)
    local scroll_sizes, scroll_err = column_scroll_sizes(input, start_index, end_index, items, items_by_key)
    if not scroll_sizes then
        return nil, scroll_err
    end

    local patterns = {}
    for _, scroll_size in ipairs(scroll_sizes) do
        local scroll_patterns = {}
        local options_by_index = {}
        local can_use_scroll_size = true

        for index = start_index, end_index do
            local target = input.targets[index]
            local forced, forced_err = forced_item_for_target(input, target, items_by_key)
            if forced_err then
                return nil, forced_err
            end

            if forced and forced.cross_size >= 1 - 0.0000001 and start_index ~= end_index then
                can_use_scroll_size = false
                break
            end

            local options, options_err = dimension_options_for_target(input, target, scroll_size, items, items_by_key)
            if not options then
                return nil, options_err
            end
            if #options == 0 then
                can_use_scroll_size = false
                break
            end

            options_by_index[index] = options
        end

        if can_use_scroll_size then
            local min_remaining_cross = {}
            min_remaining_cross[end_index + 1] = 0
            for index = end_index, start_index, -1 do
                local min_cross = nil
                for _, item in ipairs(options_by_index[index]) do
                    min_cross = min_cross and math.min(min_cross, item.cross_size) or item.cross_size
                end
                min_remaining_cross[index] = min_cross + min_remaining_cross[index + 1]
            end

            if min_remaining_cross[start_index] <= 1 + 0.0000001 then
                local chosen = {}

                local function generate_at(index, cross_sum)
                    if cross_sum + min_remaining_cross[index] > 1 + 0.0000001 then
                        return true
                    end

                    if index > end_index then
                        table.insert(scroll_patterns, {
                            scroll_size = scroll_size,
                            cross_fill = cross_sum,
                            items = { unpack_table(chosen) },
                        })
                        return true
                    end

                    for _, item in ipairs(options_by_index[index]) do
                        if cross_sum + item.cross_size <= 1 + 0.0000001 then
                            table.insert(chosen, item)
                            local ok, generation_err = generate_at(index + 1, cross_sum + item.cross_size)
                            table.remove(chosen)
                            if not ok then
                                return nil, generation_err
                            end
                        end
                    end

                    return true
                end

                local ok, pattern_err = generate_at(start_index, 0)
                if not ok then
                    return nil, pattern_err
                end

                append_best_patterns(patterns, scroll_patterns, 1)
            end
        end
    end

    return patterns
end

local function build_candidate_from_columns(input, columns)
    local placements = {}
    local dimensions = {}
    local candidate_columns = {}
    local x = 0

    for column_index, column in ipairs(columns) do
        local y = 0
        candidate_columns[column_index] = {
            start_index = column.start_index,
            end_index = column.end_index,
            pattern = column.pattern,
        }

        for offset, item in ipairs(column.pattern.items) do
            local target = input.targets[column.start_index + offset - 1]
            placements[target.id] = geometry.rect(x, y, item.scroll_size, item.cross_size)
            dimensions[target.id] = item.dimension
            y = y + item.cross_size
        end
        x = x + column.pattern.scroll_size
    end

    return {
        placements_by_id = placements,
        dimensions_by_id = dimensions,
        workspace_extent = layout_extent(placements),
        columns = candidate_columns,
    }
end

local function transform_layout(candidate, direction)
    if direction == "right" then
        return candidate
    end

    local placements = {}
    for id, rect in pairs(candidate.placements_by_id) do
        placements[id] = traversal.from_canonical(direction, rect)
    end

    candidate.placements_by_id = placements
    return candidate
end

function M.generate_candidates(input)
    local candidates = {}
    local items = canonical_dimension_items(input.config)
    local items_by_key = {}
    for _, item in ipairs(items) do
        items_by_key[item.key] = item
    end

    local columns = {}
    local max_candidates = 20000
    local max_extent = math.max(3, #input.targets * smallest_scroll_size(items))

    local function generate_from(start_index, current_extent)
        if #candidates >= max_candidates then
            return true
        end

        if start_index > #input.targets then
            local candidate = build_candidate_from_columns(input, columns)
            rank_candidate(candidate, input)
            table.insert(candidates, candidate)
            return true
        end

        for end_index = #input.targets, start_index, -1 do
            local patterns, patterns_err = generate_column_patterns(input, start_index, end_index, items, items_by_key)
            if not patterns then
                return nil, patterns_err
            end

            for _, pattern in ipairs(patterns) do
                local next_extent = current_extent + pattern.scroll_size
                if next_extent <= max_extent + 0.0000001 or #candidates == 0 then
                    table.insert(columns, {
                        start_index = start_index,
                        end_index = end_index,
                        pattern = pattern,
                    })

                    local ok, generation_err = generate_from(end_index + 1, next_extent)
                    table.remove(columns)
                    if not ok then
                        return nil, generation_err
                    end
                end
            end
        end

        return true
    end

    local ok, generation_err = generate_from(1, 0)
    if not ok then
        return nil, generation_err
    end

    if #candidates == 0 then
        return nil, "no layout candidates generated"
    end

    return candidates
end

function M.validate_candidate(candidate, input)
    for _, target in ipairs(input.targets) do
        if not candidate.placements_by_id[target.id] then
            return false
        end
        if not candidate.dimensions_by_id[target.id] then
            return false
        end
    end

    return true
end

function M.rank_candidate(candidate, input)
    rank_candidate(candidate, input)
    return candidate.ranking
end

function M.compare_candidates(a, b)
    return compare_candidates(a, b)
end

function M.solve(input)
    if not geometry or not traversal then
        return err("solver dependencies are not configured")
    end

    if type(input) ~= "table" then
        return err("solver input must be a table")
    end

    if type(input.config) ~= "table" or type(input.config.allowed_dimensions) ~= "table" then
        return err("missing normalized configuration")
    end

    if #input.config.allowed_dimensions == 0 then
        return err("config.allowed_dimensions must be non-empty")
    end

    if not traversal.direction_info(input.config.scroll_direction) then
        return err("unsupported scroll direction: " .. tostring(input.config.scroll_direction))
    end

    if type(input.config.dimensions_by_key) ~= "table" then
        return err("missing config.dimensions_by_key")
    end

    for _, dimension in ipairs(input.config.allowed_dimensions) do
        if type(dimension) ~= "table"
            or type(dimension.key) ~= "string"
            or not is_finite_number(dimension.w)
            or not is_finite_number(dimension.h)
            or dimension.w <= 0
            or dimension.h <= 0 then
            return err("config.allowed_dimensions contains an invalid dimension")
        end
    end

    input.targets = input.targets or {}
    input.dimension_mode_by_id = input.dimension_mode_by_id or {}

    if type(input.dimension_mode_by_id) ~= "table" then
        return err("dimension_mode_by_id must be a table")
    end

    if #input.targets == 0 then
        return {
            ok = true,
            layout = {
                placements_by_id = {},
                dimensions_by_id = {},
                workspace_extent = 0,
                ranking = {
                    area_range = 0,
                    workspace_extent = 0,
                },
            },
        }
    end

    local ids, ids_err = target_ids(input.targets)
    if not ids then
        return err(ids_err)
    end

    local candidates, candidates_err = M.generate_candidates(input)
    if not candidates then
        return err(candidates_err)
    end

    local best = candidates[1]
    for i = 2, #candidates do
        if compare_candidates(candidates[i], best) then
            best = candidates[i]
        end
    end

    transform_layout(best, input.config.scroll_direction)
    return { ok = true, layout = best }
end

return M
