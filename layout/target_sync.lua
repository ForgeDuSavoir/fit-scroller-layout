local M = {}

local function index_of(order, id)
    for i, current_id in ipairs(order) do
        if current_id == id then
            return i
        end
    end
end

local function contains(order, id)
    return index_of(order, id) ~= nil
end

local function insert_at(order, index, id)
    if index < 1 then
        index = 1
    elseif index > #order + 1 then
        index = #order + 1
    end

    table.insert(order, index, id)
end

local function insertion_index(order, insert_context)
    local mode = insert_context.insert_mode or "view"

    if mode == "first" then
        return 1
    end

    if mode == "after_focused" then
        local i = insert_context.focused_id and index_of(order, insert_context.focused_id)
        return i and (i + 1) or (#order + 1)
    end

    if mode == "before_focused" then
        local i = insert_context.focused_id and index_of(order, insert_context.focused_id)
        return i or (#order + 1)
    end

    if mode == "view" then
        local i = insert_context.last_visible_id and index_of(order, insert_context.last_visible_id)
        return i and (i + 1) or (#order + 1)
    end

    return #order + 1
end

local function validate_descriptors(descriptors)
    if type(descriptors) ~= "table" then
        return nil, "fit-scroller: target descriptors must be a list"
    end

    local seen = {}
    local active_count = 0
    for i, descriptor in ipairs(descriptors) do
        if type(descriptor) ~= "table" then
            return nil, "fit-scroller: target descriptor at index " .. tostring(i) .. " must be a table"
        end

        if descriptor.id == nil or descriptor.id == "" then
            return nil, "fit-scroller: target descriptor at index " .. tostring(i) .. " has no id"
        end

        if seen[descriptor.id] then
            return nil, "fit-scroller: duplicate target id during synchronization: " .. tostring(descriptor.id)
        end
        seen[descriptor.id] = true

        if descriptor.active then
            active_count = active_count + 1
        end
    end

    if active_count > 1 then
        return nil, "fit-scroller: multiple active targets during synchronization"
    end

    return true
end

function M.sync(workspace_state, descriptors, state, insert_context)
    insert_context = insert_context or {}

    local valid, validation_err = validate_descriptors(descriptors)
    if not valid then
        return nil, validation_err
    end

    local present_by_id = {}
    local descriptors_by_id = {}
    local previous_focused_id = workspace_state.focused_id
    local inserted_ids = {}
    local removed_ids = {}

    for _, descriptor in ipairs(descriptors or {}) do
        present_by_id[descriptor.id] = true
        descriptors_by_id[descriptor.id] = descriptor
    end

    local preserved_order = {}
    for _, id in ipairs(workspace_state.order) do
        if present_by_id[id] then
            table.insert(preserved_order, id)
        else
            state.remove_window_state(workspace_state, id)
            table.insert(removed_ids, id)
        end
    end
    workspace_state.order = preserved_order

    local batch_insert_index = nil
    for _, descriptor in ipairs(descriptors or {}) do
        local id = descriptor.id
        if not contains(workspace_state.order, id) then
            if batch_insert_index then
                batch_insert_index = batch_insert_index + 1
            else
                batch_insert_index = insertion_index(workspace_state.order, {
                    insert_mode = insert_context.insert_mode,
                    focused_id = previous_focused_id,
                    last_visible_id = insert_context.last_visible_id,
                })
            end

            insert_at(workspace_state.order, batch_insert_index, id)
            table.insert(inserted_ids, id)
        end
    end

    local active_id = nil
    for _, descriptor in ipairs(descriptors or {}) do
        if descriptor.active then
            active_id = descriptor.id
            break
        end
    end

    if active_id then
        workspace_state.focused_id = active_id
    elseif workspace_state.focused_id and not present_by_id[workspace_state.focused_id] then
        workspace_state.focused_id = nil
    end

    local focus_changed = workspace_state.focused_id ~= previous_focused_id

    local ordered = {}
    for _, id in ipairs(workspace_state.order) do
        local descriptor = descriptors_by_id[id]
        if descriptor then
            table.insert(ordered, descriptor)
        end
    end

    return ordered, {
        inserted_ids = inserted_ids,
        removed_ids = removed_ids,
        structural_changed = #inserted_ids > 0 or #removed_ids > 0,
        focus_changed = focus_changed,
    }
end

return M
