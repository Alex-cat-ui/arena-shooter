extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_COMBAT_SEARCH_RUNTIME_SCRIPT := preload("res://src/entities/enemy_combat_search_runtime.gd")
const ENEMY_FIRE_CONTROL_RUNTIME_SCRIPT := preload("res://src/entities/enemy_fire_control_runtime.gd")
const ENEMY_COMBAT_ROLE_RUNTIME_SCRIPT := preload("res://src/entities/enemy_combat_role_runtime.gd")
const ENEMY_ALERT_LATCH_RUNTIME_SCRIPT := preload("res://src/entities/enemy_alert_latch_runtime.gd")
const ENEMY_DETECTION_RUNTIME_SCRIPT := preload("res://src/entities/enemy_detection_runtime.gd")
const ENEMY_DEBUG_SNAPSHOT_RUNTIME_SCRIPT := preload("res://src/entities/enemy_debug_snapshot_runtime.gd")

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
	print("ENEMY RUNTIME HELPERS EXIST TEST")
	print("============================================================")

	_test_runtime_scripts_exist_and_load()
	await _test_enemy_wires_runtime_helpers()

	_t.summary("ENEMY RUNTIME HELPERS EXIST RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_runtime_scripts_exist_and_load() -> void:
	var paths := [
		"res://src/entities/enemy_combat_search_runtime.gd",
		"res://src/entities/enemy_fire_control_runtime.gd",
		"res://src/entities/enemy_combat_role_runtime.gd",
		"res://src/entities/enemy_alert_latch_runtime.gd",
		"res://src/entities/enemy_detection_runtime.gd",
		"res://src/entities/enemy_debug_snapshot_runtime.gd",
	]
	for path in paths:
		var script := load(path)
		_t.run_test("runtime script loads: %s" % path, script is GDScript)


func _test_enemy_wires_runtime_helpers() -> void:
	var world := Node2D.new()
	add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(56001, "zombie")

	var refs := enemy.get_runtime_helper_refs() as Dictionary
	var keys_ok := (
		refs.has("combat_search_runtime")
		and refs.has("fire_control_runtime")
		and refs.has("combat_role_runtime")
		and refs.has("alert_latch_runtime")
		and refs.has("detection_runtime")
		and refs.has("debug_snapshot_runtime")
	)
	_t.run_test("enemy publishes all runtime helper refs", keys_ok)
	if not keys_ok:
		world.queue_free()
		await get_tree().process_frame
		return

	var combat_search_runtime = refs.get("combat_search_runtime", null)
	var fire_control_runtime = refs.get("fire_control_runtime", null)
	var combat_role_runtime = refs.get("combat_role_runtime", null)
	var alert_latch_runtime = refs.get("alert_latch_runtime", null)
	var detection_runtime = refs.get("detection_runtime", null)
	var debug_snapshot_runtime = refs.get("debug_snapshot_runtime", null)

	_t.run_test("combat_search_runtime wired", combat_search_runtime != null and combat_search_runtime.get_script() == ENEMY_COMBAT_SEARCH_RUNTIME_SCRIPT)
	_t.run_test("fire_control_runtime wired", fire_control_runtime != null and fire_control_runtime.get_script() == ENEMY_FIRE_CONTROL_RUNTIME_SCRIPT)
	_t.run_test("combat_role_runtime wired", combat_role_runtime != null and combat_role_runtime.get_script() == ENEMY_COMBAT_ROLE_RUNTIME_SCRIPT)
	_t.run_test("alert_latch_runtime wired", alert_latch_runtime != null and alert_latch_runtime.get_script() == ENEMY_ALERT_LATCH_RUNTIME_SCRIPT)
	_t.run_test("detection_runtime wired", detection_runtime != null and detection_runtime.get_script() == ENEMY_DETECTION_RUNTIME_SCRIPT)
	_t.run_test("debug_snapshot_runtime wired", debug_snapshot_runtime != null and debug_snapshot_runtime.get_script() == ENEMY_DEBUG_SNAPSHOT_RUNTIME_SCRIPT)

	var owner_bound_ok := true
	for helper in [combat_search_runtime, fire_control_runtime, combat_role_runtime, alert_latch_runtime, detection_runtime, debug_snapshot_runtime]:
		if helper == null:
			owner_bound_ok = false
			break
		if not helper.has_method("get_owner"):
			owner_bound_ok = false
			break
		if helper.get_owner() != enemy:
			owner_bound_ok = false
			break
	_t.run_test("all runtime helpers are bound to enemy owner", owner_bound_ok)

	world.queue_free()
	await get_tree().process_frame
