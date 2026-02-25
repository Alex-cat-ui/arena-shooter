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
	print("ENEMY COMBAT ROLE RUNTIME UNIT TEST")
	print("============================================================")

	await _test_role_runtime_lock_and_reassign_contract()
	await _test_role_runtime_flank_contract_and_contextual_selection()

	_t.summary("ENEMY COMBAT ROLE RUNTIME UNIT RESULTS")
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
	enemy.debug_force_awareness_state("COMBAT")
	enemy.set_process(false)
	enemy.set_physics_process(false)
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("combat_role_runtime", null)
	return {
		"enemy": enemy,
		"runtime": runtime,
	}


func _test_role_runtime_lock_and_reassign_contract() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs: Dictionary = await _spawn_enemy(world, 84701)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("combat-role runtime: helper is available", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	var assignment := {"role": Enemy.SQUAD_ROLE_PRESSURE}
	runtime.call("update_runtime", 0.1, true, false, 4.0, false, 0, 420.0, assignment)
	var lock_after_first := float(enemy.get_debug_detection_snapshot().get("combat_role_lock_left", 0.0))
	for _i in range(10):
		runtime.call("update_runtime", 0.1, true, false, 4.0, false, 0, 420.0, assignment)
	var lock_after_one_sec := float(enemy.get_debug_detection_snapshot().get("combat_role_lock_left", 0.0))

	for _i in range(11):
		runtime.call("update_runtime", 0.1, false, false, 4.0, false, 0, 420.0, assignment)
	var snap_lost_los := enemy.get_debug_detection_snapshot() as Dictionary

	runtime.call("reset_runtime")
	for _i in range(3):
		runtime.call("update_runtime", 0.1, true, true, 0.5, true, 0, 420.0, assignment)
	var snap_path_failed := enemy.get_debug_detection_snapshot() as Dictionary

	_t.run_test("combat-role runtime: lock starts near 3.0s", lock_after_first >= 2.8 and lock_after_first <= 3.0)
	_t.run_test("combat-role runtime: lock decays under stable contact", lock_after_one_sec >= 1.8 and lock_after_one_sec <= 2.2)
	_t.run_test(
		"combat-role runtime: lost_los trigger reassigns",
		String(snap_lost_los.get("combat_role_reassign_reason", "")) == "lost_los"
	)
	_t.run_test(
		"combat-role runtime: path_failed trigger reassigns",
		String(snap_path_failed.get("combat_role_reassign_reason", "")) == "path_failed"
	)

	world.queue_free()
	await get_tree().process_frame


func _test_role_runtime_flank_contract_and_contextual_selection() -> void:
	var world := Node2D.new()
	add_child(world)
	var refs: Dictionary = await _spawn_enemy(world, 84702)
	var enemy := refs.get("enemy", null) as Enemy
	var runtime: Variant = refs.get("runtime", null)

	_t.run_test("combat-role runtime: helper exists for flank contract", runtime != null)
	if runtime == null or enemy == null:
		world.queue_free()
		await get_tree().process_frame
		return

	var valid_flank_assignment := {
		"role": Enemy.SQUAD_ROLE_FLANK,
		"slot_role": Enemy.SQUAD_ROLE_FLANK,
		"has_slot": true,
		"path_ok": true,
		"path_status": "ok",
		"slot_path_length": 420.0,
		"slot_path_eta_sec": 2.8,
	}
	var invalid_flank_assignment := {
		"role": Enemy.SQUAD_ROLE_FLANK,
		"slot_role": Enemy.SQUAD_ROLE_FLANK,
		"has_slot": true,
		"path_ok": true,
		"path_status": "unreachable_policy",
		"slot_path_length": 420.0,
		"slot_path_eta_sec": 2.8,
	}
	var pressure_assignment := {"role": Enemy.SQUAD_ROLE_PRESSURE}

	var valid_contract := bool(runtime.call("assignment_supports_flank_role", valid_flank_assignment))
	var invalid_contract := bool(runtime.call("assignment_supports_flank_role", invalid_flank_assignment))

	runtime.call("reset_runtime")
	runtime.call("update_runtime", 0.1, false, false, 4.0, false, 0, 420.0, valid_flank_assignment)
	var snap_flank := enemy.get_debug_detection_snapshot() as Dictionary

	runtime.call("reset_runtime")
	runtime.call("update_runtime", 0.1, true, false, 4.0, false, 0, 120.0, pressure_assignment)
	var snap_hold := enemy.get_debug_detection_snapshot() as Dictionary

	var invalid_context_role := int(
		runtime.call(
			"resolve_contextual_combat_role",
			Enemy.SQUAD_ROLE_FLANK,
			true,
			500.0,
			invalid_flank_assignment
		)
	)

	_t.run_test("combat-role runtime: flank contract requires path_status=ok", valid_contract and not invalid_contract)
	_t.run_test(
		"combat-role runtime: no-contact + valid flank contract picks FLANK",
		int(snap_flank.get("combat_role_current", -1)) == Enemy.SQUAD_ROLE_FLANK
	)
	_t.run_test(
		"combat-role runtime: invalid FLANK contract falls back to PRESSURE",
		invalid_context_role == Enemy.SQUAD_ROLE_PRESSURE
	)
	_t.run_test(
		"combat-role runtime: close valid-contact pressure picks HOLD",
		int(snap_hold.get("combat_role_current", -1)) == Enemy.SQUAD_ROLE_HOLD
	)

	world.queue_free()
	await get_tree().process_frame
