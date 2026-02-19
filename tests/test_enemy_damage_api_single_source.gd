extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
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
	print("ENEMY DAMAGE API SINGLE SOURCE TEST")
	print("============================================================")

	await _test_take_damage_uses_canonical_damage_flow()
	await _test_apply_damage_emits_single_event_path()

	_t.summary("ENEMY DAMAGE API SINGLE SOURCE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_take_damage_uses_canonical_damage_flow() -> void:
	var world := Node2D.new()
	add_child(world)
	_connect_signals()
	_reset_event_captures()

	var enemy := await _spawn_enemy(world, 9201)
	var hp_before := enemy.hp
	enemy.take_damage(2)
	_flush_event_bus_once()
	await get_tree().process_frame

	var snap := enemy.get_ui_awareness_snapshot() as Dictionary
	var state_now := int(snap.get("state", -1))
	var hostile_damaged := bool(snap.get("hostile_damaged", false))
	var state_escalated := state_now == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.ALERT) or state_now == int(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.COMBAT)
	var escalation_ok := (
		_hostile_escalation_events.size() == 1
		and int(_hostile_escalation_events[0].get("enemy_id", -1)) == enemy.entity_id
		and String(_hostile_escalation_events[0].get("reason", "")) == "damaged"
	)
	var damage_event_ok := (
		_damage_dealt_events.size() == 1
		and int(_damage_dealt_events[0].get("target_id", -1)) == enemy.entity_id
		and int(_damage_dealt_events[0].get("amount", -1)) == 2
		and String(_damage_dealt_events[0].get("source", "")) == "legacy_take_damage"
	)

	_t.run_test("take_damage delegates to canonical flow: hp reduced", enemy.hp == hp_before - 2)
	_t.run_test("take_damage delegates to canonical flow: hostile_damaged true", hostile_damaged)
	_t.run_test("take_damage delegates to canonical flow: state escalated above CALM", state_escalated)
	_t.run_test("take_damage delegates to canonical flow: hostile_escalation once", escalation_ok)
	_t.run_test("take_damage delegates to canonical flow: damage_dealt once with legacy source", damage_event_ok)

	_disconnect_signals()
	world.queue_free()
	await get_tree().process_frame


func _test_apply_damage_emits_single_event_path() -> void:
	var world := Node2D.new()
	add_child(world)
	_connect_signals()
	_reset_event_captures()

	var enemy := await _spawn_enemy(world, 9202)
	var hp_before := enemy.hp
	enemy.apply_damage(4, "api_direct")
	_flush_event_bus_once()
	await get_tree().process_frame

	var damage_event_ok := (
		_damage_dealt_events.size() == 1
		and int(_damage_dealt_events[0].get("target_id", -1)) == enemy.entity_id
		and int(_damage_dealt_events[0].get("amount", -1)) == 4
		and String(_damage_dealt_events[0].get("source", "")) == "api_direct"
	)

	_t.run_test("apply_damage direct path: hp reduced", enemy.hp == hp_before - 4)
	_t.run_test("apply_damage direct path: single damage_dealt event", damage_event_ok)

	_disconnect_signals()
	world.queue_free()
	await get_tree().process_frame


func _spawn_enemy(parent: Node, enemy_id: int) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	parent.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(enemy_id, "zombie")
	enemy.set_physics_process(false)
	return enemy


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


func _reset_event_captures() -> void:
	_hostile_escalation_events.clear()
	_damage_dealt_events.clear()


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
