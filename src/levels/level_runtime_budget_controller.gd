extends RefCounted
class_name LevelRuntimeBudgetController

const DEFAULT_FRAME_BUDGET_MS := 1.2
const DEFAULT_ENEMY_AI_QUOTA := 6
const DEFAULT_SQUAD_REBUILD_QUOTA := 1
const DEFAULT_NAV_TASKS_QUOTA := 2

var frame_budget_ms: float = DEFAULT_FRAME_BUDGET_MS
var enemy_ai_quota: int = DEFAULT_ENEMY_AI_QUOTA
var squad_rebuild_quota: int = DEFAULT_SQUAD_REBUILD_QUOTA
var nav_tasks_quota: int = DEFAULT_NAV_TASKS_QUOTA

var _ctx = null
var _enemy_rr_cursor: int = 0


func bind(ctx) -> void:
	if _ctx and _ctx.entities_container and is_instance_valid(_ctx.entities_container) and _ctx.entities_container.child_entered_tree.is_connected(_on_entity_child_entered):
		_ctx.entities_container.child_entered_tree.disconnect(_on_entity_child_entered)

	_ctx = ctx
	_enemy_rr_cursor = 0
	_load_config_from_game_config()
	_apply_runtime_budget_mode_to_squad_system()
	_apply_runtime_budget_mode_to_existing_enemies()

	if _ctx and _ctx.entities_container and is_instance_valid(_ctx.entities_container):
		if not _ctx.entities_container.child_entered_tree.is_connected(_on_entity_child_entered):
			_ctx.entities_container.child_entered_tree.connect(_on_entity_child_entered)

	_publish_frame_stats(0, 0, 0, 0.0)


func unbind() -> void:
	if _ctx and _ctx.entities_container and is_instance_valid(_ctx.entities_container) and _ctx.entities_container.child_entered_tree.is_connected(_on_entity_child_entered):
		_ctx.entities_container.child_entered_tree.disconnect(_on_entity_child_entered)
	_ctx = null


func process_frame(ctx, delta: float) -> void:
	if ctx == null:
		return
	if _ctx != ctx:
		bind(ctx)

	var frame_start_usec := Time.get_ticks_usec()
	var budget_usec := int(maxf(frame_budget_ms, 0.0) * 1000.0)

	var enemy_ai_updates := _process_enemy_ai_round_robin(delta, frame_start_usec, budget_usec)
	var squad_rebuild_updates := _process_squad_rebuilds(delta, frame_start_usec, budget_usec)
	var nav_task_updates := _process_nav_tasks(frame_start_usec, budget_usec)

	var spent_ms := float(Time.get_ticks_usec() - frame_start_usec) / 1000.0
	_publish_frame_stats(enemy_ai_updates, squad_rebuild_updates, nav_task_updates, spent_ms)


func _process_enemy_ai_round_robin(delta: float, frame_start_usec: int, budget_usec: int) -> int:
	var quota := maxi(enemy_ai_quota, 0)
	if quota <= 0:
		return 0
	if not _is_budget_available(frame_start_usec, budget_usec):
		return 0

	var enemies := _collect_alive_enemies()
	if enemies.is_empty():
		_enemy_rr_cursor = 0
		return 0
	if _enemy_rr_cursor >= enemies.size():
		_enemy_rr_cursor = 0

	var updates := 0
	var inspected := 0
	var max_inspected := enemies.size()
	while updates < quota and inspected < max_inspected and _is_budget_available(frame_start_usec, budget_usec):
		if _enemy_rr_cursor >= enemies.size():
			_enemy_rr_cursor = 0
		var enemy := enemies[_enemy_rr_cursor] as Node
		_enemy_rr_cursor += 1
		inspected += 1
		if not enemy or not is_instance_valid(enemy):
			continue
		if not enemy.has_method("request_runtime_budget_tick"):
			continue
		var accepted := bool(enemy.call("request_runtime_budget_tick", delta))
		if accepted:
			updates += 1
	return updates


func _process_squad_rebuilds(delta: float, frame_start_usec: int, budget_usec: int) -> int:
	var quota := maxi(squad_rebuild_quota, 0)
	if quota <= 0:
		return 0
	if not _ctx or not _ctx.enemy_squad_system or not is_instance_valid(_ctx.enemy_squad_system):
		return 0
	if not _ctx.enemy_squad_system.has_method("runtime_budget_tick"):
		return 0

	var updates := 0
	while updates < quota and _is_budget_available(frame_start_usec, budget_usec):
		var did_rebuild := bool(_ctx.enemy_squad_system.call("runtime_budget_tick", delta))
		if not did_rebuild:
			break
		updates += 1
	return updates


func _process_nav_tasks(frame_start_usec: int, budget_usec: int) -> int:
	var quota := maxi(nav_tasks_quota, 0)
	if quota <= 0:
		return 0
	if not _is_budget_available(frame_start_usec, budget_usec):
		return 0
	if not _ctx or not _ctx.room_nav_system or not is_instance_valid(_ctx.room_nav_system):
		return 0

	if _ctx.room_nav_system.has_method("runtime_budget_tick"):
		return mini(maxi(int(_ctx.room_nav_system.call("runtime_budget_tick", quota)), 0), quota)
	if _ctx.room_nav_system.has_method("process_runtime_budget_tasks"):
		return mini(maxi(int(_ctx.room_nav_system.call("process_runtime_budget_tasks", quota)), 0), quota)
	return 0


func _collect_alive_enemies() -> Array:
	var enemies: Array = []
	if not _ctx or not _ctx.entities_container or not is_instance_valid(_ctx.entities_container):
		return enemies
	for child_variant in _ctx.entities_container.get_children():
		var node := child_variant as Node
		if not node:
			continue
		if not node.is_in_group("enemies"):
			continue
		if "is_dead" in node and bool(node.is_dead):
			continue
		enemies.append(node)
	return enemies


func _apply_runtime_budget_mode_to_existing_enemies() -> void:
	if not _ctx or not _ctx.entities_container or not is_instance_valid(_ctx.entities_container):
		return
	for child_variant in _ctx.entities_container.get_children():
		_enable_runtime_budget_mode_on_enemy(child_variant as Node)


func _apply_runtime_budget_mode_to_squad_system() -> void:
	if not _ctx or not _ctx.enemy_squad_system or not is_instance_valid(_ctx.enemy_squad_system):
		return
	if _ctx.enemy_squad_system.has_method("set_runtime_budget_scheduler_enabled"):
		_ctx.enemy_squad_system.call("set_runtime_budget_scheduler_enabled", true)


func _enable_runtime_budget_mode_on_enemy(enemy: Node) -> void:
	if not enemy or not is_instance_valid(enemy):
		return
	if not enemy.is_in_group("enemies"):
		return
	if enemy.has_method("set_runtime_budget_scheduler_enabled"):
		enemy.call("set_runtime_budget_scheduler_enabled", true)


func _on_entity_child_entered(node: Node) -> void:
	call_deferred("_enable_runtime_budget_mode_on_enemy", node)


func _is_budget_available(frame_start_usec: int, budget_usec: int) -> bool:
	if budget_usec <= 0:
		return false
	return Time.get_ticks_usec() - frame_start_usec < budget_usec


func _load_config_from_game_config() -> void:
	frame_budget_ms = DEFAULT_FRAME_BUDGET_MS
	enemy_ai_quota = DEFAULT_ENEMY_AI_QUOTA
	squad_rebuild_quota = DEFAULT_SQUAD_REBUILD_QUOTA
	nav_tasks_quota = DEFAULT_NAV_TASKS_QUOTA

	if not GameConfig:
		return
	if not GameConfig.ai_balance.has("runtime_budget"):
		return
	var section := GameConfig.ai_balance["runtime_budget"] as Dictionary
	frame_budget_ms = maxf(float(section.get("frame_budget_ms", frame_budget_ms)), 0.05)
	enemy_ai_quota = maxi(int(section.get("enemy_ai_quota", enemy_ai_quota)), 0)
	squad_rebuild_quota = maxi(int(section.get("squad_rebuild_quota", squad_rebuild_quota)), 0)
	nav_tasks_quota = maxi(int(section.get("nav_tasks_quota", nav_tasks_quota)), 0)


func _publish_frame_stats(enemy_ai_updates: int, squad_rebuild_updates: int, nav_task_updates: int, spent_ms: float) -> void:
	if not _ctx:
		return
	_ctx.runtime_budget_last_frame = {
		"frame_budget_ms": frame_budget_ms,
		"spent_ms": spent_ms,
		"enemy_ai_quota": enemy_ai_quota,
		"enemy_ai_updates": enemy_ai_updates,
		"squad_rebuild_quota": squad_rebuild_quota,
		"squad_rebuild_updates": squad_rebuild_updates,
		"nav_tasks_quota": nav_tasks_quota,
		"nav_task_updates": nav_task_updates,
	}
