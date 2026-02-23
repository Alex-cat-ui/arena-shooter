extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")


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


func _ready() -> void:
	if embedded_mode:
		return
	var result := run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("FLASHLIGHT SINGLE SCANNER ROLE ASSIGNMENT TEST")
	print("============================================================")

	_snapshot_ai_balance()
	_test_only_pressure_gets_scanner_when_cap_1()
	_test_flank_never_gets_scanner_slot()
	_test_pressure_priority_over_hold_within_cap()
	_test_cap_limits_total_scanners_to_configured_value()
	_restore_ai_balance()

	_t.summary("FLASHLIGHT SINGLE SCANNER ROLE ASSIGNMENT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _snapshot_ai_balance() -> void:
	if GameConfig and GameConfig.ai_balance is Dictionary:
		_saved_ai_balance = (GameConfig.ai_balance as Dictionary).duplicate(true)


func _restore_ai_balance() -> void:
	if not GameConfig:
		return
	if _saved_ai_balance.is_empty():
		GameConfig.reset_to_defaults()
		return
	GameConfig.ai_balance = _saved_ai_balance.duplicate(true)


func _set_scanner_cap(cap: int) -> void:
	if not GameConfig or not (GameConfig.ai_balance is Dictionary):
		return
	var ai_balance := (GameConfig.ai_balance as Dictionary).duplicate(true)
	var squad := (ai_balance.get("squad", {}) as Dictionary).duplicate(true)
	squad["flashlight_scanner_cap"] = cap
	ai_balance["squad"] = squad
	GameConfig.ai_balance = ai_balance


func _make_fixture() -> Dictionary:
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

	return {
		"player": player,
		"entities": entities,
		"nav": nav,
		"squad": squad,
	}


func _free_fixture(fixture: Dictionary) -> void:
	for key in ["squad", "nav", "entities", "player"]:
		var node := fixture.get(key, null) as Node
		if node and is_instance_valid(node):
			node.free()


func _register_enemy_with_role(fixture: Dictionary, enemy_id: int, role: int, pos: Vector2 = Vector2.ZERO) -> FakeEnemy:
	var entities := fixture.get("entities", null) as Node2D
	var squad = fixture.get("squad", null)
	var enemy := FakeEnemy.new()
	enemy.entity_id = enemy_id
	enemy.global_position = pos
	entities.add_child(enemy)
	enemy.add_to_group("enemies")
	squad.register_enemy(enemy_id, enemy)
	var member := (squad._members.get(enemy_id, {}) as Dictionary).duplicate(true)
	member["role"] = role
	squad._members[enemy_id] = member
	return enemy


func _test_only_pressure_gets_scanner_when_cap_1() -> void:
	_set_scanner_cap(1)
	var fixture := _make_fixture()
	var squad = fixture.get("squad", null)
	var e1 := _register_enemy_with_role(fixture, 1, squad.Role.PRESSURE, Vector2(20, 0))
	var e2 := _register_enemy_with_role(fixture, 2, squad.Role.HOLD, Vector2(40, 0))
	var e3 := _register_enemy_with_role(fixture, 3, squad.Role.FLANK, Vector2(60, 0))
	squad.recompute_now()

	_t.run_test("Cap=1 gives PRESSURE scanner slot", squad.get_scanner_allowed(1))
	_t.run_test("Cap=1 denies HOLD when PRESSURE present", not squad.get_scanner_allowed(2))
	_t.run_test("Cap=1 denies FLANK scanner slot", not squad.get_scanner_allowed(3))
	_t.run_test(
		"Scanner push calls mirror squad scanner map",
		e1.scanner_allowed == squad.get_scanner_allowed(1)
			and e2.scanner_allowed == squad.get_scanner_allowed(2)
			and e3.scanner_allowed == squad.get_scanner_allowed(3)
	)

	_free_fixture(fixture)


func _test_flank_never_gets_scanner_slot() -> void:
	_set_scanner_cap(10)
	var fixture := _make_fixture()
	var squad = fixture.get("squad", null)
	var e1 := _register_enemy_with_role(fixture, 1, squad.Role.FLANK)
	var e2 := _register_enemy_with_role(fixture, 2, squad.Role.FLANK)
	var e3 := _register_enemy_with_role(fixture, 3, squad.Role.FLANK)
	squad.recompute_now()

	_t.run_test("FLANK id=1 never gets scanner", not squad.get_scanner_allowed(1))
	_t.run_test("FLANK id=2 never gets scanner", not squad.get_scanner_allowed(2))
	_t.run_test("FLANK id=3 never gets scanner", not squad.get_scanner_allowed(3))
	_t.run_test("FLANK push policy sets false on all enemies", not e1.scanner_allowed and not e2.scanner_allowed and not e3.scanner_allowed)

	_free_fixture(fixture)


func _test_pressure_priority_over_hold_within_cap() -> void:
	_set_scanner_cap(1)
	var fixture := _make_fixture()
	var squad = fixture.get("squad", null)
	_register_enemy_with_role(fixture, 6, squad.Role.PRESSURE)
	_register_enemy_with_role(fixture, 2, squad.Role.HOLD)
	_register_enemy_with_role(fixture, 4, squad.Role.HOLD)
	squad.recompute_now()

	_t.run_test("PRESSURE priority beats HOLD under cap", squad.get_scanner_allowed(6))
	_t.run_test("HOLD id=2 blocked when cap consumed by PRESSURE", not squad.get_scanner_allowed(2))
	_t.run_test("HOLD id=4 blocked when cap consumed by PRESSURE", not squad.get_scanner_allowed(4))

	_free_fixture(fixture)


func _test_cap_limits_total_scanners_to_configured_value() -> void:
	_set_scanner_cap(2)
	var fixture := _make_fixture()
	var squad = fixture.get("squad", null)
	_register_enemy_with_role(fixture, 1, squad.Role.PRESSURE)
	_register_enemy_with_role(fixture, 2, squad.Role.PRESSURE)
	_register_enemy_with_role(fixture, 3, squad.Role.PRESSURE)
	_register_enemy_with_role(fixture, 4, squad.Role.PRESSURE)
	squad.recompute_now()

	var total := 0
	for enemy_id in [1, 2, 3, 4]:
		if squad.get_scanner_allowed(enemy_id):
			total += 1
	_t.run_test("Cap=2 grants scanner to lowest PRESSURE id #1", squad.get_scanner_allowed(1))
	_t.run_test("Cap=2 grants scanner to lowest PRESSURE id #2", squad.get_scanner_allowed(2))
	_t.run_test("Cap=2 blocks PRESSURE id #3", not squad.get_scanner_allowed(3))
	_t.run_test("Cap=2 limits total scanner slots to 2", total == 2 and not squad.get_scanner_allowed(4))

	_free_fixture(fixture)
