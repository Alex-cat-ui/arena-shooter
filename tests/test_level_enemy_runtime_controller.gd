extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const LEVEL_CONTEXT_SCRIPT := preload("res://src/levels/level_context.gd")
const LEVEL_ENEMY_RUNTIME_CONTROLLER_SCRIPT := preload("res://src/levels/level_enemy_runtime_controller.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


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

	_test_toggle_api_removed()
	await _test_rebind_enemy_aggro_context()

	_t.summary("LEVEL ENEMY RUNTIME CONTROLLER RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_toggle_api_removed() -> void:
	var controller = LEVEL_ENEMY_RUNTIME_CONTROLLER_SCRIPT.new()
	_t.run_test("toggle_enemy_weapons API removed", not controller.has_method("toggle_enemy_weapons"))
	_t.run_test("bind_enemy_toggle_hook API removed", not controller.has_method("bind_enemy_toggle_hook"))
	_t.run_test("apply_enemy_weapon_toggle_to_all API removed", not controller.has_method("apply_enemy_weapon_toggle_to_all"))


func _test_rebind_enemy_aggro_context() -> void:
	var controller = LEVEL_ENEMY_RUNTIME_CONTROLLER_SCRIPT.new()
	var ctx = LEVEL_CONTEXT_SCRIPT.new()
	var root = Node2D.new()
	add_child(root)
	ctx.entities_container = Node2D.new()
	root.add_child(ctx.entities_container)
	ctx.navigation_service = Node.new()
	root.add_child(ctx.navigation_service)
	ctx.player = CharacterBody2D.new()
	root.add_child(ctx.player)
	ctx.enemy_aggro_coordinator = FakeAggroCoordinator.new()
	root.add_child(ctx.enemy_aggro_coordinator)

	controller.rebind_enemy_aggro_context(ctx)
	var fake := ctx.enemy_aggro_coordinator as FakeAggroCoordinator
	_t.run_test("rebind_enemy_aggro_context prefers bind_context", fake.bind_calls == 1 and fake.init_calls == 0)

	root.queue_free()
	await get_tree().process_frame
