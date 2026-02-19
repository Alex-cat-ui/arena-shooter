## navigation_enemy_wiring.gd
## Enemy wiring helpers for NavigationService.
class_name NavigationEnemyWiring
extends RefCounted

var _service: Node = null


func _init(service: Node) -> void:
	_service = service


func configure_existing_enemies() -> void:
	if not _service.entities_container:
		return
	for child in _service.entities_container.get_children():
		configure_enemy(child)


func on_entity_child_entered(node: Node) -> void:
	_service.call_deferred("_configure_enemy", node)


func configure_enemy(node: Node) -> void:
	var enemy := node as Node2D
	if not enemy:
		return
	if not enemy.is_in_group("enemies"):
		return
	var room_id := int(_service.room_id_at_point(enemy.global_position))
	enemy.set_meta("room_id", room_id)
	if enemy.has_method("set_room_navigation"):
		enemy.set_room_navigation(_service, room_id)
	if enemy.has_method("set_tactical_systems"):
		enemy.set_tactical_systems(_service.alert_system, _service.squad_system)
	if enemy.has_method("set_zone_director"):
		var zone_director := get_zone_director()
		if zone_director:
			enemy.set_zone_director(zone_director)
	var door_system := resolve_door_system_for_enemy()
	if door_system:
		enemy.set_meta("door_system", door_system)


func get_zone_director() -> Node:
	if bool(_service._zone_director_checked):
		return _service._zone_director_cache
	_service._zone_director_checked = true
	if not _service.get_tree():
		return null
	if not _service.get_tree().root:
		return null
	if _service.get_tree().root.has_node("ZoneDirector"):
		_service._zone_director_cache = _service.get_tree().root.get_node("ZoneDirector")
	return _service._zone_director_cache


func resolve_door_system_for_enemy() -> Node:
	if _service.layout is Dictionary:
		var layout_dict := _service.layout as Dictionary
		if "door_system" in layout_dict:
			return layout_dict.get("door_system", null) as Node
	if _service.layout and not (_service.layout is Dictionary) and _service.layout.has_meta("door_system"):
		return _service.layout.get_meta("door_system") as Node
	if _service.entities_container:
		var level_root: Node = _service.entities_container.get_parent()
		if level_root:
			return level_root.get_node_or_null("LayoutDoorSystem")
	return null
