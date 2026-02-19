extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _hostile_escalation_events: Array[Dictionary] = []


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("NON-PLAYER DAMAGE DOES NOT ESCALATE TO COMBAT TEST")
	print("============================================================")

	await _test_non_player_damage_does_not_escalate()

	_t.summary("NON-PLAYER DAMAGE DOES NOT ESCALATE TO COMBAT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_non_player_damage_does_not_escalate() -> void:
	_hostile_escalation_events.clear()
	_connect_signals()

	var world := Node2D.new()
	add_child(world)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(9301, "zombie")

	var hp_before := enemy.hp
	enemy.apply_damage(3, "environment_hazard")
	await get_tree().process_frame

	var snap := enemy.get_ui_awareness_snapshot() as Dictionary
	var state_now := int(snap.get("state", -1))

	_t.run_test("non-player damage: hp reduced", enemy.hp == hp_before - 3)
	_t.run_test(
		"non-player damage: state is not COMBAT",
		state_now != int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.COMBAT)
	)
	_t.run_test(
		"non-player damage: hostile_damaged remains false",
		not bool(snap.get("hostile_damaged", false))
	)
	_t.run_test(
		"non-player damage: hostile_escalation not emitted",
		_hostile_escalation_events.is_empty()
	)

	_disconnect_signals()
	world.queue_free()
	await get_tree().process_frame


func _connect_signals() -> void:
	if not EventBus:
		return
	if EventBus.has_signal("hostile_escalation") and not EventBus.hostile_escalation.is_connected(_on_hostile_escalation):
		EventBus.hostile_escalation.connect(_on_hostile_escalation)


func _disconnect_signals() -> void:
	if not EventBus:
		return
	if EventBus.has_signal("hostile_escalation") and EventBus.hostile_escalation.is_connected(_on_hostile_escalation):
		EventBus.hostile_escalation.disconnect(_on_hostile_escalation)


func _on_hostile_escalation(enemy_id: int, reason: String) -> void:
	_hostile_escalation_events.append({
		"enemy_id": enemy_id,
		"reason": reason,
	})
