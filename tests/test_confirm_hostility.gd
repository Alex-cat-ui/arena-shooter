extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")

const CANON_CONFIG := {
	"confirm_time_to_engage": 2.50,
	"confirm_decay_rate": 0.275,
	"confirm_grace_window": 0.50,
}

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
	print("CONFIRM HOSTILITY TEST")
	print("============================================================")

	_test_confirm_accumulates_with_visual_no_shadow()
	_test_confirm_zero_in_shadow()
	_test_flashlight_detects_in_shadow()
	_test_confirm_decays_after_grace()
	_test_confirm_no_decay_during_grace()
	_test_damage_sets_hostile_damaged()
	_test_hostile_never_returns_to_calm()
	_test_combat_phase_engaged_on_contact()
	_test_combat_phase_hostile_search_on_los_loss()
	_test_snapshot_returns_all_fields()

	_t.summary("CONFIRM HOSTILITY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_confirm_accumulates_with_visual_no_shadow() -> void:
	var awareness = _new_awareness()
	for _i in range(25):
		awareness.process_confirm(0.1, true, false, false, CANON_CONFIG)
	_t.run_test("confirm_accumulates_with_visual_no_shadow", _confirm01(awareness) >= 1.0)


func _test_confirm_zero_in_shadow() -> void:
	var awareness = _new_awareness()
	for _i in range(25):
		awareness.process_confirm(0.1, true, true, false, CANON_CONFIG)
	_t.run_test("confirm_zero_in_shadow", is_zero_approx(_confirm01(awareness)))


func _test_flashlight_detects_in_shadow() -> void:
	var awareness = _new_awareness()
	for _i in range(25):
		awareness.process_confirm(0.1, true, true, true, CANON_CONFIG)
	_t.run_test("flashlight_detects_in_shadow", _confirm01(awareness) >= 1.0)


func _test_confirm_decays_after_grace() -> void:
	var awareness = _new_awareness()
	while _confirm01(awareness) < 0.5:
		awareness.process_confirm(0.1, true, false, false, CANON_CONFIG)
	var before := _confirm01(awareness)
	for _i in range(20):
		awareness.process_confirm(0.1, false, false, false, CANON_CONFIG)
	var after := _confirm01(awareness)
	_t.run_test("confirm_decays_after_grace", before >= 0.5 and after < 0.5)


func _test_confirm_no_decay_during_grace() -> void:
	var awareness = _new_awareness()
	while _confirm01(awareness) < 0.5:
		awareness.process_confirm(0.1, true, false, false, CANON_CONFIG)
	var before := _confirm01(awareness)
	for _i in range(3):
		awareness.process_confirm(0.1, false, false, false, CANON_CONFIG)
	var after := _confirm01(awareness)
	_t.run_test("confirm_no_decay_during_grace", absf(after - before) <= 0.0001)


func _test_damage_sets_hostile_damaged() -> void:
	var awareness = _new_awareness()
	awareness._transition_to_combat_from_damage()
	var snap := awareness.get_ui_snapshot() as Dictionary
	_t.run_test(
		"damage_sets_hostile_damaged",
		bool(snap.get("hostile_damaged", false)) and int(snap.get("state", -1)) == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.COMBAT)
	)


func _test_hostile_never_returns_to_calm() -> void:
	var awareness = _new_awareness()
	awareness.hostile_contact = true
	awareness.register_reinforcement()
	for _i in range(300):
		awareness.process_confirm(0.1, false, false, false, CANON_CONFIG)
	_t.run_test("hostile_never_returns_to_calm", awareness.get_state_name() == "COMBAT")


func _test_combat_phase_engaged_on_contact() -> void:
	var awareness = _new_awareness()
	for _i in range(25):
		awareness.process_confirm(0.1, true, false, false, CANON_CONFIG)
	var snap := awareness.get_ui_snapshot() as Dictionary
	_t.run_test(
		"combat_phase_engaged_on_contact",
		int(snap.get("state", -1)) == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.COMBAT)
			and int(snap.get("combat_phase", -1)) == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.CombatPhase.ENGAGED)
	)


func _test_combat_phase_hostile_search_on_los_loss() -> void:
	var awareness = _new_awareness()
	for _i in range(25):
		awareness.process_confirm(0.1, true, false, false, CANON_CONFIG)
	for _i in range(10):
		awareness.process_confirm(0.1, false, false, false, CANON_CONFIG)
	var snap := awareness.get_ui_snapshot() as Dictionary
	_t.run_test(
		"combat_phase_hostile_search_on_los_loss",
		int(snap.get("combat_phase", -1)) == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.CombatPhase.HOSTILE_SEARCH)
	)


func _test_snapshot_returns_all_fields() -> void:
	var awareness = _new_awareness()
	var snap := awareness.get_ui_snapshot() as Dictionary
	var has_all_keys := (
		snap.has("state")
		and snap.has("combat_phase")
		and snap.has("confirm01")
		and snap.has("hostile_contact")
		and snap.has("hostile_damaged")
	)
	_t.run_test("snapshot_returns_all_fields", has_all_keys)


func _new_awareness():
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	return awareness


func _confirm01(awareness) -> float:
	var snap := awareness.get_ui_snapshot() as Dictionary
	return float(snap.get("confirm01", 0.0))
