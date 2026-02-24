extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SQUAD_SYSTEM_SCRIPT := preload("res://src/systems/enemy_squad_system.gd")

class FakeNav extends Node:
	var max_reachable_dist: float = 10000.0

	func room_id_at_point(_p: Vector2) -> int:
		return 0

	func build_policy_valid_path(from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> Dictionary:
		if from_pos.distance_to(to_pos) > max_reachable_dist:
			return {
				"status": "unreachable_geometry",
				"reason": "navmesh_no_path",
				"path_points": [],
			}
		return {
			"status": "ok",
			"reason": "ok",
			"path_points": [to_pos],
		}

	func nav_path_length(from_pos: Vector2, to_pos: Vector2, _enemy: Node = null) -> float:
		if from_pos.distance_to(to_pos) > max_reachable_dist:
			return INF
		return from_pos.distance_to(to_pos)

class FakeEnemy extends CharacterBody2D:
	var entity_id: int = 0
	var is_dead: bool = false


var embedded_mode: bool = false
var _t := TestHelpers.new()

var _player: Node2D = null
var _entities: Node2D = null
var _nav: FakeNav = null
var _squad = null


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY SQUAD SYSTEM TEST")
	print("============================================================")

	_setup()
	_test_unique_slot_reservations()
	_test_role_stability()
	_test_path_fallback()
	_test_assignment_includes_tactical_contract_fields()
	_test_slot_path_length_in_assignment()
	_cleanup()

	_t.summary("ENEMY SQUAD SYSTEM RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _setup() -> void:
	_player = Node2D.new()
	_player.global_position = Vector2.ZERO
	add_child(_player)

	_entities = Node2D.new()
	add_child(_entities)

	for i in range(9):
		var enemy := FakeEnemy.new()
		enemy.entity_id = 1000 + i
		enemy.global_position = Vector2(-260.0 + 32.0 * float(i), -90.0 + 20.0 * float(i % 3))
		_entities.add_child(enemy)
		enemy.add_to_group("enemies")

	_nav = FakeNav.new()
	add_child(_nav)

	_squad = ENEMY_SQUAD_SYSTEM_SCRIPT.new()
	add_child(_squad)
	_squad.initialize(_player, _nav, _entities)
	_squad.recompute_now()


func _cleanup() -> void:
	if _squad:
		_squad.queue_free()
	if _nav:
		_nav.queue_free()
	if _entities:
		_entities.queue_free()
	if _player:
		_player.queue_free()


func _test_unique_slot_reservations() -> void:
	var used := {}
	var with_slots := 0
	for child_variant in _entities.get_children():
		var enemy := child_variant as FakeEnemy
		var assignment := _squad.get_assignment(enemy.entity_id) as Dictionary
		if not bool(assignment.get("has_slot", false)):
			continue
		with_slots += 1
		var key := String(assignment.get("slot_key", ""))
		if key != "":
			used[key] = int(used.get(key, 0)) + 1
	var no_duplicates := true
	for key_variant in used.keys():
		if int(used[key_variant]) > 1:
			no_duplicates = false
	_t.run_test("Slot reservation has no duplicates", no_duplicates)
	_t.run_test("Most enemies receive slot assignments", with_slots >= 7)


func _test_role_stability() -> void:
	var role_before := {}
	for child_variant in _entities.get_children():
		var enemy := child_variant as FakeEnemy
		var assignment := _squad.get_assignment(enemy.entity_id) as Dictionary
		role_before[enemy.entity_id] = int(assignment.get("role", -1))

	_player.global_position = Vector2(120.0, 40.0)
	_squad.recompute_now()

	var stable := true
	for child_variant in _entities.get_children():
		var enemy := child_variant as FakeEnemy
		var role_after := int(_squad.get_assignment(enemy.entity_id).get("role", -1))
		if role_after != int(role_before.get(enemy.entity_id, -999)):
			stable = false
	_t.run_test("Role assignment is stable per enemy_id", stable)


func _test_path_fallback() -> void:
	_nav.max_reachable_dist = 420.0
	_squad.recompute_now()

	var has_path_ok := false
	var has_path_bad := false
	var ok_status_reason_consistent := true
	var bad_status_reason_consistent := true
	for child_variant in _entities.get_children():
		var enemy := child_variant as FakeEnemy
		var assignment := _squad.get_assignment(enemy.entity_id) as Dictionary
		if not bool(assignment.get("has_slot", false)):
			continue
		if bool(assignment.get("path_ok", false)):
			has_path_ok = true
			ok_status_reason_consistent = ok_status_reason_consistent \
				and String(assignment.get("path_status", "")) == "ok" \
				and String(assignment.get("path_reason", "")) == "ok"
		else:
			has_path_bad = true
			bad_status_reason_consistent = bad_status_reason_consistent \
				and String(assignment.get("path_status", "")) != "ok" \
				and String(assignment.get("path_reason", "")) != ""

	_t.run_test("Path-aware assignment keeps reachable slots", has_path_ok)
	_t.run_test("Fallback keeps assignment even when some slots unreachable", has_path_bad or has_path_ok)
	_t.run_test("Reachable assignments publish path_status/path_reason=ok", ok_status_reason_consistent)
	_t.run_test("Unreachable assignments publish non-ok path_status/path_reason", bad_status_reason_consistent)


func _test_assignment_includes_tactical_contract_fields() -> void:
	var has_assigned := false
	var assigned_fields_ok := true
	for child_variant in _entities.get_children():
		var enemy := child_variant as FakeEnemy
		var assignment := _squad.get_assignment(enemy.entity_id) as Dictionary
		if not bool(assignment.get("has_slot", false)):
			continue
		has_assigned = true
		assigned_fields_ok = assigned_fields_ok \
			and assignment.has("slot_role") \
			and assignment.has("path_status") \
			and assignment.has("path_reason") \
			and assignment.has("slot_path_length") \
			and assignment.has("slot_path_eta_sec") \
			and assignment.has("cover_source") \
			and assignment.has("cover_los_break_quality") \
			and assignment.has("cover_score") \
			and typeof(assignment.get("slot_role", null)) == TYPE_INT \
			and typeof(assignment.get("slot_path_eta_sec", null)) == TYPE_FLOAT
	if not has_assigned:
		assigned_fields_ok = false

	var default_assignment := _squad._default_assignment(_squad.Role.HOLD) as Dictionary
	var default_fields_ok: bool = (
		default_assignment.has("slot_role")
		and int(default_assignment.get("slot_role", -1)) == _squad.Role.HOLD
		and default_assignment.has("slot_path_eta_sec")
		and is_inf(float(default_assignment.get("slot_path_eta_sec", 0.0)))
		and default_assignment.has("path_status")
		and default_assignment.has("path_reason")
	)
	_t.run_test("Assignments publish Phase 18 tactical contract fields", assigned_fields_ok)
	_t.run_test("Default assignment includes Phase 18 tactical defaults", default_fields_ok)


func _test_slot_path_length_in_assignment() -> void:
	var default_assignment := _squad._default_assignment(_squad.Role.FLANK) as Dictionary
	_t.run_test(
		"Default assignment includes slot_path_length=INF",
		default_assignment.has("slot_path_length") and is_inf(float(default_assignment.get("slot_path_length", 0.0)))
	)

	_squad.recompute_now()
	var assigned_have_float := true
	var unassigned_have_inf := true
	for child_variant in _entities.get_children():
		var enemy := child_variant as FakeEnemy
		var assignment := _squad.get_assignment(enemy.entity_id) as Dictionary
		if bool(assignment.get("has_slot", false)):
			if not assignment.has("slot_path_length"):
				assigned_have_float = false
				continue
			if typeof(assignment.get("slot_path_length", null)) != TYPE_FLOAT:
				assigned_have_float = false
		else:
			if not is_inf(float(assignment.get("slot_path_length", 0.0))):
				unassigned_have_inf = false

	_t.run_test("Assigned slots publish float slot_path_length", assigned_have_float)
	_t.run_test("Unassigned slots keep slot_path_length=INF", unassigned_have_inf)
