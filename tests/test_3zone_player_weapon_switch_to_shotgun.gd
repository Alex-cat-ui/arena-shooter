extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const THREE_ZONE_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

const SWITCH_ATTEMPTS := 20

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
	print("3-ZONE PLAYER WEAPON SWITCH TO SHOTGUN TEST")
	print("============================================================")

	await _test_weapon_2_switches_to_shotgun_20_of_20()

	_t.summary("3-ZONE PLAYER WEAPON SWITCH TO SHOTGUN RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_weapon_2_switches_to_shotgun_20_of_20() -> void:
	var level := THREE_ZONE_SCENE.instantiate() as Node2D
	add_child(level)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := level.get_node_or_null("Stealth3ZoneTestController")
	var player := level.get_node_or_null("Entities/Player") as CharacterBody2D
	var label := level.get_node_or_null("DebugUI/DebugLabel") as Label

	_t.run_test("3zone switch: controller exists", controller != null)
	_t.run_test("3zone switch: player exists", player != null)
	if controller == null or player == null:
		await _cleanup_level(level)
		return

	var summary := controller.call("debug_get_combat_pipeline_summary") as Dictionary if controller.has_method("debug_get_combat_pipeline_summary") else {}
	var pipeline_ok := (
		bool(summary.get("combat_system_exists", false))
		and bool(summary.get("projectile_system_exists", false))
		and bool(summary.get("ability_system_exists", false))
		and bool(summary.get("player_projectile_wired", false))
		and bool(summary.get("player_ability_wired", false))
		and bool(summary.get("ability_projectile_wired", false))
		and bool(summary.get("ability_combat_wired", false))
	)
	_t.run_test("3zone switch: player weapon pipeline is wired", pipeline_ok)

	var ability: Variant = player.ability_system if "ability_system" in player else null
	if ability == null or not ability.has_method("set_weapon_by_index") or not ability.has_method("get_current_weapon"):
		_t.run_test("3zone switch: player ability system supports slot switch", false)
		await _cleanup_level(level)
		return
	_t.run_test("3zone switch: player ability system supports slot switch", true)

	var switched_count := 0
	for _attempt in range(SWITCH_ATTEMPTS):
		ability.set_weapon_by_index(0)
		await get_tree().physics_frame
		Input.action_press("weapon_2")
		await get_tree().physics_frame
		await get_tree().process_frame
		Input.action_release("weapon_2")
		await get_tree().process_frame
		if String(ability.get_current_weapon()) == "shotgun":
			switched_count += 1

	_t.run_test("3zone switch: weapon_2 switches to shotgun 20/20", switched_count == SWITCH_ATTEMPTS)

	if label != null and controller.has_method("_refresh_debug_label"):
		controller.call("_refresh_debug_label", true)
		_t.run_test("3zone switch: debug overlay includes player weapon", label.text.find("player_weapon=shotgun") >= 0)
	else:
		_t.run_test("3zone switch: debug overlay includes player weapon", false)

	await _cleanup_level(level)


func _cleanup_level(level: Node) -> void:
	Input.action_release("weapon_2")
	if level and is_instance_valid(level):
		level.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
