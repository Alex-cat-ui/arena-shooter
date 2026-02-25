extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")
const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")


class FakeNav extends Node:
	func room_id_at_point(_p: Vector2) -> int:
		return 0

	func build_path_points(_from_pos: Vector2, to_pos: Vector2) -> Array[Vector2]:
		return [to_pos]

	func nav_path_length(from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> float:
		return from_pos.distance_to(to_pos)


class FakeEnemy extends CharacterBody2D:
	var entity_id: int = 0
	var is_dead: bool = false
	var scanner_allowed: bool = true

	func set_flashlight_scanner_allowed(allowed: bool) -> void:
		scanner_allowed = allowed


var embedded_mode: bool = false
var _t := TestHelpers.new()
var _saved_ai_balance: Dictionary = {}
var _saved_stealth_canon: Dictionary = {}


func _ready() -> void:
	if embedded_mode:
		return
	var result := run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("TEAM CONTAIN WITH FLASHLIGHT PRESSURE TEST")
	print("============================================================")

	_snapshot_globals()
	_test_hold_role_gets_scanner_when_no_pressure_in_squad()
	_test_flank_enemy_compute_flashlight_returns_false_despite_alert()
	_test_pressure_enemy_compute_flashlight_passes_when_allowed()
	_test_no_squad_default_scanner_allowed_true()
	_restore_globals()

	_t.summary("TEAM CONTAIN WITH FLASHLIGHT PRESSURE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _snapshot_globals() -> void:
	if GameConfig and GameConfig.ai_balance is Dictionary:
		_saved_ai_balance = (GameConfig.ai_balance as Dictionary).duplicate(true)
	if GameConfig and GameConfig.stealth_canon is Dictionary:
		_saved_stealth_canon = (GameConfig.stealth_canon as Dictionary).duplicate(true)


func _restore_globals() -> void:
	if not GameConfig:
		return
	if _saved_ai_balance.is_empty() or _saved_stealth_canon.is_empty():
		GameConfig.reset_to_defaults()
		return
	GameConfig.ai_balance = _saved_ai_balance.duplicate(true)
	GameConfig.stealth_canon = _saved_stealth_canon.duplicate(true)


func _set_scanner_cap(cap: int) -> void:
	if not GameConfig or not (GameConfig.ai_balance is Dictionary):
		return
	var ai_balance := (GameConfig.ai_balance as Dictionary).duplicate(true)
	var squad := (ai_balance.get("squad", {}) as Dictionary).duplicate(true)
	squad["flashlight_scanner_cap"] = cap
	ai_balance["squad"] = squad
	GameConfig.ai_balance = ai_balance


func _ensure_alert_flashlight_policy_active() -> void:
	if not GameConfig:
		return
	var canon := {}
	if GameConfig.stealth_canon is Dictionary:
		canon = (GameConfig.stealth_canon as Dictionary).duplicate(true)
	canon["flashlight_works_in_alert"] = true
	GameConfig.stealth_canon = canon


func _make_squad_fixture() -> Dictionary:
	var player := Node2D.new()
	player.global_position = Vector2.ZERO
	add_child(player)
	var entities := Node2D.new()
	add_child(entities)
	var nav := FakeNav.new()
	add_child(nav)
	var squad = ENEMY_SQUAD_SYSTEM_SCRIPT.new()
	add_child(squad)
	squad.initialize(player, nav, entities)
	return {"player": player, "entities": entities, "nav": nav, "squad": squad}


func _free_fixture(fixture: Dictionary) -> void:
	for key in ["squad", "nav", "entities", "player"]:
		var node := fixture.get(key, null) as Node
		if node and is_instance_valid(node):
			node.free()


func _register_enemy_with_role(fixture: Dictionary, enemy_id: int, role: int) -> FakeEnemy:
	var entities := fixture.get("entities", null) as Node2D
	var squad = fixture.get("squad", null)
	var enemy := FakeEnemy.new()
	enemy.entity_id = enemy_id
	enemy.global_position = Vector2(24.0 * float(enemy_id), 0.0)
	entities.add_child(enemy)
	enemy.add_to_group("enemies")
	squad.register_enemy(enemy_id, enemy)
	var member := (squad._members.get(enemy_id, {}) as Dictionary).duplicate(true)
	member["role"] = role
	squad._members[enemy_id] = member
	return enemy


func _new_enemy() -> Enemy:
	var enemy := ENEMY_SCRIPT.new()
	enemy.initialize(9302, "zombie")
	return enemy


func _test_hold_role_gets_scanner_when_no_pressure_in_squad() -> void:
	_set_scanner_cap(2)
	var fixture := _make_squad_fixture()
	var squad = fixture.get("squad", null)
	_register_enemy_with_role(fixture, 1, squad.Role.HOLD)
	_register_enemy_with_role(fixture, 2, squad.Role.HOLD)
	_register_enemy_with_role(fixture, 3, squad.Role.HOLD)
	squad.recompute_now()

	_t.run_test("HOLD #1 gets scanner when no PRESSURE exists", squad.get_scanner_allowed(1))
	_t.run_test("HOLD #2 gets scanner when no PRESSURE exists", squad.get_scanner_allowed(2))
	_t.run_test("HOLD #3 blocked by cap=2", not squad.get_scanner_allowed(3))

	_free_fixture(fixture)


func _test_flank_enemy_compute_flashlight_returns_false_despite_alert() -> void:
	_ensure_alert_flashlight_policy_active()
	var enemy := _new_enemy()
	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("flank flashlight setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		enemy.free()
		return
	enemy.call("set_flashlight_scanner_allowed", false)
	detection_runtime.call("set_state_value", "_flashlight_activation_delay_timer", 0.0)
	var active := bool(detection_runtime.call("compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.ALERT))
	_t.run_test("Scanner policy blocks ALERT flashlight when scanner slot denied", not active)
	enemy.free()


func _test_pressure_enemy_compute_flashlight_passes_when_allowed() -> void:
	_ensure_alert_flashlight_policy_active()
	var enemy := _new_enemy()
	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("pressure flashlight setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		enemy.free()
		return
	enemy.call("set_flashlight_scanner_allowed", true)
	detection_runtime.call("set_state_value", "_flashlight_activation_delay_timer", 0.0)
	var active := bool(detection_runtime.call("compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.ALERT))
	_t.run_test("Scanner-allowed enemy keeps ALERT flashlight policy active", active)
	enemy.free()


func _test_no_squad_default_scanner_allowed_true() -> void:
	_ensure_alert_flashlight_policy_active()
	var enemy := _new_enemy()
	var detection_runtime := _detection_runtime(enemy)
	_t.run_test("no-squad flashlight setup: detection runtime exists", detection_runtime != null)
	if detection_runtime == null:
		enemy.free()
		return
	detection_runtime.call("set_state_value", "_flashlight_activation_delay_timer", 0.0)
	var default_allowed := bool(detection_runtime.call("get_state_value", "_flashlight_scanner_allowed", true))
	var active := bool(detection_runtime.call("compute_flashlight_active", ENEMY_ALERT_LEVELS_SCRIPT.ALERT))
	_t.run_test("No squad starts with scanner_allowed=true", default_allowed and enemy.squad_system == null)
	_t.run_test("No squad keeps individual ALERT flashlight policy", active)
	enemy.free()


func _detection_runtime(enemy: Enemy) -> Object:
	var refs := enemy.get_runtime_helper_refs()
	return refs.get("detection_runtime", null) as Object
