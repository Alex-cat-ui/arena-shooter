extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")


class FakeNavService extends Node:
	var player_room_id: int = 0
	var adj_rooms: Array = []
	var door_centers: Dictionary = {}

	func room_id_at_point(_p: Vector2) -> int:
		return player_room_id

	func get_adjacent_room_ids(room_id: int) -> Array:
		if room_id != player_room_id:
			return []
		return adj_rooms.duplicate()

	func get_door_center_between(room_a: int, room_b: int, _anchor: Vector2) -> Vector2:
		return door_centers.get("%d:%d" % [room_a, room_b], Vector2.ZERO) as Vector2


var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("TACTIC CONTAIN ASSIGNS EXIT SLOTS TEST")
	print("============================================================")

	_test_contain_uses_door_positions_when_nav_available()
	_test_contain_slots_have_unique_keys()
	_test_contain_fallback_to_ring_when_no_nav()
	_test_contain_skips_zero_door_center()

	_t.summary("TACTIC CONTAIN ASSIGNS EXIT SLOTS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _make_squad(nav: Node = null):
	var squad = ENEMY_SQUAD_SYSTEM_SCRIPT.new()
	add_child(squad)
	squad.navigation_service = nav
	return squad


func _make_nav(adj: Array, centers: Dictionary) -> FakeNavService:
	var nav := FakeNavService.new()
	nav.adj_rooms = adj.duplicate()
	nav.door_centers = centers.duplicate(true)
	add_child(nav)
	return nav


func _test_contain_uses_door_positions_when_nav_available() -> void:
	var nav := _make_nav([1, 2], {
		"0:1": Vector2(100, 0),
		"0:2": Vector2(0, 100),
	})
	var squad = _make_squad(nav)
	var slots := squad._build_contain_slots_from_exits(Vector2.ZERO) as Array

	var found_a := false
	var found_b := false
	for slot_variant in slots:
		var slot := slot_variant as Dictionary
		var pos := slot.get("position", Vector2.ZERO) as Vector2
		if pos == Vector2(100, 0):
			found_a = true
		if pos == Vector2(0, 100):
			found_b = true

	_t.run_test("Contain exits returns exactly 2 slots", slots.size() == 2)
	_t.run_test("Contain exits includes door center (100,0)", found_a)
	_t.run_test("Contain exits includes door center (0,100)", found_b)

	squad.queue_free()
	nav.queue_free()


func _test_contain_slots_have_unique_keys() -> void:
	var nav := _make_nav([1, 2, 3], {
		"0:1": Vector2(100, 0),
		"0:2": Vector2(0, 100),
		"0:3": Vector2(-100, 0),
	})
	var squad = _make_squad(nav)
	var slots := squad._build_contain_slots_from_exits(Vector2.ZERO) as Array

	var seen := {}
	var unique := true
	for slot_variant in slots:
		var slot := slot_variant as Dictionary
		var key := String(slot.get("key", ""))
		if key == "" or seen.has(key):
			unique = false
		seen[key] = true

	_t.run_test("Contain slot keys are unique", unique and slots.size() == 3)

	squad.queue_free()
	nav.queue_free()


func _test_contain_fallback_to_ring_when_no_nav() -> void:
	var squad = _make_squad(null)
	var slots_by_role := squad._build_slots(Vector2.ZERO) as Dictionary
	var hold_slots := slots_by_role.get(squad.Role.HOLD, []) as Array

	var ring_format := not hold_slots.is_empty()
	for slot_variant in hold_slots:
		var slot := slot_variant as Dictionary
		var key := String(slot.get("key", ""))
		if key.begins_with("hold_exit:"):
			ring_format = false
		if not key.begins_with("1:"):
			ring_format = false

	_t.run_test("Contain falls back to HOLD ring slots when nav missing", ring_format)

	squad.queue_free()


func _test_contain_skips_zero_door_center() -> void:
	var nav := _make_nav([1, 2], {
		"0:1": Vector2.ZERO,
		"0:2": Vector2(64, 96),
	})
	var squad = _make_squad(nav)
	var slots := squad._build_contain_slots_from_exits(Vector2.ZERO) as Array

	var only_valid := slots.size() == 1
	if only_valid:
		var slot := slots[0] as Dictionary
		only_valid = (slot.get("position", Vector2.ZERO) as Vector2) == Vector2(64, 96)

	_t.run_test("Contain skips zero door centers", only_valid)

	squad.queue_free()
	nav.queue_free()
