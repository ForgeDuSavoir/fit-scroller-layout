local M = {}

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function valid_rect(rect)
    return type(rect) == "table" and finite(rect.x) and finite(rect.y)
        and finite(rect.w) and finite(rect.h) and rect.w > 0 and rect.h > 0
end

local function clip(rect, area)
    local x, y = math.max(rect.x, area.x), math.max(rect.y, area.y)
    local right = math.min(rect.x + rect.w, area.x + area.w)
    local bottom = math.min(rect.y + rect.h, area.y + area.h)
    if x < right and y < bottom then
        return { x = x, y = y, w = right - x, h = bottom - y }
    end
end

local function distance_squared(rect, point)
    local dx = math.max(rect.x - point.x, 0, point.x - rect.x - rect.w)
    local dy = math.max(rect.y - point.y, 0, point.y - rect.y - rect.h)
    return dx * dx + dy * dy
end

-- Return an insertion index into order with the dragged ID omitted.
function M.select_slot(order, drop, rendered)
    local survivors = {}
    local indices = {}
    for _, id in ipairs(order) do
        if id ~= drop.id then
            survivors[#survivors + 1] = id
            indices[id] = #survivors
        end
    end

    local function slot(id, after)
        return { anchor_id = id, after = after, index = indices[id] + (after and 1 or 0) }
    end

    local function original_slot()
        if indices[drop.previous_id] then return slot(drop.previous_id, true) end
        if indices[drop.next_id] then return slot(drop.next_id, false) end
        return { index = math.max(1, math.min(drop.index or 1, #survivors + 1)) }
    end

    local point = drop.point
    local area = rendered and rendered.area
    local direction = rendered and rendered.direction
    if not valid_rect(area) or type(rendered.rects) ~= "table" or type(point) ~= "table" or not finite(point.x) or not finite(point.y)
        or point.x < area.x or point.x >= area.x + area.w
        or point.y < area.y or point.y >= area.y + area.h
        or (direction ~= "right" and direction ~= "left" and direction ~= "down" and direction ~= "up") then
        return original_slot()
    end

    local vertical = direction == "up" or direction == "down"
    local sign = (direction == "left" or direction == "up") and -1 or 1
    local axis, size = "x", "w"
    local cross_axis, cross_size = "y", "h"
    if vertical then axis, size, cross_axis, cross_size = "y", "h", "x", "w" end
    local strips = {}
    local first_visible, last_visible, last_strip, hovered
    local nearest, nearest_distance, first_edge, last_edge
    for _, id in ipairs(survivors) do
        local rect = rendered.rects[id]
        local region = valid_rect(rect) and clip(rect, area)
        if region then
            local start = sign * (region[axis] + (sign < 0 and region[size] or 0))
            local finish = start + region[size]
            first_edge = math.min(first_edge or start, start)
            last_edge = math.max(last_edge or finish, finish)
            first_visible = first_visible or id
            last_visible = id
            last_strip = tostring(rect[axis]) .. ":" .. tostring(rect[size])
            strips[last_strip] = (strips[last_strip] or 0) + 1
            if not hovered and point.x >= region.x and point.x < region.x + region.w
                and point.y >= region.y and point.y < region.y + region.h then
                hovered = id
            end
            local distance = distance_squared(region, point)
            if not nearest_distance or distance < nearest_distance then
                nearest, nearest_distance = id, distance
            end
        end
    end
    if not nearest then return original_slot() end

    if sign * point[axis] < first_edge then return slot(first_visible, false) end
    if sign * point[axis] > last_edge then return slot(last_visible, true) end
    if hovered == last_visible then
        local rect = rendered.rects[last_visible]
        local after
        if strips[last_strip] > 1 then
            after = point[cross_axis] >= rect[cross_axis] + rect[cross_size] / 2
        else
            after = sign * (point[axis] - rect[axis] - rect[size] / 2) >= 0
        end
        return slot(last_visible, after)
    end
    return slot(hovered or nearest, false)
end

return M
