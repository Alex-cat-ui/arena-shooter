extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const ENEMY_SCENE := preload("res://scenes/entities/enemy.tscn")
const ENEMY_ALERT_LEVELS_SCRIPT := preload("res://src/systems/enemy_alert_levels.gd")

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
	print("ENEMY DEBUG SNAPSHOT CONTRACT TEST")
	print("============================================================")

	await _test_snapshot_has_required_fields()
	await _test_snapshot_field_types_and_ranges()

	_t.summary("ENEMY DEBUG SNAPSHOT CONTRACT RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_snapshot_has_required_fields() -> void:
	var setup := await _spawn_enemy_world()
	var world := setup["world"] as Node2D
	var enemy := setup["enemy"] as Enemy

	enemy.runtime_budget_tick(0.1)
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var required_keys := [
		"state",
		"state_name",
		"suspicion",
		"has_los",
		"visibility_factor",
		"flashlight_active",
		"flashlight_hit",
		"intent_type",
		"intent_target",
		"room_alert_effective",
		"latched",
		"shotgun_fire_block_reason",
		"combat_search_progress",
		"combat_search_current_room_id",
		"combat_search_total_cap_hit",
	]
	var has_all := true
	for key_variant in required_keys:
		var key := String(key_variant)
		if not snapshot.has(key):
			has_all = false
			break

	_t.run_test("debug snapshot exposes required contract keys", has_all)

	world.queue_free()
	await get_tree().process_frame


func _test_snapshot_field_types_and_ranges() -> void:
	var setup := await _spawn_enemy_world()
	var world := setup["world"] as Node2D
	var enemy := setup["enemy"] as Enemy

	enemy.runtime_budget_tick(0.1)
	var snapshot := enemy.get_debug_detection_snapshot() as Dictionary
	var state := int(snapshot.get("state", -1))
	var suspicion := float(snapshot.get("suspicion", -1.0))
	var state_ok := state >= ENEMY_ALERT_LEVELS_SCRIPT.CALM and state <= ENEMY_ALERT_LEVELS_SCRIPT.COMBAT
	var suspicion_ok := suspicion >= 0.0 and suspicion <= 1.0
	var type_ok := (
		snapshot.get("flashlight_active", null) is bool
		and snapshot.get("flashlight_hit", null) is bool
		and snapshot.get("latched", null) is bool
		and snapshot.get("intent_target", null) is Vector2
	)
	var weapon_ok := String(snapshot.get("weapon_name", "")) == "shotgun"

	_t.run_test("debug snapshot state enum is in valid range", state_ok)
	_t.run_test("debug snapshot suspicion is clamped 0..1", suspicion_ok)
	_t.run_test("debug snapshot core field types remain stable", type_ok)
	_t.run_test("debug snapshot weapon_name contract remains shotgun", weapon_ok)

	world.queue_free()
	await get_tree().process_frame


func _spawn_enemy_world() -> Dictionary:
	if RuntimeState:
		RuntimeState.player_hp = 100
		RuntimeState.player_visibility_mul = 1.0
		RuntimeState.is_frozen = false

	var world := Node2D.new()
	add_child(world)
	var entities := Node2D.new()
	world.add_child(entities)

	var player := CharacterBody2D.new()
	player.add_to_group("player")
	player.global_position = Vector2.ZERO
	entities.add_child(player)

	var enemy := ENEMY_SCENE.instantiate() as Enemy
	enemy.global_position = Vector2(120.0, 0.0)
	entities.add_child(enemy)
	await get_tree().process_frame
	await get_tree().physics_frame
	enemy.initialize(45001, "zombie")
	return {
		"world": world,
		"enemy": enemy,
	}
