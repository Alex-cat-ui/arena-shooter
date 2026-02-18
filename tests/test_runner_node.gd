## test_runner_node.gd
## Test runner node - runs tests when scene loads (autoloads are available).
## Run via: godot --headless res://tests/test_runner.tscn
extends Node

var _tests_run := 0
var _tests_passed := 0

const AWARENESS_TEST_SCENE := "res://tests/test_enemy_awareness_system.tscn"
const AGGRO_TEST_SCENE := "res://tests/test_enemy_aggro_coordinator.tscn"
const NOISE_FLOW_TEST_SCENE := "res://tests/test_enemy_noise_alert_flow.tscn"
const DOOR_CONTROLLER_TEST_SCENE := "res://tests/test_door_physics_full.tscn"
const DOOR_INTERACTION_FLOW_SCENE := "res://tests/test_door_interaction_flow.tscn"
const DOOR_SELECTION_METRIC_SCENE := "res://tests/test_layout_door_selection_metric.tscn"
const ALERT_MARKER_TEST_SCENE := "res://tests/test_enemy_alert_marker.tscn"
const ALERT_SYSTEM_TEST_SCENE := "res://tests/test_enemy_alert_system.tscn"
const SQUAD_SYSTEM_TEST_SCENE := "res://tests/test_enemy_squad_system.tscn"
const UTILITY_BRAIN_TEST_SCENE := "res://tests/test_enemy_utility_brain.tscn"
const BEHAVIOR_INTEGRATION_TEST_SCENE := "res://tests/test_enemy_behavior_integration.tscn"
const RUNTIME_BUDGET_SCHEDULER_TEST_SCENE := "res://tests/test_enemy_runtime_budget_scheduler.tscn"
const CONFIG_VALIDATOR_AI_BALANCE_TEST_SCENE := "res://tests/test_config_validator_ai_balance.tscn"
const ENEMY_SUSPICION_TEST_SCENE := "res://tests/test_enemy_suspicion.tscn"
const FLASHLIGHT_CONE_TEST_SCENE := "res://tests/test_flashlight_cone.tscn"
const ALERT_FLASHLIGHT_DETECTION_TEST_SCENE := "res://tests/test_alert_flashlight_detection.tscn"
const STEALTH_ROOM_SMOKE_TEST_SCENE := "res://tests/test_stealth_room_smoke.tscn"
const FORCE_STATE_PATH_TEST_SCENE := "res://tests/test_force_state_path.tscn"
const WEAPONS_TOGGLE_GATE_TEST_SCENE := "res://tests/test_weapons_toggle_gate_enemy_fire.tscn"
const PLAYER_SCENE_IDENTITY_TEST_SCENE := "res://tests/test_player_scene_identity.tscn"
const COMBAT_OBSTACLE_CHASE_BASIC_TEST_SCENE := "res://tests/test_combat_obstacle_chase_basic.tscn"
const DEBUGUI_SINGLE_OWNER_TEST_SCENE := "res://tests/test_debugui_single_owner.tscn"
const STEALTH_WEAPON_PIPELINE_EQ_TEST_SCENE := "res://tests/test_stealth_weapon_pipeline_equivalence.tscn"
const STEALTH_ROOM_ALERT_FLASHLIGHT_INTEGRATION_TEST_SCENE := "res://tests/test_stealth_room_alert_flashlight_integration.tscn"
const RING_VISIBILITY_POLICY_TEST_SCENE := "res://tests/test_ring_visibility_policy.tscn"
const SHADOW_ZONE_TEST_SCENE := "res://tests/test_shadow_zone.tscn"
const MARKER_SEMANTICS_MAPPING_TEST_SCENE := "res://tests/test_marker_semantics_mapping.tscn"
const RING_VISIBLE_DURING_DECAY_TEST_SCENE := "res://tests/test_ring_visible_during_decay.tscn"
const WEAPONS_STARTUP_POLICY_ON_TEST_SCENE := "res://tests/test_weapons_startup_policy_on.tscn"
const DEBUGUI_LAYOUT_NO_OVERLAP_TEST_SCENE := "res://tests/test_debugui_layout_no_overlap.tscn"
const STEALTH_ROOM_COMBAT_FIRE_TEST_SCENE := "res://tests/test_stealth_room_combat_fire.tscn"
const STEALTH_ROOM_LKP_SEARCH_TEST_SCENE := "res://tests/test_stealth_room_lkp_search.tscn"
const COMBAT_ROOM_ALERT_SYNC_TEST_SCENE := "res://tests/test_combat_room_alert_sync.tscn"
const COMBAT_NO_DEGRADE_TEST_SCENE := "res://tests/test_combat_no_degrade.tscn"
const COMBAT_UTILITY_INTENT_AGGRESSIVE_TEST_SCENE := "res://tests/test_combat_utility_intent_aggressive.tscn"
const MAIN_MENU_STEALTH_ENTRY_TEST_SCENE := "res://tests/test_main_menu_stealth_entry.tscn"
const ENEMY_LATCH_REGISTER_UNREGISTER_TEST_SCENE := "res://tests/test_enemy_latch_register_unregister.tscn"
const ENEMY_LATCH_MIGRATION_TEST_SCENE := "res://tests/test_enemy_latch_migration.tscn"
const COMBAT_USES_LAST_SEEN_TEST_SCENE := "res://tests/test_combat_uses_last_seen_not_live_player_pos_without_los.tscn"
const LAST_SEEN_GRACE_WINDOW_TEST_SCENE := "res://tests/test_last_seen_grace_window.tscn"
const COMBAT_NO_LOS_NEVER_HOLD_RANGE_TEST_SCENE := "res://tests/test_combat_no_los_never_hold_range.tscn"
const COMBAT_INTENT_PUSH_TO_SEARCH_TEST_SCENE := "res://tests/test_combat_intent_switches_push_to_search_after_grace.tscn"
const DETOUR_SIDE_FLIP_ON_STALL_TEST_SCENE := "res://tests/test_detour_side_flip_on_stall.tscn"
const HONEST_REPATH_WITHOUT_TELEPORT_TEST_SCENE := "res://tests/test_honest_repath_without_teleport.tscn"
const FLASHLIGHT_ACTIVE_IN_COMBAT_TEST_SCENE := "res://tests/test_flashlight_active_in_combat_when_latched.tscn"
const FLASHLIGHT_BONUS_IN_COMBAT_TEST_SCENE := "res://tests/test_flashlight_bonus_applies_in_combat.tscn"
const LEVEL_RUNTIME_GUARD_TEST_SCENE := "res://tests/test_level_runtime_guard.tscn"
const LEVEL_INPUT_CONTROLLER_TEST_SCENE := "res://tests/test_level_input_controller.tscn"
const LEVEL_HUD_CONTROLLER_TEST_SCENE := "res://tests/test_level_hud_controller.tscn"
const LEVEL_CAMERA_CONTROLLER_TEST_SCENE := "res://tests/test_level_camera_controller.tscn"
const LEVEL_LAYOUT_REGEN_TEST_SCENE := "res://tests/test_level_layout_controller_regen.tscn"
const LEVEL_LAYOUT_FLOOR_TEST_SCENE := "res://tests/test_level_layout_floor_rebuild.tscn"
const LEVEL_TRANSITION_CONTROLLER_TEST_SCENE := "res://tests/test_level_transition_controller.tscn"
const LEVEL_ENEMY_RUNTIME_CONTROLLER_TEST_SCENE := "res://tests/test_level_enemy_runtime_controller.tscn"
const LEVEL_EVENTS_CONTROLLER_TEST_SCENE := "res://tests/test_level_events_controller.tscn"
const LEVEL_BOOTSTRAP_CONTROLLER_TEST_SCENE := "res://tests/test_level_bootstrap_controller.tscn"
const MISSION_TRANSITION_GATE_TEST_SCENE := "res://tests/test_mission_transition_gate.tscn"
const EVENT_BUS_BACKPRESSURE_TEST_SCENE := "res://tests/test_event_bus_backpressure.tscn"
const COMBAT_TRANSITION_STRESS_3ZONE_TEST_SCENE := "res://tests/test_3zone_combat_transition_stress.tscn"

func _ready() -> void:
	print("=" .repeat(60))
	print("INTEGRATION TEST: Core + AI + Doors + Alert")
	print("=" .repeat(60))

	await _run_tests()

	print("")
	print("=" .repeat(60))
	print("RESULTS: %d/%d tests passed" % [_tests_passed, _tests_run])
	print("=" .repeat(60))

	# Exit with appropriate code
	get_tree().quit(0 if _tests_passed == _tests_run else 1)


func _run_tests() -> void:
	print("\n--- SECTION 1: Singletons ---")

	_test("GameConfig singleton exists", func():
		return GameConfig != null
	)

	_test("RuntimeState singleton exists", func():
		return RuntimeState != null
	)

	_test("StateManager singleton exists", func():
		return StateManager != null
	)

	_test("EventBus singleton exists", func():
		return EventBus != null
	)

	print("\n--- SECTION 2: GameConfig defaults ---")

	_test("tile_size = 32", func():
		return GameConfig.tile_size == 32
	)

	_test("player_max_hp = 100", func():
		return GameConfig.player_max_hp == 100
	)

	_test("start_delay_sec = 1.5", func():
		return is_equal_approx(GameConfig.start_delay_sec, 1.5)
	)

	_test("contact_iframes_sec = 0.7", func():
		return is_equal_approx(GameConfig.contact_iframes_sec, 0.7)
	)

	_test("music_volume = 0.7", func():
		return is_equal_approx(GameConfig.music_volume, 0.7)
	)

	_test("sfx_volume = 0.7", func():
		return is_equal_approx(GameConfig.sfx_volume, 0.7)
	)

	print("\n--- SECTION 2b: Phase 0 stealth foundation ---")

	_test("GameConfig.stealth_canon has all 7 Phase 0 keys", func():
		if not (GameConfig.stealth_canon is Dictionary):
			return false
		var canon := GameConfig.stealth_canon as Dictionary
		var required_keys := [
			"confirm_time_to_engage",
			"confirm_decay_rate",
			"confirm_grace_window",
			"shadow_is_binary",
			"flashlight_works_in_alert",
			"flashlight_works_in_combat",
			"flashlight_works_in_lockdown",
		]
		for key in required_keys:
			if not canon.has(key):
				return false
		return true
	)

	_test("EventBus has Phase 0 zone/escalation signals", func():
		return EventBus.has_signal("zone_state_changed") and EventBus.has_signal("hostile_escalation")
	)

	print("\n--- SECTION 3: State transitions ---")

	_test("Initial state is MAIN_MENU", func():
		return StateManager.current_state == GameState.State.MAIN_MENU
	)

	_test("MAIN_MENU -> LEVEL_SETUP", func():
		return StateManager.change_state(GameState.State.LEVEL_SETUP)
	)

	_test("LEVEL_SETUP -> PLAYING", func():
		return StateManager.change_state(GameState.State.PLAYING)
	)

	_test("RuntimeState.is_level_active after PLAYING", func():
		return RuntimeState.is_level_active == true
	)

	_test("PLAYING -> PAUSED", func():
		return StateManager.change_state(GameState.State.PAUSED)
	)

	_test("RuntimeState.is_frozen when PAUSED", func():
		return RuntimeState.is_frozen == true
	)

	_test("PAUSED -> PLAYING", func():
		return StateManager.change_state(GameState.State.PLAYING)
	)

	_test("RuntimeState.is_frozen = false when PLAYING", func():
		return RuntimeState.is_frozen == false
	)

	_test("PLAYING -> GAME_OVER", func():
		return StateManager.change_state(GameState.State.GAME_OVER)
	)

	_test("GAME_OVER -> MAIN_MENU", func():
		return StateManager.change_state(GameState.State.MAIN_MENU)
	)

	print("\n--- SECTION 4: Config validation ---")

	_test("Valid config passes validation", func():
		GameConfig.reset_to_defaults()
		var result := ConfigValidator.validate()
		return result.is_valid
	)

	_test("Invalid tile_size caught", func():
		GameConfig.tile_size = 0
		var result := ConfigValidator.validate()
		var is_invalid := not result.is_valid
		GameConfig.reset_to_defaults()
		return is_invalid
	)

	print("\n--- SECTION 5: Vector3 utilities (CANON) ---")

	_test("vec2_to_vec3 conversion", func():
		var v3 := RuntimeState.vec2_to_vec3(Vector2(10, 20))
		return v3.x == 10 and v3.y == 20 and v3.z == 0
	)

	_test("vec3_to_vec2 conversion", func():
		var v2 := RuntimeState.vec3_to_vec2(Vector3(10, 20, 30))
		return v2.x == 10 and v2.y == 20
	)

	print("\n--- SECTION 7: Enemy stats (ТЗ v1.13) ---")

	_test("Zombie HP=100, DMG=10", func():
		var stats: Dictionary = GameConfig.enemy_stats.get("zombie", {})
		return stats.hp == 100 and stats.damage == 10
	)

	_test("Fast HP=100, DMG=7", func():
		var stats: Dictionary = GameConfig.enemy_stats.get("fast", {})
		return stats.hp == 100 and stats.damage == 7
	)

	_test("Tank HP=100, DMG=15", func():
		var stats: Dictionary = GameConfig.enemy_stats.get("tank", {})
		return stats.hp == 100 and stats.damage == 15
	)

	_test("Swarm HP=100, DMG=5", func():
		var stats: Dictionary = GameConfig.enemy_stats.get("swarm", {})
		return stats.hp == 100 and stats.damage == 5
	)

	print("\n--- SECTION 8: Projectile TTL (ТЗ v1.13) ---")

	_test("Bullet TTL = 2.0s", func():
		return GameConfig.projectile_ttl.get("bullet", 0.0) == 2.0
	)

	_test("Rocket TTL = 3.0s", func():
		return GameConfig.projectile_ttl.get("rocket", 0.0) == 3.0
	)

	_test("Piercing bullet TTL = 2.0s", func():
		return GameConfig.projectile_ttl.get("piercing_bullet", 0.0) == 2.0
	)

	print("\n--- SECTION 9: Weapon stats (ТЗ v1.13 - from GameConfig) ---")

	_test("Pistol dmg=10, rpm=180", func():
		var stats: Dictionary = GameConfig.weapon_stats.get("pistol", {})
		return stats.damage == 10 and stats.rpm == 180
	)

	_test("Weapon list reduced to pistol+shotgun", func():
		return GameConfig.weapon_stats.keys().size() == 2 and GameConfig.weapon_stats.has("pistol") and GameConfig.weapon_stats.has("shotgun")
	)

	_test("Shotgun pellets=16, dmg=6", func():
		var stats: Dictionary = GameConfig.weapon_stats.get("shotgun", {})
		return stats.pellets == 16 and stats.damage == 6
	)

	print("\n--- SECTION 10: RuntimeState reset ---")

	_test("RuntimeState reset on MAIN_MENU", func():
		StateManager.change_state(GameState.State.LEVEL_SETUP)
		StateManager.change_state(GameState.State.PLAYING)
		RuntimeState.kills = 999
		RuntimeState.damage_dealt = 999
		StateManager.change_state(GameState.State.GAME_OVER)
		StateManager.change_state(GameState.State.MAIN_MENU)
		return RuntimeState.kills == 0 and RuntimeState.damage_dealt == 0
	)

	print("\n--- SECTION 11: State transitions ---")

	_test("PLAYING -> LEVEL_COMPLETE valid", func():
		StateManager.change_state(GameState.State.LEVEL_SETUP)
		StateManager.change_state(GameState.State.PLAYING)
		var result := StateManager.change_state(GameState.State.LEVEL_COMPLETE)
		StateManager.change_state(GameState.State.MAIN_MENU)
		return result
	)

	_test("LEVEL_COMPLETE -> LEVEL_SETUP (Retry)", func():
		StateManager.change_state(GameState.State.LEVEL_SETUP)
		StateManager.change_state(GameState.State.PLAYING)
		StateManager.change_state(GameState.State.LEVEL_COMPLETE)
		var result := StateManager.change_state(GameState.State.LEVEL_SETUP)
		StateManager.change_state(GameState.State.MAIN_MENU)
		return result
	)

	_test("LEVEL_COMPLETE -> MAIN_MENU (Exit)", func():
		StateManager.change_state(GameState.State.LEVEL_SETUP)
		StateManager.change_state(GameState.State.PLAYING)
		StateManager.change_state(GameState.State.LEVEL_COMPLETE)
		return StateManager.change_state(GameState.State.MAIN_MENU)
	)

	print("\n--- SECTION 12: VFX System constants ---")

	_test("Corpse limit = 200", func():
		return VFXSystem.CORPSE_LIMIT == 200
	)

	print("\n--- SECTION 13: Footprint System constants ---")

	_test("Max footprints = 20", func():
		return FootprintSystem.MAX_FOOTPRINTS == 20
	)

	print("\n--- SECTION 14: EventBus signals ---")

	_test("blood_spawned signal exists", func():
		return EventBus.has_signal("blood_spawned")
	)

	_test("corpse_spawned signal exists", func():
		return EventBus.has_signal("corpse_spawned")
	)

	_test("footprint_spawned signal exists", func():
		return EventBus.has_signal("footprint_spawned")
	)

	# ==========================================================================
	# VISUAL POLISH TESTS
	# ==========================================================================

	print("\n--- SECTION 15: Visual Polish GameConfig defaults ---")

	_test("footprints_enabled = true", func():
		return GameConfig.footprints_enabled == true
	)

	_test("footprint_step_distance_px = 40.0", func():
		return is_equal_approx(GameConfig.footprint_step_distance_px, 40.0)
	)

	_test("footprint_lifetime_sec = 20.0", func():
		return is_equal_approx(GameConfig.footprint_lifetime_sec, 20.0)
	)

	_test("footprint_max_count = 4000", func():
		return GameConfig.footprint_max_count == 4000
	)

	_test("shadow_player_alpha = 0.25", func():
		return is_equal_approx(GameConfig.shadow_player_alpha, 0.25)
	)

	_test("hit_flash_duration = 0.06", func():
		return is_equal_approx(GameConfig.hit_flash_duration, 0.06)
	)

	_test("kill_pop_scale = 1.2", func():
		return is_equal_approx(GameConfig.kill_pop_scale, 1.2)
	)

	_test("blood_max_decals = 500", func():
		return GameConfig.blood_max_decals == 500
	)

	_test("vignette_alpha = 0.3", func():
		return is_equal_approx(GameConfig.vignette_alpha, 0.3)
	)

	_test("debug_overlay_visible = false", func():
		return GameConfig.debug_overlay_visible == false
	)

	print("\n--- SECTION 16: Visual Polish system classes ---")

	_test("ShadowSystem class exists", func():
		var inst := ShadowSystem.new()
		var exists := inst != null
		inst.free()
		return exists
	)

	_test("CombatFeedbackSystem class exists", func():
		var inst := CombatFeedbackSystem.new()
		var exists := inst != null
		inst.free()
		return exists
	)

	_test("AtmosphereSystem class exists", func():
		var inst := AtmosphereSystem.new()
		var exists := inst != null
		inst.free()
		return exists
	)

	print("\n--- SECTION 17: Visual Polish reset_to_defaults ---")

	_test("Visual polish values survive reset_to_defaults", func():
		GameConfig.footprint_step_distance_px = 999.0
		GameConfig.reset_to_defaults()
		return is_equal_approx(GameConfig.footprint_step_distance_px, 40.0)
	)

	print("\n--- SECTION 18: AI/Door/Alert suites ---")

	_test("Awareness test scene exists", func():
		return load(AWARENESS_TEST_SCENE) is PackedScene
	)
	_test("Aggro coordinator test scene exists", func():
		return load(AGGRO_TEST_SCENE) is PackedScene
	)
	_test("Noise alert flow test scene exists", func():
		return load(NOISE_FLOW_TEST_SCENE) is PackedScene
	)
	_test("Door controller test scene exists", func():
		return load(DOOR_CONTROLLER_TEST_SCENE) is PackedScene
	)
	_test("Door interaction flow test scene exists", func():
		return load(DOOR_INTERACTION_FLOW_SCENE) is PackedScene
	)
	_test("Door selection metric test scene exists", func():
		return load(DOOR_SELECTION_METRIC_SCENE) is PackedScene
	)
	_test("Enemy alert marker test scene exists", func():
		return load(ALERT_MARKER_TEST_SCENE) is PackedScene
	)
	_test("Enemy alert system test scene exists", func():
		return load(ALERT_SYSTEM_TEST_SCENE) is PackedScene
	)
	_test("Enemy squad system test scene exists", func():
		return load(SQUAD_SYSTEM_TEST_SCENE) is PackedScene
	)
	_test("Enemy utility brain test scene exists", func():
		return load(UTILITY_BRAIN_TEST_SCENE) is PackedScene
	)
	_test("Enemy behavior integration test scene exists", func():
		return load(BEHAVIOR_INTEGRATION_TEST_SCENE) is PackedScene
	)
	_test("Enemy runtime budget scheduler test scene exists", func():
		return load(RUNTIME_BUDGET_SCHEDULER_TEST_SCENE) is PackedScene
	)
	_test("Config validator AI balance test scene exists", func():
		return load(CONFIG_VALIDATOR_AI_BALANCE_TEST_SCENE) is PackedScene
	)
	_test("Enemy suspicion test scene exists", func():
		return load(ENEMY_SUSPICION_TEST_SCENE) is PackedScene
	)
	_test("Flashlight cone test scene exists", func():
		return load(FLASHLIGHT_CONE_TEST_SCENE) is PackedScene
	)
	_test("Alert flashlight detection test scene exists", func():
		return load(ALERT_FLASHLIGHT_DETECTION_TEST_SCENE) is PackedScene
	)
	_test("Stealth room smoke test scene exists", func():
		return load(STEALTH_ROOM_SMOKE_TEST_SCENE) is PackedScene
	)
	_test("Force state path test scene exists", func():
		return load(FORCE_STATE_PATH_TEST_SCENE) is PackedScene
	)
	_test("Weapons toggle gate test scene exists", func():
		return load(WEAPONS_TOGGLE_GATE_TEST_SCENE) is PackedScene
	)
	_test("Player scene identity test scene exists", func():
		return load(PLAYER_SCENE_IDENTITY_TEST_SCENE) is PackedScene
	)
	_test("Combat obstacle chase basic test scene exists", func():
		return load(COMBAT_OBSTACLE_CHASE_BASIC_TEST_SCENE) is PackedScene
	)
	_test("DebugUI single owner test scene exists", func():
		return load(DEBUGUI_SINGLE_OWNER_TEST_SCENE) is PackedScene
	)
	_test("Stealth weapon pipeline equivalence test scene exists", func():
		return load(STEALTH_WEAPON_PIPELINE_EQ_TEST_SCENE) is PackedScene
	)
	_test("Stealth room alert flashlight integration test scene exists", func():
		return load(STEALTH_ROOM_ALERT_FLASHLIGHT_INTEGRATION_TEST_SCENE) is PackedScene
	)
	_test("Ring visibility policy test scene exists", func():
		return load(RING_VISIBILITY_POLICY_TEST_SCENE) is PackedScene
	)
	_test("Shadow zone test scene exists", func():
		return load(SHADOW_ZONE_TEST_SCENE) is PackedScene
	)
	_test("Marker semantics mapping test scene exists", func():
		return load(MARKER_SEMANTICS_MAPPING_TEST_SCENE) is PackedScene
	)
	_test("Ring visible during decay test scene exists", func():
		return load(RING_VISIBLE_DURING_DECAY_TEST_SCENE) is PackedScene
	)
	_test("Weapons startup policy ON test scene exists", func():
		return load(WEAPONS_STARTUP_POLICY_ON_TEST_SCENE) is PackedScene
	)
	_test("DebugUI layout no overlap test scene exists", func():
		return load(DEBUGUI_LAYOUT_NO_OVERLAP_TEST_SCENE) is PackedScene
	)
	_test("EventBus backpressure test scene exists", func():
		return load(EVENT_BUS_BACKPRESSURE_TEST_SCENE) is PackedScene
	)
	_test("3zone combat transition stress test scene exists", func():
		return load(COMBAT_TRANSITION_STRESS_3ZONE_TEST_SCENE) is PackedScene
	)

	await _run_embedded_scene_suite("Config validator AI balance suite", CONFIG_VALIDATOR_AI_BALANCE_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy awareness suite", AWARENESS_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy aggro coordinator suite", AGGRO_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy noise alert flow suite", NOISE_FLOW_TEST_SCENE)
	await _run_embedded_scene_suite("Door controller full suite", DOOR_CONTROLLER_TEST_SCENE)
	await _run_embedded_scene_suite("Door interaction flow suite", DOOR_INTERACTION_FLOW_SCENE)
	await _run_embedded_scene_suite("Door selection metric suite", DOOR_SELECTION_METRIC_SCENE)
	await _run_embedded_scene_suite("Enemy alert marker suite", ALERT_MARKER_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy alert system suite", ALERT_SYSTEM_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy squad system suite", SQUAD_SYSTEM_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy utility brain suite", UTILITY_BRAIN_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy behavior integration suite", BEHAVIOR_INTEGRATION_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy runtime budget scheduler suite", RUNTIME_BUDGET_SCHEDULER_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy suspicion suite", ENEMY_SUSPICION_TEST_SCENE)
	await _run_embedded_scene_suite("Flashlight cone suite", FLASHLIGHT_CONE_TEST_SCENE)
	await _run_embedded_scene_suite("Alert flashlight detection suite", ALERT_FLASHLIGHT_DETECTION_TEST_SCENE)
	await _run_embedded_scene_suite("Stealth room smoke suite", STEALTH_ROOM_SMOKE_TEST_SCENE)
	await _run_embedded_scene_suite("Force state path suite", FORCE_STATE_PATH_TEST_SCENE)
	await _run_embedded_scene_suite("Weapons toggle gate suite", WEAPONS_TOGGLE_GATE_TEST_SCENE)
	await _run_embedded_scene_suite("Player scene identity suite", PLAYER_SCENE_IDENTITY_TEST_SCENE)
	await _run_embedded_scene_suite("Combat obstacle chase basic suite", COMBAT_OBSTACLE_CHASE_BASIC_TEST_SCENE)
	await _run_embedded_scene_suite("DebugUI single owner suite", DEBUGUI_SINGLE_OWNER_TEST_SCENE)
	await _run_embedded_scene_suite("Stealth weapon pipeline equivalence suite", STEALTH_WEAPON_PIPELINE_EQ_TEST_SCENE)
	await _run_embedded_scene_suite("Stealth room alert flashlight integration suite", STEALTH_ROOM_ALERT_FLASHLIGHT_INTEGRATION_TEST_SCENE)
	await _run_embedded_scene_suite("Ring visibility policy suite", RING_VISIBILITY_POLICY_TEST_SCENE)
	await _run_embedded_scene_suite("Shadow zone suite", SHADOW_ZONE_TEST_SCENE)
	await _run_embedded_scene_suite("Marker semantics mapping suite", MARKER_SEMANTICS_MAPPING_TEST_SCENE)
	await _run_embedded_scene_suite("Ring visible during decay suite", RING_VISIBLE_DURING_DECAY_TEST_SCENE)
	await _run_embedded_scene_suite("Weapons startup policy ON suite", WEAPONS_STARTUP_POLICY_ON_TEST_SCENE)
	await _run_embedded_scene_suite("DebugUI layout no overlap suite", DEBUGUI_LAYOUT_NO_OVERLAP_TEST_SCENE)
	await _run_embedded_scene_suite("EventBus backpressure suite", EVENT_BUS_BACKPRESSURE_TEST_SCENE)
	await _run_embedded_scene_suite("3zone combat transition stress suite", COMBAT_TRANSITION_STRESS_3ZONE_TEST_SCENE)

	print("\n--- SECTION 18b: Stealth phases 1-7 suites ---")

	_test("Stealth room combat fire test scene exists", func():
		return load(STEALTH_ROOM_COMBAT_FIRE_TEST_SCENE) is PackedScene
	)
	_test("Stealth room LKP search test scene exists", func():
		return load(STEALTH_ROOM_LKP_SEARCH_TEST_SCENE) is PackedScene
	)
	_test("Combat room alert sync test scene exists", func():
		return load(COMBAT_ROOM_ALERT_SYNC_TEST_SCENE) is PackedScene
	)
	_test("Combat no degrade test scene exists", func():
		return load(COMBAT_NO_DEGRADE_TEST_SCENE) is PackedScene
	)
	_test("Combat utility intent aggressive test scene exists", func():
		return load(COMBAT_UTILITY_INTENT_AGGRESSIVE_TEST_SCENE) is PackedScene
	)
	_test("Main menu stealth entry test scene exists", func():
		return load(MAIN_MENU_STEALTH_ENTRY_TEST_SCENE) is PackedScene
	)
	_test("Enemy latch register/unregister test scene exists", func():
		return load(ENEMY_LATCH_REGISTER_UNREGISTER_TEST_SCENE) is PackedScene
	)
	_test("Enemy latch migration test scene exists", func():
		return load(ENEMY_LATCH_MIGRATION_TEST_SCENE) is PackedScene
	)
	_test("Combat uses last seen test scene exists", func():
		return load(COMBAT_USES_LAST_SEEN_TEST_SCENE) is PackedScene
	)
	_test("Last seen grace window test scene exists", func():
		return load(LAST_SEEN_GRACE_WINDOW_TEST_SCENE) is PackedScene
	)
	_test("Combat no LOS never hold range test scene exists", func():
		return load(COMBAT_NO_LOS_NEVER_HOLD_RANGE_TEST_SCENE) is PackedScene
	)
	_test("Combat intent push to search test scene exists", func():
		return load(COMBAT_INTENT_PUSH_TO_SEARCH_TEST_SCENE) is PackedScene
	)
	_test("Detour side flip on stall test scene exists", func():
		return load(DETOUR_SIDE_FLIP_ON_STALL_TEST_SCENE) is PackedScene
	)
	_test("Honest repath without teleport test scene exists", func():
		return load(HONEST_REPATH_WITHOUT_TELEPORT_TEST_SCENE) is PackedScene
	)
	_test("Flashlight active in combat test scene exists", func():
		return load(FLASHLIGHT_ACTIVE_IN_COMBAT_TEST_SCENE) is PackedScene
	)
	_test("Flashlight bonus in combat test scene exists", func():
		return load(FLASHLIGHT_BONUS_IN_COMBAT_TEST_SCENE) is PackedScene
	)

	await _run_embedded_scene_suite("Stealth room combat fire suite", STEALTH_ROOM_COMBAT_FIRE_TEST_SCENE)
	await _run_embedded_scene_suite("Stealth room LKP search suite", STEALTH_ROOM_LKP_SEARCH_TEST_SCENE)
	await _run_embedded_scene_suite("Combat room alert sync suite", COMBAT_ROOM_ALERT_SYNC_TEST_SCENE)
	await _run_embedded_scene_suite("Combat no degrade suite", COMBAT_NO_DEGRADE_TEST_SCENE)
	await _run_embedded_scene_suite("Combat utility intent aggressive suite", COMBAT_UTILITY_INTENT_AGGRESSIVE_TEST_SCENE)
	await _run_embedded_scene_suite("Main menu stealth entry suite", MAIN_MENU_STEALTH_ENTRY_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy latch register/unregister suite", ENEMY_LATCH_REGISTER_UNREGISTER_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy latch migration suite", ENEMY_LATCH_MIGRATION_TEST_SCENE)
	await _run_embedded_scene_suite("Combat uses last seen suite", COMBAT_USES_LAST_SEEN_TEST_SCENE)
	await _run_embedded_scene_suite("Last seen grace window suite", LAST_SEEN_GRACE_WINDOW_TEST_SCENE)
	await _run_embedded_scene_suite("Combat no LOS never hold range suite", COMBAT_NO_LOS_NEVER_HOLD_RANGE_TEST_SCENE)
	await _run_embedded_scene_suite("Combat intent push to search suite", COMBAT_INTENT_PUSH_TO_SEARCH_TEST_SCENE)
	await _run_embedded_scene_suite("Detour side flip on stall suite", DETOUR_SIDE_FLIP_ON_STALL_TEST_SCENE)
	await _run_embedded_scene_suite("Honest repath without teleport suite", HONEST_REPATH_WITHOUT_TELEPORT_TEST_SCENE)
	await _run_embedded_scene_suite("Flashlight active in combat suite", FLASHLIGHT_ACTIVE_IN_COMBAT_TEST_SCENE)
	await _run_embedded_scene_suite("Flashlight bonus in combat suite", FLASHLIGHT_BONUS_IN_COMBAT_TEST_SCENE)

	print("\n--- SECTION 19: Level decomposition controller suites ---")

	_test("Level runtime guard test scene exists", func():
		return load(LEVEL_RUNTIME_GUARD_TEST_SCENE) is PackedScene
	)
	_test("Level input controller test scene exists", func():
		return load(LEVEL_INPUT_CONTROLLER_TEST_SCENE) is PackedScene
	)
	_test("Level HUD controller test scene exists", func():
		return load(LEVEL_HUD_CONTROLLER_TEST_SCENE) is PackedScene
	)
	_test("Level camera controller test scene exists", func():
		return load(LEVEL_CAMERA_CONTROLLER_TEST_SCENE) is PackedScene
	)
	_test("Level layout regen test scene exists", func():
		return load(LEVEL_LAYOUT_REGEN_TEST_SCENE) is PackedScene
	)
	_test("Level layout floor test scene exists", func():
		return load(LEVEL_LAYOUT_FLOOR_TEST_SCENE) is PackedScene
	)
	_test("Level transition controller test scene exists", func():
		return load(LEVEL_TRANSITION_CONTROLLER_TEST_SCENE) is PackedScene
	)
	_test("Level enemy runtime controller test scene exists", func():
		return load(LEVEL_ENEMY_RUNTIME_CONTROLLER_TEST_SCENE) is PackedScene
	)
	_test("Level events controller test scene exists", func():
		return load(LEVEL_EVENTS_CONTROLLER_TEST_SCENE) is PackedScene
	)
	_test("Level bootstrap controller test scene exists", func():
		return load(LEVEL_BOOTSTRAP_CONTROLLER_TEST_SCENE) is PackedScene
	)
	_test("Mission transition gate test scene exists", func():
		return load(MISSION_TRANSITION_GATE_TEST_SCENE) is PackedScene
	)

	await _run_embedded_scene_suite("Level runtime guard suite", LEVEL_RUNTIME_GUARD_TEST_SCENE)
	await _run_embedded_scene_suite("Level input controller suite", LEVEL_INPUT_CONTROLLER_TEST_SCENE)
	await _run_embedded_scene_suite("Level HUD controller suite", LEVEL_HUD_CONTROLLER_TEST_SCENE)
	await _run_embedded_scene_suite("Level camera controller suite", LEVEL_CAMERA_CONTROLLER_TEST_SCENE)
	await _run_embedded_scene_suite("Level layout controller regen suite", LEVEL_LAYOUT_REGEN_TEST_SCENE)
	await _run_embedded_scene_suite("Level layout floor rebuild suite", LEVEL_LAYOUT_FLOOR_TEST_SCENE)
	await _run_embedded_scene_suite("Level transition controller suite", LEVEL_TRANSITION_CONTROLLER_TEST_SCENE)
	await _run_embedded_scene_suite("Level enemy runtime controller suite", LEVEL_ENEMY_RUNTIME_CONTROLLER_TEST_SCENE)
	await _run_embedded_scene_suite("Level events controller suite", LEVEL_EVENTS_CONTROLLER_TEST_SCENE)
	await _run_embedded_scene_suite("Level bootstrap controller suite", LEVEL_BOOTSTRAP_CONTROLLER_TEST_SCENE)
	await _run_embedded_scene_suite("Mission transition gate suite", MISSION_TRANSITION_GATE_TEST_SCENE)

	print("\nAll tests completed (Core + AI + Door + Alert + Decomposition suites).")


func _test(name: String, test_func: Callable) -> void:
	_tests_run += 1
	var result: bool = false

	result = test_func.call()

	if result:
		_tests_passed += 1
		print("[PASS] %s" % name)
	else:
		print("[FAIL] %s" % name)


func _run_embedded_scene_suite(name: String, scene_path: String) -> void:
	_tests_run += 1
	var scene := load(scene_path) as PackedScene
	if scene == null:
		print("[FAIL] %s (scene load failed: %s)" % [name, scene_path])
		return

	var node := scene.instantiate()
	if node == null:
		print("[FAIL] %s (instantiate failed)" % name)
		return

	if _has_property(node, "embedded_mode"):
		node.set("embedded_mode", true)
	add_child(node)

	if not node.has_method("run_suite"):
		print("[FAIL] %s (run_suite missing)" % name)
		node.queue_free()
		await get_tree().process_frame
		return

	var result_variant: Variant = await node.run_suite()
	var result := result_variant as Dictionary
	var ok := bool(result.get("ok", false))
	if ok:
		_tests_passed += 1
		print("[PASS] %s (%d/%d)" % [name, int(result.get("passed", 0)), int(result.get("run", 0))])
	else:
		print("[FAIL] %s (%d/%d)" % [name, int(result.get("passed", 0)), int(result.get("run", 0))])

	node.queue_free()
	await get_tree().process_frame


func _has_property(obj: Object, property_name: String) -> bool:
	for p_variant in obj.get_property_list():
		var p := p_variant as Dictionary
		if String(p.get("name", "")) == property_name:
			return true
	return false
