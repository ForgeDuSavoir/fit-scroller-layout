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

function M.execute(workspace_state, effective_config, state, config, msg)
    local family, action, rest, raw = parse(msg)
    if not family then
        return unsupported(msg)
    end

    if rest then
        return unsupported(raw)
    end

    if family == "move" then
        if action ~= "previous" and action ~= "next" then
            return unsupported(raw)
        end

        local delta = action == "previous" and -1 or 1
        local changed = state.swap_order(workspace_state, state.get_focused_id(workspace_state), delta)
        return ok(changed)
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
        return ok(true)
    end

    if family == "focus" then
        if action ~= "previous" and action ~= "next" then
            return unsupported(raw)
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
