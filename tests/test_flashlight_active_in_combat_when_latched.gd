extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

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
	print("FLASHLIGHT ACTIVE IN COMBAT WHEN LATCHED TEST")
	print("============================================================")

	await _test_flashlight_active_in_combat_when_latched()

	_t.summary("FLASHLIGHT ACTIVE IN COMBAT WHEN LATCHED RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_flashlight_active_in_combat_when_latched() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("Stealth3ZoneTestController")
	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy

	_t.run_test("setup: controller exists", controller != null)
	_t.run_test("setup: player exists", player != null)
	_t.run_test("setup: enemy exists", enemy != null)
	if controller == null or player == null or enemy == null:
		room.queue_free()
		await get_tree().process_frame
		return

	enemy.set_physics_process(false)
	player.global_position = enemy.global_position + Vector2(300.0, 0.0)
	player.velocity = Vector2.ZERO
	enemy.debug_set_pursuit_facing_for_test(Vector2.RIGHT)

	if controller.has_method("_force_enemy_combat"):
		controller.call("_force_enemy_combat")
	enemy.runtime_budget_tick(0.2)
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"combat setup: state is COMBAT",
		int(snapshot.get("state", ENEMY_ALERT_LEVELS_SCRIPT.CALM)) == ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	)
	_t.run_test("combat setup: enemy is latched", bool(snapshot.get("latched", false)))
	_t.run_test("combat setup: room latch count is non-zero", int(snapshot.get("room_latch_count", 0)) > 0)
	_t.run_test("combat setup: flashlight is active", bool(snapshot.get("flashlight_active", false)))
	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("combat flashlight setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		room.queue_free()
		await get_tree().process_frame
		return
	detection_runtime.call("set_state_value", "_shadow_linger_flashlight", true)
	enemy.runtime_budget_tick(0.2)
	snapshot = enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test("combat + shadow linger keeps flashlight active", bool(snapshot.get("flashlight_active", false)))
	_t.run_test("combat + shadow linger does not drop latch", bool(snapshot.get("latched", false)))
	detection_runtime.call("set_state_value", "_shadow_linger_flashlight", false)
	enemy.runtime_budget_tick(0.2)
	snapshot = enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test(
		"combat flashlight still active after linger reset (combat latch unaffected)",
		bool(snapshot.get("flashlight_active", false))
	)

	player.global_position = enemy.global_position + Vector2(120.0, 260.0)
	enemy.runtime_budget_tick(0.25)
	snapshot = enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test("combat out-of-cone: flashlight stays active", bool(snapshot.get("flashlight_active", false)))
	_t.run_test("combat out-of-cone: no flashlight hit", not bool(snapshot.get("flashlight_hit", true)))
	_t.run_test(
		"combat out-of-cone: reason is cone_miss",
		String(snapshot.get("flashlight_inactive_reason", "")) == "cone_miss"
	)

	room.queue_free()
	await get_tree().process_frame


func _first_member_in_group_under(group_name: String, ancestor: Node) -> Node:
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			return member
	return null


func _detection_runtime(enemy: Enemy) -> Object:
	var refs := enemy.get_runtime_helper_refs()
	return refs.get("detection_runtime", null) as Object
