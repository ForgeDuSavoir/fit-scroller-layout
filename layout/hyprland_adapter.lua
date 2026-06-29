local M = {}

M.version = "display-resolution-v4-area-monitor"

local function current_dir()
    local source = debug and debug.getinfo(1, "S").source
    if type(source) ~= "string" or source:sub(1, 1) ~= "@" then
        return nil
    end

    local path = source:sub(2)
    return path:match("^(.*)/[^/]*$")
end

local function load_relative(path)
    local dir = current_dir()
    if not dir then
        return nil, "fit-scroller: unable to resolve layout module path"
    end

    local chunk, err = loadfile(dir .. "/" .. path)
    if not chunk then
        return nil, err
    end

    return chunk()
end

local config, config_load_err = load_relative("config.lua")
local state, state_load_err = load_relative("state.lua")
local target_sync, target_sync_load_err = load_relative("target_sync.lua")
local commands, commands_load_err = load_relative("commands.lua")
local geometry, geometry_load_err = load_relative("geometry.lua")
local traversal, traversal_load_err = load_relative("traversal.lua")
local solver, solver_load_err = load_relative("solver.lua")
local spatial_geometry, spatial_geometry_load_err = load_relative("spatial_geometry.lua")
local spatial_solver, spatial_solver_load_err = load_relative("spatial_solver.lua")
local viewport, viewport_load_err = load_relative("viewport.lua")

local load_err = config_load_err
    or state_load_err
    or target_sync_load_err
    or commands_load_err
    or geometry_load_err
    or traversal_load_err
    or solver_load_err
    or spatial_geometry_load_err
    or spatial_solver_load_err
    or viewport_load_err
if load_err then
    error(load_err)
end

solver.set_dependencies({
    geometry = geometry,
    traversal = traversal,
})

spatial_solver.set_dependencies({
    spatial_geometry = spatial_geometry,
})

viewport.set_dependencies({
    traversal = traversal,
})

local function target_id(target, index)
    local window = target and target.window
    if window and window.stable_id ~= nil then
        return tostring(window.stable_id)
    end

    if window and window.address ~= nil then
        return "address:" .. tostring(window.address)
    end

    if target and target.index ~= nil then
        return tostring(target.index)
    end

    return "target:" .. tostring(index)
end

local function target_active(target)
    local window = target and target.window
    return window and window.active and true or false
end

local function target_descriptors(targets)
    local descriptors = {}
    if type(targets) ~= "table" then
        return descriptors
    end

    for i, target in ipairs(targets or {}) do
        local window = target and target.window
        table.insert(descriptors, {
            id = target_id(target, i),
            target = target,
            window = window,
            active = target_active(target),
        })
    end

    return descriptors
end

local function workspace_key_from_workspace(workspace)
    if type(workspace) == "table" then
        if workspace.id ~= nil then
            return "workspace:" .. tostring(workspace.id)
        end
        if workspace.config_name ~= nil then
            return "workspace-config:" .. tostring(workspace.config_name)
        end
        if workspace.name ~= nil then
            return "workspace-name:" .. tostring(workspace.name)
        end
    elseif workspace ~= nil then
        return "workspace:" .. tostring(workspace)
    end
end

local function workspace_key(ctx)
    for _, target in ipairs(ctx.targets or {}) do
        local window = target and target.window
        local key = workspace_key_from_workspace(window and window.workspace)
        if key then
            return key
        end
    end

    return "global"
end

local function add_candidate(candidates, seen, value)
    local value_type = type(value)
    if value_type ~= "string" and value_type ~= "number" then
        return
    end

    local candidate = tostring(value)
    if candidate == "" or seen[candidate] then
        return
    end

    seen[candidate] = true
    table.insert(candidates, candidate)
end

local function safe_field(value, field)
    if value == nil then
        return nil
    end

    local ok, result = pcall(function()
        return value[field]
    end)
    if not ok then
        return nil
    end

    return result
end

local function add_monitor_candidates(candidates, seen, monitor)
    local monitor_type = type(monitor)
    if monitor_type == "table" or monitor_type == "userdata" then
        add_candidate(candidates, seen, safe_field(monitor, "name"))
        add_candidate(candidates, seen, safe_field(monitor, "output"))
        local id = safe_field(monitor, "id")
        if id ~= nil then
            add_candidate(candidates, seen, "monitor:" .. tostring(id))
        end
        return
    end

    add_candidate(candidates, seen, monitor)
end

local function add_workspace_candidates(candidates, seen, workspace)
    local workspace_type = type(workspace)
    if workspace_type ~= "table" and workspace_type ~= "userdata" then
        return
    end

    add_monitor_candidates(candidates, seen, safe_field(workspace, "monitor"))
end

local function safe_call(fn, ...)
    if type(fn) ~= "function" then
        return nil
    end

    local ok, result = pcall(fn, ...)
    if not ok then
        return nil
    end

    return result
end

local function add_area_monitor_candidate(candidates, seen, area)
    if type(area) ~= "table" or not hl or type(hl.get_monitor_at) ~= "function" then
        return
    end

    local x = area.x
    local y = area.y
    local w = area.w or area.width
    local h = area.h or area.height
    if type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
        return
    end

    add_monitor_candidates(candidates, seen, safe_call(hl.get_monitor_at, {
        x = x + (w / 2),
        y = y + (h / 2),
    }))
end

local function display_candidates(ctx)
    local candidates = {}
    local seen = {}

    for _, target in ipairs(ctx.targets or {}) do
        local window = target and safe_field(target, "window")
        add_monitor_candidates(candidates, seen, safe_field(window, "monitor"))
        add_workspace_candidates(candidates, seen, safe_field(window, "workspace"))
    end

    add_monitor_candidates(candidates, seen, ctx.monitor)
    add_monitor_candidates(candidates, seen, ctx.output)
    add_monitor_candidates(candidates, seen, ctx.display)
    add_area_monitor_candidate(candidates, seen, ctx.area)

    if hl then
        add_workspace_candidates(candidates, seen, safe_call(hl.get_active_workspace))

        local workspaces = safe_call(hl.get_workspaces)
        if type(workspaces) == "table" then
            for _, workspace in ipairs(workspaces) do
                if type(workspace) == "table" and workspace.active then
                    add_workspace_candidates(candidates, seen, workspace)
                end
            end
        end

        local windows = safe_call(hl.get_windows)
        if type(windows) == "table" then
            for _, window in ipairs(windows) do
                local window_type = type(window)
                if (window_type == "table" or window_type == "userdata") and safe_field(window, "active") then
                    add_monitor_candidates(candidates, seen, safe_field(window, "monitor"))
                    add_workspace_candidates(candidates, seen, safe_field(window, "workspace"))
                end
            end
        end
    end

    return candidates
end

local function display_id(ctx)
    local candidates = display_candidates(ctx)
    local displays = type(config.raw_config) == "table" and config.raw_config.displays or nil

    if type(displays) == "table" then
        for _, candidate in ipairs(candidates) do
            if displays[candidate] ~= nil then
                return candidate
            end
        end
    end

    return candidates[1] or "default"
end

M._display_id = display_id
M._display_candidates = display_candidates
M._config = config
M._state = state

local function workspace_context(ctx, workspace_state)
    local descriptors = target_descriptors(ctx.targets)
    local effective_config, err = config.get_for_display(display_id(ctx))
    if not effective_config then
        return nil, err
    end
    local last_visible_id = nil
    if effective_config.placement_priority == "order" and effective_config.insert_mode == "view" then
        last_visible_id = M.last_visible_id(workspace_state, effective_config)
    end

    local ordered_targets, sync_result = target_sync.sync(workspace_state, descriptors, state, {
        insert_mode = effective_config.insert_mode,
        placement_priority = effective_config.placement_priority,
        last_visible_id = last_visible_id,
    })
    if not ordered_targets then
        return nil, sync_result
    end

    return {
        state = workspace_state,
        targets = ordered_targets,
        config = effective_config,
        sync = sync_result or {},
    }
end

local function config_signature(effective_config)
    local parts = {
        "display=" .. tostring(effective_config.display_id),
        "direction=" .. tostring(effective_config.scroll_direction),
        "insert=" .. tostring(effective_config.insert_mode),
        "placement=" .. tostring(effective_config.placement_priority),
    }

    for _, key in ipairs(effective_config.toggle_cycle or {}) do
        table.insert(parts, "dimension=" .. tostring(key))
    end

    return table.concat(parts, ";")
end

M._config_signature = config_signature

local function descriptors_by_id(descriptors)
    local by_id = {}
    for _, descriptor in ipairs(descriptors or {}) do
        by_id[descriptor.id] = descriptor
    end
    return by_id
end

local function descriptor_ids(descriptors)
    local ids = {}
    for _, descriptor in ipairs(descriptors or {}) do
        table.insert(ids, descriptor.id)
    end
    return ids
end

local function sorted_keys(value)
    local keys = {}
    if type(value) ~= "table" then
        return keys
    end

    for key in pairs(value) do
        table.insert(keys, tostring(key))
    end

    table.sort(keys)
    return keys
end

local function describe_table(value)
    local parts = {}
    for _, key in ipairs(sorted_keys(value)) do
        local field = value[key]
        local field_type = type(field)
        if field_type == "string" or field_type == "number" or field_type == "boolean" or field_type == "function" then
            table.insert(parts, key .. ":" .. field_type)
        elseif field_type == "table" then
            table.insert(parts, key .. ":table")
        end
    end

    return table.concat(parts, ", ")
end

local function debug_targets(descriptors)
    local lines = { "fit-scroller debug targets:" }

    for i, descriptor in ipairs(descriptors or {}) do
        local target = descriptor.target
        local window = target and target.window
        table.insert(lines, string.format(
            "%d id=%s active=%s target={%s} window={%s}",
            i,
            tostring(descriptor.id),
            tostring(descriptor.active),
            describe_table(target),
            describe_table(window)
        ))
    end

    return table.concat(lines, "\n")
end

local function debug_config(ctx)
    local id = display_id(ctx)
    local effective_config, err = config.get_for_display(id)
    local lines = {
        "fit-scroller debug config:",
        "adapter_version=" .. tostring(M.version),
        "resolved_display=" .. tostring(id),
        "display_candidates=" .. table.concat(display_candidates(ctx), ", "),
    }

    local displays = type(config.raw_config) == "table" and config.raw_config.displays or nil
    if type(displays) == "table" then
        table.insert(lines, "configured_displays=" .. table.concat(sorted_keys(displays), ", "))
    end

    if not effective_config then
        table.insert(lines, "error=" .. tostring(err))
        return table.concat(lines, "\n")
    end

    table.insert(lines, "scroll_direction=" .. tostring(effective_config.scroll_direction))
    table.insert(lines, "insert_mode=" .. tostring(effective_config.insert_mode))
    table.insert(lines, "placement_priority=" .. tostring(effective_config.placement_priority))
    table.insert(lines, "dimensions=" .. table.concat(effective_config.toggle_cycle or {}, ", "))
    table.insert(lines, "config_signature=" .. config_signature(effective_config))
    return table.concat(lines, "\n")
end

local function numeric_area(ctx)
    local area = ctx.area
    if type(area) ~= "table" then
        return nil, "fit-scroller: Hyprland area is not a Lua table; rectangle conversion requires runtime verification"
    end

    local x = area.x or 0
    local y = area.y or 0
    local w = area.w or area.width
    local h = area.h or area.height

    if type(x) ~= "number" or type(y) ~= "number" or type(w) ~= "number" or type(h) ~= "number" then
        return nil, "fit-scroller: Hyprland area does not expose numeric x/y/w/h fields"
    end

    return geometry.rect(x, y, w, h)
end

local function convert_rect(ctx, rect)
    local area, err = numeric_area(ctx)
    if not area then
        return nil, err
    end

    return geometry.round_rect(rect, area)
end

local function is_finite_number(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end

local function validate_layout_output(layout, ordered_targets)
    if type(layout) ~= "table" then
        return nil, "fit-scroller: solver produced no layout"
    end

    if type(layout.placements_by_id) ~= "table" then
        return nil, "fit-scroller: solver produced no placements"
    end

    if type(layout.dimensions_by_id) ~= "table" then
        return nil, "fit-scroller: solver produced no dimensions"
    end

    if not is_finite_number(layout.workspace_extent) or layout.workspace_extent < 0 then
        return nil, "fit-scroller: solver produced invalid workspace_extent"
    end

    local expected = {}
    for _, descriptor in ipairs(ordered_targets or {}) do
        local id = descriptor.id
        expected[id] = true

        local rect = layout.placements_by_id[id]
        if type(rect) ~= "table" then
            return nil, "fit-scroller: solver produced no placement for target " .. tostring(id)
        end

        if not is_finite_number(rect.x) or not is_finite_number(rect.y)
            or not is_finite_number(rect.w) or rect.w <= 0
            or not is_finite_number(rect.h) or rect.h <= 0 then
            return nil, "fit-scroller: solver produced invalid placement for target " .. tostring(id)
        end

        if type(layout.dimensions_by_id[id]) ~= "table" then
            return nil, "fit-scroller: solver produced no dimension for target " .. tostring(id)
        end
    end

    for id in pairs(layout.placements_by_id) do
        if not expected[id] then
            return nil, "fit-scroller: solver produced placement for unknown target " .. tostring(id)
        end
    end

    for id in pairs(layout.dimensions_by_id) do
        if not expected[id] then
            return nil, "fit-scroller: solver produced dimension for unknown target " .. tostring(id)
        end
    end

    return true
end

local function solve_workspace(workspace)
    if workspace.config.placement_priority == "spatial" then
        local previous_layout = workspace.state.last_layout
        local event = workspace.state.pending_spatial_event

        if not event then
            local added_ids = workspace.sync.added_ids or workspace.sync.inserted_ids or {}
            local removed_ids = workspace.sync.removed_ids or {}
            local current_signature = workspace.state.config_signature
            local next_signature = config_signature(workspace.config)

            if type(previous_layout) ~= "table" then
                event = { kind = "initial" }
            elseif current_signature ~= next_signature then
                event = { kind = "config_changed" }
            elseif #added_ids == 1 and #removed_ids == 0 then
                event = { kind = "window_added", target_id = added_ids[1] }
            elseif #removed_ids == 1 and #added_ids == 0 then
                local removed_id = removed_ids[1]
                event = {
                    kind = "window_removed",
                    target_id = removed_id,
                    previous_rect = previous_layout.placements_by_id and previous_layout.placements_by_id[removed_id],
                }
            elseif #added_ids > 0 or #removed_ids > 0 or workspace.state.pending_layout_update then
                event = { kind = "config_changed" }
            else
                event = { kind = "config_changed" }
            end
        end

        return spatial_solver.solve({
            config = workspace.config,
            targets = workspace.targets,
            dimension_mode_by_id = workspace.state.dimension_mode_by_id,
            last_layout = previous_layout,
            viewport_offset = state.get_viewport_offset(workspace.state),
            event = event,
        })
    end

    return solver.solve({
        config = workspace.config,
        targets = workspace.targets,
        dimension_mode_by_id = workspace.state.dimension_mode_by_id,
    })
end

local function viewport_size_for_direction(direction)
    local info = traversal.direction_info(direction)
    if info.scroll_axis == "x" then
        return 1
    end
    return 1
end

local apply_viewport_offset

local function update_viewport_offset(workspace, layout, reveal_id)
    local direction = workspace.config.scroll_direction
    local current_offset = state.get_viewport_offset(workspace.state)

    if not reveal_id then
        local clamped, clamp_err = viewport.clamp_offset(current_offset, viewport_size_for_direction(direction), layout.workspace_extent)
        if not clamped then
            return false, clamp_err
        end
        state.set_viewport_offset(workspace.state, clamped)
        layout.viewport_offset = clamped
        return true
    end

    local reveal_rect = layout.placements_by_id[reveal_id]
    if not reveal_rect then
        return false, "fit-scroller: window to reveal has no placement"
    end

    local result = viewport.reveal({
        direction = direction,
        viewport = geometry.rect(0, 0, 1, 1),
        workspace_extent = layout.workspace_extent,
        current_offset = current_offset,
        focused_rect = reveal_rect,
    })

    if not result.ok then
        return false, result.error
    end

    state.set_viewport_offset(workspace.state, result.offset)
    layout.viewport_offset = result.offset
    return true
end

local function prepare_areas(ctx, ordered_targets, effective_config, layout)
    local converted_by_id = {}
    for _, descriptor in ipairs(ordered_targets) do
        local rect = layout.placements_by_id[descriptor.id]
        if not rect then
            return nil, "fit-scroller: solver produced no placement for target " .. tostring(descriptor.id)
        end

        local shifted_rect = apply_viewport_offset(rect, effective_config.scroll_direction, layout.viewport_offset or 0)
        local converted, convert_err = convert_rect(ctx, shifted_rect)
        if not converted then
            return nil, convert_err
        end

        converted_by_id[descriptor.id] = converted
    end

    return converted_by_id
end

local function place_areas(ordered_targets, converted_by_id)
    for _, descriptor in ipairs(ordered_targets) do
        local target = descriptor.target
        if not target or type(target.place) ~= "function" then
            return false, "fit-scroller: target cannot be placed: " .. tostring(descriptor.id)
        end
    end

    for _, descriptor in ipairs(ordered_targets) do
        local target = descriptor.target
        local ok, place_err = pcall(function()
            target:place(converted_by_id[descriptor.id])
        end)
        if not ok then
            return false, "fit-scroller: target placement failed for " .. tostring(descriptor.id) .. ": " .. tostring(place_err)
        end
    end

    return true
end

local function ordered_descriptors_for_layout(workspace_state, descriptors, layout)
    local by_id = descriptors_by_id(descriptors)
    local ordered = {}
    local used = {}

    for _, id in ipairs(workspace_state.order or {}) do
        if by_id[id] and layout.placements_by_id[id] then
            table.insert(ordered, by_id[id])
            used[id] = true
        end
    end

    for _, descriptor in ipairs(descriptors or {}) do
        if not used[descriptor.id] then
            if not layout.placements_by_id[descriptor.id] then
                return nil, "fit-scroller: last layout is not compatible with target " .. tostring(descriptor.id)
            end
            table.insert(ordered, descriptor)
        end
    end

    return ordered
end

local function recover_with_last_layout(ctx, workspace_state, effective_config, original_err)
    local layout = workspace_state.last_layout
    if type(layout) ~= "table" or type(layout.placements_by_id) ~= "table" then
        return original_err
    end

    local descriptors = target_descriptors(ctx.targets)
    local ordered_targets, order_err = ordered_descriptors_for_layout(workspace_state, descriptors, layout)
    if not ordered_targets then
        return original_err .. " (recovery skipped: " .. order_err .. ")"
    end

    local recovery_layout = {
        placements_by_id = layout.placements_by_id,
        dimensions_by_id = layout.dimensions_by_id,
        workspace_extent = layout.workspace_extent,
        viewport_offset = state.get_viewport_offset(workspace_state),
    }

    local converted_by_id, convert_err = prepare_areas(ctx, ordered_targets, effective_config, recovery_layout)
    if not converted_by_id then
        return original_err .. " (recovery skipped: " .. convert_err .. ")"
    end

    local placed, place_err = place_areas(ordered_targets, converted_by_id)
    if not placed then
        return original_err .. " (recovery skipped: " .. place_err .. ")"
    end

    return original_err .. " (recovered with last valid layout)"
end

apply_viewport_offset = function(rect, direction, offset)
    local info = traversal.direction_info(direction)
    local visible = {
        x = rect.x,
        y = rect.y,
        w = rect.w,
        h = rect.h,
    }

    if info.scroll_axis == "x" then
        if info.scroll_sign == 1 then
            visible.x = visible.x - offset
        else
            visible.x = visible.x + offset + 1
        end
    elseif info.scroll_sign == 1 then
        visible.y = visible.y - offset
    else
        visible.y = visible.y + offset + 1
    end

    return visible
end

local function visible_rect(rect, direction, offset)
    return apply_viewport_offset(rect, direction, offset or 0)
end

function M.last_visible_id(workspace_state, effective_config)
    local layout = workspace_state.last_layout
    if type(layout) ~= "table" or type(layout.placements_by_id) ~= "table" then
        return nil
    end

    local viewport_rect = geometry.rect(0, 0, 1, 1)
    local offset = state.get_viewport_offset(workspace_state)
    local last_id = nil

    for _, id in ipairs(workspace_state.order or {}) do
        local rect = layout.placements_by_id[id]
        if rect then
            local shifted = visible_rect(rect, effective_config.scroll_direction, offset)
            if geometry.is_fully_visible(shifted, viewport_rect) then
                last_id = id
            end
        end
    end

    return last_id
end

local function should_solve(workspace)
    return workspace.sync.structural_changed
        or workspace.state.pending_layout_update
        or workspace.state.last_layout == nil
        or workspace.state.config_signature ~= config_signature(workspace.config)
end

local function reveal_target_id(workspace, did_solve)
    local inserted_ids = workspace.sync.inserted_ids or {}

    if inserted_ids[#inserted_ids] then
        return inserted_ids[#inserted_ids]
    end

    if did_solve or workspace.sync.focus_changed or workspace.state.pending_viewport_update then
        return workspace.state.focused_id
    end
end

local function focus_descriptor(descriptor)
    local target = descriptor and descriptor.target
    local window = descriptor and descriptor.window or target and target.window
    local address = window and window.address

    if type(address) ~= "string" or address == "" then
        return false, "fit-scroller: focus target has no Hyprland window address"
    end

    if not address:match("^address:") then
        address = "address:" .. address
    end

    if not hl or not hl.dsp or type(hl.dsp.focus) ~= "function" or type(hl.dispatch) ~= "function" then
        return false, "fit-scroller: Hyprland Lua focus dispatcher is unavailable"
    end

    local dispatcher_ok, dispatcher = pcall(function()
        return hl.dsp.focus({ window = address })
    end)
    if not dispatcher_ok or not dispatcher then
        return false, "fit-scroller: failed to create Hyprland focus dispatcher for " .. tostring(address)
    end

    local dispatch_ok, dispatch_err = pcall(function()
        return hl.dispatch(dispatcher)
    end)
    if not dispatch_ok then
        return false, "fit-scroller: Hyprland focus dispatch failed: " .. tostring(dispatch_err)
    end

    return true
end

function M.recalculate(ctx)
    if type(ctx) ~= "table" then
        return "fit-scroller: missing Hyprland layout context"
    end

    local current_state = state.get_workspace_state(workspace_key(ctx))
    local draft_state = state.clone_workspace_state(current_state)
    local workspace, err = workspace_context(ctx, draft_state)
    if not workspace then
        local effective_config = config.get_for_display(display_id(ctx))
        if effective_config then
            return recover_with_last_layout(ctx, current_state, effective_config, err)
        end
        return err
    end

    local ordered_targets = workspace.targets
    local n = #ordered_targets
    if n == 0 then
        state.update_last_layout(draft_state, {
            placements_by_id = {},
            dimensions_by_id = {},
            workspace_extent = 0,
        })
        draft_state.config_signature = config_signature(workspace.config)
        state.set_viewport_offset(draft_state, 0)
        draft_state.pending_layout_update = false
        draft_state.pending_viewport_update = false
        draft_state.pending_spatial_event = nil
        local valid_state, state_err = state.validate_workspace_state(draft_state, {})
        if not valid_state then
            return state_err
        end
        state.commit_workspace_state(current_state, draft_state)
        return
    end

    if ctx.area == nil then
        return "fit-scroller: missing Hyprland layout area"
    end

    local layout = workspace.state.last_layout
    local did_solve = should_solve(workspace)

    if did_solve then
        local result = solve_workspace(workspace)
        if not result.ok then
            return recover_with_last_layout(ctx, current_state, workspace.config, result.error)
        end
        layout = result.layout
    end

    local valid_layout, layout_err = validate_layout_output(layout, ordered_targets)
    if not valid_layout then
        return recover_with_last_layout(ctx, current_state, workspace.config, layout_err)
    end

    local viewport_ok, viewport_err = update_viewport_offset(workspace, layout, reveal_target_id(workspace, did_solve))
    if not viewport_ok then
        return recover_with_last_layout(ctx, current_state, workspace.config, viewport_err)
    end

    local converted_by_id, convert_err = prepare_areas(ctx, ordered_targets, workspace.config, layout)
    if not converted_by_id then
        return recover_with_last_layout(ctx, current_state, workspace.config, convert_err)
    end

    local placed, place_err = place_areas(ordered_targets, converted_by_id)
    if not placed then
        return recover_with_last_layout(ctx, current_state, workspace.config, place_err)
    end

    state.update_last_layout(draft_state, layout)
    draft_state.config_signature = config_signature(workspace.config)
    draft_state.pending_layout_update = false
    draft_state.pending_viewport_update = false
    draft_state.pending_spatial_event = nil
    local valid_state, state_err = state.validate_workspace_state(draft_state, descriptor_ids(ordered_targets))
    if not valid_state then
        return recover_with_last_layout(ctx, current_state, workspace.config, state_err)
    end
    state.commit_workspace_state(current_state, draft_state)
end

function M.layout_msg(ctx, msg)
    if type(ctx) ~= "table" then
        return "fit-scroller: missing Hyprland layout context"
    end

    local current_state = state.get_workspace_state(workspace_key(ctx))
    local draft_state = state.clone_workspace_state(current_state)
    local workspace, err = workspace_context(ctx, draft_state)
    if not workspace then
        return err
    end

    if type(msg) == "string" and msg:match("^%s*debug%s+targets%s*$") then
        return debug_targets(workspace.targets)
    end

    if type(msg) == "string" and msg:match("^%s*debug%s+config%s*$") then
        return debug_config(ctx)
    end

    local result = commands.execute(workspace.state, workspace.config, state, config, msg)
    if not result.ok then
        return result.error
    end

    if result.spatial_event then
        workspace.state.pending_spatial_event = result.spatial_event
    end

    if result.needs_layout_update then
        local validation = solve_workspace(workspace)
        if not validation.ok then
            return validation.error
        end

        local layout = validation.layout
        local valid_layout, layout_err = validate_layout_output(layout, workspace.targets)
        if not valid_layout then
            return layout_err
        end

        local viewport_ok, viewport_err = update_viewport_offset(workspace, layout, reveal_target_id(workspace, true))
        if not viewport_ok then
            return viewport_err
        end

        local converted_by_id, convert_err = prepare_areas(ctx, workspace.targets, workspace.config, layout)
        if not converted_by_id then
            return convert_err
        end

        local placed, place_err = place_areas(workspace.targets, converted_by_id)
        if not placed then
            return place_err
        end

        state.update_last_layout(draft_state, layout)
        draft_state.config_signature = config_signature(workspace.config)
        draft_state.pending_layout_update = false
        draft_state.pending_viewport_update = false
        draft_state.pending_spatial_event = nil
        local valid_state, state_err = state.validate_workspace_state(draft_state, descriptor_ids(workspace.targets))
        if not valid_state then
            return state_err
        end
        state.commit_workspace_state(current_state, draft_state)
        return true
    end

    if result.focus_target_id then
        local descriptor = descriptors_by_id(workspace.targets)[result.focus_target_id]
        if not descriptor then
            return "fit-scroller: focus target is not present: " .. tostring(result.focus_target_id)
        end

        local focused, focus_err = focus_descriptor(descriptor)
        if not focused then
            return focus_err
        end
    end

    if result.needs_viewport_update then
        draft_state.pending_viewport_update = true
    end

    local valid_state, state_err = state.validate_workspace_state(draft_state, descriptor_ids(workspace.targets))
    if not valid_state then
        return state_err
    end
    state.commit_workspace_state(current_state, draft_state)
    return true
end

return M
