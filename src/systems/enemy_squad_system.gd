## enemy_squad_system.gd
## Tactical slot assignment around player with stable roles and reservation TTL.
class_name EnemySquadSystem
extends Node

enum Role {
	PRESSURE,
	HOLD,
	FLANK,
}

const REBUILD_INTERVAL_SEC := 0.35
const SLOT_RESERVATION_TTL_SEC := 1.1
const PRESSURE_RADIUS_PX := 380.0
const HOLD_RADIUS_PX := 520.0
const FLANK_RADIUS_PX := 640.0
const PRESSURE_SLOT_COUNT := 6
const HOLD_SLOT_COUNT := 8
const FLANK_SLOT_COUNT := 8
const INVALID_PATH_SCORE_PENALTY := 100000.0

var player_node: Node2D = null
var navigation_service: Node = null
var entities_container: Node = null

var _members: Dictionary = {}           # enemy_id -> {"enemy_ref": WeakRef, "role": int, "assignment": Dictionary}
var _rebuild_timer: float = 0.0
var _clock_sec: float = 0.0
var runtime_budget_scheduler_enabled: bool = false


func initialize(p_player_node: Node2D, p_navigation_service: Node, p_entities_container: Node = null) -> void:
	player_node = p_player_node
	navigation_service = p_navigation_service
	bind_entities_container(p_entities_container)
	_recompute_assignments()


func bind_entities_container(p_entities_container: Node) -> void:
	if entities_container and entities_container.child_entered_tree.is_connected(_on_entity_child_entered):
		entities_container.child_entered_tree.disconnect(_on_entity_child_entered)
	if entities_container and entities_container.child_exiting_tree.is_connected(_on_entity_child_exiting):
		entities_container.child_exiting_tree.disconnect(_on_entity_child_exiting)

	entities_container = p_entities_container
	if not entities_container:
		return
	if not entities_container.child_entered_tree.is_connected(_on_entity_child_entered):
		entities_container.child_entered_tree.connect(_on_entity_child_entered)
	if not entities_container.child_exiting_tree.is_connected(_on_entity_child_exiting):
		entities_container.child_exiting_tree.connect(_on_entity_child_exiting)
	_register_existing_enemies()


func register_enemy(enemy_id: int, enemy_node: Node) -> void:
	if enemy_id <= 0 or enemy_node == null:
		return
	_members[enemy_id] = {
		"enemy_ref": weakref(enemy_node),
		"role": _stable_role_for_enemy_id(enemy_id),
		"assignment": _default_assignment(_stable_role_for_enemy_id(enemy_id)),
	}


func deregister_enemy(enemy_id: int) -> void:
	_members.erase(enemy_id)


func get_assignment(enemy_id: int) -> Dictionary:
	if not _members.has(enemy_id):
		return _default_assignment(_stable_role_for_enemy_id(enemy_id))
	var member := _members[enemy_id] as Dictionary
	var assignment := member.get("assignment", _default_assignment(int(member.get("role", Role.PRESSURE)))) as Dictionary
	return assignment.duplicate(true)


func recompute_now() -> void:
	_recompute_assignments()


func _process(delta: float) -> void:
	if runtime_budget_scheduler_enabled:
		return
	runtime_budget_tick(delta)


func set_runtime_budget_scheduler_enabled(enabled: bool) -> void:
	runtime_budget_scheduler_enabled = enabled
	set_process(not enabled)


func runtime_budget_tick(delta: float) -> bool:
	_clock_sec += maxf(delta, 0.0)
	_rebuild_timer -= delta
	if _rebuild_timer > 0.0:
		return false
	_rebuild_timer = _squad_cfg_float("rebuild_interval_sec", REBUILD_INTERVAL_SEC)
	_recompute_assignments()
	return true


func _recompute_assignments() -> void:
	_cleanup_stale_members()
	if _members.is_empty() or player_node == null or not is_instance_valid(player_node):
		return

	var slots_by_role := _build_slots(player_node.global_position)
	var used_slot_keys := {}
	var ids: Array[int] = []
	for id_variant in _members.keys():
		ids.append(int(id_variant))
	ids.sort()

	for enemy_id in ids:
		var member := _members[enemy_id] as Dictionary
		var enemy := _member_enemy(member)
		var role := int(member.get("role", Role.PRESSURE))
		if enemy == null:
			member["assignment"] = _default_assignment(role)
			_members[enemy_id] = member
			continue

		var slot_pick := _pick_slot_for_enemy(enemy, role, slots_by_role, used_slot_keys)
		if slot_pick.is_empty():
			member["assignment"] = _default_assignment(role)
			_members[enemy_id] = member
			continue

		var slot_key := String(slot_pick.get("key", ""))
		used_slot_keys[slot_key] = true
		member["assignment"] = {
			"role": role,
			"slot_position": slot_pick.get("position", enemy.global_position) as Vector2,
			"slot_key": slot_key,
			"path_ok": bool(slot_pick.get("path_ok", false)),
			"has_slot": true,
			"reserved_until": _clock_sec + _squad_cfg_float("slot_reservation_ttl_sec", SLOT_RESERVATION_TTL_SEC),
		}
		_members[enemy_id] = member


func _pick_slot_for_enemy(enemy: Node2D, preferred_role: int, slots_by_role: Dictionary, used_slot_keys: Dictionary) -> Dictionary:
	var role_priority := _role_priority(preferred_role)
	var best_any := {}
	var best_any_score := INF

	for role in role_priority:
		if not slots_by_role.has(role):
			continue
		var slots := slots_by_role[role] as Array
		var best_for_role := {}
		var best_score := INF
		for slot_variant in slots:
			var slot := slot_variant as Dictionary
			var key := String(slot.get("key", ""))
			if key == "" or used_slot_keys.has(key):
				continue
			var pos := slot.get("position", enemy.global_position) as Vector2
			var path_ok := _is_slot_path_ok(enemy, pos)
			var score := enemy.global_position.distance_to(pos)
			if not path_ok:
				score += _squad_cfg_float("invalid_path_score_penalty", INVALID_PATH_SCORE_PENALTY)
			if score < best_score:
				best_score = score
				best_for_role = {
					"key": key,
					"position": pos,
					"path_ok": path_ok,
				}
		if best_for_role.is_empty():
			continue
		if bool(best_for_role.get("path_ok", false)):
			return best_for_role
		if best_score < best_any_score:
			best_any_score = best_score
			best_any = best_for_role

	return best_any


func _is_slot_path_ok(enemy: Node2D, slot_pos: Vector2) -> bool:
	if navigation_service == null:
		return true
	if navigation_service.has_method("room_id_at_point"):
		var slot_room := int(navigation_service.room_id_at_point(slot_pos))
		if slot_room < 0:
			return false
	if navigation_service.has_method("build_path_points"):
			var path := navigation_service.build_path_points(enemy.global_position, slot_pos) as Array
			if path.is_empty():
				return false
			var tail := path[path.size() - 1] as Vector2
			if tail.distance_to(slot_pos) > _squad_cfg_float("slot_path_tail_tolerance_px", 24.0):
				return false
	return true


func _build_slots(player_pos: Vector2) -> Dictionary:
	return {
		Role.PRESSURE: _build_ring_slots(
			player_pos,
			_squad_cfg_float("pressure_radius_px", PRESSURE_RADIUS_PX),
			_squad_cfg_int("pressure_slot_count", PRESSURE_SLOT_COUNT),
			Role.PRESSURE,
			0.0
		),
		Role.HOLD: _build_ring_slots(
			player_pos,
			_squad_cfg_float("hold_radius_px", HOLD_RADIUS_PX),
			_squad_cfg_int("hold_slot_count", HOLD_SLOT_COUNT),
			Role.HOLD,
			0.0
		),
		Role.FLANK: _build_ring_slots(
			player_pos,
			_squad_cfg_float("flank_radius_px", FLANK_RADIUS_PX),
			_squad_cfg_int("flank_slot_count", FLANK_SLOT_COUNT),
			Role.FLANK,
			PI / float(maxi(_squad_cfg_int("flank_slot_count", FLANK_SLOT_COUNT), 1))
		),
	}


func _build_ring_slots(center: Vector2, radius: float, count: int, role: int, phase: float) -> Array:
	var slots: Array = []
	if count <= 0:
		return slots
	for i in range(count):
		var ang := phase + TAU * float(i) / float(count)
		slots.append({
			"key": "%d:%d" % [role, i],
			"position": center + Vector2.RIGHT.rotated(ang) * radius,
		})
	return slots


func _cleanup_stale_members() -> void:
	var remove_ids: Array[int] = []
	for id_variant in _members.keys():
		var enemy_id := int(id_variant)
		var member := _members[id_variant] as Dictionary
		var enemy := _member_enemy(member)
		if enemy == null:
			remove_ids.append(enemy_id)
			continue
		if "is_dead" in enemy and bool(enemy.is_dead):
			remove_ids.append(enemy_id)
	for enemy_id in remove_ids:
		_members.erase(enemy_id)


func _member_enemy(member: Dictionary) -> Node2D:
	var wref := member.get("enemy_ref", null) as WeakRef
	if wref == null:
		return null
	var node := wref.get_ref() as Node2D
	if node == null or not is_instance_valid(node):
		return null
	return node


func _default_assignment(role: int) -> Dictionary:
	return {
		"role": role,
		"slot_position": Vector2.ZERO,
		"slot_key": "",
		"path_ok": false,
		"has_slot": false,
		"reserved_until": 0.0,
	}


func _stable_role_for_enemy_id(enemy_id: int) -> int:
	var bucket := posmod(enemy_id, 6)
	if bucket == 0 or bucket == 3:
		return Role.PRESSURE
	if bucket == 1 or bucket == 4:
		return Role.HOLD
	return Role.FLANK


func _role_priority(primary_role: int) -> Array[int]:
	match primary_role:
		Role.PRESSURE:
			return [Role.PRESSURE, Role.HOLD, Role.FLANK]
		Role.HOLD:
			return [Role.HOLD, Role.FLANK, Role.PRESSURE]
		Role.FLANK:
			return [Role.FLANK, Role.HOLD, Role.PRESSURE]
		_:
			return [Role.PRESSURE, Role.HOLD, Role.FLANK]


func _register_existing_enemies() -> void:
	if not entities_container:
		return
	for child_variant in entities_container.get_children():
		var enemy := child_variant as Node
		if enemy == null or not enemy.is_in_group("enemies"):
			continue
		if not ("entity_id" in enemy):
			continue
		register_enemy(int(enemy.entity_id), enemy)


func _on_entity_child_entered(node: Node) -> void:
	call_deferred("_register_entered_enemy", node)


func _register_entered_enemy(node: Node) -> void:
	if node == null or not node.is_in_group("enemies"):
		return
	if not ("entity_id" in node):
		return
	register_enemy(int(node.entity_id), node)


func _on_entity_child_exiting(node: Node) -> void:
	if node == null or not ("entity_id" in node):
		return
	deregister_enemy(int(node.entity_id))


func _squad_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("squad"):
		var section := GameConfig.ai_balance["squad"] as Dictionary
		return float(section.get(key, fallback))
	return fallback


func _squad_cfg_int(key: String, fallback: int) -> int:
	if GameConfig and GameConfig.ai_balance.has("squad"):
		var section := GameConfig.ai_balance["squad"] as Dictionary
		return int(section.get(key, fallback))
	return fallback
