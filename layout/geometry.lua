local M = {}

function M.rect(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

function M.area(rect)
    return rect.w * rect.h
end

function M.dimension_area(dimension)
    return dimension.w * dimension.h
end

function M.dimension_rect(viewport, dimension, x, y)
    return M.rect(
        x,
        y,
        viewport.w * dimension.w,
        viewport.h * dimension.h
    )
end

function M.contains(outer, inner)
    return inner.x >= outer.x
        and inner.y >= outer.y
        and inner.x + inner.w <= outer.x + outer.w
        and inner.y + inner.h <= outer.y + outer.h
end

function M.overlaps(a, b)
    return a.x < b.x + b.w
        and b.x < a.x + a.w
        and a.y < b.y + b.h
        and b.y < a.y + a.h
end

function M.intersection(a, b)
    local x1 = math.max(a.x, b.x)
    local y1 = math.max(a.y, b.y)
    local x2 = math.min(a.x + a.w, b.x + b.w)
    local y2 = math.min(a.y + a.h, b.y + b.h)

    if x2 <= x1 or y2 <= y1 then
        return nil
    end

    return M.rect(x1, y1, x2 - x1, y2 - y1)
end

function M.visible_area(rect, viewport)
    local visible = M.intersection(rect, viewport)
    if not visible then
        return 0
    end

    return M.area(visible)
end

function M.is_fully_visible(rect, viewport)
    return M.contains(viewport, rect)
end

function M.compare_dimension_size(a, b)
    local area_a = M.dimension_area(a)
    local area_b = M.dimension_area(b)
    if area_a ~= area_b then
        return area_a > area_b and -1 or 1
    end
    if a.w ~= b.w then
        return a.w > b.w and -1 or 1
    end
    if a.h ~= b.h then
        return a.h > b.h and -1 or 1
    end
    return 0
end

function M.round_rect(rect, pixel_viewport)
    local x1 = pixel_viewport.x + rect.x * pixel_viewport.w
    local y1 = pixel_viewport.y + rect.y * pixel_viewport.h
    local x2 = pixel_viewport.x + (rect.x + rect.w) * pixel_viewport.w
    local y2 = pixel_viewport.y + (rect.y + rect.h) * pixel_viewport.h

    x1 = math.floor(x1 + 0.5)
    y1 = math.floor(y1 + 0.5)
    x2 = math.floor(x2 + 0.5)
    y2 = math.floor(y2 + 0.5)

    return M.rect(x1, y1, x2 - x1, y2 - y1)
end

return M
