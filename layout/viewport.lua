local M = {}

local traversal = nil

function M.set_dependencies(dependencies)
    traversal = dependencies.traversal
end

local function ok(offset, previous)
    return {
        ok = true,
        offset = offset,
        changed = offset ~= previous,
    }
end

local function is_finite_number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validate_extent_inputs(viewport_size, workspace_extent)
    if not is_finite_number(viewport_size) or viewport_size <= 0 then
        return nil, "fit-scroller: viewport size on scroll axis must be positive"
    end

    if not is_finite_number(workspace_extent) or workspace_extent < 0 then
        return nil, "fit-scroller: workspace extent must be a non-negative finite number"
    end

    return true
end

function M.max_offset(viewport_size, workspace_extent)
    local valid, validation_err = validate_extent_inputs(viewport_size, workspace_extent)
    if not valid then
        return nil, validation_err
    end

    return math.max(0, workspace_extent - viewport_size)
end

function M.clamp_offset(current_offset, viewport_size, workspace_extent)
    if not is_finite_number(current_offset) then
        return nil, "fit-scroller: viewport offset must be a finite number"
    end

    local max, max_err = M.max_offset(viewport_size, workspace_extent)
    if not max then
        return nil, max_err
    end

    return math.max(0, math.min(current_offset or 0, max))
end

function M.reveal(input)
    if not traversal then
        return { ok = false, error = "fit-scroller: viewport dependencies are not configured" }
    end

    if type(input) ~= "table" then
        return { ok = false, error = "fit-scroller: viewport input must be a table" }
    end

    local info = traversal.direction_info(input.direction)
    if not info then
        return { ok = false, error = "fit-scroller: unsupported scroll direction: " .. tostring(input.direction) }
    end

    if not input.focused_rect then
        return { ok = false, error = "fit-scroller: focused window has no placement" }
    end

    local viewport_size = info.scroll_axis == "x" and input.viewport.w or input.viewport.h
    local workspace_extent = input.workspace_extent
    local valid, validation_err = validate_extent_inputs(viewport_size, workspace_extent)
    if not valid then
        return { ok = false, error = validation_err }
    end

    local previous, clamp_err = M.clamp_offset(input.current_offset, viewport_size, workspace_extent)
    if not previous then
        return { ok = false, error = clamp_err }
    end

    local start = info.scroll_axis == "x" and input.focused_rect.x or input.focused_rect.y
    local size = info.scroll_axis == "x" and input.focused_rect.w or input.focused_rect.h
    if not is_finite_number(start) or not is_finite_number(size) or size <= 0 then
        return { ok = false, error = "fit-scroller: focused window rectangle is invalid" }
    end

    local window_start = start
    local window_end = start + size
    if info.scroll_sign == -1 then
        window_start = math.abs(start + size)
        window_end = math.abs(start)
    end

    local viewport_start = previous
    local viewport_end = previous + viewport_size
    local next_offset = previous

    if window_start >= viewport_start and window_end <= viewport_end then
        return ok(next_offset, previous)
    end

    if size > viewport_size then
        next_offset = window_start
    elseif window_start < viewport_start then
        next_offset = window_start
    elseif window_end > viewport_end then
        next_offset = window_end - viewport_size
    end

    next_offset = M.clamp_offset(next_offset, viewport_size, workspace_extent)
    return ok(next_offset, previous)
end

return M
