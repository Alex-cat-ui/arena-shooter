extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")
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
	print("SUSPICIOUS FLASHLIGHT 30 PERCENT SEEDED TEST")
	print("============================================================")

	_test_seeded_suspicious_shadow_scan_flashlight_is_reproducible_same_entity_same_ticks()
	_test_seeded_suspicious_shadow_scan_flashlight_hits_exactly_30_of_100_ticks()
	_test_seeded_suspicious_shadow_scan_flashlight_changes_with_entity_id_same_ticks()
	_test_suspicious_flashlight_gate_is_off_when_shadow_scan_inactive()

	_t.summary("SUSPICIOUS FLASHLIGHT 30 PERCENT SEEDED RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_seeded_suspicious_shadow_scan_flashlight_is_reproducible_same_entity_same_ticks() -> void:
	var enemy := _new_sampling_enemy(true)
	var seq_a := _sample_sequence(enemy, 1501)
	var seq_b := _sample_sequence(enemy, 1501)
	_t.run_test(
		"same entity + same tick window yields reproducible suspicious flashlight sequence",
		seq_a == seq_b
	)
	enemy.free()
	GameConfig.reset_to_defaults()


func _test_seeded_suspicious_shadow_scan_flashlight_hits_exactly_30_of_100_ticks() -> void:
	var enemy := _new_sampling_enemy(true)
	var seq := _sample_sequence(enemy, 1501)
	var active_count := 0
	for active_variant in seq:
		if bool(active_variant):
			active_count += 1
	_t.run_test(
		"suspicious flashlight seeded gate hits exactly 30 of 100 ticks for entity_id=1501",
		active_count == 30
	)
	enemy.free()
	GameConfig.reset_to_defaults()


func _test_seeded_suspicious_shadow_scan_flashlight_changes_with_entity_id_same_ticks() -> void:
	var enemy := _new_sampling_enemy(true)
	var seq_a := _sample_sequence(enemy, 1501)
	var seq_c := _sample_sequence(enemy, 1502)
	var differs := false
	for i in range(100):
		if bool(seq_a[i]) != bool(seq_c[i]):
			differs = true
			break
	_t.run_test(
		"different entity ids produce different suspicious flashlight sequences over same tick window",
		differs
	)
	enemy.free()
	GameConfig.reset_to_defaults()


func _test_suspicious_flashlight_gate_is_off_when_shadow_scan_inactive() -> void:
	var enemy := _new_sampling_enemy(false)
	enemy.entity_id = 1501
	enemy.set("_debug_tick_id", 0)
	var tick0 := bool(enemy.call("_compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS))
	enemy.set("_debug_tick_id", 2)
	var tick2 := bool(enemy.call("_compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS))
	_t.run_test(
		"suspicious flashlight gate is off at tick 0 when shadow scan inactive",
		not tick0
	)
	_t.run_test(
		"suspicious flashlight gate is off at tick 2 when shadow scan inactive",
		not tick2
	)
	enemy.free()
	GameConfig.reset_to_defaults()


func _new_sampling_enemy(shadow_scan_active: bool) -> Enemy:
	GameConfig.reset_to_defaults()
	if GameConfig and GameConfig.stealth_canon is Dictionary:
		var canon := GameConfig.stealth_canon as Dictionary
		canon["flashlight_works_in_alert"] = true
	var enemy := ENEMY_SCRIPT.new()
	enemy.set("_flashlight_activation_delay_timer", 0.0)
	enemy.set_shadow_scan_active(shadow_scan_active)
	enemy.set_flashlight_scanner_allowed(true)
	return enemy


func _sample_sequence(enemy: Enemy, entity_value: int) -> Array:
	var seq: Array = []
	enemy.entity_id = entity_value
	for tick in range(100):
		enemy.set("_debug_tick_id", tick)
		seq.append(bool(enemy.call("_compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS)))
	return seq
