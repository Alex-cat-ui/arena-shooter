extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const GAME_SYSTEMS_SCRIPT := preload("res://src/systems/game_systems.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


class UpdateSystem:
	extends Node
	var updates: int = 0
	var last_delta: float = 0.0

	func update(delta: float) -> void:
		updates += 1
		last_delta = delta


class RuntimeBudgetSystem:
	extends Node
	var ticks: int = 0

	func runtime_budget_tick(_delta: float) -> bool:
		ticks += 1
		return true


class NoArgUpdateSystem:
	extends Node
	var update_calls: int = 0

	func update() -> void:
		update_calls += 1


class PauseAwareSystem:
	extends Node
	var pause_calls: Array[bool] = []

	func set_paused(paused: bool) -> void:
		pause_calls.append(paused)


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("GAME SYSTEMS RUNTIME TEST")
	print("============================================================")

	await _test_game_systems_runtime_contract()

	_t.summary("GAME SYSTEMS RUNTIME RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_game_systems_runtime_contract() -> void:
	var systems := GAME_SYSTEMS_SCRIPT.new()
	add_child(systems)

	var updater := UpdateSystem.new()
	var budget := RuntimeBudgetSystem.new()
	var no_arg := NoArgUpdateSystem.new()
	var pause_aware := PauseAwareSystem.new()
	add_child(updater)
	add_child(budget)
	add_child(no_arg)
	add_child(pause_aware)

	_t.run_test("register_system accepts known slot", systems.register_system(&"aim_system", updater))
	_t.run_test("register_system rejects unknown slot", not systems.register_system(&"unknown_slot", updater))

	# Duplicate registration of the same instance must still produce a single update call.
	systems.register_system(&"combat_system", updater)
	systems.register_system(&"projectile_system", budget)
	systems.register_system(&"spawner_system", no_arg)
	systems.register_system(&"music_system", pause_aware)

	systems.update_systems(0.25)
	_t.run_test("update(delta) systems are ticked once per frame", updater.updates == 1 and is_equal_approx(updater.last_delta, 0.25))
	_t.run_test("runtime_budget_tick(delta) fallback is supported", budget.ticks == 1)
	_t.run_test("zero-arg update() methods are not called with delta", no_arg.update_calls == 0)

	systems.pause_systems()
	_t.run_test("pause flag is raised", systems.is_paused())
	_t.run_test("set_paused(true) is propagated to registered systems", pause_aware.pause_calls.size() >= 1 and pause_aware.pause_calls[0] == true)

	systems.update_systems(0.4)
	_t.run_test("paused systems are not updated", updater.updates == 1 and budget.ticks == 1)

	systems.resume_systems()
	_t.run_test("pause flag is lowered", not systems.is_paused())
	_t.run_test("set_paused(false) is propagated on resume", pause_aware.pause_calls.size() >= 2 and pause_aware.pause_calls[-1] == false)

	systems.update_systems(0.5)
	_t.run_test("updates resume after resume_systems()", updater.updates == 2 and budget.ticks == 2)

	pause_aware.queue_free()
	no_arg.queue_free()
	budget.queue_free()
	updater.queue_free()
	systems.queue_free()
	await get_tree().process_frame
