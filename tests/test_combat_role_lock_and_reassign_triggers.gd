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
	print("COMBAT ROLE LOCK AND REASSIGN TRIGGERS TEST")
	print("============================================================")

	await _test_role_lock_and_triggered_reassign()

	_t.summary("COMBAT ROLE LOCK AND REASSIGN TRIGGERS RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_role_lock_and_triggered_reassign() -> void:
	var world := Node2D.new()
	add_child(world)
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(6101, "zombie")
	enemy.debug_force_awareness_state("COMBAT")
	enemy.set_process(false)
	enemy.set_physics_process(false)
	var runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("combat_role_runtime", null)
	_t.run_test("combat-role runtime helper is available", runtime != null)
	if runtime == null:
		world.queue_free()
		await get_tree().process_frame
		return

	var assignment := {"role": 0}
	runtime.call("update_runtime", 0.1, true, false, 4.0, false, 0, 420.0, assignment)
	var lock_after_first := float(enemy.get_debug_detection_snapshot().get("combat_role_lock_left", 0.0))
	for _i in range(10):
		runtime.call("update_runtime", 0.1, true, false, 4.0, false, 0, 420.0, assignment)
	var lock_after_one_sec := float(enemy.get_debug_detection_snapshot().get("combat_role_lock_left", 0.0))

	# Early trigger: lost_los > 1.0s
	for _i in range(11):
		runtime.call("update_runtime", 0.1, false, false, 4.0, false, 0, 420.0, assignment)
	var snap_lost_los := enemy.get_debug_detection_snapshot() as Dictionary

	# Early trigger: stuck > 1.2s
	for _i in range(13):
		runtime.call("update_runtime", 0.1, true, true, 0.5, false, 0, 420.0, assignment)
	var snap_stuck := enemy.get_debug_detection_snapshot() as Dictionary

	# Early trigger: path_failed >= 3
	for _i in range(3):
		runtime.call("update_runtime", 0.1, true, true, 0.5, true, 0, 420.0, assignment)
	var snap_path_failed := enemy.get_debug_detection_snapshot() as Dictionary

	# Early trigger: target_room_changed
	runtime.call("update_runtime", 0.1, true, false, 4.0, false, 1, 420.0, assignment)
	runtime.call("update_runtime", 0.1, true, false, 4.0, false, 2, 420.0, assignment)
	var snap_target_room := enemy.get_debug_detection_snapshot() as Dictionary

	runtime.call("reset_runtime")
	var flank_assignment := {
		"role": Enemy.SQUAD_ROLE_FLANK,
		"slot_role": Enemy.SQUAD_ROLE_FLANK,
		"has_slot": true,
		"path_ok": true,
		"path_status": "ok",
		"path_reason": "ok",
		"slot_path_length": 420.0,
		"slot_path_eta_sec": 2.8,
	}
	runtime.call("update_runtime", 0.1, false, false, 4.0, false, 0, 420.0, flank_assignment)
	var snap_context_flank := enemy.get_debug_detection_snapshot() as Dictionary

	runtime.call("reset_runtime")
	var invalid_flank_assignment := {
		"role": Enemy.SQUAD_ROLE_FLANK,
		"slot_role": Enemy.SQUAD_ROLE_FLANK,
		"has_slot": true,
		"path_ok": true,
		"path_status": "unreachable_policy",
		"path_reason": "policy_blocked",
		"slot_path_length": 420.0,
		"slot_path_eta_sec": 2.8,
	}
	runtime.call("update_runtime", 0.1, false, false, 4.0, false, 0, 420.0, invalid_flank_assignment)
	var snap_context_invalid_flank := enemy.get_debug_detection_snapshot() as Dictionary
	var valid_contact_invalid_flank_role := int(
		runtime.call("resolve_contextual_combat_role", Enemy.SQUAD_ROLE_FLANK, true, 500.0, invalid_flank_assignment)
	)

	runtime.call("reset_runtime")
	runtime.call("update_runtime", 0.1, true, false, 4.0, false, 0, 900.0, assignment)
	var snap_context_pressure := enemy.get_debug_detection_snapshot() as Dictionary

	runtime.call("reset_runtime")
	runtime.call("update_runtime", 0.1, true, false, 4.0, false, 0, 120.0, assignment)
	var snap_context_hold := enemy.get_debug_detection_snapshot() as Dictionary

	_t.run_test("role lock starts near 3.0s", lock_after_first >= 2.8 and lock_after_first <= 3.0)
	_t.run_test("role is not recalculated every tick under lock", lock_after_one_sec >= 1.8 and lock_after_one_sec <= 2.2)
	_t.run_test("early trigger: lost_los reassigns role", String(snap_lost_los.get("combat_role_reassign_reason", "")) == "lost_los")
	_t.run_test("early trigger: stuck reassigns role", String(snap_stuck.get("combat_role_reassign_reason", "")) == "stuck")
	_t.run_test("early trigger: path_failed reassigns role", String(snap_path_failed.get("combat_role_reassign_reason", "")) == "path_failed")
	_t.run_test("early trigger: target_room_changed reassigns role", String(snap_target_room.get("combat_role_reassign_reason", "")) == "target_room_changed")
	_t.run_test(
		"context role: no contact + flank availability picks FLANK",
		int(snap_context_flank.get("combat_role_current", -1)) == Enemy.SQUAD_ROLE_FLANK
	)
	_t.run_test(
		"context role: no contact + invalid flank contract does not keep FLANK",
		int(snap_context_invalid_flank.get("combat_role_current", -1)) != Enemy.SQUAD_ROLE_FLANK
	)
	_t.run_test(
		"context role: valid contact + invalid FLANK falls back to PRESSURE",
		valid_contact_invalid_flank_role == Enemy.SQUAD_ROLE_PRESSURE
	)
	_t.run_test(
		"context role: far contact distance picks PRESSURE",
		int(snap_context_pressure.get("combat_role_current", -1)) == Enemy.SQUAD_ROLE_PRESSURE
	)
	_t.run_test(
		"context role: close contact without flank picks HOLD",
		int(snap_context_hold.get("combat_role_current", -1)) == Enemy.SQUAD_ROLE_HOLD
	)

	world.queue_free()
	await get_tree().process_frame
