local M = {}

local EPSILON = 0.000001

local DIRECTIONS = {
    right = { scroll_axis = "x", cross_axis = "y", scroll_sign = 1 },
    left = { scroll_axis = "x", cross_axis = "y", scroll_sign = -1 },
    down = { scroll_axis = "y", cross_axis = "x", scroll_sign = 1 },
    up = { scroll_axis = "y", cross_axis = "x", scroll_sign = -1 },
}

local SIDES = {
    left = true,
    right = true,
    up = true,
    down = true,
}

local function epsilon(value)
    return value or EPSILON
end

function M.is_finite_number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

function M.direction_info(direction)
    return DIRECTIONS[direction]
end

function M.validate_rect(rect)
    if type(rect) ~= "table" then
        return nil, "fit-scroller: spatial rectangle must be a table"
    end

    if not M.is_finite_number(rect.x) then
        return nil, "fit-scroller: spatial rectangle x must be finite"
    end

    if not M.is_finite_number(rect.y) then
        return nil, "fit-scroller: spatial rectangle y must be finite"
    end

    if not M.is_finite_number(rect.w) or rect.w <= 0 then
        return nil, "fit-scroller: spatial rectangle w must be positive"
    end

    if not M.is_finite_number(rect.h) or rect.h <= 0 then
        return nil, "fit-scroller: spatial rectangle h must be positive"
    end

    return true
end

function M.validate_direction(direction)
    if not DIRECTIONS[direction] then
        return nil, "fit-scroller: unsupported spatial direction: " .. tostring(direction)
    end

    return true
end

function M.area(rect)
    return rect.w * rect.h
end

function M.center(rect)
    return {
        x = rect.x + rect.w / 2,
        y = rect.y + rect.h / 2,
    }
end

function M.interval(rect, axis)
    if axis == "x" then
        return rect.x, rect.x + rect.w
    end

    if axis == "y" then
        return rect.y, rect.y + rect.h
    end

    return nil, nil
end

function M.axis_size(rect, axis)
    if axis == "x" then
        return rect.w
    end

    if axis == "y" then
        return rect.h
    end
end

function M.scroll_interval(rect, direction)
    local info = DIRECTIONS[direction]
    if not info then
        return nil, nil
    end

    local start, finish = M.interval(rect, info.scroll_axis)
    if info.scroll_sign == -1 then
        return math.abs(finish), math.abs(start)
    end

    return start, finish
end

function M.cross_interval(rect, direction)
    local info = DIRECTIONS[direction]
    if not info then
        return nil, nil
    end

    return M.interval(rect, info.cross_axis)
end

function M.interval_overlap(a_start, a_end, b_start, b_end, eps)
    eps = epsilon(eps)
    local start = math.max(a_start, b_start)
    local finish = math.min(a_end, b_end)
    local size = finish - start

    if size <= eps then
        return 0
    end

    return size
end

function M.overlaps(a, b, eps)
    eps = epsilon(eps)
    return a.x < b.x + b.w - eps
        and b.x < a.x + a.w - eps
        and a.y < b.y + b.h - eps
        and b.y < a.y + a.h - eps
end

function M.is_within_cross_axis(rect, direction, eps)
    eps = epsilon(eps)
    local start, finish = M.cross_interval(rect, direction)
    if not start then
        return false
    end

    return start >= -eps and finish <= 1 + eps
end

function M.is_visible(rect, viewport_offset, direction)
    if not M.is_finite_number(viewport_offset) then
        return false
    end

    local scroll_start, scroll_end = M.scroll_interval(rect, direction)
    local cross_start, cross_end = M.cross_interval(rect, direction)
    if not scroll_start or not cross_start then
        return false
    end

    return M.interval_overlap(scroll_start, scroll_end, viewport_offset, viewport_offset + 1) > 0
        and M.interval_overlap(cross_start, cross_end, 0, 1) > 0
end

function M.is_fully_visible(rect, viewport_offset, direction, eps)
    eps = epsilon(eps)
    if not M.is_finite_number(viewport_offset) then
        return false
    end

    local scroll_start, scroll_end = M.scroll_interval(rect, direction)
    local cross_start, cross_end = M.cross_interval(rect, direction)
    if not scroll_start or not cross_start then
        return false
    end

    return scroll_start >= viewport_offset - eps
        and scroll_end <= viewport_offset + 1 + eps
        and cross_start >= -eps
        and cross_end <= 1 + eps
end

function M.visible_overlap(rect, viewport_offset, direction)
    if not M.is_finite_number(viewport_offset) then
        return 0
    end

    local scroll_start, scroll_end = M.scroll_interval(rect, direction)
    local cross_start, cross_end = M.cross_interval(rect, direction)
    if not scroll_start or not cross_start then
        return 0
    end

    local scroll_overlap = M.interval_overlap(scroll_start, scroll_end, viewport_offset, viewport_offset + 1)
    local cross_overlap = M.interval_overlap(cross_start, cross_end, 0, 1)
    return scroll_overlap * cross_overlap
end

local function perpendicular_overlap_for_side(a, b, side, eps)
    if side == "left" or side == "right" then
        return M.interval_overlap(a.y, a.y + a.h, b.y, b.y + b.h, eps)
    end

    return M.interval_overlap(a.x, a.x + a.w, b.x, b.x + b.w, eps)
end

function M.adjacent_side(a, b, eps)
    eps = epsilon(eps)

    if math.abs((b.x + b.w) - a.x) <= eps and perpendicular_overlap_for_side(a, b, "left", eps) > 0 then
        return "left"
    end

    if math.abs((a.x + a.w) - b.x) <= eps and perpendicular_overlap_for_side(a, b, "right", eps) > 0 then
        return "right"
    end

    if math.abs((b.y + b.h) - a.y) <= eps and perpendicular_overlap_for_side(a, b, "up", eps) > 0 then
        return "up"
    end

    if math.abs((a.y + a.h) - b.y) <= eps and perpendicular_overlap_for_side(a, b, "down", eps) > 0 then
        return "down"
    end
end

function M.is_adjacent(a, b, side, eps)
    if side ~= nil and not SIDES[side] then
        return false
    end

    local actual = M.adjacent_side(a, b, eps)
    if side then
        return actual == side
    end

    return actual ~= nil
end

function M.movement_distance(previous_rect, next_rect)
    local a = M.center(previous_rect)
    local b = M.center(next_rect)
    return math.abs(a.x - b.x) + math.abs(a.y - b.y)
end

function M.resize_distance(previous_rect, next_rect)
    return math.abs(previous_rect.w - next_rect.w) + math.abs(previous_rect.h - next_rect.h)
end

function M.is_moved(previous_rect, next_rect, eps)
    return M.movement_distance(previous_rect, next_rect) > epsilon(eps)
end

function M.is_resized(previous_rect, next_rect, eps)
    return M.resize_distance(previous_rect, next_rect) > epsilon(eps)
end

function M.directional_progress(previous_rect, next_rect, direction, eps)
    eps = epsilon(eps)
    local a = M.center(previous_rect)
    local b = M.center(next_rect)

    if direction == "left" then
        return a.x - b.x > eps
    end

    if direction == "right" then
        return b.x - a.x > eps
    end

    if direction == "up" then
        return a.y - b.y > eps
    end

    if direction == "down" then
        return b.y - a.y > eps
    end

    return false
end

return M
