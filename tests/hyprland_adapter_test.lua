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
    assert_eq(targets[1].last_rect.w, 500, "spatial first target fits before scroll")
    assert_eq(targets[1].last_rect.h, 1000, "spatial first target keeps largest height")
    assert_eq(targets[2].last_rect.w, 500, "spatial second target fits before scroll")
    assert_eq(targets[2].last_rect.h, 1000, "spatial second target keeps largest height")
    assert_eq(targets[1].last_rect.x, 0, "spatial first target remains visible")
    assert_eq(targets[2].last_rect.x, 500, "spatial second target remains visible")
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

local function test_adapter_spatial_window_removal_expands_remaining_auto_window_without_scroll()
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
    assert_eq(target_a.last_rect.y, 0, "A preserved y")
    assert_eq(target_a.last_rect.w, 1000, "A expanded width")
    assert_eq(target_a.last_rect.h, 1000, "A expanded height")
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

local function test_adapter_centers_non_filling_layout()
    local adapter = load_adapter()
    adapter._config.raw_config.default.allowed_dimensions = { { 0.5, 0.5 } }
    adapter._config.raw_config.default.center_windows = true

    local target = placed_target("A", "center-non-filling", true)
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 800 },
        monitor = { name = "default" },
        targets = { target },
    }

    assert_eq(adapter.recalculate(ctx), nil, "centered recalc")
    assert_eq(target.last_rect.x, 250, "centered x")
    assert_eq(target.last_rect.y, 200, "centered y")
    assert_eq(target.last_rect.w, 500, "centered width")
    assert_eq(target.last_rect.h, 400, "centered height")

    local ws = workspace_state(adapter, "center-non-filling")
    assert_eq(ws.last_layout.placements_by_id.A.x, 0, "stored layout x remains uncentered")
    assert_eq(ws.last_layout.placements_by_id.A.y, 0, "stored layout y remains uncentered")
end

local function test_adapter_center_windows_false_keeps_current_placement()
    local adapter = load_adapter()
    adapter._config.raw_config.default.allowed_dimensions = { { 0.5, 0.5 } }
    adapter._config.raw_config.default.center_windows = false

    local target = placed_target("A", "center-disabled", true)
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 800 },
        monitor = { name = "default" },
        targets = { target },
    }

    assert_eq(adapter.recalculate(ctx), nil, "uncentered recalc")
    assert_eq(target.last_rect.x, 0, "uncentered x")
    assert_eq(target.last_rect.y, 0, "uncentered y")
    assert_eq(target.last_rect.w, 500, "uncentered width")
    assert_eq(target.last_rect.h, 400, "uncentered height")
end

local function test_adapter_centering_noops_when_layout_fills_viewport()
    local adapter = load_adapter()
    adapter._config.raw_config.default.allowed_dimensions = { { 1.0, 1.0 } }
    adapter._config.raw_config.default.center_windows = true

    local target = placed_target("A", "center-full", true)
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 800 },
        monitor = { name = "default" },
        targets = { target },
    }

    assert_eq(adapter.recalculate(ctx), nil, "full recalc")
    assert_eq(target.last_rect.x, 0, "full x")
    assert_eq(target.last_rect.y, 0, "full y")
    assert_eq(target.last_rect.w, 1000, "full width")
    assert_eq(target.last_rect.h, 800, "full height")
end

local function test_adapter_center_windows_is_not_solver_signature()
    local adapter = load_adapter()
    local centered = assert(adapter._config.get_for_display("default", {
        default = {
            allowed_dimensions = { { 0.5, 0.5 } },
            scroll_direction = "right",
            center_windows = true,
        },
    }))
    local uncentered = assert(adapter._config.get_for_display("default", {
        default = {
            allowed_dimensions = { { 0.5, 0.5 } },
            scroll_direction = "right",
            center_windows = false,
        },
    }))

    assert_eq(adapter._config_signature(centered), adapter._config_signature(uncentered), "centering is not solver signature")
end

local function drag_fixture(priority)
    local adapter = load_adapter()
    adapter._config.raw_config.default.placement_priority = priority or "order"
    local a, b = placed_target("A", "drag", true), placed_target("B", "drag", false)
    local ws = a.window.workspace
    ws.tiled_layout = "lua:fit-scroller"
    for _, target in ipairs({ a, b }) do
        target.window.layout = { name = ws.tiled_layout }
        target.window.floating = false
    end
    hl.get_monitor_at_cursor = function() return { active_workspace = ws } end
    hl.get_workspace_windows = function() return { a.window, b.window } end
    local ctx = { targets = { a, b }, area = { x = 0, y = 0, w = 1000, h = 1000 } }
    assert_eq(adapter.recalculate(ctx), nil, "initial drag layout")
    return adapter, ctx, a, b
end

local function test_drag_captures_non_focused_target_before_sync()
    local adapter, ctx, a, b = drag_fixture()
    local ws = workspace_state(adapter, "drag")
    adapter._state.set_dimension_mode(ws, "B", { kind = "forced", key = "0.5x1.0" })
    adapter.drag_press()
    ctx.targets = { a }
    assert_eq(adapter.recalculate(ctx), nil, "removal callback")
    assert_eq(ws.dimension_mode_by_id.B, nil, "ordinary removal still clears mode")
    hl.get_cursor_pos = function() return { x = 300, y = 225 } end
    ctx.targets = { a, b }
    local effective = assert(adapter._config.get_for_display("default"))
    local drop = assert(adapter._observe_drag(ctx, "workspace:drag", effective))
    assert_eq(drop.id, "B", "drag identity is not focus")
    assert_eq(drop.index, 2, "original slot")
    assert_eq(drop.previous_id, "A", "original neighbor")
    assert_eq(drop.mode.key, "0.5x1.0", "original forced mode")
    assert_eq(drop.point.x, 300, "drop cursor x")
    assert_eq(drop.point.y, 225, "drop cursor y")
    local slot = adapter._select_drag_slot("workspace:drag", { { id = "A" }, { id = "B" } }, drop)
    assert_eq(slot.anchor_id, "A", "uses last rendered surviving tile")
    assert_eq(slot.index, 1, "leading half of last visible tile inserts before")
    assert_eq(adapter.recalculate(ctx), nil, "apply drag drop")
    assert_eq(table.concat(ws.order, ","), "B,A", "drop reorders windows")
    assert_eq(ws.dimension_mode_by_id.B.key, "0.5x1.0", "forced mode restored")
    assert_eq(ws.focused_id, "A", "drop does not change focus")
    assert_eq(adapter._observe_drag(ctx, "workspace:drag", effective), nil, "committed drop is one shot")

    ctx.targets = { a, b, placed_target("C", "drag", false) }
    adapter._config.raw_config.default.insert_mode = "last"
    assert_eq(adapter.recalculate(ctx), nil, "normal insertion following drop")
    assert_eq(table.concat(ws.order, ","), "B,A,C", "normal insertion ignores the old drop")
end

local function test_drag_can_move_first_tile_to_last()
    local adapter, ctx, a, b = drag_fixture()
    adapter.drag_press()
    ctx.targets = { b }
    assert_eq(adapter.recalculate(ctx), nil, "detach first tile")
    hl.get_cursor_pos = function() return { x = 750, y = 500 } end
    ctx.targets = { a, b }
    assert_eq(adapter.recalculate(ctx), nil, "drop on last tile trailing half")
    assert_eq(table.concat(workspace_state(adapter, "drag").order, ","), "B,A", "first tile moves to last")
end

local function test_drag_retries_failed_placement_with_original_point()
    local adapter, ctx, a, b = drag_fixture()
    local ws = workspace_state(adapter, "drag")
    adapter.drag_press()
    hl.get_cursor_pos = function() return { x = 250, y = 500 } end
    ctx.targets = { a }
    assert_eq(adapter.recalculate(ctx), nil, "detach dragged tile")
    ctx.targets = { a, b }
    local place = b.place
    b.place = function() error("test placement failure") end
    local err = adapter.recalculate(ctx)
    assert_true(err and err:match("test placement failure"), "drop placement failure reported")
    assert_eq(table.concat(ws.order, ","), "A", "failed drop does not commit order")
    b.place = place
    hl.get_cursor_pos = function() return { x = 1100, y = 500 } end
    assert_eq(adapter.recalculate(ctx), nil, "retry detached target before cleanup")
    assert_eq(table.concat(ws.order, ","), "B,A", "retry uses original drop point")
end

local function test_drag_ignores_canceled_and_spatial_sessions()
    for _, kind in ipairs({ "release", "closed", "cross-workspace", "spatial", "expired", "unrelated", "floating" }) do
        local adapter, ctx, a, b = drag_fixture(kind == "spatial" and "spatial" or "order")
        if kind == "floating" then b.window.floating = true end
        adapter.drag_press()
        ctx.targets = { a }
        assert_eq(adapter.recalculate(ctx), nil, "removal callback: " .. kind)
        if kind == "release" then
            adapter.drag_release()
        elseif kind == "closed" then
            adapter.drag_window_departed(b.window)
        elseif kind == "cross-workspace" then
            hl.get_monitor_at_cursor = function() return { active_workspace = { id = "other" } } end
        elseif kind == "unrelated" then
            ctx.targets = { a, placed_target("C", "drag", false) }
            assert_eq(adapter.recalculate(ctx), nil, "unrelated insertion cancels drop")
        end
        b.window.floating = false
        ctx.targets = { a, b }
        local effective = assert(adapter._config.get_for_display("default"))
        local real_time = os.time
        if kind == "expired" then os.time = function() return real_time() + 31 end end
        local ok, drop = pcall(adapter._observe_drag, ctx, "workspace:drag", effective)
        os.time = real_time
        assert_true(ok, tostring(drop))
        assert_eq(drop, nil, "no tracked drop: " .. kind)
    end
end

local function test_stationary_and_sole_tile_drags_keep_original_slot()
    for _, sole in ipairs({ false, true }) do
        local adapter, ctx, a, b = drag_fixture()
        local ws = workspace_state(adapter, "drag")
        if sole then
            ctx.targets = { b }
            hl.get_workspace_windows = function() return { b.window } end
            assert_eq(adapter.recalculate(ctx), nil, "prepare sole tile")
        end
        adapter._state.set_dimension_mode(ws, "B", { kind = "forced", key = "0.5x1.0" })
        hl.get_cursor_pos = function() return { x = 250, y = 500 } end
        adapter.drag_press()
        ctx.targets = sole and {} or { a }
        assert_eq(adapter.recalculate(ctx), nil, "detach tile")
        ctx.targets = sole and { b } or { a, b }
        assert_eq(adapter.recalculate(ctx), nil, "return tile")
        assert_eq(table.concat(ws.order, ","), sole and "B" or "A,B", "original slot retained")
        assert_eq(ws.dimension_mode_by_id.B.key, "0.5x1.0", "original forced mode retained")
    end
end

return {
    name = "hyprland_adapter",
    tests = {
        test_drag_captures_non_focused_target_before_sync,
        test_drag_can_move_first_tile_to_last,
        test_drag_retries_failed_placement_with_original_point,
        test_drag_ignores_canceled_and_spatial_sessions,
        test_stationary_and_sole_tile_drags_keep_original_slot,
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
        test_adapter_spatial_window_removal_expands_remaining_auto_window_without_scroll,
        test_adapter_failed_spatial_move_preserves_state,
        test_adapter_failed_forced_dimension_preserves_state,
        test_adapter_failed_return_to_auto_preserves_forced_state,
        test_adapter_failed_target_sync_preserves_state,
        test_adapter_failed_rectangle_conversion_preserves_layout_and_viewport,
        test_adapter_rejects_incomplete_layout_before_placement,
        test_adapter_successful_structural_command_commits_once,
        test_adapter_centers_non_filling_layout,
        test_adapter_center_windows_false_keeps_current_placement,
        test_adapter_centering_noops_when_layout_fills_viewport,
        test_adapter_center_windows_is_not_solver_signature,
    },
}
