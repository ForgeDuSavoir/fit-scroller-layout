local M = {}

local DIRECTIONS = {
    right = {
        direction = "right",
        scroll_axis = "x",
        cross_axis = "y",
        primary = "x",
        secondary = "y",
        scroll_sign = 1,
    },
    left = {
        direction = "left",
        scroll_axis = "x",
        cross_axis = "y",
        primary = "x",
        secondary = "y",
        scroll_sign = -1,
    },
    down = {
        direction = "down",
        scroll_axis = "y",
        cross_axis = "x",
        primary = "y",
        secondary = "x",
        scroll_sign = 1,
    },
    up = {
        direction = "up",
        scroll_axis = "y",
        cross_axis = "x",
        primary = "y",
        secondary = "x",
        scroll_sign = -1,
    },
}

function M.direction_info(direction)
    return DIRECTIONS[direction]
end

function M.scroll_axis(direction)
    local info = M.direction_info(direction)
    return info and info.scroll_axis
end

function M.cross_axis(direction)
    local info = M.direction_info(direction)
    return info and info.cross_axis
end

function M.from_canonical(direction, rect)
    if direction == "right" then
        return { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end

    if direction == "left" then
        return { x = -(rect.x + rect.w), y = rect.y, w = rect.w, h = rect.h }
    end

    if direction == "down" then
        return { x = rect.y, y = rect.x, w = rect.h, h = rect.w }
    end

    if direction == "up" then
        return { x = rect.y, y = -(rect.x + rect.w), w = rect.h, h = rect.w }
    end
end

function M.to_canonical(direction, rect)
    if direction == "right" then
        return { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
    end

    if direction == "left" then
        return { x = -(rect.x + rect.w), y = rect.y, w = rect.w, h = rect.h }
    end

    if direction == "down" then
        return { x = rect.y, y = rect.x, w = rect.h, h = rect.w }
    end

    if direction == "up" then
        return { x = -(rect.y + rect.h), y = rect.x, w = rect.h, h = rect.w }
    end
end

function M.compare_positions(direction, a, b)
    local ca = M.to_canonical(direction, a)
    local cb = M.to_canonical(direction, b)

    if ca.x ~= cb.x then
        return ca.x < cb.x and -1 or 1
    end
    if ca.y ~= cb.y then
        return ca.y < cb.y and -1 or 1
    end
    if ca.w ~= cb.w then
        return ca.w < cb.w and -1 or 1
    end
    if ca.h ~= cb.h then
        return ca.h < cb.h and -1 or 1
    end

    return 0
end

return M
