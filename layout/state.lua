local M = {}

local workspaces = {}

local function new_workspace_state()
    return {
        order = {},
        dimension_mode_by_id = {},
        focused_id = nil,
        viewport_offset = 0,
        last_layout = nil,
    }
end

local function copy_array(values)
    local out = {}
    for i, value in ipairs(values or {}) do
        out[i] = value
    end
    return out
end

local function copy_map(values)
    local out = {}
    for key, value in pairs(values or {}) do
        if type(value) == "table" then
            local nested = {}
            for nested_key, nested_value in pairs(value) do
                nested[nested_key] = nested_value
            end
            out[key] = nested
        else
            out[key] = value
        end
    end
    return out
end

local function copy_layout(layout)
    if type(layout) ~= "table" then
        return layout
    end

    local out = {}
    for key, value in pairs(layout) do
        if key == "placements_by_id" or key == "dimensions_by_id" then
            out[key] = copy_map(value)
        elseif key == "target_ids" then
            out[key] = copy_array(value)
        elseif type(value) == "table" then
            out[key] = copy_map(value)
        else
            out[key] = value
        end
    end
    return out
end

function M.get_workspace_state(workspace_key)
    local key = workspace_key or "global"
    if not workspaces[key] then
        workspaces[key] = new_workspace_state()
    end

    return workspaces[key]
end

function M.clone_workspace_state(workspace_state)
    return {
        order = copy_array(workspace_state.order),
        dimension_mode_by_id = copy_map(workspace_state.dimension_mode_by_id),
        focused_id = workspace_state.focused_id,
        viewport_offset = workspace_state.viewport_offset or 0,
        last_layout = copy_layout(workspace_state.last_layout),
        pending_layout_update = workspace_state.pending_layout_update,
        pending_viewport_update = workspace_state.pending_viewport_update,
    }
end

function M.commit_workspace_state(workspace_state, draft_state)
    workspace_state.order = copy_array(draft_state.order)
    workspace_state.dimension_mode_by_id = copy_map(draft_state.dimension_mode_by_id)
    workspace_state.focused_id = draft_state.focused_id
    workspace_state.viewport_offset = draft_state.viewport_offset or 0
    workspace_state.last_layout = copy_layout(draft_state.last_layout)
    workspace_state.pending_layout_update = draft_state.pending_layout_update
    workspace_state.pending_viewport_update = draft_state.pending_viewport_update
end

function M.set_focused_id(workspace_state, id)
    workspace_state.focused_id = id
end

function M.get_focused_id(workspace_state)
    return workspace_state.focused_id
end

function M.get_dimension_mode(workspace_state, id)
    return workspace_state.dimension_mode_by_id[id] or { kind = "auto" }
end

function M.set_dimension_mode(workspace_state, id, mode)
    if not id then
        return false
    end

    if not mode or mode.kind == "auto" then
        workspace_state.dimension_mode_by_id[id] = nil
        return true
    end

    workspace_state.dimension_mode_by_id[id] = {
        kind = "forced",
        key = mode.key,
    }
    return true
end

function M.remove_window_state(workspace_state, id)
    workspace_state.dimension_mode_by_id[id] = nil
    if workspace_state.focused_id == id then
        workspace_state.focused_id = nil
    end
end

function M.index_of(workspace_state, id)
    for i, current_id in ipairs(workspace_state.order) do
        if current_id == id then
            return i
        end
    end
end

function M.swap_order(workspace_state, focused_id, delta)
    local i = focused_id and M.index_of(workspace_state, focused_id)
    local j = i and (i + delta)

    if not i or j < 1 or j > #workspace_state.order then
        return false
    end

    workspace_state.order[i], workspace_state.order[j] = workspace_state.order[j], workspace_state.order[i]
    return true
end

function M.get_viewport_offset(workspace_state)
    return workspace_state.viewport_offset or 0
end

function M.set_viewport_offset(workspace_state, offset)
    workspace_state.viewport_offset = offset
end

function M.update_last_layout(workspace_state, layout)
    workspace_state.last_layout = copy_layout(layout)
end

function M.validate_workspace_state(workspace_state, present_ids)
    if type(workspace_state) ~= "table" then
        return false, "fit-scroller: workspace state must be a table"
    end

    local present = {}
    for _, id in ipairs(present_ids or workspace_state.order or {}) do
        present[id] = true
    end

    local seen = {}
    for _, id in ipairs(workspace_state.order or {}) do
        if seen[id] then
            return false, "fit-scroller: duplicate id in workspace order: " .. tostring(id)
        end
        if present_ids and not present[id] then
            return false, "fit-scroller: workspace order contains missing id: " .. tostring(id)
        end
        seen[id] = true
    end

    for id in pairs(workspace_state.dimension_mode_by_id or {}) do
        if not seen[id] then
            return false, "fit-scroller: dimension mode references missing id: " .. tostring(id)
        end
    end

    if workspace_state.focused_id and not seen[workspace_state.focused_id] then
        return false, "fit-scroller: focused id is not present: " .. tostring(workspace_state.focused_id)
    end

    local offset = workspace_state.viewport_offset
    if type(offset) ~= "number" or offset ~= offset or offset < 0 then
        return false, "fit-scroller: viewport_offset must be a finite non-negative number"
    end

    local layout = workspace_state.last_layout
    if layout and type(layout.placements_by_id) == "table" then
        for id in pairs(layout.placements_by_id) do
            if present_ids and not present[id] then
                return false, "fit-scroller: last_layout contains missing id: " .. tostring(id)
            end
        end
    end

    return true
end

function M._reset()
    workspaces = {}
end

return M
