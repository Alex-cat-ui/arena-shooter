extends RefCounted
class_name LevelEnemyRuntimeController

var _ctx = null


func bind_enemy_toggle_hook(ctx) -> void:
	_ctx = ctx
	if not ctx.entities_container:
		return
	if not ctx.entities_container.child_entered_tree.is_connected(_on_entity_child_entered_enemy_toggle):
		ctx.entities_container.child_entered_tree.connect(_on_entity_child_entered_enemy_toggle)


func unbind_enemy_toggle_hook() -> void:
	if _ctx and _ctx.entities_container:
		if _ctx.entities_container.child_entered_tree.is_connected(_on_entity_child_entered_enemy_toggle):
			_ctx.entities_container.child_entered_tree.disconnect(_on_entity_child_entered_enemy_toggle)
	_ctx = null


func _on_entity_child_entered_enemy_toggle(node: Node) -> void:
	if not _ctx or not _ctx.level:
		return
	_ctx.level.call_deferred("_apply_enemy_weapon_toggle_to_node_deferred", node)


func apply_enemy_weapon_toggle_to_all(ctx) -> void:
	if not ctx.entities_container:
		return
	for child in ctx.entities_container.get_children():
		apply_enemy_weapon_toggle_to_node(ctx, child)


func apply_enemy_weapon_toggle_to_node(ctx, node: Node) -> void:
	if not node:
		return
	if not node.is_in_group("enemies"):
		return
	if "weapons_enabled" in node:
		node.weapons_enabled = ctx.enemy_weapons_enabled


func toggle_enemy_weapons(ctx) -> bool:
	ctx.enemy_weapons_enabled = not ctx.enemy_weapons_enabled
	apply_enemy_weapon_toggle_to_all(ctx)
	return ctx.enemy_weapons_enabled


func rebind_enemy_aggro_context(ctx) -> void:
	if not ctx.enemy_aggro_coordinator:
		return
	if ctx.enemy_aggro_coordinator.has_method("bind_context"):
		ctx.enemy_aggro_coordinator.bind_context(ctx.entities_container, ctx.room_nav_system, ctx.player)
		return
	if ctx.enemy_aggro_coordinator.has_method("initialize"):
		ctx.enemy_aggro_coordinator.initialize(ctx.entities_container, ctx.room_nav_system, ctx.player)
