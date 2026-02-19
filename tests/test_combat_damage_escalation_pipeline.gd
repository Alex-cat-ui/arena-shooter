extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const COMBAT_SYSTEM_SCRIPT := preload("res://src/systems/combat_system.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _hostile_escalation_events: Array[Dictionary] = []
var _damage_dealt_events: Array[Dictionary] = []


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("COMBAT DAMAGE ESCALATION PIPELINE TEST")
	print("============================================================")

	await _test_combat_damage_uses_enemy_apply_damage_pipeline()

	_t.summary("COMBAT DAMAGE ESCALATION PIPELINE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_combat_damage_uses_enemy_apply_damage_pipeline() -> void:
	_hostile_escalation_events.clear()
	_damage_dealt_events.clear()
	_connect_signals()

	var world := Node2D.new()
	add_child(world)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(9101, "zombie")
	enemy.set_physics_process(false)

	var combat := COMBAT_SYSTEM_SCRIPT.new()
	world.add_child(combat)
	await get_tree().process_frame

	var hp_before := enemy.hp
	combat.damage_enemy(enemy, 3, "phase1_pipeline_test")
	_flush_event_bus_once()
	await get_tree().process_frame

	var snap := enemy.get_ui_awareness_snapshot() as Dictionary
	var state_now := int(snap.get("state", -1))
	var hostile_damaged := bool(snap.get("hostile_damaged", false))
	var state_escalated := state_now == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.ALERT) or state_now == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.COMBAT)
	var escalated_once := (
		_hostile_escalation_events.size() == 1
		and int(_hostile_escalation_events[0].get("enemy_id", -1)) == enemy.entity_id
		and String(_hostile_escalation_events[0].get("reason", "")) == "damaged"
	)
	var damage_event_ok := (
		_damage_dealt_events.size() == 1
		and int(_damage_dealt_events[0].get("target_id", -1)) == enemy.entity_id
		and int(_damage_dealt_events[0].get("amount", -1)) == 3
		and String(_damage_dealt_events[0].get("source", "")) == "phase1_pipeline_test"
	)

	_t.run_test("combat->enemy pipeline reduces HP", enemy.hp == hp_before - 3)
	_t.run_test("combat->enemy pipeline marks hostile_damaged", hostile_damaged)
	_t.run_test("combat->enemy pipeline escalates awareness above CALM", state_escalated)
	_t.run_test("combat->enemy pipeline emits hostile_escalation once", escalated_once)
	_t.run_test("combat->enemy pipeline emits damage_dealt once", damage_event_ok)

	_disconnect_signals()
	world.queue_free()
	await get_tree().process_frame


func _connect_signals() -> void:
	if not EventBus:
		return
	if EventBus.has_signal("hostile_escalation") and not EventBus.hostile_escalation.is_connected(_on_hostile_escalation):
		EventBus.hostile_escalation.connect(_on_hostile_escalation)
	if EventBus.has_signal("damage_dealt") and not EventBus.damage_dealt.is_connected(_on_damage_dealt):
		EventBus.damage_dealt.connect(_on_damage_dealt)


func _disconnect_signals() -> void:
	if not EventBus:
		return
	if EventBus.has_signal("hostile_escalation") and EventBus.hostile_escalation.is_connected(_on_hostile_escalation):
		EventBus.hostile_escalation.disconnect(_on_hostile_escalation)
	if EventBus.has_signal("damage_dealt") and EventBus.damage_dealt.is_connected(_on_damage_dealt):
		EventBus.damage_dealt.disconnect(_on_damage_dealt)


func _flush_event_bus_once() -> void:
	if EventBus and EventBus.has_method("_process"):
		EventBus.call("_process", 0.016)


func _on_hostile_escalation(enemy_id: int, reason: String) -> void:
	_hostile_escalation_events.append({
		"enemy_id": enemy_id,
		"reason": reason,
	})


func _on_damage_dealt(target_id: int, amount: int, source: String) -> void:
	_damage_dealt_events.append({
		"target_id": target_id,
		"amount": amount,
		"source": source,
	})
