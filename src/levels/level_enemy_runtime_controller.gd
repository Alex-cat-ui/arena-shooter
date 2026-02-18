extends RefCounted
class_name LevelEnemyRuntimeController


func rebind_enemy_aggro_context(ctx) -> void:
	if not ctx.enemy_aggro_coordinator:
		return
	if ctx.enemy_aggro_coordinator.has_method("bind_context"):
		ctx.enemy_aggro_coordinator.bind_context(ctx.entities_container, ctx.navigation_service, ctx.player)
		return
	if ctx.enemy_aggro_coordinator.has_method("initialize"):
		ctx.enemy_aggro_coordinator.initialize(ctx.entities_container, ctx.navigation_service, ctx.player)
