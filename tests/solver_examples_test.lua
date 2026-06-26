local support = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "tests") .. "/support.lua")

local assert_eq = support.assert_eq
local assert_true = support.assert_true

local config = support.load_layout("config")
local geometry = support.load_layout("geometry")
local traversal = support.load_layout("traversal")
local solver = support.load_layout("solver")

solver.set_dependencies({ geometry = geometry, traversal = traversal })

local EPSILON = 0.0000001

local CONFIG_1 = {
    { 1.0, 1.0 },
    { 0.5, 1.0 },
    { 0.5, 0.5 },
}

local CONFIG_2 = {
    { 0.66, 1.0 },
    { 0.5, 1.0 },
    { 0.33, 1.0 },
    { 0.5, 0.5 },
    { 0.33, 0.5 },
}

local CONFIG_3 = {
    { 1.0, 1.0 },
    { 0.66, 1.0 },
    { 0.5, 1.0 },
    { 1.0, 0.66 },
    { 0.66, 0.66 },
    { 0.5, 0.66 },
    { 0.33, 0.66 },
    { 0.66, 0.5 },
    { 0.5, 0.5 },
    { 0.33, 0.5 },
    { 0.5, 0.33 },
    { 0.33, 0.33 },
}

local BASE_EXAMPLES = {
    {
        name = "base 1.1",
        dimensions = CONFIG_1,
        windows = {
            { id = "A", forced = "0.5x1.0", expected = "0.5x1.0" },
            { id = "B", expected = "0.5x0.5" },
            { id = "C", expected = "0.5x0.5" },
            { id = "D", expected = "0.5x0.5" },
            { id = "E", expected = "0.5x0.5" },
        },
    },
    {
        name = "base 1.2",
        dimensions = CONFIG_1,
        windows = {
            { id = "A", expected = "0.5x1.0" },
            { id = "B", forced = "0.5x1.0", expected = "0.5x1.0" },
            { id = "C", expected = "0.5x0.5" },
            { id = "D", expected = "0.5x0.5" },
            { id = "E", expected = "0.5x1.0" },
        },
    },
    {
        name = "base 1.3",
        dimensions = CONFIG_1,
        windows = {
            { id = "A", expected = "0.5x0.5" },
            { id = "B", expected = "0.5x0.5" },
            { id = "C", forced = "0.5x1.0", expected = "0.5x1.0" },
            { id = "D", expected = "0.5x0.5" },
            { id = "E", expected = "0.5x0.5" },
        },
    },
    {
        name = "base 1.4",
        dimensions = CONFIG_1,
        windows = {
            { id = "A", expected = "0.5x0.5" },
            { id = "B", expected = "0.5x0.5" },
            { id = "C", expected = "0.5x1.0" },
            { id = "D", forced = "0.5x1.0", expected = "0.5x1.0" },
            { id = "E", expected = "0.5x1.0" },
        },
    },
    {
        name = "base 1.5",
        dimensions = CONFIG_1,
        windows = {
            { id = "A", expected = "0.5x0.5" },
            { id = "B", expected = "0.5x0.5" },
            { id = "C", expected = "0.5x0.5" },
            { id = "D", expected = "0.5x0.5" },
            { id = "E", forced = "0.5x1.0", expected = "0.5x1.0" },
        },
    },
    {
        name = "base 2.1",
        dimensions = CONFIG_2,
        windows = {
            { id = "A", expected = "0.33x1.0" },
            { id = "B", expected = "0.33x1.0" },
            { id = "C", expected = "0.33x1.0" },
        },
    },
    {
        name = "base 2.2",
        dimensions = CONFIG_2,
        windows = {
            { id = "A", expected = "0.5x0.5" },
            { id = "B", expected = "0.5x0.5" },
            { id = "C", expected = "0.5x0.5" },
            { id = "D", expected = "0.5x0.5" },
        },
    },
    {
        name = "base 2.3",
        dimensions = CONFIG_2,
        windows = {
            { id = "A", expected = "0.33x0.5" },
            { id = "B", expected = "0.33x0.5" },
            { id = "C", expected = "0.33x0.5" },
            { id = "D", expected = "0.33x0.5" },
            { id = "E", expected = "0.33x1.0" },
        },
    },
    {
        name = "base 3.1",
        dimensions = CONFIG_3,
        windows = {
            { id = "A", expected = "0.5x1.0" },
            { id = "B", expected = "0.5x1.0" },
        },
    },
    {
        name = "base 3.2",
        dimensions = CONFIG_3,
        windows = {
            { id = "A", expected = "0.5x0.5" },
            { id = "B", expected = "0.5x0.5" },
            { id = "C", expected = "0.5x1.0" },
        },
    },
    {
        name = "base 3.3",
        dimensions = CONFIG_3,
        windows = {
            { id = "A", expected = "0.5x0.5" },
            { id = "B", expected = "0.5x0.5" },
            { id = "C", expected = "0.5x0.5" },
            { id = "D", expected = "0.5x0.5" },
        },
    },
    {
        name = "base 3.4",
        dimensions = CONFIG_3,
        windows = {
            { id = "A", expected = "0.33x0.5" },
            { id = "B", expected = "0.33x0.5" },
            { id = "C", expected = "0.33x0.5" },
            { id = "D", expected = "0.33x0.5" },
            { id = "E", expected = "0.33x0.66" },
        },
    },
    {
        name = "base 3.5",
        dimensions = CONFIG_3,
        windows = {
            { id = "A", expected = "0.33x0.5" },
            { id = "B", expected = "0.33x0.5" },
            { id = "C", expected = "0.33x0.5" },
            { id = "D", expected = "0.33x0.5" },
            { id = "E", expected = "0.33x0.5" },
            { id = "F", expected = "0.33x0.5" },
        },
    },
    {
        name = "base 3.6",
        dimensions = CONFIG_3,
        windows = {
            { id = "A", expected = "0.33x0.33" },
            { id = "B", expected = "0.33x0.33" },
            { id = "C", expected = "0.33x0.33" },
            { id = "D", expected = "0.33x0.5" },
            { id = "E", expected = "0.33x0.5" },
            { id = "F", expected = "0.33x0.5" },
            { id = "G", expected = "0.33x0.5" },
        },
    },
    {
        name = "base 3.7",
        dimensions = CONFIG_3,
        windows = {
            { id = "A", expected = "0.33x0.33" },
            { id = "B", expected = "0.33x0.33" },
            { id = "C", expected = "0.33x0.33" },
            { id = "D", expected = "0.33x0.33" },
            { id = "E", expected = "0.33x0.33" },
            { id = "F", expected = "0.33x0.33" },
            { id = "G", expected = "0.33x0.5" },
            { id = "H", expected = "0.33x0.5" },
        },
    },
}

local FORCED_EXAMPLES = {
    {
        name = "forced A.1",
        dimensions = CONFIG_2,
        windows = {
            { id = "A", expected = "0.33x0.5" },
            { id = "B", expected = "0.33x0.5" },
            { id = "C", forced = "0.5x1.0", expected = "0.5x1.0" },
            { id = "D", expected = "0.33x0.5" },
            { id = "E", expected = "0.33x0.5" },
        },
    },
    {
        name = "forced A.2",
        dimensions = CONFIG_2,
        windows = {
            { id = "A", forced = "0.66x1.0", expected = "0.66x1.0" },
            { id = "B", expected = "0.33x0.5" },
            { id = "C", expected = "0.33x0.5" },
            { id = "D", expected = "0.33x0.5" },
            { id = "E", expected = "0.33x0.5" },
        },
    },
    {
        name = "forced A.3",
        dimensions = CONFIG_2,
        windows = {
            { id = "A", expected = "0.33x1.0" },
            { id = "B", forced = "0.33x1.0", expected = "0.33x1.0" },
            { id = "C", expected = "0.33x0.5" },
            { id = "D", expected = "0.33x0.5" },
        },
    },
    {
        name = "forced A.4",
        dimensions = CONFIG_2,
        windows = {
            { id = "A", expected = "0.33x0.5" },
            { id = "B", expected = "0.33x0.5" },
            { id = "C", expected = "0.33x1.0" },
            { id = "D", forced = "0.66x1.0", expected = "0.66x1.0" },
            { id = "E", expected = "0.33x0.5" },
            { id = "F", expected = "0.33x0.5" },
        },
    },
    {
        name = "forced A.5",
        dimensions = CONFIG_2,
        windows = {
            { id = "A", expected = "0.33x1.0" },
            { id = "B", forced = "0.33x0.5", expected = "0.33x0.5" },
            { id = "C", forced = "0.33x0.5", expected = "0.33x0.5" },
            { id = "D", expected = "0.33x0.5" },
            { id = "E", expected = "0.33x0.5" },
        },
    },
    {
        name = "forced B.1",
        dimensions = CONFIG_3,
        windows = {
            { id = "A", expected = "0.33x0.66" },
            { id = "B", forced = "0.66x1.0", expected = "0.66x1.0" },
            { id = "C", expected = "0.33x0.66" },
        },
    },
    {
        name = "forced B.2",
        dimensions = CONFIG_3,
        windows = {
            { id = "A", expected = "0.33x0.5" },
            { id = "B", expected = "0.33x0.5" },
            { id = "C", forced = "0.66x0.5", expected = "0.66x0.5" },
            { id = "D", expected = "0.66x0.5" },
            { id = "E", expected = "0.33x0.66" },
        },
    },
    {
        name = "forced B.3",
        dimensions = CONFIG_3,
        windows = {
            { id = "A", forced = "1.0x1.0", expected = "1.0x1.0" },
            { id = "B", expected = "0.33x0.5" },
            { id = "C", expected = "0.33x0.5" },
            { id = "D", expected = "0.33x0.5" },
            { id = "E", expected = "0.33x0.5" },
            { id = "F", expected = "0.33x0.66" },
        },
    },
    {
        name = "forced B.4",
        dimensions = CONFIG_3,
        windows = {
            { id = "A", expected = "0.33x0.5" },
            { id = "B", expected = "0.33x0.5" },
            { id = "C", expected = "0.33x0.5" },
            { id = "D", expected = "0.33x0.5" },
            { id = "E", forced = "0.5x1.0", expected = "0.5x1.0" },
            { id = "F", expected = "0.33x0.33" },
            { id = "G", expected = "0.33x0.33" },
            { id = "H", expected = "0.33x0.33" },
        },
    },
    {
        name = "forced B.5",
        dimensions = CONFIG_3,
        windows = {
            { id = "A", expected = "0.33x0.5" },
            { id = "B", expected = "0.33x0.5" },
            { id = "C", forced = "0.33x0.66", expected = "0.33x0.66" },
            { id = "D", forced = "0.33x0.33", expected = "0.33x0.33" },
            { id = "E", expected = "0.33x0.33" },
            { id = "F", expected = "0.33x0.33" },
            { id = "G", expected = "0.33x0.33" },
        },
    },
    {
        name = "forced fullscreen anchor minimizes global overflow",
        dimensions = CONFIG_1,
        windows = {
            { id = "A", expected = "0.5x0.5" },
            { id = "B", expected = "0.5x0.5" },
            { id = "C", forced = "1.0x1.0", expected = "1.0x1.0" },
            { id = "D", expected = "0.5x1.0" },
        },
    },
}

local function normalized_config(dimensions)
    return assert(config.get_for_display("default", {
        default = {
            allowed_dimensions = dimensions,
            scroll_direction = "right",
            insert_mode = "view",
        },
    }))
end

local function targets_for(example)
    local targets = {}
    for i, window in ipairs(example.windows) do
        targets[i] = { id = window.id }
    end
    return targets
end

local function dimension_modes_for(example)
    local modes = {}
    for _, window in ipairs(example.windows) do
        if window.forced then
            modes[window.id] = { kind = "forced", key = window.forced }
        end
    end
    return modes
end

local function assert_nearly_equal(actual, expected, label)
    assert_true(math.abs(actual - expected) <= EPSILON, label .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function assert_no_overlaps(example, placements)
    for i = 1, #example.windows do
        local a = placements[example.windows[i].id]
        for j = i + 1, #example.windows do
            local b = placements[example.windows[j].id]
            assert_true(not geometry.overlaps(a, b), example.name .. " overlap " .. example.windows[i].id .. " " .. example.windows[j].id)
        end
    end
end

local function assert_cross_axis_bounds(example, placements)
    for _, window in ipairs(example.windows) do
        local rect = placements[window.id]
        assert_true(rect.y >= -EPSILON, example.name .. " y lower bound " .. window.id)
        assert_true(rect.y + rect.h <= 1 + EPSILON, example.name .. " y upper bound " .. window.id)
    end
end

local function assert_logical_order(example, placements)
    local last_x = nil
    local last_y = nil
    for _, window in ipairs(example.windows) do
        local rect = placements[window.id]
        if last_x ~= nil then
            assert_true(
                rect.x > last_x + EPSILON or (math.abs(rect.x - last_x) <= EPSILON and rect.y >= last_y - EPSILON),
                example.name .. " preserves logical order at " .. window.id
            )
        end
        last_x = rect.x
        last_y = rect.y
    end
end

local function assert_example(example)
    local cfg = normalized_config(example.dimensions)
    local result = solver.solve({
        config = cfg,
        targets = targets_for(example),
        dimension_mode_by_id = dimension_modes_for(example),
    })

    assert_true(result.ok, example.name .. " solve failed: " .. tostring(result.error))

    local layout = result.layout
    for _, window in ipairs(example.windows) do
        local dimension = layout.dimensions_by_id[window.id]
        assert_true(dimension ~= nil, example.name .. " missing dimension " .. window.id)
        assert_eq(dimension.key, window.expected, example.name .. " dimension " .. window.id)
        assert_true(cfg.dimensions_by_key[dimension.key] ~= nil, example.name .. " invented dimension " .. window.id)

        if window.forced then
            assert_eq(dimension.key, window.forced, example.name .. " forced dimension " .. window.id)
        end

        local rect = layout.placements_by_id[window.id]
        assert_true(rect ~= nil, example.name .. " missing placement " .. window.id)
        assert_nearly_equal(rect.w, dimension.w, example.name .. " rect width " .. window.id)
        assert_nearly_equal(rect.h, dimension.h, example.name .. " rect height " .. window.id)
    end

    assert_no_overlaps(example, layout.placements_by_id)
    assert_cross_axis_bounds(example, layout.placements_by_id)
    assert_logical_order(example, layout.placements_by_id)
end

local function add_example_tests(tests, examples)
    for _, example in ipairs(examples) do
        table.insert(tests, function()
            assert_example(example)
        end)
    end
end

local tests = {}
add_example_tests(tests, BASE_EXAMPLES)
add_example_tests(tests, FORCED_EXAMPLES)

return {
    name = "solver_examples",
    tests = tests,
}
