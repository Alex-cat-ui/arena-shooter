extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const SHADOW_ZONE_SCRIPT := preload("res://src/systems/stealth/shadow_zone.gd")
const NAVIGATION_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")


class FakeEnemy:
	extends Node2D

	var flashlight_active: bool = false

	func is_flashlight_active_for_navigation() -> bool:
		return flashlight_active

var embedded_mode: bool = false
var _t := TestHelpers.new()
var _spotted_count: int = 0
var _spotted_enemy_id_filter: int = -1


func _ready() -> void:
	if embedded_mode:
		return
	var result := await run_suite()
	get_tree().quit(0 if bool(result.get("ok", false)) else 1)


func _on_enemy_player_spotted_for_test(enemy_id: int, _position: Vector3) -> void:
	if enemy_id == _spotted_enemy_id_filter:
		_spotted_count += 1


func run_suite() -> Dictionary:
	print("")
	print("============================================================")
	print("SHADOW ZONE TEST")
	print("============================================================")

	if RuntimeState:
		RuntimeState.player_visibility_mul = 1.0

	await _test_enter_exit_changes_visibility_multiplier()
	_test_runtime_reset_restores_default_visibility()
	await _test_navigation_service_shadow_walk_rule()
	await _test_calm_shadow_blocks_spotted_and_los()
	await _test_spotted_emits_once_per_confirm_episode()

	_t.summary("SHADOW ZONE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_enter_exit_changes_visibility_multiplier() -> void:
	var zone := SHADOW_ZONE_SCRIPT.new()
	zone.shadow_multiplier = 0.35
	add_child(zone)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	add_child(player)

	zone.call("_on_body_entered", player)
	var expected_multiplier := 0.35
	if GameConfig and GameConfig.stealth_canon is Dictionary and bool(GameConfig.stealth_canon.get("shadow_is_binary", true)):
		expected_multiplier = 0.0
	_t.run_test(
		"player entering shadow zone updates RuntimeState multiplier",
		RuntimeState and is_equal_approx(RuntimeState.player_visibility_mul, expected_multiplier)
	)

	zone.call("_on_body_exited", player)
	_t.run_test(
		"player exiting shadow zone restores RuntimeState multiplier",
		RuntimeState and is_equal_approx(RuntimeState.player_visibility_mul, 1.0)
	)

	player.queue_free()
	zone.queue_free()
	await get_tree().process_frame


func _test_runtime_reset_restores_default_visibility() -> void:
	if RuntimeState:
		RuntimeState.player_visibility_mul = 0.2
		RuntimeState.reset()
	_t.run_test(
		"RuntimeState.reset restores player visibility multiplier",
		RuntimeState and is_equal_approx(RuntimeState.player_visibility_mul, 1.0)
	)


func _test_navigation_service_shadow_walk_rule() -> void:
	var navigation_service := NAVIGATION_SERVICE_SCRIPT.new()
	add_child(navigation_service)

	var zone := SHADOW_ZONE_SCRIPT.new()
	zone.position = Vector2(120.0, 80.0)
	var shape_node := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(100.0, 60.0)
	shape_node.shape = shape
	zone.add_child(shape_node)
	add_child(zone)
	await get_tree().process_frame

	var point_in_shadow := zone.global_position
	var point_outside_shadow := zone.global_position + Vector2(160.0, 0.0)

	var enemy_without_flashlight := FakeEnemy.new()
	enemy_without_flashlight.flashlight_active = false
	add_child(enemy_without_flashlight)

	var enemy_with_flashlight := FakeEnemy.new()
	enemy_with_flashlight.flashlight_active = true
	add_child(enemy_with_flashlight)

	var allowed_without_flashlight := navigation_service.can_enemy_traverse_point(enemy_without_flashlight, point_in_shadow)
	var allowed_with_flashlight := navigation_service.can_enemy_traverse_point(enemy_with_flashlight, point_in_shadow)
	var allowed_outside_shadow := navigation_service.can_enemy_traverse_point(enemy_without_flashlight, point_outside_shadow)

	_t.run_test("shadow walk rule blocks movement in shadow without flashlight", not allowed_without_flashlight)
	_t.run_test("shadow walk rule allows movement in shadow with flashlight", allowed_with_flashlight)
	_t.run_test("shadow walk rule allows movement outside shadow", allowed_outside_shadow)

	enemy_without_flashlight.queue_free()
	enemy_with_flashlight.queue_free()
	zone.queue_free()
	navigation_service.queue_free()
	await get_tree().process_frame


func _test_calm_shadow_blocks_spotted_and_los() -> void:
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_hp = 100
		RuntimeState.player_visibility_mul = 0.0

	var world := Node2D.new()
	add_child(world)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(220.0, 0.0)
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2.ZERO
	world.add_child(enemy)
	await get_tree().process_frame
	enemy.initialize(9191, "zombie")

	_spotted_count = 0
	_spotted_enemy_id_filter = 9191
	if EventBus:
		if not EventBus.enemy_player_spotted.is_connected(_on_enemy_player_spotted_for_test):
			EventBus.enemy_player_spotted.connect(_on_enemy_player_spotted_for_test)

	for _i in range(40):
		enemy.runtime_budget_tick(0.25)
		await get_tree().process_frame

	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test("calm shadow blocks spotted event emission", _spotted_count == 0)
	_t.run_test("calm shadow blocks behavior LOS", not bool(snapshot.get("has_los", true)))
	_t.run_test(
		"calm shadow keeps awareness CALM",
		int(snapshot.get("state", -1)) == int(ENEMY_ALERT_LEVELS_SCRIPT.CALM)
	)

	if EventBus and EventBus.enemy_player_spotted.is_connected(_on_enemy_player_spotted_for_test):
		EventBus.enemy_player_spotted.disconnect(_on_enemy_player_spotted_for_test)
	_spotted_enemy_id_filter = -1
	world.queue_free()
	await get_tree().process_frame
	if RuntimeState:
		RuntimeState.player_visibility_mul = 1.0


func _test_spotted_emits_once_per_confirm_episode() -> void:
	if RuntimeState:
		RuntimeState.is_frozen = false
		RuntimeState.player_hp = 100
		RuntimeState.player_visibility_mul = 1.0

	var world := Node2D.new()
	add_child(world)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = Vector2(260.0, 0.0)
	world.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2.ZERO
	world.add_child(enemy)
	await get_tree().process_frame
	enemy.initialize(9192, "zombie")

	_spotted_count = 0
	_spotted_enemy_id_filter = 9192
	if EventBus:
		if not EventBus.enemy_player_spotted.is_connected(_on_enemy_player_spotted_for_test):
			EventBus.enemy_player_spotted.connect(_on_enemy_player_spotted_for_test)

	for _i in range(48):
		enemy.runtime_budget_tick(0.25)
		await get_tree().process_frame

	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	_t.run_test("confirmed contact emits bounded spotted events", _spotted_count >= 1 and _spotted_count <= 2)
	_t.run_test(
		"confirmed contact reaches COMBAT",
		int(snapshot.get("state", -1)) == int(ENEMY_ALERT_LEVELS_SCRIPT.COMBAT)
	)

	if EventBus and EventBus.enemy_player_spotted.is_connected(_on_enemy_player_spotted_for_test):
		EventBus.enemy_player_spotted.disconnect(_on_enemy_player_spotted_for_test)
	_spotted_enemy_id_filter = -1
	world.queue_free()
	await get_tree().process_frame
