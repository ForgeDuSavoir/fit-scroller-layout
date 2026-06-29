local M = {}

local function unsupported(msg)
    local value = type(msg) == "string" and msg:match("^%s*(.-)%s*$") or ""
    if value == "" then
        return { ok = false, error = "fit-scroller: expected command" }
    end

    return { ok = false, error = "fit-scroller: unsupported command: " .. value }
end

local function parse(msg)
    if type(msg) ~= "string" then
        return nil
    end

    local trimmed = msg:match("^%s*(.-)%s*$")
    if trimmed == "" then
        return nil
    end

    local family, action, rest = trimmed:match("^(%S+)%s*(%S*)%s*(.*)$")
    return family, action ~= "" and action or nil, rest ~= "" and rest or nil, trimmed
end

local function ok(changed)
    return {
        ok = true,
        changed = changed,
        needs_layout_update = changed,
    }
end

local DIRECTIONS = {
    left = true,
    right = true,
    up = true,
    down = true,
}

local function placement_priority(effective_config)
    if type(effective_config) == "table" and effective_config.placement_priority then
        return effective_config.placement_priority
    end

    return "order"
end

local function mode_error(required, raw)
    return {
        ok = false,
        error = "fit-scroller: command requires " .. required .. " placement: " .. tostring(raw),
    }
end

function M.execute(workspace_state, effective_config, state, config, msg)
    local family, action, rest, raw = parse(msg)
    if not family then
        return unsupported(msg)
    end

    if rest then
        return unsupported(raw)
    end

    local priority = placement_priority(effective_config)

    if family == "move" then
        if action == "previous" or action == "next" then
            if priority ~= "order" then
                return mode_error("order", raw)
            end

            local delta = action == "previous" and -1 or 1
            local changed = state.swap_order(workspace_state, state.get_focused_id(workspace_state), delta)
            return ok(changed)
        end

        if DIRECTIONS[action] then
            if priority ~= "spatial" then
                return mode_error("spatial", raw)
            end

            local focused_id = state.get_focused_id(workspace_state)
            if not focused_id then
                return ok(false)
            end

            return {
                ok = true,
                changed = true,
                needs_layout_update = true,
                spatial_event = {
                    kind = "move",
                    target_id = focused_id,
                    direction = action,
                },
            }
        end

        if action then
            return unsupported(raw)
        end

        return unsupported(raw)
    end

    if family == "toggle" then
        if action ~= "dimension" then
            return unsupported(raw)
        end

        local focused_id = state.get_focused_id(workspace_state)
        if not focused_id then
            return ok(false)
        end

        local current_mode = state.get_dimension_mode(workspace_state, focused_id)
        local next_mode, err = config.next_dimension_mode(effective_config, current_mode)
        if not next_mode then
            return { ok = false, error = err }
        end

        state.set_dimension_mode(workspace_state, focused_id, next_mode)
        if priority == "spatial" then
            if next_mode.kind == "auto" then
                return {
                    ok = true,
                    changed = true,
                    needs_layout_update = true,
                    spatial_event = {
                        kind = "dimension_auto",
                        target_id = focused_id,
                        previous_key = current_mode and current_mode.key,
                    },
                }
            end

            return {
                ok = true,
                changed = true,
                needs_layout_update = true,
                spatial_event = {
                    kind = "dimension_forced",
                    target_id = focused_id,
                    key = next_mode.key,
                },
            }
        end

        return ok(true)
    end

    if family == "focus" then
        if action == "previous" or action == "next" then
            if priority ~= "order" then
                return mode_error("order", raw)
            end

            local focused_id = state.get_focused_id(workspace_state)
            local current_index = focused_id and state.index_of(workspace_state, focused_id)
            if not current_index then
                return ok(false)
            end

            local delta = action == "previous" and -1 or 1
            local target_id = workspace_state.order[current_index + delta]
            if not target_id then
                return ok(false)
            end

            return {
                ok = true,
                changed = true,
                needs_viewport_update = true,
                focus_target_id = target_id,
            }
        end

        if DIRECTIONS[action] then
            if priority ~= "spatial" then
                return mode_error("spatial", raw)
            end

            local focused_id = state.get_focused_id(workspace_state)
            if not focused_id then
                return ok(false)
            end

            return {
                ok = true,
                changed = true,
                needs_viewport_update = true,
                focus_direction = action,
            }
        end

        if action then
            return unsupported(raw)
        end

        return unsupported(raw)
    end

    if family == "reveal" then
        if action ~= "focus" then
            return unsupported(raw)
        end

        return {
            ok = true,
            changed = true,
            needs_viewport_update = true,
            reveal_focus = true,
        }
    end

    if family == "follow" then
        if action then
            return unsupported(raw)
        end

        return {
            ok = true,
            changed = true,
            needs_viewport_update = true,
            reveal_focus = true,
        }
    end

    return unsupported(raw)
end

return M
