local support = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "tests") .. "/support.lua")

local assert_true = support.assert_true

local config = support.load_layout("config")
local geometry = support.load_layout("geometry")
local traversal = support.load_layout("traversal")
local solver = support.load_layout("solver")

solver.set_dependencies({ geometry = geometry, traversal = traversal })

local function normalized_config(dimensions)
    return assert(config.get_for_display("default", {
        default = {
            allowed_dimensions = dimensions,
            scroll_direction = "right",
            insert_mode = "view",
        },
    }))
end

local function targets(count)
    local out = {}
    for index = 1, count do
        out[index] = { id = "W" .. tostring(index) }
    end
    return out
end

local function assert_candidate_generation_is_bounded(label, dimensions, count)
    local candidates, err = solver.generate_candidates({
        config = normalized_config(dimensions),
        targets = targets(count),
        dimension_mode_by_id = {},
    })

    assert_true(candidates ~= nil, label .. " failed: " .. tostring(err))
    assert_true(#candidates <= 32, label .. " generated too many candidates: " .. tostring(#candidates))
end

local function test_default_timeout_case_keeps_candidate_count_bounded()
    assert_candidate_generation_is_bounded("default timeout case", {
        { 1.0, 1.0 },
        { 0.5, 1.0 },
        { 0.5, 0.5 },
    }, 9)
end

local function test_default_timeout_plus_one_case_keeps_candidate_count_bounded()
    assert_candidate_generation_is_bounded("default timeout plus one case", {
        { 1.0, 1.0 },
        { 0.5, 1.0 },
        { 0.5, 0.5 },
    }, 10)
end

local function test_thirds_timeout_case_keeps_candidate_count_bounded()
    assert_candidate_generation_is_bounded("thirds timeout case", {
        { 0.66, 1.0 },
        { 0.5, 1.0 },
        { 0.33, 1.0 },
        { 0.5, 0.5 },
        { 0.33, 0.5 },
    }, 6)
end

local function test_thirds_timeout_plus_one_case_keeps_candidate_count_bounded()
    assert_candidate_generation_is_bounded("thirds timeout plus one case", {
        { 0.66, 1.0 },
        { 0.5, 1.0 },
        { 0.33, 1.0 },
        { 0.5, 0.5 },
        { 0.33, 0.5 },
    }, 7)
end

return {
    name = "solver_performance",
    tests = {
        test_default_timeout_case_keeps_candidate_count_bounded,
        test_default_timeout_plus_one_case_keeps_candidate_count_bounded,
        test_thirds_timeout_case_keeps_candidate_count_bounded,
        test_thirds_timeout_plus_one_case_keeps_candidate_count_bounded,
    },
}
