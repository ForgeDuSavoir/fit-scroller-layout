local M = {}

local function current_dir()
    local source = debug and debug.getinfo(1, "S").source
    if type(source) ~= "string" or source:sub(1, 1) ~= "@" then
        return "tests"
    end

    return source:sub(2):match("^(.*)/[^/]*$") or "tests"
end

M.test_dir = current_dir()
M.project_root = M.test_dir:match("^(.*)/tests$") or "."

function M.load_layout(name)
    return dofile(M.project_root .. "/layout/" .. name .. ".lua")
end

function M.assert_eq(actual, expected, label)
    if actual ~= expected then
        error((label or "assertion failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
    end
end

function M.assert_true(value, label)
    if not value then
        error(label or "assertion failed", 2)
    end
end

function M.run_suite(suite)
    for _, test in ipairs(suite.tests or {}) do
        test()
    end
end

return M
