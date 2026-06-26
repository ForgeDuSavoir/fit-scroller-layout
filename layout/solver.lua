local M = {}

local geometry = nil
local traversal = nil

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

local function nearly_equal(a, b)
    return math.abs(a - b) <= 0.0000001
end

local function rect_fits(rect, existing)
    if rect.x < 0 or rect.y < 0 or rect.y + rect.h > 1 + 0.0000001 then
        return false
    end

    for _, placed in ipairs(existing) do
        if geometry.overlaps(rect, placed) then
            return false
        end
    end

    return true
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

local function sorted_unique(values)
    table.sort(values)

    local out = {}
    local last = nil
    for _, value in ipairs(values) do
        if last == nil or math.abs(value - last) > 0.0000001 then
            table.insert(out, value)
            last = value
        end
    end

    return out
end

local function place_in_region(region_x, w, h, existing)
    local xs = { region_x }
    local ys = { 0 }

    for _, rect in ipairs(existing) do
        if rect.x >= region_x and rect.x < region_x + 1 then
            table.insert(xs, rect.x)
            table.insert(xs, rect.x + rect.w)
            table.insert(ys, rect.y)
            table.insert(ys, rect.y + rect.h)
        end
    end

    xs = sorted_unique(xs)
    ys = sorted_unique(ys)

    for _, x in ipairs(xs) do
        for _, y in ipairs(ys) do
            local rect = geometry.rect(x, y, w, h)
            if x + w <= region_x + 1 + 0.0000001 and rect_fits(rect, existing) then
                return rect
            end
        end
    end
end

local function pack_candidate(input, dimensions_by_target_id)
    local placements = {}
    local dimensions = {}
    local existing = {}
    local region_x = 0

    for _, target in ipairs(input.targets) do
        local dimension = dimensions_by_target_id[target.id]
        local packed_dimension = canonical_dimension(dimension, input.config.scroll_direction)

        if packed_dimension.h > 1 then
            return nil, "dimension " .. dimension.key .. " does not fit on the cross axis for target " .. tostring(target.id)
        end

        local rect = place_in_region(region_x, packed_dimension.w, packed_dimension.h, existing)
        while not rect do
            region_x = region_x + 1
            rect = place_in_region(region_x, packed_dimension.w, packed_dimension.h, existing)
        end

        placements[target.id] = rect
        dimensions[target.id] = dimension
        table.insert(existing, rect)
    end

    return {
        placements_by_id = placements,
        dimensions_by_id = dimensions,
        workspace_extent = layout_extent(placements),
    }
end

local function rank_candidate(candidate, input)
    local min_area = nil
    local max_area = nil

    for _, target in ipairs(input.targets) do
        local dimension = candidate.dimensions_by_id[target.id]
        local area = geometry.dimension_area(dimension)
        min_area = min_area and math.min(min_area, area) or area
        max_area = max_area and math.max(max_area, area) or area
    end

    candidate.ranking = {
        area_range = (max_area or 0) - (min_area or 0),
        workspace_extent = candidate.workspace_extent,
    }
end

local function compare_candidates(a, b)
    if a.ranking.area_range ~= b.ranking.area_range then
        return a.ranking.area_range < b.ranking.area_range
    end
    if a.ranking.workspace_extent ~= b.ranking.workspace_extent then
        return a.ranking.workspace_extent < b.ranking.workspace_extent
    end
    return false
end

local function canonical_allowed_dimensions(config)
    local out = {}
    for _, dimension in ipairs(config.allowed_dimensions or {}) do
        local canonical = canonical_dimension(dimension, config.scroll_direction)
        table.insert(out, {
            dimension = dimension,
            w = canonical.w,
            h = canonical.h,
        })
    end
    return out
end

local function find_canonical_dimension(config, w, h)
    for _, item in ipairs(canonical_allowed_dimensions(config)) do
        if nearly_equal(item.w, w) and nearly_equal(item.h, h) then
            return item.dimension
        end
    end
end

local function split_candidates_for_slot(slot, allowed)
    local candidates = {}

    for _, a in ipairs(allowed) do
        for _, b in ipairs(allowed) do
            if nearly_equal(a.h, slot.rect.h)
                and nearly_equal(b.h, slot.rect.h)
                and nearly_equal(a.w + b.w, slot.rect.w) then
                table.insert(candidates, {
                    {
                        rect = geometry.rect(slot.rect.x, slot.rect.y, a.w, a.h),
                        dimension = a.dimension,
                    },
                    {
                        rect = geometry.rect(slot.rect.x + a.w, slot.rect.y, b.w, b.h),
                        dimension = b.dimension,
                    },
                })
            end

            if nearly_equal(a.w, slot.rect.w)
                and nearly_equal(b.w, slot.rect.w)
                and nearly_equal(a.h + b.h, slot.rect.h) then
                table.insert(candidates, {
                    {
                        rect = geometry.rect(slot.rect.x, slot.rect.y, a.w, a.h),
                        dimension = a.dimension,
                    },
                    {
                        rect = geometry.rect(slot.rect.x, slot.rect.y + a.h, b.w, b.h),
                        dimension = b.dimension,
                    },
                })
            end
        end
    end

    table.sort(candidates, function(a, b)
        local area_range_a = math.abs(geometry.area(a[1].rect) - geometry.area(a[2].rect))
        local area_range_b = math.abs(geometry.area(b[1].rect) - geometry.area(b[2].rect))
        if area_range_a ~= area_range_b then
            return area_range_a < area_range_b
        end

        local extent_a = math.max(rect_extent(a[1].rect), rect_extent(a[2].rect))
        local extent_b = math.max(rect_extent(b[1].rect), rect_extent(b[2].rect))
        if extent_a ~= extent_b then
            return extent_a < extent_b
        end

        return a[1].rect.x < b[1].rect.x
    end)

    return candidates[1]
end

local function append_slot(slots, allowed)
    local best = nil
    for _, item in ipairs(allowed) do
        if item.h <= 1 + 0.0000001 then
            if not best
                or item.w < best.w
                or (item.w == best.w and item.h > best.h) then
                best = item
            end
        end
    end

    if not best then
        return nil, "no allowed dimension can be appended"
    end

    local extent = 0
    for _, slot in ipairs(slots) do
        extent = math.max(extent, rect_extent(slot.rect))
    end

    table.insert(slots, {
        rect = geometry.rect(extent, 0, best.w, best.h),
        dimension = best.dimension,
    })

    return true
end

local function generate_split_slots(input)
    local full_dimension = find_canonical_dimension(input.config, 1, 1)
    if not full_dimension then
        return nil, "split mode requires an allowed full viewport dimension"
    end

    local slots = {
        {
            rect = geometry.rect(0, 0, 1, 1),
            dimension = full_dimension,
        },
    }
    local allowed = canonical_allowed_dimensions(input.config)

    while #slots < #input.targets do
        local best_index = nil
        local best_area = nil

        for i, slot in ipairs(slots) do
            local area = geometry.area(slot.rect)
            if not best_area or area > best_area then
                best_area = area
                best_index = i
            end
        end

        local split = best_index and split_candidates_for_slot(slots[best_index], allowed)
        if split then
            table.remove(slots, best_index)
            table.insert(slots, best_index, split[2])
            table.insert(slots, best_index, split[1])
        else
            local appended, append_err = append_slot(slots, allowed)
            if not appended then
                return nil, append_err
            end
        end
    end

    return slots
end

local function layout_from_slots(input, slots)
    local placements = {}
    local dimensions = {}

    for i, target in ipairs(input.targets) do
        local slot = slots[i]
        local forced, forced_err = forced_dimension_for_target(input, target)
        if forced_err then
            return nil, forced_err
        end
        if forced and forced.key ~= slot.dimension.key then
            return nil, "forced dimension does not match split slot"
        end

        placements[target.id] = slot.rect
        dimensions[target.id] = slot.dimension
    end

    local layout = {
        placements_by_id = placements,
        dimensions_by_id = dimensions,
        workspace_extent = layout_extent(placements),
    }
    rank_candidate(layout, input)
    return layout
end

local function solve_split(input)
    local slots, slots_err = generate_split_slots(input)
    if not slots then
        return nil, slots_err
    end

    return layout_from_slots(input, slots)
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
    local dimensions_by_target_id = {}

    local function generate(index)
        if index > #input.targets then
            local candidate, candidate_err = pack_candidate(input, dimensions_by_target_id)
            if not candidate then
                return nil, candidate_err
            end

            rank_candidate(candidate, input)
            table.insert(candidates, candidate)
            return true
        end

        local target = input.targets[index]
        local forced, forced_err = forced_dimension_for_target(input, target)
        if forced_err then
            return nil, forced_err
        end

        if forced then
            dimensions_by_target_id[target.id] = forced
            return generate(index + 1)
        end

        for _, dimension in ipairs(input.config.allowed_dimensions) do
            dimensions_by_target_id[target.id] = dimension
            local ok, generation_err = generate(index + 1)
            if not ok then
                return nil, generation_err
            end
        end

        dimensions_by_target_id[target.id] = nil
        return true
    end

    local ok, generation_err = generate(1)
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

    local tiling_mode = input.config.tiling_mode or "split"
    if tiling_mode ~= "split" and tiling_mode ~= "ajuste" then
        return err("unsupported tiling mode: " .. tostring(tiling_mode))
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

    local best = nil
    local split_err = nil

    if tiling_mode == "split" then
        best, split_err = solve_split(input)
    end

    if not best then
        local candidates, candidates_err = M.generate_candidates(input)
        if not candidates then
            return err(split_err or candidates_err)
        end

        best = candidates[1]
        for i = 2, #candidates do
            if compare_candidates(candidates[i], best) then
                best = candidates[i]
            end
        end
    end

    transform_layout(best, input.config.scroll_direction)
    return { ok = true, layout = best }
end

return M
