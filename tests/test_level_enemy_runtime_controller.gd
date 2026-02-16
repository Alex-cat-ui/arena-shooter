extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_ENEMY_RUNTIME_CONTROLLER_SCRIPT := preload("res://src/levels/level_enemy_runtime_controller.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class FakeEnemy:
	extends Node2D
	var weapons_enabled: bool = true

	func _init() -> void:
		add_to_group("enemies")


class FakeLevel:
	extends Node2D
	var controller = null
	var ctx = null

	func _apply_enemy_weapon_toggle_to_node_deferred(node: Node) -> void:
		if controller and ctx:
			controller.apply_enemy_weapon_toggle_to_node(ctx, node)


class FakeAggroCoordinator:
	extends Node
	var bind_calls: int = 0
	var init_calls: int = 0
	func bind_context(_entities, _nav, _player) -> void:
		bind_calls += 1
	func initialize(_entities, _nav, _player) -> void:
		init_calls += 1


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("LEVEL ENEMY RUNTIME CONTROLLER TEST")
	print("============================================================")

	await _test_toggle_apply_and_hook()
	await _test_rebind_enemy_aggro_context()

	_t.summary("LEVEL ENEMY RUNTIME CONTROLLER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_toggle_apply_and_hook() -> void:
	var controller = LEVEL_ENEMY_RUNTIME_CONTROLLER_SCRIPT.new()
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	var level := FakeLevel.new()
	level.controller = controller
	level.ctx = ctx
	ctx.level = level
	ctx.entities_container = Node2D.new()
	level.add_child(ctx.entities_container)
	add_child(level)

	var enemy_a := FakeEnemy.new()
	var enemy_b := FakeEnemy.new()
	ctx.entities_container.add_child(enemy_a)
	ctx.entities_container.add_child(enemy_b)

	ctx.enemy_weapons_enabled = false
	controller.apply_enemy_weapon_toggle_to_all(ctx)
	_t.run_test("apply_enemy_weapon_toggle_to_all updates existing enemies", not enemy_a.weapons_enabled and not enemy_b.weapons_enabled)

	var enabled := controller.toggle_enemy_weapons(ctx)
	_t.run_test("toggle_enemy_weapons flips runtime flag", enabled and enemy_a.weapons_enabled and enemy_b.weapons_enabled)

	ctx.enemy_weapons_enabled = false
	controller.bind_enemy_toggle_hook(ctx)
	var enemy_c := FakeEnemy.new()
	ctx.entities_container.add_child(enemy_c)
	await get_tree().process_frame
	await get_tree().process_frame
	_t.run_test("child_entered hook applies toggle to new enemies", enemy_c.weapons_enabled == false)

	controller.unbind_enemy_toggle_hook()
	level.queue_free()
	await get_tree().process_frame


func _test_rebind_enemy_aggro_context() -> void:
	var controller = LEVEL_ENEMY_RUNTIME_CONTROLLER_SCRIPT.new()
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	var root = Node2D.new()
	add_child(root)
	ctx.entities_container = Node2D.new()
	root.add_child(ctx.entities_container)
	ctx.room_nav_system = Node.new()
	root.add_child(ctx.room_nav_system)
	ctx.player = CharacterBody2D.new()
	root.add_child(ctx.player)
	ctx.enemy_aggro_coordinator = FakeAggroCoordinator.new()
	root.add_child(ctx.enemy_aggro_coordinator)

	controller.rebind_enemy_aggro_context(ctx)
	var fake := ctx.enemy_aggro_coordinator as FakeAggroCoordinator
	_t.run_test("rebind_enemy_aggro_context prefers bind_context", fake.bind_calls == 1 and fake.init_calls == 0)

	root.queue_free()
	await get_tree().process_frame
