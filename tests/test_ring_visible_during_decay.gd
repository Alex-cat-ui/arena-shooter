extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const STEALTH_TEST_CONFIG_SCRIPT := preload("res://src/levels/stealth_test_config.gd")

var embedded_mode: bool = false
var _t := TestHelpers.new()


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("RING VISIBLE DURING DECAY TEST")
	print("============================================================")

	await _test_ring_visible_during_decay()
	await _test_ring_hidden_combat_even_with_progress()
	await _test_ring_visible_growth_phase()

	_t.summary("RING VISIBLE DURING DECAY RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _spawn_enemy(world: Node2D, seed_id: int) -> Enemy:
	var enemy := ENEMY_SCENE.instantiate() as Enemy
	world.add_child(enemy)
	await get_tree().process_frame
	enemy.initialize(seed_id, "zombie")
	enemy.enable_suspicion_test_profile(STEALTH_TEST_CONFIG_SCRIPT.suspicion_profile())
	await get_tree().process_frame
	# Stop enemy physics so runtime_budget_tick doesn't overwrite awareness_state meta
	enemy.set_physics_process(false)
	return enemy


## In CALM state, ring stays visible as progress decays from 1.0 toward 0.
func _test_ring_visible_during_decay() -> void:
	var world := Node2D.new()
	add_child(world)

	var enemy := await _spawn_enemy(world, 9901)
	var ring := enemy.get_node_or_null("SuspicionRing") as SuspicionRingPresenter
	_t.run_test("decay: ring node exists", ring != null)
	if ring == null:
		world.queue_free()
		await get_tree().process_frame
		return

	ring.set_enabled(true)

	# Simulate suspicion reaching peak then decaying
	enemy.set_meta("awareness_state", "CALM")
	ring.set_progress(1.0)
	await get_tree().process_frame
	_t.run_test("decay: visible at peak (1.0)", ring.visible)

	# Simulate decay steps — ring should remain visible
	var decay_steps := [0.8, 0.5, 0.2, 0.05, 0.001]
	for step in decay_steps:
		ring.set_progress(step)
		await get_tree().process_frame
		_t.run_test("decay: visible at progress %.3f" % step, ring.visible)

	# At zero progress — ring hidden
	ring.set_progress(0.0)
	await get_tree().process_frame
	_t.run_test("decay: hidden at progress 0.0", not ring.visible)

	world.queue_free()
	await get_tree().process_frame


## Non-CALM states force ring hidden even with progress.
func _test_ring_hidden_combat_even_with_progress() -> void:
	var world := Node2D.new()
	add_child(world)

	var enemy := await _spawn_enemy(world, 9902)
	var ring := enemy.get_node_or_null("SuspicionRing") as SuspicionRingPresenter
	if ring == null:
		_t.run_test("combat-decay: ring node exists", false)
		world.queue_free()
		await get_tree().process_frame
		return

	ring.set_enabled(true)
	ring.set_progress(0.7)

	enemy.set_meta("awareness_state", "CALM")
	await get_tree().process_frame
	_t.run_test("combat-decay: visible in CALM", ring.visible)

	enemy.set_meta("awareness_state", "SUSPICIOUS")
	await get_tree().process_frame
	_t.run_test("combat-decay: hidden in SUSPICIOUS with progress 0.7", not ring.visible)

	enemy.set_meta("awareness_state", "ALERT")
	await get_tree().process_frame
	_t.run_test("combat-decay: hidden in ALERT with progress 0.7", not ring.visible)

	enemy.set_meta("awareness_state", "COMBAT")
	await get_tree().process_frame
	_t.run_test("combat-decay: hidden in COMBAT with progress 0.7", not ring.visible)

	# Return to CALM — ring reappears
	enemy.set_meta("awareness_state", "CALM")
	await get_tree().process_frame
	_t.run_test("combat-decay: visible again after returning to CALM", ring.visible)

	world.queue_free()
	await get_tree().process_frame


## In CALM state ring is visible during growth phase (progress increasing from 0).
func _test_ring_visible_growth_phase() -> void:
	var world := Node2D.new()
	add_child(world)

	var enemy := await _spawn_enemy(world, 9903)
	var ring := enemy.get_node_or_null("SuspicionRing") as SuspicionRingPresenter
	if ring == null:
		_t.run_test("growth: ring node exists", false)
		world.queue_free()
		await get_tree().process_frame
		return

	ring.set_enabled(true)
	ring.set_progress(0.0)
	enemy.set_meta("awareness_state", "CALM")
	await get_tree().process_frame
	_t.run_test("growth: hidden at progress 0", not ring.visible)

	var growth_steps := [0.01, 0.1, 0.3, 0.6, 1.0]
	for step in growth_steps:
		ring.set_progress(step)
		await get_tree().process_frame
		_t.run_test("growth: visible at progress %.2f" % step, ring.visible)

	world.queue_free()
	await get_tree().process_frame
