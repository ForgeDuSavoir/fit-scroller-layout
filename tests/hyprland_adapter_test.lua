local support = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "tests") .. "/support.lua")

local assert_eq = support.assert_eq
local assert_true = support.assert_true

local function load_adapter()
    _G.hl = { dsp = {}, dispatch = function() return true end }
    return support.load_layout("hyprland_adapter")
end

local function placed_target(id, workspace_id, active)
    return {
        window = {
            stable_id = id,
            active = active,
            address = "0x" .. id,
            workspace = { id = workspace_id },
        },
        place = function(self, rect)
            self.last_rect = { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
        end,
    }
end

local function workspace_state(adapter, id)
    return adapter._state.get_workspace_state("workspace:" .. id)
end

local function test_adapter_no_partial_placement()
    local adapter = load_adapter()
    local placed = 0
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = {
            {
                window = {
                    stable_id = "A",
                    active = true,
                    address = "0xA",
                    workspace = { id = "adapter-no-partial" },
                },
                place = function()
                    placed = placed + 1
                end,
            },
            {
                window = {
                    stable_id = "B",
                    active = false,
                    address = "0xB",
                    workspace = { id = "adapter-no-partial" },
                },
            },
        },
    }

    local err = adapter.recalculate(ctx)
    assert_true(err and err:match("cannot be placed"), "missing place returns error")
    assert_eq(placed, 0, "no partial placement")
end

local function test_adapter_focus_only_keeps_dimensions()
    local adapter = load_adapter()
    local targets = {
        placed_target("A", "adapter-focus-only", true),
        placed_target("B", "adapter-focus-only", false),
        placed_target("C", "adapter-focus-only", false),
        placed_target("D", "adapter-focus-only", false),
        placed_target("E", "adapter-focus-only", false),
    }
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = targets,
    }

    assert_eq(adapter.recalculate(ctx), nil, "initial adapter recalc")
    local before = {}
    for i, current in ipairs(targets) do
        before[i] = current.last_rect.w .. "x" .. current.last_rect.h
    end

    targets[1].window.active = false
    targets[5].window.active = true
    assert_eq(adapter.recalculate(ctx), nil, "focus-only adapter recalc")

    for i, current in ipairs(targets) do
        local after = current.last_rect.w .. "x" .. current.last_rect.h
        assert_eq(after, before[i], "focus-only keeps dimensions " .. tostring(i))
    end
end

local function test_adapter_workspace_switch_keeps_forced_dimensions()
    local adapter = load_adapter()
    local workspace_one_targets = {
        placed_target("A", "workspace-one", true),
        placed_target("B", "workspace-one", false),
    }
    local workspace_two_targets = {
        placed_target("C", "workspace-two", true),
        placed_target("D", "workspace-two", false),
    }

    local ctx_one = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = workspace_one_targets,
    }
    local ctx_two = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = workspace_two_targets,
    }

    assert_eq(adapter.recalculate(ctx_one), nil, "initial workspace one recalc")
    assert_eq(workspace_one_targets[1].last_rect.w, 500, "auto width before toggle")
    assert_eq(adapter.layout_msg(ctx_one, "toggle dimension"), true, "toggle dimension")
    assert_eq(adapter.recalculate(ctx_one), nil, "forced workspace one recalc")
    assert_eq(workspace_one_targets[1].last_rect.w, 1000, "forced width before switch")
    assert_eq(workspace_one_targets[1].last_rect.h, 1000, "forced height before switch")

    assert_eq(adapter.recalculate(ctx_two), nil, "workspace two recalc")
    assert_eq(adapter.recalculate(ctx_one), nil, "workspace one return recalc")

    assert_eq(workspace_one_targets[1].last_rect.w, 1000, "forced width survives workspace switch")
    assert_eq(workspace_one_targets[1].last_rect.h, 1000, "forced height survives workspace switch")
end

local function test_adapter_display_id_uses_window_monitor_when_ctx_has_no_monitor()
    local adapter = load_adapter()
    local ctx = {
        targets = {
            {
                window = {
                    monitor = { name = "HDMI-A-1" },
                },
            },
        },
    }

    assert_eq(adapter._display_id(ctx), "HDMI-A-1", "display id from window monitor")
end

local function test_adapter_display_id_prefers_configured_window_monitor_over_ctx_monitor()
    local adapter = load_adapter()
    adapter._config.raw_config.displays["HDMI-A-1"] = {
        allowed_dimensions = { { 1.0, 1.0 } },
        scroll_direction = "down",
    }

    local ctx = {
        monitor = function() end,
        targets = {
            {
                window = {
                    monitor = { name = "HDMI-A-1" },
                },
            },
        },
    }

    assert_eq(adapter._display_id(ctx), "HDMI-A-1", "configured window monitor wins")
end

local function test_adapter_display_id_uses_active_workspace_monitor_when_ctx_has_no_targets()
    _G.hl = {
        dsp = {},
        dispatch = function() return true end,
        get_active_workspace = function()
            return {
                monitor = { name = "HDMI-A-1" },
            }
        end,
    }

    local adapter = support.load_layout("hyprland_adapter")
    adapter._config.raw_config.displays["HDMI-A-1"] = {
        allowed_dimensions = { { 1.0, 1.0 } },
        scroll_direction = "down",
    }

    assert_eq(adapter._display_id({}), "HDMI-A-1", "display id from active workspace monitor")
end

local function test_adapter_display_id_uses_area_monitor_when_ctx_has_no_targets()
    local monitor = setmetatable({}, {
        __index = function(_, key)
            if key == "name" then
                return "HDMI-A-1"
            end
        end,
    })

    _G.hl = {
        dsp = {},
        dispatch = function() return true end,
        get_monitor_at = function(point)
            if point.x == 1500 and point.y == 500 then
                return monitor
            end
        end,
    }

    local adapter = support.load_layout("hyprland_adapter")
    adapter._config.raw_config.displays["HDMI-A-1"] = {
        allowed_dimensions = { { 1.0, 1.0 } },
        scroll_direction = "down",
    }

    assert_eq(adapter._display_id({
        area = { x = 1000, y = 0, w = 1000, h = 1000 },
    }), "HDMI-A-1", "display id from area monitor")
end

local function test_adapter_resolves_layout_again_when_display_config_changes()
    local adapter = load_adapter()
    adapter._config.raw_config.displays["HDMI-A-1"] = {
        allowed_dimensions = {
            { 1.0, 1.0 },
            { 1.0, 0.5 },
        },
        scroll_direction = "down",
    }

    local targets = {
        placed_target("A", "display-config-change", true),
        placed_target("B", "display-config-change", false),
    }
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = targets,
    }

    assert_eq(adapter.recalculate(ctx), nil, "initial default display recalc")
    assert_eq(targets[2].last_rect.x, 500, "default display places second target horizontally")

    ctx.monitor.name = "HDMI-A-1"
    assert_eq(adapter.recalculate(ctx), nil, "override display recalc")
    assert_eq(targets[2].last_rect.x, 0, "override display recalculates x")
    assert_eq(targets[2].last_rect.y, 500, "override display places second target vertically")
end

local function test_adapter_uses_spatial_solver_for_spatial_priority()
    local adapter = load_adapter()
    adapter._config.raw_config.default.placement_priority = "spatial"

    local targets = {
        placed_target("A", "spatial-adapter", true),
        placed_target("B", "spatial-adapter", false),
    }
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = targets,
    }

    assert_eq(adapter.recalculate(ctx), nil, "spatial adapter recalc")
    assert_eq(targets[1].last_rect.w, 1000, "spatial first target keeps largest width")
    assert_eq(targets[1].last_rect.h, 1000, "spatial first target keeps largest height")
    assert_eq(targets[2].last_rect.w, 1000, "spatial second target keeps largest width")
    assert_eq(targets[2].last_rect.h, 1000, "spatial second target keeps largest height")
    assert_eq(targets[1].last_rect.x, -1000, "spatial reveal shifts first target off viewport")
    assert_eq(targets[2].last_rect.x, 0, "spatial reveal shows newest target")
end

local function test_adapter_spatial_window_addition_splits_existing_window()
    local adapter = load_adapter()
    adapter._config.raw_config.default.placement_priority = "spatial"

    local target_a = placed_target("A", "spatial-window-addition", true)
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = { target_a },
    }

    assert_eq(adapter.recalculate(ctx), nil, "initial spatial recalc")
    assert_eq(target_a.last_rect.x, 0, "initial A x")
    assert_eq(target_a.last_rect.w, 1000, "initial A width")

    local target_b = placed_target("B", "spatial-window-addition", true)
    target_a.window.active = false
    ctx.targets = { target_a, target_b }

    assert_eq(adapter.recalculate(ctx), nil, "spatial addition recalc")
    assert_eq(target_a.last_rect.x, 0, "split A x")
    assert_eq(target_a.last_rect.w, 500, "split A width")
    assert_eq(target_a.last_rect.h, 1000, "split A height")
    assert_eq(target_b.last_rect.x, 500, "split B x")
    assert_eq(target_b.last_rect.w, 500, "split B width")
    assert_eq(target_b.last_rect.h, 1000, "split B height")
end

local function test_adapter_spatial_negative_scroll_initial_window_is_visible()
    for _, direction in ipairs({ "left", "up" }) do
        local adapter = load_adapter()
        adapter._config.raw_config.default.placement_priority = "spatial"
        adapter._config.raw_config.default.scroll_direction = direction

        local target_a = placed_target("A", "spatial-negative-initial-" .. direction, true)
        local ctx = {
            area = { x = 0, y = 0, w = 1000, h = 1000 },
            monitor = { name = "default" },
            targets = { target_a },
        }

        assert_eq(adapter.recalculate(ctx), nil, "spatial initial recalc " .. direction)
        assert_eq(target_a.last_rect.x, 0, "initial visible x " .. direction)
        assert_eq(target_a.last_rect.y, 0, "initial visible y " .. direction)
        assert_eq(target_a.last_rect.w, 1000, "initial visible width " .. direction)
        assert_eq(target_a.last_rect.h, 1000, "initial visible height " .. direction)
    end
end

local function test_adapter_spatial_window_removal_preserves_remaining_window()
    local adapter = load_adapter()
    adapter._config.raw_config.default.placement_priority = "spatial"

    local target_a = placed_target("A", "spatial-window-removal", true)
    local target_b = placed_target("B", "spatial-window-removal", false)
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = { target_a },
    }

    assert_eq(adapter.recalculate(ctx), nil, "initial spatial recalc")
    ctx.targets = { target_a, target_b }
    assert_eq(adapter.recalculate(ctx), nil, "spatial addition recalc")
    assert_eq(target_a.last_rect.w, 500, "A split width before removal")
    assert_eq(target_b.last_rect.x, 500, "B split x before removal")

    ctx.targets = { target_a }
    assert_eq(adapter.recalculate(ctx), nil, "spatial removal recalc")
    assert_eq(target_a.last_rect.x, 0, "A preserved x")
    assert_eq(target_a.last_rect.w, 500, "A preserved width")
    assert_eq(target_a.last_rect.h, 1000, "A preserved height")
end

local function test_adapter_failed_spatial_move_preserves_state()
    local adapter = load_adapter()
    adapter._config.raw_config.default.placement_priority = "spatial"
    adapter._config.raw_config.default.allowed_dimensions = { { 0.5, 1.0 } }

    local target_a = placed_target("A", "spatial-failed-move", true)
    local target_b = placed_target("B", "spatial-failed-move", false)
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = { target_a, target_b },
    }

    assert_eq(adapter.recalculate(ctx), nil, "initial spatial recalc")
    local ws = workspace_state(adapter, "spatial-failed-move")
    local before_a_x = ws.last_layout.placements_by_id.A.x
    local before_b_x = ws.last_layout.placements_by_id.B.x

    target_b.place = nil
    local err = adapter.layout_msg(ctx, "move right")
    assert_true(err and err:match("cannot be placed"), "failed move returns placement error")

    assert_eq(ws.last_layout.placements_by_id.A.x, before_a_x, "failed move preserves A placement")
    assert_eq(ws.last_layout.placements_by_id.B.x, before_b_x, "failed move preserves B placement")
    assert_eq(ws.pending_spatial_event, nil, "failed move does not commit pending event")
end

local function test_adapter_failed_forced_dimension_preserves_state()
    local adapter = load_adapter()
    adapter._config.raw_config.default.placement_priority = "spatial"

    local target_a = placed_target("A", "spatial-failed-forced", true)
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = { target_a },
    }

    assert_eq(adapter.recalculate(ctx), nil, "initial spatial recalc")
    target_a.place = nil
    local err = adapter.layout_msg(ctx, "toggle dimension")
    assert_true(err and err:match("cannot be placed"), "failed forced dimension returns placement error")

    local ws = workspace_state(adapter, "spatial-failed-forced")
    assert_eq(ws.dimension_mode_by_id.A, nil, "failed forced dimension preserves auto mode")
end

local function test_adapter_failed_return_to_auto_preserves_forced_state()
    local adapter = load_adapter()
    adapter._config.raw_config.default.placement_priority = "spatial"
    adapter._config.raw_config.default.allowed_dimensions = { { 1.0, 1.0 } }

    local target_a = placed_target("A", "spatial-failed-auto", true)
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = { target_a },
    }

    assert_eq(adapter.recalculate(ctx), nil, "initial spatial recalc")
    assert_eq(adapter.layout_msg(ctx, "toggle dimension"), true, "force dimension succeeds")

    local ws = workspace_state(adapter, "spatial-failed-auto")
    assert_eq(ws.dimension_mode_by_id.A.kind, "forced", "forced state committed")

    target_a.place = nil
    local err = adapter.layout_msg(ctx, "toggle dimension")
    assert_true(err and err:match("cannot be placed"), "failed auto return returns placement error")
    assert_eq(ws.dimension_mode_by_id.A.kind, "forced", "failed auto return preserves forced mode")
end

local function test_adapter_failed_target_sync_preserves_state()
    local adapter = load_adapter()

    local target_a = placed_target("A", "sync-preserve", true)
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = { target_a },
    }

    assert_eq(adapter.recalculate(ctx), nil, "initial recalc")
    local ws = workspace_state(adapter, "sync-preserve")
    assert_eq(table.concat(ws.order, " "), "A", "initial order")

    local target_b = placed_target("B", "sync-preserve", true)
    ctx.targets = { target_a, target_b }
    local err = adapter.recalculate(ctx)
    assert_true(err and err:match("multiple active"), "target sync validation fails")
    assert_eq(table.concat(ws.order, " "), "A", "failed sync preserves order")
    assert_eq(ws.focused_id, "A", "failed sync preserves focus")
end

local function test_adapter_failed_rectangle_conversion_preserves_layout_and_viewport()
    local adapter = load_adapter()
    adapter._config.raw_config.default.placement_priority = "spatial"

    local target_a = placed_target("A", "convert-preserve", true)
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = { target_a },
    }

    assert_eq(adapter.recalculate(ctx), nil, "initial recalc")
    local ws = workspace_state(adapter, "convert-preserve")
    local before_x = ws.last_layout.placements_by_id.A.x
    local before_offset = ws.viewport_offset

    ctx.area = { x = 0, y = 0, w = "bad", h = 1000 }
    local err = adapter.recalculate(ctx)
    assert_true(err and err:match("does not expose numeric"), "conversion fails")
    assert_eq(ws.last_layout.placements_by_id.A.x, before_x, "conversion failure preserves layout")
    assert_eq(ws.viewport_offset, before_offset, "conversion failure preserves viewport")
end

local function test_adapter_rejects_incomplete_layout_before_placement()
    local adapter = load_adapter()
    adapter._config.raw_config.default.placement_priority = "spatial"
    adapter._config.raw_config.default.allowed_dimensions = { { 1.0, 1.0 } }

    local target_a = placed_target("A", "incomplete-layout", true)
    local target_b = placed_target("B", "incomplete-layout", false)
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = { target_a, target_b },
    }
    local cfg = assert(adapter._config.get_for_display("default"))
    local ws = workspace_state(adapter, "incomplete-layout")
    ws.order = { "A", "B" }
    ws.focused_id = "A"
    ws.viewport_offset = 0
    ws.config_signature = adapter._config_signature(cfg)
    ws.last_layout = {
        placements_by_id = {
            A = { x = 0, y = 0, w = 1, h = 1 },
        },
        dimensions_by_id = {
            A = { key = "1.0x1.0", w = 1, h = 1 },
        },
        workspace_extent = 1,
    }

    local placed = 0
    target_a.place = function() placed = placed + 1 end
    target_b.place = function() placed = placed + 1 end

    local err = adapter.recalculate(ctx)
    assert_true(err and err:match("no placement for target B"), "incomplete layout is rejected")
    assert_eq(placed, 0, "incomplete layout is rejected before placement")
    assert_eq(ws.last_layout.placements_by_id.B, nil, "incomplete layout failure preserves state")
end

local function test_adapter_successful_structural_command_commits_once()
    local adapter = load_adapter()
    adapter._config.raw_config.default.placement_priority = "spatial"
    adapter._config.raw_config.default.allowed_dimensions = { { 1.0, 1.0 } }

    local target_a = placed_target("A", "commit-once", true)
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        monitor = { name = "default" },
        targets = { target_a },
    }

    assert_eq(adapter.recalculate(ctx), nil, "initial recalc")

    local commits = 0
    local original_commit = adapter._state.commit_workspace_state
    adapter._state.commit_workspace_state = function(...)
        commits = commits + 1
        return original_commit(...)
    end

    local ok = adapter.layout_msg(ctx, "toggle dimension")
    adapter._state.commit_workspace_state = original_commit

    assert_eq(ok, true, "structural command succeeds")
    assert_eq(commits, 1, "structural command commits once")
end

return {
    name = "hyprland_adapter",
    tests = {
        test_adapter_no_partial_placement,
        test_adapter_focus_only_keeps_dimensions,
        test_adapter_workspace_switch_keeps_forced_dimensions,
        test_adapter_display_id_uses_window_monitor_when_ctx_has_no_monitor,
        test_adapter_display_id_prefers_configured_window_monitor_over_ctx_monitor,
        test_adapter_display_id_uses_active_workspace_monitor_when_ctx_has_no_targets,
        test_adapter_display_id_uses_area_monitor_when_ctx_has_no_targets,
        test_adapter_resolves_layout_again_when_display_config_changes,
        test_adapter_uses_spatial_solver_for_spatial_priority,
        test_adapter_spatial_window_addition_splits_existing_window,
        test_adapter_spatial_negative_scroll_initial_window_is_visible,
        test_adapter_spatial_window_removal_preserves_remaining_window,
        test_adapter_failed_spatial_move_preserves_state,
        test_adapter_failed_forced_dimension_preserves_state,
        test_adapter_failed_return_to_auto_preserves_forced_state,
        test_adapter_failed_target_sync_preserves_state,
        test_adapter_failed_rectangle_conversion_preserves_layout_and_viewport,
        test_adapter_rejects_incomplete_layout_before_placement,
        test_adapter_successful_structural_command_commits_once,
    },
}
