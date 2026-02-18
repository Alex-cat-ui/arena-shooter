extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const STEALTH_TEST_CONFIG_SCRIPT := preload("res://src/levels/stealth_test_config.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()
const CANON_CONFIG := {
	"confirm_time_to_engage": 2.50,
	"confirm_decay_rate": 0.275,
	"confirm_grace_window": 0.50,
}


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY SUSPICION TEST")
	print("============================================================")

	_test_confirm_path_not_instant_combat()
	_test_suspicion_accumulates_without_instant_combat()
	_test_only_threshold_confirms_visual_and_enters_combat()
	_test_micro_los_grace_reduced_decay()
	_test_noise_does_not_trigger_combat_or_confirmation()
	_test_flashlight_bonus_requires_los()
	await _test_enemy_debug_snapshot_contract()

	_t.summary("ENEMY SUSPICION RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _profile() -> Dictionary:
	return STEALTH_TEST_CONFIG_SCRIPT.suspicion_profile()


func _test_confirm_path_not_instant_combat() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	var transitions: Array[Dictionary] = awareness.process_confirm(0.1, true, false, false, CANON_CONFIG)
	_t.run_test("confirm path: first LOS tick does not instantly enter COMBAT", not _has_transition(transitions, "CALM", "COMBAT", "confirmed_contact") and awareness.get_state_name() != "COMBAT")


func _test_suspicion_accumulates_without_instant_combat() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness.set_suspicion_profile_enabled(true)
	awareness.process_suspicion(0.1, true, 0.25, false, _profile())
	_t.run_test("suspicion mode: no instant COMBAT on first LOS tick", awareness.get_state_name() != "COMBAT")
	_t.run_test("suspicion mode: suspicion increases on LOS", float(awareness.get_suspicion()) > 0.0)


func _test_only_threshold_confirms_visual_and_enters_combat() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness.set_suspicion_profile_enabled(true)
	var profile := _profile()

	var steps: int = 0
	while awareness.get_state_name() != "COMBAT" and steps < 128:
		awareness.process_suspicion(0.1, true, 1.0, false, profile)
		steps += 1

	_t.run_test("suspicion threshold eventually enters COMBAT", awareness.get_state_name() == "COMBAT")
	_t.run_test("COMBAT in suspicion mode sets confirmed visual", bool(awareness.has_confirmed_visual()))


func _test_micro_los_grace_reduced_decay() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness.set_suspicion_profile_enabled(true)
	var profile := _profile()

	awareness.process_suspicion(1.0, true, 0.5, false, profile)
	var before_loss: float = float(awareness.get_suspicion())
	awareness.process_suspicion(0.1, false, 0.5, false, profile)
	var after_loss: float = float(awareness.get_suspicion())

	var expected_decay := float(profile["suspicion_decay_rate"]) * float(profile["los_grace_decay_mult"]) * 0.1
	var expected_after := clampf(before_loss - expected_decay, 0.0, 1.0)
	_t.run_test("micro LOS loss uses reduced decay", absf(after_loss - expected_after) <= 0.0001)


func _test_noise_does_not_trigger_combat_or_confirmation() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness.set_suspicion_profile_enabled(true)
	awareness.register_noise()

	_t.run_test("noise sets ALERT (not COMBAT)", awareness.get_state_name() == "ALERT")
	_t.run_test("noise does not set confirmed visual", not bool(awareness.has_confirmed_visual()))
	_t.run_test("noise does not max suspicion", float(awareness.get_suspicion()) < 1.0)


func _test_flashlight_bonus_requires_los() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness.set_suspicion_profile_enabled(true)
	var profile := _profile()
	awareness.register_noise() # -> ALERT

	awareness.process_suspicion(1.0, false, 0.4, true, profile)
	var no_los_value: float = float(awareness.get_suspicion())

	awareness.reset()
	awareness.set_suspicion_profile_enabled(true)
	awareness.register_noise() # -> ALERT
	awareness.process_suspicion(1.0, true, 0.4, true, profile)
	var with_los_value: float = float(awareness.get_suspicion())

	var baseline_without_bonus := float(profile["suspicion_gain_rate_alert"]) * 0.4
	_t.run_test("flashlight has no effect without LOS", is_equal_approx(no_los_value, 0.0))
	_t.run_test("flashlight boosts suspicion only with LOS", with_los_value > baseline_without_bonus)


func _test_enemy_debug_snapshot_contract() -> void:
	if RuntimeState:
		RuntimeState.player_hp = 100
		RuntimeState.player_visibility_mul = 1.0
		RuntimeState.is_frozen = false

	var world := Node2D.new()
	add_child(world)
	var entities := Node2D.new()
	world.add_child(entities)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(0.0, 0.0)
	entities.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2(120.0, 0.0)
	entities.add_child(enemy)
	await get_tree().process_frame

	enemy.initialize(9911, "zombie")
	enemy.enable_suspicion_test_profile(_profile())
	enemy.set_flashlight_hit_for_detection(false)
	enemy.runtime_budget_tick(0.1)

	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var has_keys := snapshot.has("state") and snapshot.has("suspicion") and snapshot.has("has_los") and snapshot.has("visibility_factor") and snapshot.has("flashlight_hit") and snapshot.has("confirmed")
	_t.run_test("enemy exposes required debug detection snapshot fields", has_keys)
	_t.run_test("snapshot state is valid enum", int(snapshot.get("state", -1)) >= ENEMY_ALERT_LEVELS_SCRIPT.CALM and int(snapshot.get("state", -1)) <= ENEMY_ALERT_LEVELS_SCRIPT.COMBAT)
	_t.run_test("snapshot suspicion is clamped", float(snapshot.get("suspicion", -1.0)) >= 0.0 and float(snapshot.get("suspicion", 2.0)) <= 1.0)

	world.queue_free()
	await get_tree().process_frame


func _has_transition(transitions: Array[Dictionary], from_state: String, to_state: String, reason: String) -> bool:
	for tr_variant in transitions:
		var tr := tr_variant as Dictionary
		if String(tr.get("from_state", "")) != from_state:
			continue
		if String(tr.get("to_state", "")) != to_state:
			continue
		if String(tr.get("reason", "")) != reason:
			continue
		return true
	return false
