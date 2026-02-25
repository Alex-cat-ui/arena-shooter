extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
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
	print("ENEMY DETECTION RUNTIME FLASHLIGHT POLICY UNIT TEST")
	print("============================================================")

	await _test_calm_override_and_scanner_gate_contract()
	await _test_suspicious_seeded_bucket_30_percent_contract()
	await _test_latched_combat_keeps_flashlight_contract()

	_t.summary("ENEMY DETECTION RUNTIME FLASHLIGHT POLICY UNIT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _spawn_enemy(world: Node2D, id: int) -> Dictionary:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(id, "zombie")
	enemy.set_process(false)
	enemy.set_physics_process(false)
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("detection_runtime", null)
	return {
		"enemy": enemy,
		"runtime": runtime,
	}


func _test_calm_override_and_scanner_gate_contract() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs := await _spawn_enemy(world, 84961)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("detection runtime flashlight: helper is available", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("set_state_value", "_shadow_check_flashlight_override", true)
	runtime.call("set_state_value", "_flashlight_scanner_allowed", true)
	var calm_active := bool(runtime.call("compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.CALM))

	runtime.call("set_state_value", "_flashlight_scanner_allowed", false)
	var blocked_by_scanner := not bool(runtime.call("compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.CALM))

	_t.run_test("detection runtime flashlight: CALM override enables scanner", calm_active)
	_t.run_test("detection runtime flashlight: scanner gate blocks active flashlight", blocked_by_scanner)

	world.queue_free()
	await get_tree().process_frame


func _test_suspicious_seeded_bucket_30_percent_contract() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs := await _spawn_enemy(world, 1501)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("detection runtime suspicious bucket: helper is available", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("set_state_value", "_shadow_scan_active", true)
	runtime.call("set_state_value", "_shadow_linger_flashlight", false)
	runtime.call("set_state_value", "_flashlight_activation_delay_timer", 0.0)
	runtime.call("set_state_value", "_flashlight_scanner_allowed", true)

	var active_ticks := 0
	for tick in range(100):
		runtime.call("set_state_value", "_debug_tick_id", tick)
		if bool(runtime.call("compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS)):
			active_ticks += 1

	_t.run_test("detection runtime suspicious bucket: active ticks are exactly 30/100", active_ticks == 30)

	world.queue_free()
	await get_tree().process_frame


func _test_latched_combat_keeps_flashlight_contract() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs := await _spawn_enemy(world, 84962)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("detection runtime latched combat: helper is available", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	runtime.call("set_state_value", "_combat_latched", true)
	runtime.call("set_state_value", "_flashlight_scanner_allowed", true)
	runtime.call("set_state_value", "_flashlight_activation_delay_timer", 0.0)
	var active_while_latched := bool(runtime.call("compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.CALM))

	runtime.call("set_state_value", "_combat_latched", false)
	runtime.call("set_state_value", "_shadow_check_flashlight_override", false)
	var inactive_when_not_latched := not bool(runtime.call("compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.CALM))

	_t.run_test("detection runtime latched combat: flashlight stays active from COMBAT latch", active_while_latched)
	_t.run_test("detection runtime latched combat: flashlight deactivates after latch/override clear", inactive_when_not_latched)

	world.queue_free()
	await get_tree().process_frame
