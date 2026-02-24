extends Node

const TestHelpers = preload("res://tests/test_helpers.gd")
const STEALTH_ROOM_SCENE := preload("res://src/levels/stealth_3zone_test.tscn")

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
	print("STEALTH WEAPON PIPELINE EQUIVALENCE TEST")
	print("============================================================")

	await _test_stealth_weapon_pipeline_equivalence()

	_t.summary("STEALTH WEAPON PIPELINE EQUIVALENCE RESULTS")
	return {
		"ok": _t.quit_code() == 0,
		"run": _t.tests_run,
		"passed": _t.tests_passed,
	}


func _test_stealth_weapon_pipeline_equivalence() -> void:
	var room := STEALTH_ROOM_SCENE.instantiate()
	add_child(room)
	await get_tree().process_frame
	await get_tree().physics_frame

	var controller := room.get_node_or_null("Stealth3ZoneTestController")
	var player := room.get_node_or_null("Entities/Player") as CharacterBody2D
	var enemy := _first_member_in_group_under("enemies", room) as Enemy

	_t.run_test("pipeline eq: controller exists", controller != null)
	_t.run_test("pipeline eq: player exists", player != null)
	_t.run_test("pipeline eq: enemy exists", enemy != null)
	if controller == null or player == null or enemy == null:
		room.queue_free()
		await get_tree().process_frame
		return

	var pipeline_summary := {}
	if controller.has_method("debug_get_combat_pipeline_summary"):
		pipeline_summary = controller.call("debug_get_combat_pipeline_summary") as Dictionary
	else:
		_t.run_test("pipeline eq: combat pipeline summary method available", false)

	_t.run_test("pipeline eq: combat system exists", bool(pipeline_summary.get("combat_system_exists", false)))
	_t.run_test("pipeline eq: projectile system exists", bool(pipeline_summary.get("projectile_system_exists", false)))
	_t.run_test("pipeline eq: ability system exists", bool(pipeline_summary.get("ability_system_exists", false)))
	_t.run_test("pipeline eq: player ability is wired", bool(pipeline_summary.get("player_ability_wired", false)))
	_t.run_test("pipeline eq: ability->projectile wiring exists", bool(pipeline_summary.get("ability_projectile_wired", false)))
	_t.run_test("pipeline eq: ability->combat wiring exists", bool(pipeline_summary.get("ability_combat_wired", false)))
	_t.run_test("pipeline eq: player projectile fallback API removed", not ("projectile_system" in player))

	var combat_node := room.get_node_or_null("Systems/CombatSystem")
	var projectile_node := room.get_node_or_null("Systems/ProjectileSystem")
	var ability_node := room.get_node_or_null("Systems/AbilitySystem")
	_t.run_test(
		"pipeline eq: 3zone has canonical system node names",
		combat_node != null and projectile_node != null and ability_node != null
	)
	_t.run_test(
		"pipeline eq: combat system player target is current player",
		combat_node != null and "player_node" in combat_node and combat_node.player_node == player
	)

	var ability_wiring_matches: bool = (
		ability_node != null
		and "projectile_system" in ability_node
		and "combat_system" in ability_node
		and ability_node.projectile_system == projectile_node
		and ability_node.combat_system == combat_node
	)
	_t.run_test("pipeline eq: ability wiring matches LevelMVP contract", ability_wiring_matches)

	_t.run_test(
		"pipeline eq: enemy weapons toggle API removed",
		not enemy.has_method("set_weapons_enabled_for_test") and not enemy.has_method("is_weapons_enabled_for_test")
	)
	_t.run_test("pipeline eq: enemy type matches production spawner default", enemy.enemy_type == "zombie")

	var fire_runtime: Variant = (enemy.get_runtime_helper_refs() as Dictionary).get("fire_control_runtime", null)
	_t.run_test("pipeline eq: fire runtime helper exists", fire_runtime != null)
	var expected_shotgun := GameConfig.weapon_stats.get("shotgun", {}) as Dictionary if GameConfig else {}
	var actual_shotgun := fire_runtime.call("shotgun_stats") as Dictionary if fire_runtime != null else {}
	var shotgun_loadout_matches := (
		not expected_shotgun.is_empty()
		and not actual_shotgun.is_empty()
		and int(actual_shotgun.get("pellets", -1)) == int(expected_shotgun.get("pellets", -2))
		and is_equal_approx(float(actual_shotgun.get("cooldown_sec", -1.0)), float(expected_shotgun.get("cooldown_sec", -2.0)))
		and is_equal_approx(float(actual_shotgun.get("shot_damage_total", -1.0)), float(expected_shotgun.get("shot_damage_total", -2.0)))
	)
	_t.run_test("pipeline eq: enemy shotgun loadout comes from production stats", shotgun_loadout_matches)

	var player_ability: Variant = player.ability_system if "ability_system" in player else null
	var player_loadout_matches: bool = (
		player_ability != null
		and player_ability.has_method("get_current_weapon")
		and String(player_ability.get_current_weapon()) == "pistol"
	)
	_t.run_test("pipeline eq: player loadout starts at production default weapon", player_loadout_matches)
	var player_weapon_list_matches: bool = (
		player_ability != null
		and player_ability.has_method("get_weapon_list")
		and (player_ability.get_weapon_list() as Array) == ["pistol", "shotgun"]
	)
	_t.run_test("pipeline eq: player weapon list reduced to pistol+shotgun", player_weapon_list_matches)

	room.queue_free()
	await get_tree().process_frame


func _first_member_in_group_under(group_name: String, ancestor: Node) -> Node:
	for member_variant in get_tree().get_nodes_in_group(group_name):
		var member := member_variant as Node
		if member == null:
			continue
		if member == ancestor or ancestor.is_ancestor_of(member):
			return member
	return null
