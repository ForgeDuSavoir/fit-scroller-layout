local support = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "tests") .. "/support.lua")
local select_slot = support.load_layout("order_drop").select_slot
local eq = support.assert_eq
local function rect(x, y, w, h) return { x = x, y = y, w = w, h = h } end

local function test_drop_before_hovered_tile_in_all_directions()
    for _, direction in ipairs({ "right", "left", "down", "up" }) do
        local vertical = direction == "down" or direction == "up"
        local reversed = direction == "left" or direction == "up"
        local a_start, b_start = reversed and 60 or 10, reversed and 10 or 60
        local rendered = { area = rect(0, 0, 100, 100), direction = direction, rects = {
            A = vertical and rect(0, a_start, 100, 30) or rect(a_start, 0, 30, 100),
            B = vertical and rect(0, b_start, 100, 30) or rect(b_start, 0, 30, 100),
        } }
        local function index_at(coordinate)
            local point = vertical and { x = 50, y = coordinate } or { x = coordinate, y = 50 }
            return select_slot({ "A", "B", "D" }, { id = "D", point = point }, rendered).index
        end
        eq(index_at(a_start + 5), 1, direction .. " non-last first half")
        eq(index_at(a_start + 25), 1, direction .. " non-last second half")
        eq(index_at(b_start + (reversed and 25 or 5)), 2, direction .. " last leading half")
        eq(index_at(b_start + 15), 3, direction .. " last midpoint")
        eq(index_at(b_start + (reversed and 5 or 25)), 3, direction .. " last trailing half")
        rendered.rects.A = vertical and rect(10, 20, 30, 60) or rect(20, 10, 60, 30)
        rendered.rects.B = vertical and rect(50, 20, 30, 60) or rect(20, 50, 60, 30)
        local point = vertical and { x = 55, y = 65 } or { x = 65, y = 55 }
        eq(select_slot({ "A", "B" }, { id = "D", point = point }, rendered).index, 2,
            direction .. " before last stacked tile")
        point = vertical and { x = 75, y = 65 } or { x = 65, y = 75 }
        eq(select_slot({ "A", "B" }, { id = "D", point = point }, rendered).index, 3,
            direction .. " after last stacked tile")
        point = vertical and { x = 45, y = 50 } or { x = 50, y = 45 }
        local gap = select_slot({ "A", "B" }, { id = "D", point = point }, rendered)
        eq(gap.anchor_id, "A", direction .. " gap tie uses logical order")
        eq(gap.index, 1, direction .. " gap inserts before A")
    end
end

local function test_visible_edges_and_fallback()
    local order = { "hidden-first", "A", "D", "B", "hidden-last" }
    local drop = { id = "D", previous_id = "A", next_id = "B", index = 3, point = { x = 105, y = 250 } }
    local rendered = { area = rect(100, 200, 100, 100), direction = "right", rects = {
        ["hidden-first"] = rect(50, 200, 50, 100), A = rect(120, 200, 20, 100),
        B = rect(160, 200, 20, 100), ["hidden-last"] = rect(200, 200, 50, 100),
        D = rect(100, 200, 20, 100), removed = rect(100, 200, 20, 100),
    } }
    eq(select_slot(order, drop, rendered).index, 2, "leading visible edge is not workspace start")
    drop.point.x = 175
    eq(select_slot(order, drop, rendered).index, 4, "last visible tile trailing half precedes hidden tiles")
    drop.point.x = 195
    eq(select_slot(order, drop, rendered).index, 4, "trailing visible edge is not workspace end")
    drop.point.x = 205
    eq(select_slot(order, drop, rendered).index, 3, "outside restores neighbor slot")
    eq(select_slot({ "B" }, drop, nil).index, 1, "fallback before surviving next neighbor")
    eq(select_slot({ "hidden-first" }, drop, nil).index, 2, "clamp original index")
    eq(select_slot({ "D" }, drop, nil).index, 1, "sole window fallback")
end

local function test_centered_and_clipped_rectangles()
    local rendered = { area = rect(100, 200, 100, 100), direction = "right", rects = {
        A = rect(80, 225, 40, 50), B = rect(135, 225, 50, 50),
    } }
    local drop = { id = "D", point = { x = 150, y = 250 } }
    local slot = select_slot({ "A", "B" }, drop, rendered)
    eq(slot.anchor_id, "B", "centered tile is hit in screen coordinates")
    eq(slot.after, false, "hover inserts before centered tile")
    drop.point.x = 105
    slot = select_slot({ "A", "B" }, drop, rendered)
    eq(slot.anchor_id, "A", "partially visible tile remains eligible")
    eq(slot.after, false, "hover inserts before partially visible tile")
end

return { name = "order_drop", tests = {
    test_drop_before_hovered_tile_in_all_directions,
    test_visible_edges_and_fallback,
    test_centered_and_clipped_rectangles,
} }
