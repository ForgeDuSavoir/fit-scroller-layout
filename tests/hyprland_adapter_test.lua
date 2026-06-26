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

return {
    name = "hyprland_adapter",
    tests = {
        test_adapter_no_partial_placement,
        test_adapter_focus_only_keeps_dimensions,
        test_adapter_workspace_switch_keeps_forced_dimensions,
    },
}
