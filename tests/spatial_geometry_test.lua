local support = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "tests") .. "/support.lua")

local assert_eq = support.assert_eq
local assert_true = support.assert_true

local spatial_geometry = support.load_layout("spatial_geometry")

local function rect(x, y, w, h)
    return { x = x, y = y, w = w, h = h }
end

local function test_rect_validation()
    assert_true(spatial_geometry.validate_rect(rect(0, 0, 1, 1)), "valid rect")

    local invalid, err = spatial_geometry.validate_rect({ x = 0, y = 0, w = 0, h = 1 })
    assert_eq(invalid, nil, "zero width rejected")
    assert_true(err:match("w"), "width error")

    invalid, err = spatial_geometry.validate_rect({ x = 0, y = 0, w = 1, h = math.huge })
    assert_eq(invalid, nil, "infinite height rejected")
    assert_true(err:match("h"), "height error")
end

local function test_overlap_and_adjacency()
    local a = rect(0, 0, 0.5, 0.5)
    local overlapping = rect(0.25, 0.25, 0.5, 0.5)
    local right = rect(0.5, 0, 0.5, 0.5)
    local down = rect(0, 0.5, 0.5, 0.5)
    local diagonal = rect(0.5, 0.5, 0.5, 0.5)

    assert_eq(spatial_geometry.overlaps(a, overlapping), true, "overlap detected")
    assert_eq(spatial_geometry.overlaps(a, right), false, "touching edges do not overlap")
    assert_eq(spatial_geometry.is_adjacent(a, right), true, "right adjacency")
    assert_eq(spatial_geometry.is_adjacent(a, right, "right"), true, "right side")
    assert_eq(spatial_geometry.adjacent_side(a, right), "right", "right side reported")
    assert_eq(spatial_geometry.is_adjacent(a, down, "down"), true, "down side")
    assert_eq(spatial_geometry.is_adjacent(a, diagonal), false, "corner touch is not adjacency")
end

local function test_scroll_and_cross_intervals()
    local horizontal = rect(1.25, 0.25, 0.5, 0.5)
    local vertical = rect(0.25, 1.25, 0.5, 0.5)
    local left = rect(-1.75, 0.25, 0.5, 0.5)
    local up = rect(0.25, -1.75, 0.5, 0.5)

    local start, finish = spatial_geometry.scroll_interval(horizontal, "right")
    assert_eq(start, 1.25, "right scroll start")
    assert_eq(finish, 1.75, "right scroll end")

    start, finish = spatial_geometry.cross_interval(horizontal, "right")
    assert_eq(start, 0.25, "right cross start")
    assert_eq(finish, 0.75, "right cross end")

    start, finish = spatial_geometry.scroll_interval(vertical, "down")
    assert_eq(start, 1.25, "down scroll start")
    assert_eq(finish, 1.75, "down scroll end")

    start, finish = spatial_geometry.cross_interval(vertical, "down")
    assert_eq(start, 0.25, "down cross start")
    assert_eq(finish, 0.75, "down cross end")

    start, finish = spatial_geometry.scroll_interval(left, "left")
    assert_eq(start, 1.25, "left scroll start uses near edge")
    assert_eq(finish, 1.75, "left scroll end uses far edge")

    start, finish = spatial_geometry.scroll_interval(up, "up")
    assert_eq(start, 1.25, "up scroll start uses near edge")
    assert_eq(finish, 1.75, "up scroll end uses far edge")
end

local function test_visibility()
    local visible = rect(0.25, 0, 0.5, 1)
    local partial = rect(0.75, 0, 0.5, 1)
    local hidden = rect(1.25, 0, 0.5, 1)
    local off_cross = rect(0.25, 1.1, 0.5, 0.5)
    local left_visible = rect(-0.75, 0, 0.5, 1)
    local down_visible = rect(0, 1.25, 1, 0.5)

    assert_eq(spatial_geometry.is_visible(visible, 0, "right"), true, "visible right")
    assert_eq(spatial_geometry.is_fully_visible(visible, 0, "right"), true, "fully visible right")
    assert_eq(spatial_geometry.is_visible(partial, 0, "right"), true, "partially visible right")
    assert_eq(spatial_geometry.is_fully_visible(partial, 0, "right"), false, "partial is not fully visible")
    assert_eq(spatial_geometry.is_visible(hidden, 0, "right"), false, "hidden right")
    assert_eq(spatial_geometry.is_visible(off_cross, 0, "right"), false, "hidden cross axis")
    assert_eq(spatial_geometry.visible_overlap(partial, 0, "right"), 0.25, "visible overlap area")
    assert_eq(spatial_geometry.is_visible(left_visible, 0, "left"), true, "visible left")
    assert_eq(spatial_geometry.is_visible(down_visible, 1, "down"), true, "visible down offset")
end

local function test_cross_axis_bounds()
    assert_eq(spatial_geometry.is_within_cross_axis(rect(0, 0, 0.5, 1), "right"), true, "right cross bounds")
    assert_eq(spatial_geometry.is_within_cross_axis(rect(0, -0.1, 0.5, 1), "right"), false, "right cross before bounds")
    assert_eq(spatial_geometry.is_within_cross_axis(rect(0, 0, 0.5, 1.1), "right"), false, "right cross after bounds")
    assert_eq(spatial_geometry.is_within_cross_axis(rect(0, 0, 1, 0.5), "down"), true, "down cross bounds")
    assert_eq(spatial_geometry.is_within_cross_axis(rect(-0.1, 0, 1, 0.5), "down"), false, "down cross before bounds")
end

local function test_movement_resize_and_progress()
    local before = rect(0, 0, 0.5, 0.5)
    local moved = rect(0.5, 0, 0.5, 0.5)
    local resized = rect(0, 0, 1, 0.5)

    assert_eq(spatial_geometry.movement_distance(before, moved), 0.5, "movement distance")
    assert_eq(spatial_geometry.resize_distance(before, resized), 0.5, "resize distance")
    assert_eq(spatial_geometry.is_moved(before, moved), true, "is moved")
    assert_eq(spatial_geometry.is_resized(before, resized), true, "is resized")
    assert_eq(spatial_geometry.directional_progress(before, moved, "right"), true, "right progress")
    assert_eq(spatial_geometry.directional_progress(before, moved, "left"), false, "no left progress")
    assert_eq(spatial_geometry.directional_progress(before, rect(0, -0.5, 0.5, 0.5), "up"), true, "up progress")
    assert_eq(spatial_geometry.directional_progress(before, rect(0, 0.5, 0.5, 0.5), "down"), true, "down progress")
end

return {
    name = "spatial_geometry",
    tests = {
        test_rect_validation,
        test_overlap_and_adjacency,
        test_scroll_and_cross_intervals,
        test_visibility,
        test_cross_axis_bounds,
        test_movement_resize_and_progress,
    },
}
