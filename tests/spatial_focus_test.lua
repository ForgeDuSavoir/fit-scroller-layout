local support = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "tests") .. "/support.lua")

local assert_eq = support.assert_eq
local assert_true = support.assert_true

local spatial_geometry = support.load_layout("spatial_geometry")
local spatial_focus = support.load_layout("spatial_focus")

spatial_focus.set_dependencies({ spatial_geometry = spatial_geometry })

local function rect(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

local function layout(placements)
    return { placements_by_id = placements }
end

local function resolve(direction, placements)
    return spatial_focus.resolve({
        focused_id = "A",
        direction = direction,
        last_layout = layout(placements),
    })
end

local function test_focus_direction_selects_candidates()
    local placements = {
        A = rect(1, 1, 0.5, 0.5),
        L = rect(0, 1, 0.5, 0.5),
        R = rect(2, 1, 0.5, 0.5),
        U = rect(1, 0, 0.5, 0.5),
        D = rect(1, 2, 0.5, 0.5),
    }

    local left = resolve("left", placements)
    assert_true(left.ok, left.error)
    assert_eq(left.focus_target_id, "L", "left target")

    local right = resolve("right", placements)
    assert_true(right.ok, right.error)
    assert_eq(right.focus_target_id, "R", "right target")

    local up = resolve("up", placements)
    assert_true(up.ok, up.error)
    assert_eq(up.focus_target_id, "U", "up target")

    local down = resolve("down", placements)
    assert_true(down.ok, down.error)
    assert_eq(down.focus_target_id, "D", "down target")
end

local function test_perpendicular_overlap_beats_distance()
    local result = resolve("left", {
        A = rect(1, 1, 0.5, 0.5),
        close_no_overlap = rect(0.7, 0, 0.2, 0.2),
        farther_overlap = rect(0, 1.1, 0.2, 0.2),
    })

    assert_true(result.ok, result.error)
    assert_eq(result.focus_target_id, "farther_overlap", "overlap wins")
end

local function test_directional_distance_breaks_overlap_tie()
    local result = resolve("right", {
        A = rect(1, 1, 0.5, 0.5),
        near = rect(1.75, 1, 0.5, 0.5),
        far = rect(3, 1, 0.5, 0.5),
    })

    assert_true(result.ok, result.error)
    assert_eq(result.focus_target_id, "near", "nearest directional candidate wins")
end

local function test_center_distance_and_stable_id_tie_breakers()
    local center = resolve("down", {
        A = rect(1, 1, 0.5, 0.5),
        offset = rect(0.5, 2, 0.5, 0.5),
        aligned = rect(1, 2, 0.5, 0.5),
    })

    assert_true(center.ok, center.error)
    assert_eq(center.focus_target_id, "aligned", "center distance breaks tie")

    local stable = resolve("up", {
        A = rect(1, 1, 0.5, 0.5),
        B = rect(1, 0, 0.5, 0.5),
        C = rect(1, 0, 0.5, 0.5),
    })

    assert_true(stable.ok, stable.error)
    assert_eq(stable.focus_target_id, "B", "stable id breaks tie")
end

local function test_no_candidate_is_noop()
    local result = resolve("left", {
        A = rect(1, 1, 0.5, 0.5),
        R = rect(2, 1, 0.5, 0.5),
    })

    assert_true(result.ok, result.error)
    assert_eq(result.changed, false, "no candidate is no-op")
    assert_eq(result.focus_target_id, nil, "no focus target")
end

local function test_no_focused_id_is_noop()
    local result = spatial_focus.resolve({
        direction = "right",
        last_layout = layout({
            A = rect(1, 1, 0.5, 0.5),
        }),
    })

    assert_true(result.ok, result.error)
    assert_eq(result.changed, false, "no focused id is no-op")
end

local function test_validation_errors()
    local missing_layout = spatial_focus.resolve({
        focused_id = "A",
        direction = "right",
    })
    assert_eq(missing_layout.ok, false, "missing layout rejected")
    assert_true(missing_layout.error:match("last_layout"), "missing layout error")

    local missing_focused = spatial_focus.resolve({
        focused_id = "A",
        direction = "right",
        last_layout = layout({
            B = rect(1, 1, 0.5, 0.5),
        }),
    })
    assert_eq(missing_focused.ok, false, "missing focused placement rejected")
    assert_true(missing_focused.error:match("focused target"), "missing focused error")

    local invalid_direction = spatial_focus.resolve({
        focused_id = "A",
        direction = "previous",
        last_layout = layout({
            A = rect(1, 1, 0.5, 0.5),
        }),
    })
    assert_eq(invalid_direction.ok, false, "invalid direction rejected")
    assert_true(invalid_direction.error:match("unsupported"), "invalid direction error")
end

return {
    name = "spatial_focus",
    tests = {
        test_focus_direction_selects_candidates,
        test_perpendicular_overlap_beats_distance,
        test_directional_distance_breaks_overlap_tie,
        test_center_distance_and_stable_id_tie_breakers,
        test_no_candidate_is_noop,
        test_no_focused_id_is_noop,
        test_validation_errors,
    },
}
