local root = (... and (...):match("^(.*)/[^/]+$")) or "tests"
local project_root = root == "tests" and "." or root .. "/.."

local function load(name)
    return dofile(project_root .. "/layout/" .. name .. ".lua")
end

local config = load("config")
local state = load("state")
local target_sync = load("target_sync")
local commands = load("commands")
local geometry = load("geometry")
local traversal = load("traversal")
local solver = load("solver")
local viewport = load("viewport")

solver.set_dependencies({ geometry = geometry, traversal = traversal })
viewport.set_dependencies({ traversal = traversal })

local function assert_eq(actual, expected, label)
    if actual ~= expected then
        error((label or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

local function assert_true(value, label)
    if not value then
        error(label or "assertion failed", 2)
    end
end

local function test_config_defaults_and_validation()
    local cfg = assert(config.get_for_display("default", {
        default = {
            allowed_dimensions = { { 1, 1 } },
            scroll_direction = "right",
        },
    }))
    assert_eq(cfg.tiling_mode, "split", "tiling default")
    assert_eq(cfg.insert_mode, "view", "insert default")

    local invalid, err = config.get_for_display("default", {
        default = {
            allowed_dimensions = { { 1, 1 } },
            scroll_direction = "right",
            tiling_mode = "split",
            insert_mode = "focus",
        },
    })
    assert_eq(invalid, nil, "invalid insert mode rejected")
    assert_true(err:match("insert_mode"), "insert mode error message")
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

local function test_solver_split_and_independence()
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

local function test_adapter_no_partial_placement()
    _G.hl = { dsp = {}, dispatch = function() return true end }
    local adapter = dofile(project_root .. "/layout/hyprland_adapter.lua")
    local placed = 0
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        workspace = { id = "phase5-no-partial" },
        monitor = { name = "default" },
        targets = {
            {
                window = { stable_id = "A", active = true, address = "0xA" },
                place = function()
                    placed = placed + 1
                end,
            },
            {
                window = { stable_id = "B", active = false, address = "0xB" },
            },
        },
    }

    local err = adapter.recalculate(ctx)
    assert_true(err and err:match("cannot be placed"), "missing place returns error")
    assert_eq(placed, 0, "no partial placement")
end

local function test_adapter_focus_only_keeps_dimensions()
    _G.hl = { dsp = {}, dispatch = function() return true end }
    local adapter = dofile(project_root .. "/layout/hyprland_adapter.lua")

    local function target(id, active)
        return {
            window = { stable_id = id, active = active, address = "0x" .. id },
            place = function(self, rect)
                self.last_rect = { x = rect.x, y = rect.y, w = rect.w, h = rect.h }
            end,
        }
    end

    local targets = {
        target("A", true),
        target("B", false),
        target("C", false),
        target("D", false),
        target("E", false),
    }
    local ctx = {
        area = { x = 0, y = 0, w = 1000, h = 1000 },
        workspace = { id = "phase5-focus-only" },
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

test_config_defaults_and_validation()
test_target_sync_validation_is_transactional()
test_insert_modes()
test_solver_split_and_independence()
test_viewport_validation()
test_command_intents_and_failed_validation()
test_adapter_no_partial_placement()
test_adapter_focus_only_keeps_dimensions()

print("phase5 ok")
