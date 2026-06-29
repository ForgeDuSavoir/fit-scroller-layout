local support = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "tests") .. "/support.lua")

local assert_eq = support.assert_eq
local assert_true = support.assert_true

local config = support.load_layout("config")
local state = support.load_layout("state")
local target_sync = support.load_layout("target_sync")
local commands = support.load_layout("commands")
local geometry = support.load_layout("geometry")
local traversal = support.load_layout("traversal")
local solver = support.load_layout("solver")
local viewport = support.load_layout("viewport")

solver.set_dependencies({ geometry = geometry, traversal = traversal })
viewport.set_dependencies({ traversal = traversal })

local function test_config_defaults_and_validation()
    local cfg = assert(config.get_for_display("default", {
        default = {
            allowed_dimensions = { { 1, 1 } },
            scroll_direction = "right",
        },
    }))
    assert_eq(cfg.insert_mode, "view", "insert default")
    assert_eq(cfg.placement_priority, "order", "placement priority default")

    local invalid, err = config.get_for_display("default", {
        default = {
            allowed_dimensions = { { 1, 1 } },
            scroll_direction = "right",
            insert_mode = "focus",
        },
    })
    assert_eq(invalid, nil, "invalid insert mode rejected")
    assert_true(err:match("insert_mode"), "insert mode error message")
end

local function test_config_placement_priority()
    local order_cfg = assert(config.get_for_display("default", {
        default = {
            allowed_dimensions = { { 1, 1 } },
            scroll_direction = "right",
            placement_priority = "order",
        },
    }))
    assert_eq(order_cfg.placement_priority, "order", "order placement priority")

    local spatial_cfg = assert(config.get_for_display("default", {
        default = {
            allowed_dimensions = { { 1, 1 } },
            scroll_direction = "right",
            placement_priority = "spatial",
            insert_mode = "before_focused",
        },
    }))
    assert_eq(spatial_cfg.placement_priority, "spatial", "spatial placement priority")
    assert_eq(spatial_cfg.insert_mode, "before_focused", "spatial still validates and exposes insert mode")

    local display_cfg = assert(config.get_for_display("DP-1", {
        default = {
            allowed_dimensions = { { 1, 1 } },
            scroll_direction = "right",
            placement_priority = "order",
        },
        displays = {
            ["DP-1"] = {
                placement_priority = "spatial",
            },
        },
    }))
    assert_eq(display_cfg.placement_priority, "spatial", "display placement priority override")

    local invalid, err = config.get_for_display("default", {
        default = {
            allowed_dimensions = { { 1, 1 } },
            scroll_direction = "right",
            placement_priority = "geometry",
        },
    })
    assert_eq(invalid, nil, "invalid placement priority rejected")
    assert_true(err:match("placement_priority"), "placement priority error message")
end

local function test_target_sync_validation_is_transactional()
    state._reset()
    local ws = state.get_workspace_state("sync")
    ws.order = { "A", "B" }
    ws.dimension_mode_by_id.B = { kind = "forced", key = "0.5x1.0" }

    local ordered, err = target_sync.sync(ws, {
        { id = "A", active = true },
        { id = "A", active = false },
    }, state, { insert_mode = "last" })

    assert_eq(ordered, nil, "duplicate sync rejected")
    assert_true(err:match("duplicate"), "duplicate sync error")
    assert_eq(table.concat(ws.order, " "), "A B", "sync failure keeps order")
    assert_true(ws.dimension_mode_by_id.B ~= nil, "sync failure keeps dimensions")
end

local function test_insert_modes()
    local expected = {
        last = "A B C D E",
        first = "D E A B C",
        view = "A B D E C",
        after_focused = "A B D E C",
        before_focused = "A D E B C",
    }

    for mode, order in pairs(expected) do
        state._reset()
        local ws = state.get_workspace_state("insert-" .. mode)
        ws.order = { "A", "B", "C" }
        ws.focused_id = "B"
        target_sync.sync(ws, {
            { id = "A" },
            { id = "B" },
            { id = "C" },
            { id = "D" },
            { id = "E" },
        }, state, { insert_mode = mode, last_visible_id = "B" })
        assert_eq(table.concat(ws.order, " "), order, "insert " .. mode)
    end
end

local function test_spatial_target_sync_ignores_insert_mode()
    local modes = {
        "last",
        "first",
        "view",
        "after_focused",
        "before_focused",
    }

    for _, mode in ipairs(modes) do
        state._reset()
        local ws = state.get_workspace_state("spatial-insert-" .. mode)
        ws.order = { "A", "B", "C" }
        ws.focused_id = "B"

        local ordered, result = target_sync.sync(ws, {
            { id = "A" },
            { id = "B" },
            { id = "C" },
            { id = "D" },
            { id = "E" },
        }, state, {
            placement_priority = "spatial",
            insert_mode = mode,
            last_visible_id = "B",
        })

        assert_true(ordered ~= nil, "spatial sync succeeds for " .. mode)
        assert_eq(table.concat(ws.order, " "), "A B C D E", "spatial sync appends for stable iteration " .. mode)
        assert_eq(table.concat(result.added_ids, " "), "D E", "spatial sync added ids " .. mode)
        assert_eq(table.concat(result.inserted_ids, " "), "D E", "spatial sync inserted compatibility ids " .. mode)
        assert_eq(result.structural_changed, true, "spatial sync structural change " .. mode)
    end
end

local function test_spatial_target_sync_reports_removals_and_cleans_state()
    state._reset()
    local ws = state.get_workspace_state("spatial-removal")
    ws.order = { "A", "B", "C" }
    ws.focused_id = "B"
    ws.dimension_mode_by_id.B = { kind = "forced", key = "1.0x1.0" }

    local ordered, result = target_sync.sync(ws, {
        { id = "A" },
        { id = "C", active = true },
        { id = "D" },
    }, state, {
        placement_priority = "spatial",
        insert_mode = "first",
    })

    assert_true(ordered ~= nil, "spatial removal sync succeeds")
    assert_eq(table.concat(ws.order, " "), "A C D", "spatial removal preserves existing order and appends new id")
    assert_eq(table.concat(result.removed_ids, " "), "B", "spatial removed ids")
    assert_eq(table.concat(result.added_ids, " "), "D", "spatial added ids")
    assert_eq(ws.dimension_mode_by_id.B, nil, "spatial removal cleans dimension mode")
    assert_eq(ws.focused_id, "C", "spatial sync updates active focus")
    assert_eq(result.focus_changed, true, "spatial sync reports focus change")
end

local function test_solver_output_is_focus_and_viewport_independent()
    local cfg = assert(config.get_for_display("default"))
    local targets = {}
    for _, id in ipairs({ "A", "B", "C", "D", "E", "F", "G", "H" }) do
        table.insert(targets, { id = id })
    end

    local result = solver.solve({
        config = cfg,
        targets = targets,
        dimension_mode_by_id = {},
        focused_id = "A",
        viewport_offset = 0,
    })
    assert_true(result.ok, result.error)

    local shifted = solver.solve({
        config = cfg,
        targets = targets,
        dimension_mode_by_id = {},
        focused_id = "H",
        viewport_offset = 99,
    })
    assert_true(shifted.ok, shifted.error)

    local p = result.layout.placements_by_id
    local q = shifted.layout.placements_by_id
    for _, id in ipairs({ "A", "B", "C", "D", "E", "F", "G", "H" }) do
        assert_eq(p[id].x, q[id].x, "focus independence x " .. id)
        assert_eq(p[id].y, q[id].y, "focus independence y " .. id)
        assert_eq(p[id].w, q[id].w, "focus independence w " .. id)
        assert_eq(p[id].h, q[id].h, "focus independence h " .. id)
    end

    assert_eq(p.A.x, 0, "A x")
    assert_eq(p.B.y, 0.5, "B y")
    assert_eq(p.C.x, 0.5, "C x")
    assert_eq(p.E.x, 1.0, "E x")
    assert_eq(p.G.x, 1.5, "G x")
end

local function test_viewport_validation()
    local offset, err = viewport.clamp_offset(nil, 1, 2)
    assert_eq(offset, nil, "nil offset rejected")
    assert_true(err:match("offset"), "nil offset error")

    local result = viewport.reveal({
        direction = "right",
        viewport = { x = 0, y = 0, w = 1, h = 1 },
        workspace_extent = -1,
        current_offset = 0,
        focused_rect = { x = 0, y = 0, w = 1, h = 1 },
    })
    assert_eq(result.ok, false, "negative workspace rejected")
end

local function test_command_intents_and_failed_validation()
    local cfg = assert(config.get_for_display("default"))
    state._reset()
    local ws = state.get_workspace_state("commands")
    ws.order = { "A", "B" }
    ws.focused_id = "A"

    local focus = commands.execute(ws, cfg, state, config, "focus next")
    assert_true(focus.ok, focus.error)
    assert_eq(focus.focus_target_id, "B", "focus target")
    assert_eq(focus.needs_viewport_update, true, "focus is viewport-only")
    assert_eq(focus.needs_layout_update, nil, "focus does not request layout")
    assert_eq(table.concat(ws.order, " "), "A B", "focus does not reorder")

    local move = commands.execute(ws, cfg, state, config, "move next")
    assert_true(move.ok, move.error)
    assert_eq(move.needs_layout_update, true, "move requests layout")
    assert_eq(table.concat(ws.order, " "), "B A", "move reorders")

    state.set_dimension_mode(ws, "A", { kind = "forced", key = "missing" })
    local before = ws.dimension_mode_by_id.A.key
    local invalid = commands.execute(ws, cfg, state, config, "toggle dimension")
    assert_eq(invalid.ok, false, "invalid toggle fails")
    assert_eq(ws.dimension_mode_by_id.A.key, before, "invalid toggle keeps state")
end

local function test_command_placement_priority_modes()
    local order_cfg = assert(config.get_for_display("default"))
    local spatial_cfg = assert(config.get_for_display("default", {
        default = {
            allowed_dimensions = { { 1, 1 }, { 0.5, 1 } },
            scroll_direction = "right",
            placement_priority = "spatial",
        },
    }))

    state._reset()
    local ws = state.get_workspace_state("command-modes")
    ws.order = { "A", "B" }
    ws.focused_id = "A"

    local spatial_move_in_order = commands.execute(ws, order_cfg, state, config, "move left")
    assert_eq(spatial_move_in_order.ok, false, "spatial move rejected in order mode")
    assert_true(spatial_move_in_order.error:match("spatial placement"), "spatial move mode error")

    local order_move_in_spatial = commands.execute(ws, spatial_cfg, state, config, "move next")
    assert_eq(order_move_in_spatial.ok, false, "order move rejected in spatial mode")
    assert_true(order_move_in_spatial.error:match("order placement"), "order move mode error")
    assert_eq(table.concat(ws.order, " "), "A B", "rejected order move does not reorder")

    local spatial_move = commands.execute(ws, spatial_cfg, state, config, "move right")
    assert_true(spatial_move.ok, spatial_move.error)
    assert_eq(spatial_move.needs_layout_update, true, "spatial move requests layout")
    assert_eq(spatial_move.spatial_event.kind, "move", "spatial move event kind")
    assert_eq(spatial_move.spatial_event.target_id, "A", "spatial move target")
    assert_eq(spatial_move.spatial_event.direction, "right", "spatial move direction")
    assert_eq(table.concat(ws.order, " "), "A B", "spatial move does not mutate order")

    local spatial_focus_in_order = commands.execute(ws, order_cfg, state, config, "focus down")
    assert_eq(spatial_focus_in_order.ok, false, "spatial focus rejected in order mode")
    assert_true(spatial_focus_in_order.error:match("spatial placement"), "spatial focus mode error")

    local order_focus_in_spatial = commands.execute(ws, spatial_cfg, state, config, "focus next")
    assert_eq(order_focus_in_spatial.ok, false, "order focus rejected in spatial mode")
    assert_true(order_focus_in_spatial.error:match("order placement"), "order focus mode error")

    local spatial_focus = commands.execute(ws, spatial_cfg, state, config, "focus down")
    assert_true(spatial_focus.ok, spatial_focus.error)
    assert_eq(spatial_focus.needs_viewport_update, true, "spatial focus is viewport intent")
    assert_eq(spatial_focus.needs_layout_update, nil, "spatial focus does not request layout")
    assert_eq(spatial_focus.focus_direction, "down", "spatial focus direction")
    assert_eq(spatial_focus.focus_target_id, nil, "spatial focus target is resolved later")

    local toggle = commands.execute(ws, spatial_cfg, state, config, "toggle dimension")
    assert_true(toggle.ok, toggle.error)
    assert_eq(toggle.needs_layout_update, true, "toggle dimension remains structural")
    assert_eq(toggle.spatial_event.kind, "dimension_forced", "spatial toggle reports forced event")
    assert_eq(toggle.spatial_event.target_id, "A", "spatial toggle target")
    assert_eq(toggle.spatial_event.key, "1.0x1.0", "spatial toggle forced key")
    assert_eq(state.get_dimension_mode(ws, "A").kind, "forced", "toggle works in spatial mode")

    local auto = commands.execute(ws, spatial_cfg, state, config, "toggle dimension")
    assert_true(auto.ok, auto.error)
    assert_eq(auto.spatial_event.kind, "dimension_forced", "spatial toggle cycles forced dimensions")

    local back_to_auto = commands.execute(ws, spatial_cfg, state, config, "toggle dimension")
    assert_true(back_to_auto.ok, back_to_auto.error)
    assert_eq(back_to_auto.spatial_event.kind, "dimension_auto", "spatial toggle reports auto event")
    assert_eq(back_to_auto.spatial_event.target_id, "A", "spatial auto target")
    assert_eq(back_to_auto.spatial_event.previous_key, "0.5x1.0", "spatial auto previous key")
    assert_eq(state.get_dimension_mode(ws, "A").kind, "auto", "toggle returns to auto in spatial mode")
end

return {
    name = "core",
    tests = {
        test_config_defaults_and_validation,
        test_config_placement_priority,
        test_target_sync_validation_is_transactional,
        test_insert_modes,
        test_spatial_target_sync_ignores_insert_mode,
        test_spatial_target_sync_reports_removals_and_cleans_state,
        test_solver_output_is_focus_and_viewport_independent,
        test_viewport_validation,
        test_command_intents_and_failed_validation,
        test_command_placement_priority_modes,
    },
}
