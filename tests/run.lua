local test_dir = debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "tests"
local support = dofile(test_dir .. "/support.lua")

local suites = {
    dofile(test_dir .. "/core_test.lua"),
    dofile(test_dir .. "/hyprland_adapter_test.lua"),
}

local total = 0
for _, suite in ipairs(suites) do
    support.run_suite(suite)
    total = total + #(suite.tests or {})
end

print("fit-scroller tests ok (" .. tostring(total) .. " tests)")
