extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")

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


func _test_confirm_path_not_instant_combat() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	var transitions: Array[Dictionary] = awareness.process_confirm(0.1, true, false, false, CANON_CONFIG)
	_t.run_test("confirm path: first LOS tick does not instantly enter COMBAT", not _has_transition(transitions, "CALM", "COMBAT", "confirmed_contact") and awareness.get_state_name() != "COMBAT")


func _test_suspicion_accumulates_without_instant_combat() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness.process_confirm(0.1, true, false, false, CANON_CONFIG)
	var snapshot := awareness.get_ui_snapshot()
	_t.run_test("confirm mode: no instant COMBAT on first LOS tick", awareness.get_state_name() != "COMBAT")
	_t.run_test("confirm mode: suspicion increases on LOS", float(awareness.get_suspicion()) > 0.0)
	_t.run_test("confirm mode: confirm progress increases on LOS", float(snapshot.get("confirm01", 0.0)) > 0.0)


func _test_only_threshold_confirms_visual_and_enters_combat() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()

	var steps: int = 0
	while awareness.get_state_name() != "COMBAT" and steps < 128:
		awareness.process_confirm(0.1, true, false, false, CANON_CONFIG)
		steps += 1

	_t.run_test("confirm threshold eventually enters COMBAT", awareness.get_state_name() == "COMBAT")
	_t.run_test("COMBAT in confirm mode sets confirmed visual", bool(awareness.has_confirmed_visual()))


func _test_micro_los_grace_reduced_decay() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness.process_confirm(1.0, true, false, false, CANON_CONFIG)
	var before_loss := float(awareness.get_ui_snapshot().get("confirm01", 0.0))
	awareness.process_confirm(0.1, false, false, false, CANON_CONFIG)
	var during_grace := float(awareness.get_ui_snapshot().get("confirm01", 0.0))
	awareness.process_confirm(0.6, false, false, false, CANON_CONFIG)
	var after_grace := float(awareness.get_ui_snapshot().get("confirm01", 0.0))

	_t.run_test("confirm grace keeps progress before decay window", is_equal_approx(during_grace, before_loss))
	_t.run_test("confirm progress decays after grace window", after_grace < during_grace)


func _test_noise_does_not_trigger_combat_or_confirmation() -> void:
	var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	awareness.reset()
	awareness.register_noise()

	_t.run_test("noise sets ALERT (not COMBAT)", awareness.get_state_name() == "ALERT")
	_t.run_test("noise does not set confirmed visual", not bool(awareness.has_confirmed_visual()))
	_t.run_test("noise does not max suspicion", float(awareness.get_suspicion()) < 1.0)


func _test_flashlight_bonus_requires_los() -> void:
	var without_flashlight = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	without_flashlight.reset()
	without_flashlight.process_confirm(1.0, true, true, false, CANON_CONFIG)
	var without_snapshot := without_flashlight.get_ui_snapshot()

	var with_flashlight = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
	with_flashlight.reset()
	with_flashlight.process_confirm(1.0, true, true, true, CANON_CONFIG)
	var with_snapshot := with_flashlight.get_ui_snapshot()

	_t.run_test("shadow LOS without flashlight does not progress confirm", is_equal_approx(float(without_snapshot.get("confirm01", 0.0)), 0.0))
	_t.run_test("shadow LOS with flashlight opens confirm channel", float(with_snapshot.get("confirm01", 0.0)) > float(without_snapshot.get("confirm01", 0.0)))
	_t.run_test("flashlight in shadow increases suspicion vs no flashlight", float(with_flashlight.get_suspicion()) > float(without_flashlight.get_suspicion()))


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
