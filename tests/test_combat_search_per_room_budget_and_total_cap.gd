extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeNav:
	extends Node

	var room_centers := {
		0: Vector2(0.0, 0.0),
		1: Vector2(180.0, 0.0),
		2: Vector2(360.0, 0.0),
	}
	var neighbors := {
		0: [1],
		1: [0, 2],
		2: [1],
	}

	func room_id_at_point(p: Vector2) -> int:
		if p.x < 120.0:
			return 0
		if p.x < 280.0:
			return 1
		return 2

	func get_neighbors(room_id: int) -> Array:
		return neighbors.get(room_id, [])

	func get_room_center(room_id: int) -> Vector2:
		return room_centers.get(room_id, Vector2.ZERO)


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("COMBAT SEARCH PER-ROOM BUDGET AND TOTAL CAP TEST")
	print("============================================================")

	await _test_search_budget_and_cap()

	_t.summary("COMBAT SEARCH PER-ROOM BUDGET AND TOTAL CAP RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_search_budget_and_cap() -> void:
	var world := Node2D.new()
	add_child(world)
	var nav := FakeNav.new()
	world.add_child(nav)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2(0.0, 0.0)
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(6201, "zombie")
	enemy.set_room_navigation(nav, 0)
	enemy.debug_force_awareness_state("COMBAT")

	var seen_budgets: Array[float] = []
	var prev_room := int(enemy.get_debug_detection_snapshot().get("combat_search_current_room_id", -1))
	for _i in range(60): # 30s total with 0.5 step
		enemy.call("_update_combat_search_runtime", 0.5, false, Vector2(420.0, 0.0), true)
		var snap := enemy.get_debug_detection_snapshot() as Dictionary
		var room_id := int(snap.get("combat_search_current_room_id", -1))
		var budget := float(snap.get("combat_search_room_budget_sec", 0.0))
		if room_id != prev_room and budget > 0.0:
			seen_budgets.append(budget)
		prev_room = room_id

	var end_snap := enemy.get_debug_detection_snapshot() as Dictionary
	var total_elapsed := float(end_snap.get("combat_search_total_elapsed_sec", 0.0))
	var cap_hit := bool(end_snap.get("combat_search_total_cap_hit", false))
	var budgets_in_range := not seen_budgets.is_empty()
	for value in seen_budgets:
		budgets_in_range = budgets_in_range and value >= 4.0 and value <= 8.0

	_t.run_test("per-room budget is always within 4..8s", budgets_in_range)
	_t.run_test("combat search total elapsed reaches cap horizon", total_elapsed >= 24.0)
	_t.run_test("combat search total cap flag is raised at/after 24s", cap_hit)

	world.queue_free()
	await get_tree().process_frame
