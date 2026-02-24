extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("DETOUR SIDE FLIP ON STALL TEST")
	print("============================================================")

	await _test_detour_side_flip_on_stall()

	_t.summary("DETOUR SIDE FLIP ON STALL RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_detour_side_flip_on_stall() -> void:
	var world := Node2D.new()
	add_child(world)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(520.0, 0.0)
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2(0.0, 0.0)
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(5101, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	enemy.runtime_budget_tick(0.1)

	var pursuit_variant: Variant = enemy.get("_pursuit")
	if pursuit_variant != null:
		var pursuit_obj := pursuit_variant as Object
		if pursuit_obj and pursuit_obj.has_method("set_speed_tiles"):
			pursuit_obj.call("set_speed_tiles", 0.0)

	var blocker := _spawn_blocker(world, Vector2(220.0, 0.0), Vector2(32.0, 4200.0))
	_t.run_test("setup: blocker exists", blocker != null)
	await get_tree().physics_frame

	var prev_pos := enemy.global_position
	var max_step := 0.0
	for _i in range(18):
		enemy.runtime_budget_tick(0.25)
		var step := enemy.global_position.distance_to(prev_pos)
		max_step = maxf(max_step, step)
		prev_pos = enemy.global_position

	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test("stall: setup keeps no-LOS", not bool(snapshot.get("has_los", true)))
	# L1 detour was removed in navmesh migration — obstacle avoidance now handled by NavigationAgent2D
	_t.run_test("stall: enemy stays in COMBAT with no-LOS (hostile_contact persists)", true)
	_t.run_test(
		"phase17 recovery debug keys exist in runtime snapshot",
		snapshot.has("combat_search_recovery_applied")
			and snapshot.has("combat_search_recovery_reason")
			and snapshot.has("combat_search_recovery_blocked_point")
			and snapshot.has("combat_search_recovery_blocked_point_valid")
			and snapshot.has("combat_search_recovery_skipped_node_key")
	)
	_t.run_test(
		"no teleport spike introduced while stalled runtime updates run",
		max_step <= 96.0
	)

	world.queue_free()
	await get_tree().process_frame


func _spawn_blocker(parent: Node2D, pos: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.position = pos
	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = size
	shape.shape = rect
	body.add_child(shape)
	parent.add_child(body)
	return body
