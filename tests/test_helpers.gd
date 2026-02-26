## test_helpers.gd
## Shared test infrastructure: assertions, layout helpers, and common world setup.
class_name TestHelpers
extends RefCounted

const LAYOUT_SCRIPT := preload("res://src/systems/procedural_layout_v2.gd")
const DOOR_SCRIPT := preload("res://src/systems/door_controller_v3.gd")

var tests_run := 0
var tests_passed := 0

## T4: Error guard state - tracks unexpected push_error/push_warning from production code.
## Full per-call interception is not available in pure GDScript without a C++ extension.
## Enforcement: exit code 1 on any failure; CI detects additional "ERROR:" lines in output.
var _guard_active: bool = false
var _guard_label: String = ""
var _guard_run_at_start: int = 0
var _guard_passed_at_start: int = 0
var _orphan_nodes_baseline: int = -1
var _watchdog_warning_baseline: int = -1


func _init() -> void:
	_orphan_nodes_baseline = _read_orphan_node_count()
	_watchdog_warning_baseline = _read_watchdog_warning_count()


func check(test_name: String, ok: bool) -> void:
	tests_run += 1
	if ok:
		tests_passed += 1
		print("[PASS] %s" % test_name)
	else:
		push_error("[FAIL] %s" % test_name)


func run_test(test_name: String, ok: bool) -> void:
	check(test_name, ok)


func quit_code() -> int:
	return 0 if tests_passed == tests_run else 1


func summary(title: String) -> void:
	_apply_runtime_guards()
	print("")
	print("=".repeat(60))
	print("%s: %d/%d passed" % [title, tests_passed, tests_run])
	print("=".repeat(60))


## T4: Begin an error guard section. Any unexpected test failures between
## begin_error_guard and assert_no_guard_failures indicate a production error leak.
func begin_error_guard(label: String) -> void:
	_guard_active = true
	_guard_label = label
	_guard_run_at_start = tests_run
	_guard_passed_at_start = tests_passed


## T4: End guard and assert that no new unexpected failures occurred beyond expected count.
## expected_new_failures: number of test failures expected to have been introduced.
func assert_no_guard_failures(test_name: String, expected_new_failures: int = 0) -> void:
	_guard_active = false
	var new_failures := (tests_run - tests_passed) - (_guard_run_at_start - _guard_passed_at_start)
	var unexpected := new_failures - expected_new_failures
	run_test(test_name, unexpected <= 0)
	_guard_label = ""


## T4: Fatal assert - if ok is false, this is treated as a non-recoverable test error.
## Use for invariants that must hold for subsequent tests to be meaningful.
func fatal_assert(test_name: String, ok: bool) -> bool:
	run_test(test_name, ok)
	if not ok:
		push_error("[T4-FATAL] Test suite halted: %s" % test_name)
	return ok


func _apply_runtime_guards() -> void:
	var orphan_now := _read_orphan_node_count()
	if _orphan_nodes_baseline >= 0 and orphan_now >= 0:
		run_test(
			"runtime guard: no orphan node leaks",
			orphan_now <= _orphan_nodes_baseline
		)
	var warning_now := _read_watchdog_warning_count()
	if _watchdog_warning_baseline >= 0 and warning_now >= 0:
		run_test(
			"runtime guard: no AIWatchdog runtime warnings",
			warning_now <= _watchdog_warning_baseline
		)


func _read_orphan_node_count() -> int:
	return int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT))


func _read_watchdog_warning_count() -> int:
	if AIWatchdog == null or not AIWatchdog.has_method("get_snapshot"):
		return -1
	var snap := AIWatchdog.get_snapshot() as Dictionary
	if not snap.has("warning_events_total"):
		return -1
	return int(snap.get("warning_events_total", 0))


static func quit_with_result(run: int, passed: int) -> int:
	return 0 if passed == run else 1


# ---------------------------------------------------------------------------
# Static layout helpers
# ---------------------------------------------------------------------------

## Supports both:
##   room_id_at_point(layout, point)
##   room_id_at_point(rooms, void_ids, point)
static func room_id_at_point(layout_or_rooms, p_or_void_ids: Variant, maybe_point: Variant = null) -> int:
	var rooms: Array = []
	var void_ids: Array = []
	var point := Vector2.ZERO

	if maybe_point == null:
		if layout_or_rooms == null:
			return -1
		rooms = layout_or_rooms.rooms as Array
		void_ids = layout_or_rooms._void_ids as Array
		point = p_or_void_ids as Vector2
	else:
		rooms = layout_or_rooms as Array
		void_ids = p_or_void_ids as Array
		point = maybe_point as Vector2

	for i in range(rooms.size()):
		if i in void_ids:
			continue
		var room := rooms[i] as Dictionary
		for rect_variant in (room.get("rects", []) as Array):
			var r := rect_variant as Rect2
			if r.grow(0.25).has_point(point):
				return i
	return -1


static func door_key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]


## Supports both:
##   door_adjacent_room_ids(layout, door)
##   door_adjacent_room_ids(rooms, door, void_ids, wall_thickness)
static func door_adjacent_room_ids(layout_or_rooms, door: Rect2, void_ids: Array = [], wall_thickness: float = 16.0) -> Array:
	var rooms: Array = []
	var resolved_void_ids: Array = void_ids
	var probe := maxf(wall_thickness * 0.8, 8.0)

	if layout_or_rooms is Array:
		rooms = layout_or_rooms as Array
	else:
		rooms = layout_or_rooms.rooms as Array
		resolved_void_ids = layout_or_rooms._void_ids as Array
		probe = maxf(float(layout_or_rooms._door_wall_thickness()) * 0.8, 8.0)

	var ids: Dictionary = {}
	var center := door.get_center()
	if door.size.y > door.size.x:
		var left_id := room_id_at_point(rooms, resolved_void_ids, Vector2(center.x - probe, center.y))
		var right_id := room_id_at_point(rooms, resolved_void_ids, Vector2(center.x + probe, center.y))
		if left_id >= 0:
			ids[left_id] = true
		if right_id >= 0:
			ids[right_id] = true
	else:
		var top_id := room_id_at_point(rooms, resolved_void_ids, Vector2(center.x, center.y - probe))
		var bottom_id := room_id_at_point(rooms, resolved_void_ids, Vector2(center.x, center.y + probe))
		if top_id >= 0:
			ids[top_id] = true
		if bottom_id >= 0:
			ids[bottom_id] = true
	return ids.keys()


## Supports both:
##   is_door_graph_connected(layout)
##   is_door_graph_connected(rooms, doors, void_ids)
static func is_door_graph_connected(layout_or_rooms, doors: Array = [], void_ids: Array = []) -> bool:
	var rooms: Array = []
	var resolved_void_ids: Array = void_ids
	var door_adj: Dictionary = {}

	if layout_or_rooms is Array:
		rooms = layout_or_rooms as Array
		for i in range(rooms.size()):
			door_adj[i] = []
		for door_variant in doors:
			var door := door_variant as Rect2
			var ids := door_adjacent_room_ids(rooms, door, resolved_void_ids)
			if ids.size() != 2:
				continue
			var a := int(ids[0])
			var b := int(ids[1])
			if b not in (door_adj[a] as Array):
				(door_adj[a] as Array).append(b)
			if a not in (door_adj[b] as Array):
				(door_adj[b] as Array).append(a)
	else:
		rooms = layout_or_rooms.rooms as Array
		resolved_void_ids = layout_or_rooms._void_ids as Array
		door_adj = layout_or_rooms._door_adj as Dictionary

	var solid_ids: Array[int] = []
	for i in range(rooms.size()):
		if i in resolved_void_ids:
			continue
		solid_ids.append(i)
	if solid_ids.is_empty():
		return false

	var start_id := solid_ids[0]
	var visited: Dictionary = {start_id: true}
	var queue: Array = [start_id]
	while not queue.is_empty():
		var curr := int(queue.pop_front())
		if not door_adj.has(curr):
			continue
		for n_variant in (door_adj[curr] as Array):
			var ni := int(n_variant)
			if ni in resolved_void_ids:
				continue
			if visited.has(ni):
				continue
			visited[ni] = true
			queue.append(ni)
	return visited.size() == solid_ids.size()


static func count_half_doors(layout) -> int:
	var bad := 0
	for door_variant in layout.doors:
		var door := door_variant as Rect2
		var ids := door_adjacent_room_ids(layout, door)
		if ids.size() != 2:
			bad += 1
	return bad


static func count_overlapping_doors(layout) -> int:
	var overlaps := 0
	for i in range(layout.doors.size()):
		var a := layout.doors[i] as Rect2
		for j in range(i + 1, layout.doors.size()):
			var b := layout.doors[j] as Rect2
			if a.grow(2.0).intersects(b.grow(2.0)):
				overlaps += 1
	return overlaps


static func count_missing_adjacent_doors(layout) -> int:
	var edge_keys_with_doors: Dictionary = {}
	for item_variant in layout._door_map:
		var item := item_variant as Dictionary
		var a := int(item["a"])
		var b := int(item["b"])
		edge_keys_with_doors[door_key(a, b)] = true

	var missing := 0
	var edges: Array = layout._build_room_adjacency_edges()
	for edge_variant in edges:
		var edge := edge_variant as Dictionary
		var a := int(edge["a"])
		var b := int(edge["b"])
		if layout._is_closet_room(a) or layout._is_closet_room(b):
			continue
		if not layout._edge_is_geometrically_doorable(edge):
			continue
		if not (layout._room_requires_full_adjacency(a) or layout._room_requires_full_adjacency(b)):
			continue
		var key := door_key(a, b)
		if not edge_keys_with_doors.has(key):
			missing += 1
	return missing


# ---------------------------------------------------------------------------
# Layout generation helpers
# ---------------------------------------------------------------------------

static func create_dummy_player(parent: Node = null) -> CharacterBody2D:
	var player := CharacterBody2D.new()
	var col_shape := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	col_shape.shape = shape
	player.add_child(col_shape)
	if parent:
		parent.add_child(player)
	return player


static func create_layout_nodes(parent: Node) -> Dictionary:
	var walls := Node2D.new()
	parent.add_child(walls)
	var debug := Node2D.new()
	parent.add_child(debug)
	var player := create_dummy_player(parent)
	return {"walls": walls, "debug": debug, "player": player}


## Generates layout and returns {layout, walls, debug, player}.
static func create_layout(parent: Node, seed_value: int, arena: Rect2, mission: int = 3) -> Dictionary:
	var nodes := create_layout_nodes(parent)
	var layout := LAYOUT_SCRIPT.generate_and_build(
		arena,
		seed_value,
		nodes["walls"] as Node2D,
		nodes["debug"] as Node2D,
		nodes["player"] as Node2D,
		mission
	)
	return {
		"layout": layout,
		"walls": nodes["walls"],
		"debug": nodes["debug"],
		"player": nodes["player"],
	}


# ---------------------------------------------------------------------------
# Door helpers
# ---------------------------------------------------------------------------

static func add_wall(parent: Node2D, center: Vector2, size: Vector2) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.collision_mask = 0
	wall.position = center
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	shape_node.shape = shape
	wall.add_child(shape_node)
	parent.add_child(wall)


## Supports:
##   spawn_mover(parent, pos, layer, mask, group)
##   spawn_mover(parent, pos, initial_velocity)
static func spawn_mover(parent: Node2D, pos: Vector2, layer_or_velocity: Variant = 1, mask: int = 1, group_name: String = "") -> CharacterBody2D:
	var layer := 1
	var initial_velocity := Vector2.ZERO
	if layer_or_velocity is Vector2:
		initial_velocity = layer_or_velocity as Vector2
	else:
		layer = int(layer_or_velocity)

	var mover := CharacterBody2D.new()
	mover.position = pos
	mover.velocity = initial_velocity
	mover.collision_layer = layer
	mover.collision_mask = mask
	if not group_name.is_empty():
		mover.add_to_group(group_name)
	var shape_node := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 12.0
	shape_node.shape = shape
	mover.add_child(shape_node)
	parent.add_child(mover)
	return mover


static func create_horizontal_door_world(parent: Node, opening: Rect2 = Rect2(-60.0, -6.0, 120.0, 12.0), wall_thickness: float = 16.0) -> Dictionary:
	var world := Node2D.new()
	parent.add_child(world)
	add_wall(world, Vector2(-180.0, 0.0), Vector2(240.0, 16.0))
	add_wall(world, Vector2(180.0, 0.0), Vector2(240.0, 16.0))
	var door := DOOR_SCRIPT.new()
	world.add_child(door)
	door.configure_from_opening(opening, wall_thickness)
	return {"root": world, "door": door}
