local M = {}

local spatial_geometry = nil
local EPSILON = 0.000001

function M.set_dependencies(dependencies)
    spatial_geometry = dependencies and dependencies.spatial_geometry
end

local function err(message)
    return { ok = false, error = "fit-scroller: spatial focus: " .. message }
end

local function ok_noop()
    return { ok = true, changed = false }
end

local function center_distance(a, b)
    return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

local function candidate_metrics(focused_rect, focused_center, candidate_rect, candidate_center, direction)
    local directional_distance
    local perpendicular_overlap

    if direction == "left" then
        directional_distance = focused_center.x - candidate_center.x
        perpendicular_overlap = spatial_geometry.interval_overlap(
            focused_rect.y,
            focused_rect.y + focused_rect.h,
            candidate_rect.y,
            candidate_rect.y + candidate_rect.h
        )
    elseif direction == "right" then
        directional_distance = candidate_center.x - focused_center.x
        perpendicular_overlap = spatial_geometry.interval_overlap(
            focused_rect.y,
            focused_rect.y + focused_rect.h,
            candidate_rect.y,
            candidate_rect.y + candidate_rect.h
        )
    elseif direction == "up" then
        directional_distance = focused_center.y - candidate_center.y
        perpendicular_overlap = spatial_geometry.interval_overlap(
            focused_rect.x,
            focused_rect.x + focused_rect.w,
            candidate_rect.x,
            candidate_rect.x + candidate_rect.w
        )
    elseif direction == "down" then
        directional_distance = candidate_center.y - focused_center.y
        perpendicular_overlap = spatial_geometry.interval_overlap(
            focused_rect.x,
            focused_rect.x + focused_rect.w,
            candidate_rect.x,
            candidate_rect.x + candidate_rect.w
        )
    end

    return {
        directional_distance = directional_distance,
        perpendicular_overlap = perpendicular_overlap or 0,
        center_distance = center_distance(focused_center, candidate_center),
    }
end

local function is_directional_candidate(focused_center, candidate_center, direction)
    if direction == "left" then
        return candidate_center.x < focused_center.x - EPSILON
    end

    if direction == "right" then
        return candidate_center.x > focused_center.x + EPSILON
    end

    if direction == "up" then
        return candidate_center.y < focused_center.y - EPSILON
    end

    if direction == "down" then
        return candidate_center.y > focused_center.y + EPSILON
    end

    return false
end

local function compare_candidates(a, b)
    if a.perpendicular_overlap ~= b.perpendicular_overlap then
        return a.perpendicular_overlap > b.perpendicular_overlap
    end

    if a.directional_distance ~= b.directional_distance then
        return a.directional_distance < b.directional_distance
    end

    if a.center_distance ~= b.center_distance then
        return a.center_distance < b.center_distance
    end

    return tostring(a.id) < tostring(b.id)
end

function M.resolve(input)
    if not spatial_geometry then
        return err("dependencies are not configured")
    end

    if type(input) ~= "table" then
        return err("input must be a table")
    end

    local valid_direction, direction_err = spatial_geometry.validate_direction(input.direction)
    if not valid_direction then
        return err(direction_err)
    end

    local focused_id = input.focused_id
    if not focused_id then
        return ok_noop()
    end

    local layout = input.last_layout
    local placements = type(layout) == "table" and layout.placements_by_id or nil
    if type(placements) ~= "table" then
        return err("last_layout placements are required")
    end

    local focused_rect = placements[focused_id]
    if not focused_rect then
        return err("focused target has no placement: " .. tostring(focused_id))
    end

    local valid_rect, rect_err = spatial_geometry.validate_rect(focused_rect)
    if not valid_rect then
        return err("focused target placement is invalid: " .. rect_err)
    end

    local focused_center = spatial_geometry.center(focused_rect)
    local candidates = {}

    for id, rect in pairs(placements) do
        if id ~= focused_id then
            local candidate_valid, candidate_err = spatial_geometry.validate_rect(rect)
            if not candidate_valid then
                return err("target placement is invalid for " .. tostring(id) .. ": " .. candidate_err)
            end

            local candidate_center = spatial_geometry.center(rect)
            if is_directional_candidate(focused_center, candidate_center, input.direction) then
                local metrics = candidate_metrics(focused_rect, focused_center, rect, candidate_center, input.direction)
                table.insert(candidates, {
                    id = id,
                    perpendicular_overlap = metrics.perpendicular_overlap,
                    directional_distance = metrics.directional_distance,
                    center_distance = metrics.center_distance,
                })
            end
        end
    end

    if #candidates == 0 then
        return ok_noop()
    end

    table.sort(candidates, compare_candidates)

    return {
        ok = true,
        changed = true,
        focus_target_id = candidates[1].id,
        target_id = candidates[1].id,
        direction = input.direction,
    }
end

return M
