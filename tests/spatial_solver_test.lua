local support = dofile((debug.getinfo(1, "S").source:sub(2):match("^(.*)/[^/]*$") or "tests") .. "/support.lua")

local assert_eq = support.assert_eq
local assert_true = support.assert_true

local config = support.load_layout("config")
local spatial_geometry = support.load_layout("spatial_geometry")
local spatial_solver = support.load_layout("spatial_solver")

spatial_solver.set_dependencies({ spatial_geometry = spatial_geometry })

local function normalized_config(dimensions, direction)
    return assert(config.get_for_display("default", {
        default = {
            allowed_dimensions = dimensions,
            scroll_direction = direction or "right",
            placement_priority = "spatial",
        },
    }))
end

local function targets(ids)
    local out = {}
    for _, id in ipairs(ids) do
        table.insert(out, { id = id })
    end
    return out
end

local function assert_complete_layout(layout, ids)
    for _, id in ipairs(ids) do
        assert_true(layout.placements_by_id[id] ~= nil, "placement for " .. id)
        assert_true(layout.dimensions_by_id[id] ~= nil, "dimension for " .. id)
    end

    for id in pairs(layout.placements_by_id) do
        local known = false
        for _, expected_id in ipairs(ids) do
            if id == expected_id then
                known = true
                break
            end
        end
        assert_true(known, "unknown placement id " .. tostring(id))
    end
end

local function assert_no_overlap(layout, ids)
    for i = 1, #ids do
        for j = i + 1, #ids do
            local a = layout.placements_by_id[ids[i]]
            local b = layout.placements_by_id[ids[j]]
            assert_eq(spatial_geometry.overlaps(a, b), false, "no overlap " .. ids[i] .. " " .. ids[j])
        end
    end
end

local function last_layout(placements, dimensions)
    return {
        placements_by_id = placements,
        dimensions_by_id = dimensions or {},
        workspace_extent = 1,
    }
end

local function test_initial_global_rebuild_returns_complete_layout()
    local ids = { "A", "B", "C" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        viewport_offset = 0,
        event = { kind = "initial" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.workspace_extent, 3, "initial extent uses largest auto dimension")
    assert_eq(result.layout.dimensions_by_id.A.key, "1.0x1.0", "auto uses largest dimension")
    assert_eq(result.layout.placements_by_id.A.x, 0, "A x")
    assert_eq(result.layout.placements_by_id.B.x, 1, "B x")
    assert_eq(result.layout.placements_by_id.C.x, 2, "C x")
    assert_eq(result.diagnostics.strategy, "initial_global_rebuild", "diagnostic strategy")
end

local function test_initial_global_rebuild_honors_forced_dimensions()
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 }, { 0.5, 0.5 } }),
        targets = targets({ "A", "B" }),
        dimension_mode_by_id = {
            B = { kind = "forced", key = "0.5x0.5" },
        },
        viewport_offset = 0,
        event = { kind = "initial" },
    })

    assert_true(result.ok, result.error)
    assert_eq(result.layout.dimensions_by_id.A.key, "1.0x1.0", "auto dimension")
    assert_eq(result.layout.dimensions_by_id.B.key, "0.5x0.5", "forced dimension")
    assert_eq(result.layout.placements_by_id.B.w, 0.5, "forced width")
    assert_eq(result.layout.placements_by_id.B.h, 0.5, "forced height")
end

local function test_initial_global_rebuild_handles_vertical_and_negative_directions()
    local down = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }, "down"),
        targets = targets({ "A", "B" }),
        dimension_mode_by_id = {},
        viewport_offset = 0,
        event = { kind = "initial" },
    })
    assert_true(down.ok, down.error)
    assert_eq(down.layout.placements_by_id.B.x, 0, "down x")
    assert_eq(down.layout.placements_by_id.B.y, 1, "down y")

    local left = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }, "left"),
        targets = targets({ "A", "B" }),
        dimension_mode_by_id = {},
        viewport_offset = 0,
        event = { kind = "initial" },
    })
    assert_true(left.ok, left.error)
    assert_eq(left.layout.placements_by_id.A.x, -1, "left A x")
    assert_eq(left.layout.placements_by_id.B.x, -2, "left B x")

    local up = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }, "up"),
        targets = targets({ "A", "B" }),
        dimension_mode_by_id = {},
        viewport_offset = 0,
        event = { kind = "initial" },
    })
    assert_true(up.ok, up.error)
    assert_eq(up.layout.placements_by_id.A.y, -1, "up A y")
    assert_eq(up.layout.placements_by_id.B.y, -2, "up B y")
end

local function test_validation_rejects_invalid_inputs()
    local cfg = normalized_config({ { 1, 1 } })

    local wrong_priority = spatial_solver.solve({
        config = assert(config.get_for_display("default", {
            default = {
                allowed_dimensions = { { 1, 1 } },
                scroll_direction = "right",
                placement_priority = "order",
            },
        })),
        targets = targets({ "A" }),
        dimension_mode_by_id = {},
        viewport_offset = 0,
        event = { kind = "initial" },
    })
    assert_eq(wrong_priority.ok, false, "wrong priority rejected")
    assert_true(wrong_priority.error:match("placement_priority"), "priority error")

    local duplicate = spatial_solver.solve({
        config = cfg,
        targets = targets({ "A", "A" }),
        dimension_mode_by_id = {},
        viewport_offset = 0,
        event = { kind = "initial" },
    })
    assert_eq(duplicate.ok, false, "duplicate ids rejected")
    assert_true(duplicate.error:match("duplicate"), "duplicate error")

    local forced = spatial_solver.solve({
        config = cfg,
        targets = targets({ "A" }),
        dimension_mode_by_id = {
            A = { kind = "forced", key = "missing" },
        },
        viewport_offset = 0,
        event = { kind = "initial" },
    })
    assert_eq(forced.ok, false, "invalid forced key rejected")
    assert_true(forced.error:match("forced dimension"), "forced key error")

    local offset = spatial_solver.solve({
        config = cfg,
        targets = targets({ "A" }),
        dimension_mode_by_id = {},
        viewport_offset = -1,
        event = { kind = "initial" },
    })
    assert_eq(offset.ok, false, "negative offset rejected")
    assert_true(offset.error:match("viewport_offset"), "offset error")
end

local function test_global_rebuild_preserves_visible_existing_windows()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 2, y = 0, w = 1, h = 1 },
            B = { x = 3, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
            B = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 2,
        event = { kind = "config_changed" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "global_preserve", "global rebuild preserves visible geometry")
    assert_eq(result.layout.placements_by_id.A.x, 2, "visible A x preserved")
    assert_eq(result.layout.placements_by_id.B.x, 3, "B x preserved")
end

local function test_global_rebuild_handles_multiple_added_windows()
    local ids = { "A", "B", "C" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 2, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 2,
        event = { kind = "config_changed" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "global_preserve", "global rebuild appends multiple additions")
    assert_eq(result.layout.placements_by_id.A.x, 2, "existing A preserved")
    assert_eq(result.layout.placements_by_id.B.x, 3, "new B appended")
    assert_eq(result.layout.placements_by_id.C.x, 4, "new C appended")
end

local function test_global_rebuild_handles_multiple_removed_windows()
    local ids = { "A", "D" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 1, h = 1 },
            B = { x = 1, y = 0, w = 1, h = 1 },
            C = { x = 2, y = 0, w = 1, h = 1 },
            D = { x = 3, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
            B = { key = "1.0x1.0", w = 1, h = 1 },
            C = { key = "1.0x1.0", w = 1, h = 1 },
            D = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "config_changed" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "global_preserve", "global rebuild removes missing ids")
    assert_eq(result.layout.placements_by_id.B, nil, "removed B absent")
    assert_eq(result.layout.placements_by_id.C, nil, "removed C absent")
    assert_eq(result.layout.placements_by_id.A.x, 0, "A preserved")
    assert_eq(result.layout.placements_by_id.D.x, 3, "D preserved")
end

local function test_global_rebuild_without_last_layout_is_dense()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        viewport_offset = 0,
        event = { kind = "config_changed" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "global_rebuild", "missing last layout uses dense rebuild")
    assert_eq(result.layout.placements_by_id.A.x, 0, "dense A x")
    assert_eq(result.layout.placements_by_id.B.x, 1, "dense B x")
end

local function test_global_rebuild_preserves_forced_dimensions()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {
            B = { kind = "forced", key = "0.5x1.0" },
        },
        last_layout = last_layout({
            A = { x = 2, y = 0, w = 1, h = 1 },
            B = { x = 3, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 2,
        event = { kind = "config_changed" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.dimensions_by_id.B.key, "0.5x1.0", "forced dimension preserved")
    assert_eq(result.layout.placements_by_id.B.w, 0.5, "forced width preserved")
end

local function test_global_rebuild_rejects_invalid_forced_dimension()
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }),
        targets = targets({ "A" }),
        dimension_mode_by_id = {
            A = { kind = "forced", key = "missing" },
        },
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "config_changed" },
    })

    assert_eq(result.ok, false, "invalid forced key rejects global rebuild")
    assert_true(result.error:match("forced dimension"), "invalid forced key error")
end

local function test_local_event_requires_last_layout()
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }),
        targets = targets({ "A", "B" }),
        dimension_mode_by_id = {},
        viewport_offset = 0,
        event = { kind = "window_added", target_id = "B" },
    })

    assert_eq(result.ok, false, "local event without last layout rejected")
    assert_true(result.error:match("last_layout"), "last layout error")
end

local function test_window_added_splits_visible_auto_window()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 }, { 0.5, 0.5 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_added", target_id = "B" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_split", "window add uses local split")
    assert_eq(result.layout.dimensions_by_id.A.key, "0.5x1.0", "source resized")
    assert_eq(result.layout.dimensions_by_id.B.key, "0.5x1.0", "new window dimension")
    assert_eq(result.layout.placements_by_id.A.x, 0, "source x")
    assert_eq(result.layout.placements_by_id.B.x, 0.5, "new x")
    assert_eq(result.layout.workspace_extent, 1, "split does not increase extent")
end

local function test_window_added_prefers_visible_split_source()
    local ids = { "A", "B", "C" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 1, h = 1 },
            B = { x = 2, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
            B = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_added", target_id = "C" },
    })

    assert_true(result.ok, result.error)
    assert_eq(result.layout.diagnostics.strategy, "local_split", "window add uses local split")
    assert_eq(result.layout.dimensions_by_id.A.key, "0.5x1.0", "visible source split")
    assert_eq(result.layout.dimensions_by_id.B.key, "1.0x1.0", "non-visible source unchanged")
    assert_eq(result.layout.placements_by_id.C.x, 0.5, "new window placed in visible source")
end

local function test_window_added_appends_when_no_split_exists()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_added", target_id = "B" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_append", "window add appends")
    assert_eq(result.layout.placements_by_id.B.x, 1, "new window appended")
    assert_eq(result.layout.workspace_extent, 2, "append increases extent")
end

local function test_window_added_appends_adjacent_for_negative_scroll_directions()
    local left = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }, "left"),
        targets = targets({ "A", "B" }),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = -1, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_added", target_id = "B" },
    })

    assert_true(left.ok, left.error)
    assert_complete_layout(left.layout, { "A", "B" })
    assert_eq(left.layout.diagnostics.strategy, "local_append", "left append")
    assert_eq(left.layout.placements_by_id.B.x, -2, "left append is adjacent before min x")
    assert_eq(left.layout.workspace_extent, 2, "left append extent")

    local up = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }, "up"),
        targets = targets({ "A", "B" }),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = -1, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_added", target_id = "B" },
    })

    assert_true(up.ok, up.error)
    assert_complete_layout(up.layout, { "A", "B" })
    assert_eq(up.layout.diagnostics.strategy, "local_append", "up append")
    assert_eq(up.layout.placements_by_id.B.y, -2, "up append is adjacent before min y")
    assert_eq(up.layout.workspace_extent, 2, "up append extent")
end

local function test_window_added_does_not_split_forced_source()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {
            A = { kind = "forced", key = "1.0x1.0" },
        },
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_added", target_id = "B" },
    })

    assert_true(result.ok, result.error)
    assert_eq(result.layout.diagnostics.strategy, "local_append", "forced source is not split")
    assert_eq(result.layout.dimensions_by_id.A.key, "1.0x1.0", "forced source unchanged")
    assert_eq(result.layout.placements_by_id.B.x, 1, "new window appended after forced source")
end

local function test_window_removed_can_preserve_remaining_rects()
    local ids = { "A", "C" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 0.5, 0.5 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 0.5 },
            B = { x = 0.5, y = 0, w = 0.5, h = 0.5 },
            C = { x = 0.5, y = 0.5, w = 0.5, h = 0.5 },
        }, {
            A = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            B = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            C = { key = "0.5x0.5", w = 0.5, h = 0.5 },
        }),
        viewport_offset = 0,
        event = { kind = "window_removed", target_id = "B" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_preserve", "removal can preserve")
    assert_eq(result.layout.placements_by_id.A.x, 0, "A x preserved")
    assert_eq(result.layout.placements_by_id.A.w, 0.5, "A width preserved")
    assert_eq(result.layout.placements_by_id.C.x, 0.5, "C x preserved")
    assert_eq(result.layout.placements_by_id.C.y, 0.5, "C y preserved")
end

local function test_window_removed_trailing_window_reduces_extent()
    local ids = { "A" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 1, h = 1 },
            B = { x = 1, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
            B = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_removed", target_id = "B" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_preserve", "trailing removal preserves")
    assert_eq(result.layout.workspace_extent, 1, "trailing removal reduces extent")
end

local function test_window_removed_preserves_trailing_full_height_hole_and_reduces_extent()
    local ids = { "A" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
            B = { x = 0.5, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_removed", target_id = "B" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_preserve", "trailing full-height hole is not expanded")
    assert_eq(result.layout.dimensions_by_id.A.key, "0.5x1.0", "auto window dimension preserved")
    assert_eq(result.layout.placements_by_id.A.x, 0, "preserved x")
    assert_eq(result.layout.placements_by_id.A.w, 0.5, "preserved width")
    assert_eq(result.layout.workspace_extent, 0.5, "trailing full-height removal shrinks extent")
end

local function test_window_removed_compacts_full_height_hole()
    local ids = { "A", "C", "D" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 0.5 }, { 0.5, 1 }, { 0.5, 0.5 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 0.5 },
            B = { x = 0.5, y = 0, w = 0.5, h = 1 },
            C = { x = 0, y = 0.5, w = 0.5, h = 0.5 },
            D = { x = 1, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
            C = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            D = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_removed", target_id = "B" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_compact_full_cross_hole", "removal closes full-height hole by shifting")
    assert_eq(result.layout.dimensions_by_id.A.key, "0.5x0.5", "top auto window dimension preserved")
    assert_eq(result.layout.dimensions_by_id.C.key, "0.5x0.5", "bottom auto window dimension preserved")
    assert_eq(result.layout.placements_by_id.A.x, 0, "top x preserved")
    assert_eq(result.layout.placements_by_id.A.w, 0.5, "top width preserved")
    assert_eq(result.layout.placements_by_id.C.x, 0, "bottom x preserved")
    assert_eq(result.layout.placements_by_id.C.w, 0.5, "bottom width preserved")
    assert_eq(result.layout.placements_by_id.D.x, 0.5, "following column shifted left")
    assert_eq(result.layout.placements_by_id.D.w, 0.5, "following column width preserved")
    assert_eq(result.layout.workspace_extent, 1, "compaction closes extent")
end

local function test_window_removed_compacts_full_height_hole_leftward_scroll()
    local ids = { "A", "C", "D" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 0.5 }, { 0.5, 1 }, { 0.5, 0.5 } }, "left"),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = -0.5, y = 0, w = 0.5, h = 0.5 },
            B = { x = -1, y = 0, w = 0.5, h = 1 },
            C = { x = -0.5, y = 0.5, w = 0.5, h = 0.5 },
            D = { x = -1.5, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
            C = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            D = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_removed", target_id = "B" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_compact_full_cross_hole", "left scroll closes hole by shifting right")
    assert_eq(result.layout.placements_by_id.A.x, -0.5, "origin column preserved")
    assert_eq(result.layout.placements_by_id.C.x, -0.5, "origin shared column preserved")
    assert_eq(result.layout.placements_by_id.D.x, -1, "following column shifted right")
    assert_eq(result.layout.workspace_extent, 1, "left extent compacted")
end

local function test_window_removed_compacts_full_width_hole_upward_scroll()
    local ids = { "A", "C", "D" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 0.5, 1 }, { 1, 0.5 }, { 0.5, 0.5 } }, "up"),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = -0.5, w = 0.5, h = 0.5 },
            B = { x = 0, y = -1, w = 1, h = 0.5 },
            C = { x = 0.5, y = -0.5, w = 0.5, h = 0.5 },
            D = { x = 0, y = -1.5, w = 1, h = 0.5 },
        }, {
            A = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            B = { key = "1.0x0.5", w = 1, h = 0.5 },
            C = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            D = { key = "1.0x0.5", w = 1, h = 0.5 },
        }),
        viewport_offset = 0,
        event = { kind = "window_removed", target_id = "B" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_compact_full_cross_hole", "up scroll closes hole by shifting down")
    assert_eq(result.layout.placements_by_id.A.y, -0.5, "origin row preserved")
    assert_eq(result.layout.placements_by_id.C.y, -0.5, "origin shared row preserved")
    assert_eq(result.layout.placements_by_id.D.y, -1, "following row shifted down")
    assert_eq(result.layout.workspace_extent, 1, "up extent compacted")
end

local function test_window_removed_does_not_resize_forced_adjacent_window()
    local ids = { "A" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {
            A = { kind = "forced", key = "0.5x1.0" },
        },
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
            B = { x = 0.5, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_removed", target_id = "B" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_preserve", "forced neighbor is preserved")
    assert_eq(result.layout.dimensions_by_id.A.key, "0.5x1.0", "forced dimension preserved")
    assert_eq(result.layout.placements_by_id.A.w, 0.5, "forced width preserved")
end

local function test_window_removed_fills_partial_hole_by_shrinking_column_when_same_width_is_unavailable()
    local ids = { "B", "C" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 0.5 }, { 0.25, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 0.5 },
            B = { x = 0, y = 0.5, w = 0.5, h = 0.5 },
            C = { x = 0.5, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            B = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            C = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_removed", target_id = "A" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_cross_fill", "partial hole filled by column resize")
    assert_eq(result.layout.dimensions_by_id.B.key, "0.25x1.0", "column window shrinks scroll size")
    assert_eq(result.layout.placements_by_id.B.x, 0, "column window keeps scroll start")
    assert_eq(result.layout.placements_by_id.B.y, 0, "column window fills cross-axis hole")
    assert_eq(result.layout.placements_by_id.B.w, 0.25, "column width shrinks")
    assert_eq(result.layout.placements_by_id.B.h, 1, "column height expands")
    assert_eq(result.layout.placements_by_id.C.x, 0.25, "following column compacted")
    assert_eq(result.layout.workspace_extent, 1.25, "scroll extent shrinks")
end

local function test_window_removed_fills_partial_hole_on_vertical_scroll_axis()
    local ids = { "B", "C" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 0.5 }, { 1, 0.25 } }, "down"),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 0.5 },
            B = { x = 0.5, y = 0, w = 0.5, h = 0.5 },
            C = { x = 0, y = 0.5, w = 1, h = 1 },
        }, {
            A = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            B = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            C = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_removed", target_id = "A" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_cross_fill", "partial hole filled on vertical scroll")
    assert_eq(result.layout.dimensions_by_id.B.key, "1.0x0.25", "row window shrinks scroll size")
    assert_eq(result.layout.placements_by_id.B.x, 0, "row window fills cross-axis hole")
    assert_eq(result.layout.placements_by_id.B.y, 0, "row window keeps scroll start")
    assert_eq(result.layout.placements_by_id.B.w, 1, "row width expands")
    assert_eq(result.layout.placements_by_id.B.h, 0.25, "row height shrinks")
    assert_eq(result.layout.placements_by_id.C.y, 0.25, "following row compacted upward")
    assert_eq(result.layout.workspace_extent, 1.25, "vertical scroll extent shrinks")
end

local function test_window_removed_missing_previous_rect_uses_global_rebuild()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 2, y = 0, w = 1, h = 1 },
            B = { x = 3, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
            B = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "window_removed", target_id = "Z" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "global_preserve", "missing previous rect uses global preserve")
    assert_eq(result.layout.placements_by_id.A.x, 2, "global preserve A x")
    assert_eq(result.layout.placements_by_id.B.x, 3, "global preserve B x")
end

local function test_dimension_forced_resizes_target_locally()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {
            A = { kind = "forced", key = "1.0x1.0" },
        },
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
            B = { x = 1, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "dimension_forced", target_id = "A", key = "1.0x1.0" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_resize", "forced resize is local")
    assert_eq(result.layout.dimensions_by_id.A.key, "1.0x1.0", "forced dimension applied")
    assert_eq(result.layout.placements_by_id.A.w, 1, "forced width")
    assert_eq(result.layout.placements_by_id.B.x, 1, "unrelated window preserved")
end

local function test_dimension_forced_pushes_overlapping_auto_neighbor()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {
            A = { kind = "forced", key = "1.0x1.0" },
        },
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
            B = { x = 0.5, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "dimension_forced", target_id = "A", key = "1.0x1.0" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_push", "forced resize pushes auto neighbor")
    assert_eq(result.layout.placements_by_id.A.w, 1, "forced target width")
    assert_eq(result.layout.placements_by_id.B.x, 1, "auto neighbor pushed")
    assert_eq(result.layout.dimensions_by_id.B.key, "0.5x1.0", "auto neighbor dimension preserved")
end

local function test_dimension_forced_compacts_full_height_hole()
    local ids = { "A", "B", "C" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 1, 0.5 }, { 0.5, 1 }, { 0.5, 0.5 } }),
        targets = targets(ids),
        dimension_mode_by_id = {
            A = { kind = "forced", key = "0.5x1.0" },
        },
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 1, h = 1 },
            B = { x = 1, y = 0, w = 0.5, h = 0.5 },
            C = { x = 1, y = 0.5, w = 0.5, h = 0.5 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
            B = { key = "0.5x0.5", w = 0.5, h = 0.5 },
            C = { key = "0.5x0.5", w = 0.5, h = 0.5 },
        }),
        viewport_offset = 0,
        event = { kind = "dimension_forced", target_id = "A", key = "0.5x1.0" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_compact_full_cross_hole", "forced shrink closes full-height hole by shifting")
    assert_eq(result.layout.placements_by_id.A.x, 0, "forced target x preserved")
    assert_eq(result.layout.placements_by_id.A.w, 0.5, "forced target width applied")
    assert_eq(result.layout.placements_by_id.B.x, 0.5, "top column window shifted left")
    assert_eq(result.layout.placements_by_id.B.y, 0, "top row preserved")
    assert_eq(result.layout.placements_by_id.B.w, 0.5, "top width preserved")
    assert_eq(result.layout.placements_by_id.B.h, 0.5, "top height preserved")
    assert_eq(result.layout.placements_by_id.C.x, 0.5, "bottom column window shifted left")
    assert_eq(result.layout.placements_by_id.C.y, 0.5, "bottom row preserved")
    assert_eq(result.layout.placements_by_id.C.w, 0.5, "bottom width preserved")
    assert_eq(result.layout.placements_by_id.C.h, 0.5, "bottom height preserved")
    assert_eq(result.layout.workspace_extent, 1, "extent shrinks after compaction")
end

local function test_dimension_forced_does_not_push_forced_neighbor_locally()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {
            A = { kind = "forced", key = "1.0x1.0" },
            B = { kind = "forced", key = "0.5x1.0" },
        },
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
            B = { x = 0.5, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "dimension_forced", target_id = "A", key = "1.0x1.0" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "global_rebuild", "forced blocker uses rebuild fallback")
    assert_eq(result.layout.dimensions_by_id.B.key, "0.5x1.0", "forced neighbor dimension preserved")
end

local function test_dimension_forced_rejects_invalid_or_mismatched_key()
    local ids = { "A" }
    local base = {
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {
            A = { kind = "forced", key = "1.0x1.0" },
        },
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
    }

    base.event = { kind = "dimension_forced", target_id = "A", key = "0.5x1.0" }
    local mismatched = spatial_solver.solve(base)
    assert_eq(mismatched.ok, false, "mismatched forced key rejected")
    assert_true(mismatched.error:match("does not match"), "mismatch error")

    base.dimension_mode_by_id.A.key = "missing"
    base.event = { kind = "dimension_forced", target_id = "A", key = "missing" }
    local invalid = spatial_solver.solve(base)
    assert_eq(invalid.ok, false, "invalid forced key rejected")
    assert_true(invalid.error:match("forced dimension"), "invalid key error")
end

local function test_dimension_auto_shrinks_large_forced_window_and_reduces_extent()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 1, h = 1 },
            B = { x = 1, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "dimension_auto", target_id = "A", previous_key = "1.0x1.0" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_auto_compact", "auto return compacts")
    assert_eq(result.layout.dimensions_by_id.A.key, "0.5x1.0", "large forced window can shrink")
    assert_eq(result.layout.placements_by_id.B.x, 0.5, "neighbor compacted into freed space")
    assert_eq(result.layout.workspace_extent, 1, "auto return reduces extent")
end

local function test_dimension_auto_grows_small_forced_window_when_no_compaction_gain_exists()
    local ids = { "A" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "dimension_auto", target_id = "A", previous_key = "0.5x1.0" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_eq(result.layout.dimensions_by_id.A.key, "1.0x1.0", "small forced window grows to best auto")
    assert_eq(result.layout.placements_by_id.A.w, 1, "auto grown width")
end

local function test_dimension_auto_fills_visible_gap_without_preferring_previous_forced_dimension()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {
            B = { kind = "forced", key = "0.5x1.0" },
        },
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
            B = { x = 1, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "dimension_auto", target_id = "A", previous_key = "0.5x1.0" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.dimensions_by_id.A.key, "1.0x1.0", "previous forced dimension is not preferred")
    assert_eq(result.layout.placements_by_id.A.w, 1, "visible gap filled")
    assert_eq(result.layout.placements_by_id.B.x, 1, "neighbor remains adjacent")
end

local function test_dimension_auto_rejects_target_that_is_still_forced()
    local ids = { "A" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {
            A = { kind = "forced", key = "0.5x1.0" },
        },
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "dimension_auto", target_id = "A", previous_key = "0.5x1.0" },
    })

    assert_eq(result.ok, false, "dimension_auto requires draft auto mode")
    assert_true(result.error:match("not auto"), "auto mode error")
end

local function test_move_right_swaps_with_compatible_neighbor()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
            B = { x = 0.5, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "move", target_id = "A", direction = "right" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_swap", "move right swaps")
    assert_eq(result.layout.placements_by_id.A.x, 0.5, "A moved right")
    assert_eq(result.layout.placements_by_id.B.x, 0, "B swapped left")
end

local function test_move_left_swaps_with_compatible_neighbor()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
            B = { x = 0.5, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "move", target_id = "B", direction = "left" },
    })

    assert_true(result.ok, result.error)
    assert_eq(result.layout.diagnostics.strategy, "local_swap", "move left swaps")
    assert_eq(result.layout.placements_by_id.B.x, 0, "B moved left")
    assert_eq(result.layout.placements_by_id.A.x, 0.5, "A swapped right")
end

local function test_move_up_and_down_swap_vertically()
    local ids = { "A", "B" }
    local down = spatial_solver.solve({
        config = normalized_config({ { 1, 0.5 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 1, h = 0.5 },
            B = { x = 0, y = 0.5, w = 1, h = 0.5 },
        }, {
            A = { key = "1.0x0.5", w = 1, h = 0.5 },
            B = { key = "1.0x0.5", w = 1, h = 0.5 },
        }),
        viewport_offset = 0,
        event = { kind = "move", target_id = "A", direction = "down" },
    })

    assert_true(down.ok, down.error)
    assert_eq(down.layout.diagnostics.strategy, "local_swap", "move down swaps")
    assert_eq(down.layout.placements_by_id.A.y, 0.5, "A moved down")

    local up = spatial_solver.solve({
        config = normalized_config({ { 1, 0.5 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 1, h = 0.5 },
            B = { x = 0, y = 0.5, w = 1, h = 0.5 },
        }, {
            A = { key = "1.0x0.5", w = 1, h = 0.5 },
            B = { key = "1.0x0.5", w = 1, h = 0.5 },
        }),
        viewport_offset = 0,
        event = { kind = "move", target_id = "B", direction = "up" },
    })

    assert_true(up.ok, up.error)
    assert_eq(up.layout.diagnostics.strategy, "local_swap", "move up swaps")
    assert_eq(up.layout.placements_by_id.B.y, 0, "B moved up")
end

local function test_move_splits_auto_neighbor_when_swap_is_incompatible()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 }, { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {
            A = { kind = "forced", key = "0.5x1.0" },
        },
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
            B = { x = 1, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
            B = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "move", target_id = "A", direction = "right" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_no_overlap(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "local_split_move", "move splits auto neighbor")
    assert_eq(result.layout.placements_by_id.A.x, 1, "target inserted into neighbor space")
    assert_eq(result.layout.placements_by_id.B.x, 1.5, "auto neighbor resized after split")
    assert_eq(result.layout.dimensions_by_id.A.key, "0.5x1.0", "forced target dimension preserved")
    assert_eq(result.layout.dimensions_by_id.B.key, "0.5x1.0", "auto neighbor resized")
end

local function test_move_preserves_forced_dimensions_on_swap()
    local ids = { "A", "B" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 0.5, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {
            A = { kind = "forced", key = "0.5x1.0" },
            B = { kind = "forced", key = "0.5x1.0" },
        },
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 0.5, h = 1 },
            B = { x = 0.5, y = 0, w = 0.5, h = 1 },
        }, {
            A = { key = "0.5x1.0", w = 0.5, h = 1 },
            B = { key = "0.5x1.0", w = 0.5, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "move", target_id = "A", direction = "right" },
    })

    assert_true(result.ok, result.error)
    assert_eq(result.layout.diagnostics.strategy, "local_swap", "forced swap succeeds")
    assert_eq(result.layout.dimensions_by_id.A.key, "0.5x1.0", "A forced dimension preserved")
    assert_eq(result.layout.dimensions_by_id.B.key, "0.5x1.0", "B forced dimension preserved")
end

local function test_move_without_progress_is_noop()
    local ids = { "A" }
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }),
        targets = targets(ids),
        dimension_mode_by_id = {},
        last_layout = last_layout({
            A = { x = 0, y = 0, w = 1, h = 1 },
        }, {
            A = { key = "1.0x1.0", w = 1, h = 1 },
        }),
        viewport_offset = 0,
        event = { kind = "move", target_id = "A", direction = "left" },
    })

    assert_true(result.ok, result.error)
    assert_complete_layout(result.layout, ids)
    assert_eq(result.layout.diagnostics.strategy, "noop", "no-progress move is noop")
    assert_eq(result.layout.placements_by_id.A.x, 0, "A remains in place")
end

local function test_zero_targets_initial_layout()
    local result = spatial_solver.solve({
        config = normalized_config({ { 1, 1 } }),
        targets = {},
        dimension_mode_by_id = {},
        viewport_offset = 0,
        event = { kind = "initial" },
    })

    assert_true(result.ok, result.error)
    assert_eq(result.layout.workspace_extent, 0, "empty extent")
    assert_eq(next(result.layout.placements_by_id), nil, "empty placements")
    assert_eq(next(result.layout.dimensions_by_id), nil, "empty dimensions")
end

return {
    name = "spatial_solver",
    tests = {
        test_initial_global_rebuild_returns_complete_layout,
        test_initial_global_rebuild_honors_forced_dimensions,
        test_initial_global_rebuild_handles_vertical_and_negative_directions,
        test_validation_rejects_invalid_inputs,
        test_global_rebuild_preserves_visible_existing_windows,
        test_global_rebuild_handles_multiple_added_windows,
        test_global_rebuild_handles_multiple_removed_windows,
        test_global_rebuild_without_last_layout_is_dense,
        test_global_rebuild_preserves_forced_dimensions,
        test_global_rebuild_rejects_invalid_forced_dimension,
        test_local_event_requires_last_layout,
        test_window_added_splits_visible_auto_window,
        test_window_added_prefers_visible_split_source,
        test_window_added_appends_when_no_split_exists,
        test_window_added_appends_adjacent_for_negative_scroll_directions,
        test_window_added_does_not_split_forced_source,
        test_window_removed_can_preserve_remaining_rects,
        test_window_removed_trailing_window_reduces_extent,
        test_window_removed_preserves_trailing_full_height_hole_and_reduces_extent,
        test_window_removed_compacts_full_height_hole,
        test_window_removed_compacts_full_height_hole_leftward_scroll,
        test_window_removed_compacts_full_width_hole_upward_scroll,
        test_window_removed_does_not_resize_forced_adjacent_window,
        test_window_removed_fills_partial_hole_by_shrinking_column_when_same_width_is_unavailable,
        test_window_removed_fills_partial_hole_on_vertical_scroll_axis,
        test_window_removed_missing_previous_rect_uses_global_rebuild,
        test_dimension_forced_resizes_target_locally,
        test_dimension_forced_pushes_overlapping_auto_neighbor,
        test_dimension_forced_compacts_full_height_hole,
        test_dimension_forced_does_not_push_forced_neighbor_locally,
        test_dimension_forced_rejects_invalid_or_mismatched_key,
        test_dimension_auto_shrinks_large_forced_window_and_reduces_extent,
        test_dimension_auto_grows_small_forced_window_when_no_compaction_gain_exists,
        test_dimension_auto_fills_visible_gap_without_preferring_previous_forced_dimension,
        test_dimension_auto_rejects_target_that_is_still_forced,
        test_move_right_swaps_with_compatible_neighbor,
        test_move_left_swaps_with_compatible_neighbor,
        test_move_up_and_down_swap_vertically,
        test_move_splits_auto_neighbor_when_swap_is_incompatible,
        test_move_preserves_forced_dimensions_on_swap,
        test_move_without_progress_is_noop,
        test_zero_targets_initial_layout,
    },
}
