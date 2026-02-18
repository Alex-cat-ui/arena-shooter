extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_RUNTIME_BUDGET_CONTROLLER_SCRIPT := preload("res://src/levels/level_runtime_budget_controller.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeEnemy:
	extends Node2D
	var entity_id: int = 0
	var is_dead: bool = false
	var runtime_budget_enabled: bool = false
	var queued_ticks: int = 0
	var applied_ticks: int = 0

	func _init(p_entity_id: int = 0) -> void:
		entity_id = p_entity_id

	func set_runtime_budget_scheduler_enabled(enabled: bool) -> void:
		runtime_budget_enabled = enabled

	func request_runtime_budget_tick(_delta: float = 0.0) -> bool:
		if is_dead or not runtime_budget_enabled:
			return false
		queued_ticks += 1
		return true

	func flush_tick() -> void:
		if queued_ticks <= 0:
			return
		queued_ticks -= 1
		applied_ticks += 1


class FakeSquadSystem:
	extends Node
	var runtime_budget_scheduler_enabled: bool = false
	var rebuild_calls: int = 0
	var rebuild_success: int = 0
	var _timer: float = 0.0

	func set_runtime_budget_scheduler_enabled(enabled: bool) -> void:
		runtime_budget_scheduler_enabled = enabled

	func runtime_budget_tick(delta: float) -> bool:
		rebuild_calls += 1
		_timer -= delta
		if _timer > 0.0:
			return false
		_timer = 0.2
		rebuild_success += 1
		return true


class FakeNavSystem:
	extends Node
	var calls: int = 0
	var total_processed: int = 0

	func runtime_budget_tick(quota: int) -> int:
		calls += 1
		var processed := mini(maxi(quota, 0), 2)
		total_processed += processed
		return processed


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("ENEMY RUNTIME BUDGET SCHEDULER TEST")
	print("============================================================")

	await _test_round_robin_and_quotas()
	await _test_new_enemy_auto_enrollment()

	_t.summary("ENEMY RUNTIME BUDGET SCHEDULER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_round_robin_and_quotas() -> void:
	var setup := await _create_runtime_world(4)
	var ctx = setup.get("ctx")
	var controller = setup.get("controller")
	var enemies := setup.get("enemies", []) as Array
	var squad: FakeSquadSystem = setup.get("squad") as FakeSquadSystem
	var nav: FakeNavSystem = setup.get("nav") as FakeNavSystem

	controller.frame_budget_ms = 10.0
	controller.enemy_ai_quota = 2
	controller.squad_rebuild_quota = 1
	controller.nav_tasks_quota = 2
	controller.bind(ctx)
	await get_tree().process_frame

	var quotas_ok := true
	for _frame in range(3):
		controller.process_frame(ctx, 1.0 / 60.0)
		var stats := ctx.runtime_budget_last_frame as Dictionary
		var enemy_updates := int(stats.get("enemy_ai_updates", 0))
		var enemy_quota := int(stats.get("enemy_ai_quota", 0))
		var squad_updates := int(stats.get("squad_rebuild_updates", 0))
		var squad_quota := int(stats.get("squad_rebuild_quota", 0))
		var nav_updates := int(stats.get("nav_task_updates", 0))
		var nav_quota := int(stats.get("nav_tasks_quota", 0))
		quotas_ok = quotas_ok and enemy_updates <= enemy_quota and squad_updates <= squad_quota and nav_updates <= nav_quota
		for enemy_variant in enemies:
			var enemy := enemy_variant as FakeEnemy
			enemy.flush_tick()

	var fairness_ok := true
	for enemy_variant in enemies:
		var enemy := enemy_variant as FakeEnemy
		if enemy.applied_ticks <= 0:
			fairness_ok = false
	_t.run_test("Runtime budget caps per-frame quotas", quotas_ok)
	_t.run_test("Round-robin visits all enemies over multiple frames", fairness_ok)
	_t.run_test("Squad system switched to runtime budget mode", squad.runtime_budget_scheduler_enabled)
	_t.run_test("Nav tasks run through runtime budget quota", nav.calls >= 1 and nav.total_processed <= 6)

	await _destroy_runtime_world(setup)


func _test_new_enemy_auto_enrollment() -> void:
	var setup := await _create_runtime_world(1)
	var ctx = setup.get("ctx")
	var controller = setup.get("controller")

	controller.bind(ctx)
	await get_tree().process_frame

	var late_enemy := FakeEnemy.new(9999)
	late_enemy.add_to_group("enemies")
	ctx.entities_container.add_child(late_enemy)
	await get_tree().process_frame

	_t.run_test("Late-joined enemies are auto-enrolled in runtime budget mode", late_enemy.runtime_budget_enabled)

	await _destroy_runtime_world(setup)


func _create_runtime_world(enemy_count: int) -> Dictionary:
	var root := Node2D.new()
	add_child(root)

	var entities := Node2D.new()
	root.add_child(entities)

	var enemies: Array = []
	for i in range(enemy_count):
		var enemy := FakeEnemy.new(1000 + i)
		enemy.add_to_group("enemies")
		entities.add_child(enemy)
		enemies.append(enemy)

	var squad := FakeSquadSystem.new()
	root.add_child(squad)

	var nav := FakeNavSystem.new()
	root.add_child(nav)

	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	ctx.entities_container = entities
	ctx.enemy_squad_system = squad
	ctx.navigation_service = nav

	var controller = LEVEL_RUNTIME_BUDGET_CONTROLLER_SCRIPT.new()
	ctx.runtime_budget_controller = controller

	await get_tree().process_frame
	return {
		"root": root,
		"ctx": ctx,
		"controller": controller,
		"enemies": enemies,
		"squad": squad,
		"nav": nav,
	}


func _destroy_runtime_world(setup: Dictionary) -> void:
	var controller = setup.get("controller")
	if controller and controller.has_method("unbind"):
		controller.unbind()

	var ctx = setup.get("ctx")
	if ctx:
		ctx.runtime_budget_controller = null
		ctx.entities_container = null
		ctx.enemy_squad_system = null
		ctx.navigation_service = null

	var root := setup.get("root") as Node
	if root:
		root.queue_free()
	await get_tree().process_frame
