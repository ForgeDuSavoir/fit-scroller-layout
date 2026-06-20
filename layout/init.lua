local function current_dir()
    local source = debug and debug.getinfo(1, "S").source
    if type(source) ~= "string" or source:sub(1, 1) ~= "@" then
        return nil
    end

    local path = source:sub(2)
    return path:match("^(.*)/[^/]*$")
end

local function load_relative(path)
    local dir = current_dir()
    if not dir then
        return nil, "fit-scroller: unable to resolve layout/init.lua path"
    end

    local chunk, err = loadfile(dir .. "/" .. path)
    if not chunk then
        return nil, err
    end

    return chunk()
end

local adapter, err = load_relative("hyprland_adapter.lua")
if not adapter then
    error(err)
end

local function window_layout_name(window)
    local ok, layout = pcall(function()
        return window and window.layout
    end)
    if not ok or type(layout) ~= "table" then
        return nil
    end

    return layout.name
end

local function install_focus_listener()
    if not hl or type(hl.on) ~= "function" or type(hl.dispatch) ~= "function" or not hl.dsp or type(hl.dsp.layout) ~= "function" then
        return
    end

    if rawget(_G, "__fit_scroller_focus_subscription") then
        return
    end

    local ok, subscription = pcall(function()
        return hl.on("window.active", function(window)
            if window_layout_name(window) ~= "lua:fit-scroller" then
                return
            end

            hl.dispatch(hl.dsp.layout("follow"))
        end)
    end)

    if ok then
        _G.__fit_scroller_focus_subscription = subscription or true
    end
end

install_focus_listener()

hl.layout.register("fit-scroller", {
    recalculate = function(ctx)
        return adapter.recalculate(ctx)
    end,

    layout_msg = function(ctx, msg)
        return adapter.layout_msg(ctx, msg)
    end,
})
