## test_runner_node.gd
## Test runner node - runs tests when scene loads (autoloads are available).
## Run via: godot --headless res://tests/test_runner.tscn
extends Node

var _tests_run := 0
var _tests_passed := 0

const AWARENESS_TEST_SCENE := "res://tests/test_enemy_awareness_system.tscn"
const CONFIRM_HOSTILITY_TEST_SCENE := "res://tests/test_confirm_hostility.tscn"
const AGGRO_TEST_SCENE := "res://tests/test_enemy_aggro_coordinator.tscn"
const NOISE_FLOW_TEST_SCENE := "res://tests/test_enemy_noise_alert_flow.tscn"
const DOOR_CONTROLLER_TEST_SCENE := "res://tests/test_door_controller_full.tscn"
const DOOR_INTERACTION_FLOW_SCENE := "res://tests/test_door_interaction_flow.tscn"
const DOOR_SELECTION_METRIC_SCENE := "res://tests/test_layout_door_selection_metric.tscn"
const ALERT_MARKER_TEST_SCENE := "res://tests/test_enemy_alert_marker.tscn"
const ALERT_SYSTEM_TEST_SCENE := "res://tests/test_enemy_alert_system.tscn"
const SQUAD_SYSTEM_TEST_SCENE := "res://tests/test_enemy_squad_system.tscn"
const UTILITY_BRAIN_TEST_SCENE := "res://tests/test_enemy_utility_brain.tscn"
const PURSUIT_MODE_SELECTION_BY_CONTEXT_TEST_SCENE := "res://tests/test_pursuit_mode_selection_by_context.tscn"
const MODE_TRANSITION_GUARD_NO_JITTER_TEST_SCENE := "res://tests/test_mode_transition_guard_no_jitter.tscn"
const BEHAVIOR_INTEGRATION_TEST_SCENE := "res://tests/test_enemy_behavior_integration.tscn"
const RUNTIME_BUDGET_SCHEDULER_TEST_SCENE := "res://tests/test_enemy_runtime_budget_scheduler.tscn"
const CONFIG_VALIDATOR_AI_BALANCE_TEST_SCENE := "res://tests/test_config_validator_ai_balance.tscn"
const GAME_CONFIG_RESET_CONSISTENCY_NON_LAYOUT_TEST_SCENE := "res://tests/test_game_config_reset_consistency_non_layout.tscn"
const GAME_SYSTEMS_RUNTIME_TEST_SCENE := "res://tests/test_game_systems_runtime.tscn"
const PHYSICS_WORLD_RUNTIME_TEST_SCENE := "res://tests/test_physics_world_runtime.tscn"
const ENEMY_SUSPICION_TEST_SCENE := "res://tests/test_enemy_suspicion.tscn"
const SUSPICION_CONFIG_IN_STEALTH_CANON_TEST_SCENE := "res://tests/test_suspicion_config_in_stealth_canon.tscn"
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
const AI_TRANSITION_SINGLE_OWNER_TEST_SCENE := "res://tests/test_ai_transition_single_owner.tscn"
const AI_NO_DUPLICATE_STATE_CHANGE_PER_TICK_TEST_SCENE := "res://tests/test_ai_no_duplicate_state_change_per_tick.tscn"
const THREE_ZONE_PLAYER_WEAPON_SWITCH_TEST_SCENE := "res://tests/test_3zone_player_weapon_switch_to_shotgun.tscn"
const THREE_ZONE_PLAYER_SHOTGUN_FIRE_PIPELINE_TEST_SCENE := "res://tests/test_3zone_player_shotgun_fire_pipeline.tscn"
const THREE_ZONE_ENEMY_EACH_SPAWN_FIRES_SHOTGUN_TEST_SCENE := "res://tests/test_3zone_enemy_each_spawn_fires_shotgun.tscn"
const ENEMY_SHOTGUN_FIRE_BLOCK_REASONS_TEST_SCENE := "res://tests/test_enemy_shotgun_fire_block_reasons.tscn"
const ALERT_TO_COMBAT_REQUIRES_5S_CONFIRM_TEST_SCENE := "res://tests/test_alert_to_combat_requires_5s_continuous_confirm.tscn"
const PEEK_CORNER_CONFIRM_THRESHOLD_TEST_SCENE := "res://tests/test_peek_corner_confirm_threshold.tscn"
const NO_COMBAT_LATCH_BEFORE_CONFIRM_COMPLETE_TEST_SCENE := "res://tests/test_no_combat_latch_before_confirm_complete.tscn"
const LAST_SEEN_ONLY_IN_SUSPICIOUS_ALERT_TEST_SCENE := "res://tests/test_last_seen_used_only_in_suspicious_alert.tscn"
const TEAMMATE_CALL_DEDUP_AND_COOLDOWN_TEST_SCENE := "res://tests/test_teammate_call_dedup_and_cooldown.tscn"
const ALERT_CALL_ONLY_ON_STATE_ENTRY_TEST_SCENE := "res://tests/test_alert_call_only_on_state_entry.tscn"
const ALERT_DEGRADE_HOLD_GRACE_DECAY_TEST_SCENE := "res://tests/test_alert_degrade_hold_grace_decay.tscn"
const SUSPICION_CHANNELS_VS_CONFIRM_CHANNEL_TEST_SCENE := "res://tests/test_suspicion_channels_vs_confirm_channel.tscn"
const TEAMMATE_CALL_ROOM_GRAPH_GATE_TEST_SCENE := "res://tests/test_teammate_call_room_graph_gate_no_telepathy.tscn"
const COMBAT_ROLE_LOCK_AND_REASSIGN_TRIGGERS_TEST_SCENE := "res://tests/test_combat_role_lock_and_reassign_triggers.tscn"
const COMBAT_SEARCH_PER_ROOM_BUDGET_AND_TOTAL_CAP_TEST_SCENE := "res://tests/test_combat_search_per_room_budget_and_total_cap.tscn"
const COMBAT_NEXT_ROOM_SCORING_NO_LOOPS_TEST_SCENE := "res://tests/test_combat_next_room_scoring_no_loops.tscn"
const COMBAT_TO_ALERT_REQUIRES_NO_CONTACT_AND_SEARCH_PROGRESS_TEST_SCENE := "res://tests/test_combat_to_alert_requires_no_contact_and_search_progress.tscn"
const FIRST_SHOT_DELAY_STARTS_ON_FIRST_VALID_FIRING_SOLUTION_TEST_SCENE := "res://tests/test_first_shot_delay_starts_on_first_valid_firing_solution.tscn"
const FIRST_SHOT_TIMER_STARTS_ON_FIRST_VALID_FIRING_SOLUTION_TEST_SCENE := "res://tests/test_first_shot_timer_starts_on_first_valid_firing_solution.tscn"
const FIRST_SHOT_TIMER_PAUSE_AND_RESET_AFTER_2_5S_TEST_SCENE := "res://tests/test_first_shot_timer_pause_and_reset_after_2_5s.tscn"
const TELEGRAPH_PROFILE_PRODUCTION_VS_DEBUG_TEST_SCENE := "res://tests/test_telegraph_profile_production_vs_debug.tscn"
const ENEMY_DAMAGE_IS_EXACTLY_1HP_PER_SUCCESSFUL_SHOT_TEST_SCENE := "res://tests/test_enemy_damage_is_exactly_1hp_per_successful_shot.tscn"
const COMBAT_DAMAGE_ESCALATION_PIPELINE_TEST_SCENE := "res://tests/test_combat_damage_escalation_pipeline.tscn"
const ENEMY_DAMAGE_API_SINGLE_SOURCE_TEST_SCENE := "res://tests/test_enemy_damage_api_single_source.tscn"
const ENEMY_FIRE_COOLDOWN_MIN_GUARD_TEST_SCENE := "res://tests/test_enemy_fire_cooldown_min_guard.tscn"
const ENEMY_FIRE_DECISION_CONTRACT_TEST_SCENE := "res://tests/test_enemy_fire_decision_contract.tscn"
const ENEMY_FIRE_TRACE_CACHE_RUNTIME_TEST_SCENE := "res://tests/test_enemy_fire_trace_cache_runtime.tscn"
const PURSUIT_INTENT_ONLY_RUNTIME_TEST_SCENE := "res://tests/test_pursuit_intent_only_runtime.tscn"
const PURSUIT_STALL_FALLBACK_INVARIANTS_TEST_SCENE := "res://tests/test_pursuit_stall_fallback_invariants.tscn"
const PURSUIT_ORIGIN_TARGET_NOT_SENTINEL_TEST_SCENE := "res://tests/test_pursuit_origin_target_not_sentinel.tscn"
const ALERT_COMBAT_CONTEXT_NEVER_PATROL_TEST_SCENE := "res://tests/test_alert_combat_context_never_patrol.tscn"
const NAVIGATION_RUNTIME_QUERIES_TEST_SCENE := "res://tests/test_navigation_runtime_queries.tscn"
const NAVIGATION_FAILURE_REASON_CONTRACT_TEST_SCENE := "res://tests/test_navigation_failure_reason_contract.tscn"
const NAV_OBSTACLE_FALLBACK_TEST_SCENE := "res://tests/test_nav_obstacle_extraction_fallback.tscn"
const NAV_CLEARANCE_MARGIN_TEST_SCENE := "res://tests/test_nav_clearance_margin_avoids_wall_hugging.tscn"
const NAVIGATION_POLICY_DETOUR_BLOCKED_TEST_SCENE := "res://tests/test_navigation_policy_detour_shadow_blocked_direct.tscn"
const NAVIGATION_POLICY_DETOUR_TWO_WP_TEST_SCENE := "res://tests/test_navigation_policy_detour_two_waypoints.tscn"
const NAVIGATION_SHADOW_POLICY_RUNTIME_TEST_SCENE := "res://tests/test_navigation_shadow_policy_runtime.tscn"
const NAVIGATION_SHOT_GATE_PARITY_TEST_SCENE := "res://tests/test_navigation_shot_gate_parity.tscn"
const NAVIGATION_PATH_POLICY_PARITY_TEST_SCENE := "res://tests/test_navigation_path_policy_parity.tscn"
const NAVIGATION_SHADOW_COST_PREFERS_COVER_PATH_TEST_SCENE := "res://tests/test_navigation_shadow_cost_prefers_cover_path.tscn"
const NAVIGATION_SHADOW_COST_PUSH_MODE_SHORTCUT_TEST_SCENE := "res://tests/test_navigation_shadow_cost_push_mode_allows_shortcut.tscn"
const TACTIC_CONTAIN_EXIT_SLOTS_TEST_SCENE := "res://tests/test_tactic_contain_assigns_exit_slots.tscn"
const TACTIC_FLANK_BUDGET_GUARD_TEST_SCENE := "res://tests/test_tactic_flank_requires_path_and_time_budget.tscn"
const MULTI_ENEMY_PRESSURE_NO_PATROL_REGRESSION_TEST_SCENE := "res://tests/test_multi_enemy_pressure_no_patrol_regression.tscn"
const SHADOW_SEARCH_STAGE_TRANSITION_TEST_SCENE := "res://tests/test_shadow_search_stage_transition_contract.tscn"
const SHADOW_SEARCH_PROGRESSIVE_COVERAGE_TEST_SCENE := "res://tests/test_shadow_search_choreography_progressive_coverage.tscn"
const FLASHLIGHT_SCANNER_ROLE_ASSIGNMENT_TEST_SCENE := "res://tests/test_flashlight_single_scanner_role_assignment.tscn"
const TEAM_CONTAIN_FLASHLIGHT_PRESSURE_TEST_SCENE := "res://tests/test_team_contain_with_flashlight_pressure.tscn"
const COMM_DELAY_PREVENTS_TELEPATHY_TEST_SCENE := "res://tests/test_comm_delay_prevents_telepathy.tscn"
const REACTION_LATENCY_WINDOW_RESPECTED_TEST_SCENE := "res://tests/test_reaction_latency_window_respected.tscn"
const SEEDED_VARIATION_DETERMINISTIC_PER_SEED_TEST_SCENE := "res://tests/test_seeded_variation_deterministic_per_seed.tscn"
const BLOOD_EVIDENCE_INVESTIGATE_ANCHOR_TEST_SCENE := "res://tests/test_blood_evidence_sets_investigate_anchor.tscn"
const BLOOD_EVIDENCE_NO_INSTANT_COMBAT_TEST_SCENE := "res://tests/test_blood_evidence_no_instant_combat_without_confirm.tscn"
const BLOOD_EVIDENCE_TTL_EXPIRES_TEST_SCENE := "res://tests/test_blood_evidence_ttl_expires.tscn"
const FRIENDLY_BLOCK_PREVENTS_FIRE_AND_TRIGGERS_REPOSITION_TEST_SCENE := "res://tests/test_friendly_block_prevents_fire_and_triggers_reposition.tscn"
const SHADOW_FLASHLIGHT_RULE_BLOCKS_OR_ALLOWS_FIRE_TEST_SCENE := "res://tests/test_shadow_flashlight_rule_blocks_or_allows_fire.tscn"
const SHADOW_SINGLE_SOURCE_OF_TRUTH_NAV_AND_DETECTION_TEST_SCENE := "res://tests/test_shadow_single_source_of_truth_nav_and_detection.tscn"
const SHADOW_POLICY_HARD_BLOCK_WITHOUT_GRANT_TEST_SCENE := "res://tests/test_shadow_policy_hard_block_without_grant.tscn"
const SHADOW_ENEMY_STUCK_WHEN_INSIDE_SHADOW_TEST_SCENE := "res://tests/test_shadow_enemy_stuck_when_inside_shadow.tscn"
const SHADOW_ENEMY_UNSTUCK_AFTER_FLASHLIGHT_ACTIVATION_TEST_SCENE := "res://tests/test_shadow_enemy_unstuck_after_flashlight_activation.tscn"
const SHADOW_STALL_ESCAPES_TO_LIGHT_TEST_SCENE := "res://tests/test_shadow_stall_escapes_to_light.tscn"
const SHADOW_UNREACHABLE_CANON_TEST_SCENE := "res://tests/test_shadow_unreachable_transitions_to_search_not_patrol.tscn"
const DOOR_ENEMY_OBLIQUE_OPEN_THEN_CROSS_NO_WALL_STALL_TEST_SCENE := "res://tests/test_door_enemy_oblique_open_then_cross_no_wall_stall.tscn"
const STALL_DEFINITION_REPRODUCIBLE_THRESHOLDS_TEST_SCENE := "res://tests/test_stall_definition_reproducible_thresholds.tscn"
const PURSUIT_PLAN_LOCK_EDGE_CASE_TEST_SCENE := "res://tests/test_nearest_reachable_fallback_by_nav_distance.tscn"
const ZONE_DIRECTOR_SINGLE_OWNER_TRANSITIONS_TEST_SCENE := "res://tests/test_zone_director_single_owner_transitions.tscn"
const ZONE_HYSTERESIS_HOLD_AND_NO_EVENT_DECAY_TEST_SCENE := "res://tests/test_zone_hysteresis_hold_and_no_event_decay.tscn"
const ZONE_STATE_MACHINE_CONTRACT_TEST_SCENE := "res://tests/test_zone_state_machine_contract.tscn"
const ZONE_REINFORCEMENT_BUDGET_CONTRACT_TEST_SCENE := "res://tests/test_zone_reinforcement_budget_contract.tscn"
const ZONE_PROFILE_MODIFIERS_EXACT_VALUES_TEST_SCENE := "res://tests/test_zone_profile_modifiers_exact_values.tscn"
const CONFIRM_5S_INVARIANT_ACROSS_ZONE_PROFILES_TEST_SCENE := "res://tests/test_confirm_5s_invariant_across_zone_profiles.tscn"
const WAVE_CALL_PERMISSION_MATRIX_AND_COOLDOWNS_TEST_SCENE := "res://tests/test_wave_call_permission_matrix_and_cooldowns.tscn"
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
const COLLISION_BLOCK_FORCES_IMMEDIATE_REPATH_TEST_SCENE := "res://tests/test_collision_block_forces_immediate_repath.tscn"
const COLLISION_BLOCK_PRESERVES_INTENT_CONTEXT_TEST_SCENE := "res://tests/test_collision_block_preserves_intent_context.tscn"
const HONEST_REPATH_WITHOUT_TELEPORT_TEST_SCENE := "res://tests/test_honest_repath_without_teleport.tscn"
const FLASHLIGHT_ACTIVE_IN_COMBAT_TEST_SCENE := "res://tests/test_flashlight_active_in_combat_when_latched.tscn"
const FLASHLIGHT_SINGLE_SOURCE_PARITY_TEST_SCENE := "res://tests/test_flashlight_single_source_parity.tscn"
const FLASHLIGHT_BONUS_IN_COMBAT_TEST_SCENE := "res://tests/test_flashlight_bonus_applies_in_combat.tscn"
const ALERT_HOLD_DYNAMIC_TEST_SCENE := "res://tests/test_alert_hold_dynamic.tscn"
const PATROL_ROUTE_VARIETY_TEST_SCENE := "res://tests/test_patrol_route_variety.tscn"
const PATROL_ROUTE_TRAVERSABILITY_FILTER_TEST_SCENE := "res://tests/test_patrol_route_traversability_filter.tscn"
const ALERT_INVESTIGATE_ANCHOR_TEST_SCENE := "res://tests/test_alert_investigate_anchor.tscn"
const ALERT_COMBAT_SHADOW_BOUNDARY_SCAN_INTENT_TEST_SCENE := "res://tests/test_alert_combat_shadow_boundary_scan_intent.tscn"
const SUSPICIOUS_SHADOW_SCAN_TEST_SCENE := "res://tests/test_suspicious_shadow_scan.tscn"
const SHADOW_ROUTE_FILTER_TEST_SCENE := "res://tests/test_shadow_route_filter.tscn"
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
const AI_LONG_RUN_STRESS_TEST_SCENE := "res://tests/test_ai_long_run_stress.tscn"
const ENEMY_CROWD_AVOIDANCE_REDUCES_JAMS_TEST_SCENE := "res://tests/test_enemy_crowd_avoidance_reduces_jams.tscn"
const REFACTOR_KPI_CONTRACT_TEST_SCENE := "res://tests/test_refactor_kpi_contract.tscn"
const ENEMY_SCRIPT := preload("res://src/entities/enemy.gd")
const ENEMY_AWARENESS_SYSTEM_SCRIPT := preload("res://src/systems/enemy_awareness_system.gd")
const ENEMY_PATROL_SYSTEM_SCRIPT := preload("res://src/systems/enemy_patrol_system.gd")
const ENEMY_PURSUIT_SYSTEM_SCRIPT := preload("res://src/systems/enemy_pursuit_system.gd")
const NAVIGATION_SERVICE_SCRIPT := preload("res://src/systems/navigation_service.gd")


class PhaseShadowNavStub:
	extends Node

	var in_shadow: bool = true

	func is_point_in_shadow(_point: Vector2) -> bool:
		return in_shadow


class PhaseShadowOwner:
	extends CharacterBody2D

	var flashlight_active_for_nav: bool = false

	func is_flashlight_active_for_navigation() -> bool:
		return flashlight_active_for_nav


class PhaseShadowZoneStub:
	extends Node2D

	func contains_point(_point: Vector2) -> bool:
		return true

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

	_test("GameConfig.stealth_canon has all 8 Phase 0 keys", func():
		if not (GameConfig.stealth_canon is Dictionary):
			return false
		var canon := GameConfig.stealth_canon as Dictionary
		var required_keys := [
			"confirm_time_to_engage",
			"confirm_decay_rate",
			"confirm_grace_window",
			"minimum_hold_alert_sec",
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
		return _scene_exists(AWARENESS_TEST_SCENE)
	)
	_test("Confirm hostility test scene exists", func():
		return _scene_exists(CONFIRM_HOSTILITY_TEST_SCENE)
	)
	_test("Aggro coordinator test scene exists", func():
		return _scene_exists(AGGRO_TEST_SCENE)
	)
	_test("Noise alert flow test scene exists", func():
		return _scene_exists(NOISE_FLOW_TEST_SCENE)
	)
	_test("Door controller test scene exists", func():
		return _scene_exists(DOOR_CONTROLLER_TEST_SCENE)
	)
	_test("Door interaction flow test scene exists", func():
		return _scene_exists(DOOR_INTERACTION_FLOW_SCENE)
	)
	_test("Door selection metric test scene exists", func():
		return _scene_exists(DOOR_SELECTION_METRIC_SCENE)
	)
	_test("Enemy alert marker test scene exists", func():
		return _scene_exists(ALERT_MARKER_TEST_SCENE)
	)
	_test("Enemy alert system test scene exists", func():
		return _scene_exists(ALERT_SYSTEM_TEST_SCENE)
	)
	_test("Enemy squad system test scene exists", func():
		return _scene_exists(SQUAD_SYSTEM_TEST_SCENE)
	)
	_test("Enemy utility brain test scene exists", func():
		return _scene_exists(UTILITY_BRAIN_TEST_SCENE)
	)
	_test("Pursuit mode selection by context test scene exists", func():
		return _scene_exists(PURSUIT_MODE_SELECTION_BY_CONTEXT_TEST_SCENE)
	)
	_test("Mode transition guard no jitter test scene exists", func():
		return _scene_exists(MODE_TRANSITION_GUARD_NO_JITTER_TEST_SCENE)
	)
	_test("Enemy behavior integration test scene exists", func():
		return _scene_exists(BEHAVIOR_INTEGRATION_TEST_SCENE)
	)
	_test("Enemy runtime budget scheduler test scene exists", func():
		return _scene_exists(RUNTIME_BUDGET_SCHEDULER_TEST_SCENE)
	)
	_test("Config validator AI balance test scene exists", func():
		return _scene_exists(CONFIG_VALIDATOR_AI_BALANCE_TEST_SCENE)
	)
	_test("GameConfig reset consistency (non-layout) test scene exists", func():
		return _scene_exists(GAME_CONFIG_RESET_CONSISTENCY_NON_LAYOUT_TEST_SCENE)
	)
	_test("Enemy suspicion test scene exists", func():
		return _scene_exists(ENEMY_SUSPICION_TEST_SCENE)
	)
	_test("Suspicion config in stealth canon test scene exists", func():
		return _scene_exists(SUSPICION_CONFIG_IN_STEALTH_CANON_TEST_SCENE)
	)
	_test("Flashlight cone test scene exists", func():
		return _scene_exists(FLASHLIGHT_CONE_TEST_SCENE)
	)
	_test("Alert flashlight detection test scene exists", func():
		return _scene_exists(ALERT_FLASHLIGHT_DETECTION_TEST_SCENE)
	)
	_test("Stealth room smoke test scene exists", func():
		return _scene_exists(STEALTH_ROOM_SMOKE_TEST_SCENE)
	)
	_test("Force state path test scene exists", func():
		return _scene_exists(FORCE_STATE_PATH_TEST_SCENE)
	)
	_test("Weapons toggle gate test scene exists", func():
		return _scene_exists(WEAPONS_TOGGLE_GATE_TEST_SCENE)
	)
	_test("Player scene identity test scene exists", func():
		return _scene_exists(PLAYER_SCENE_IDENTITY_TEST_SCENE)
	)
	_test("Combat obstacle chase basic test scene exists", func():
		return _scene_exists(COMBAT_OBSTACLE_CHASE_BASIC_TEST_SCENE)
	)
	_test("DebugUI single owner test scene exists", func():
		return _scene_exists(DEBUGUI_SINGLE_OWNER_TEST_SCENE)
	)
	_test("Stealth weapon pipeline equivalence test scene exists", func():
		return _scene_exists(STEALTH_WEAPON_PIPELINE_EQ_TEST_SCENE)
	)
	_test("Stealth room alert flashlight integration test scene exists", func():
		return _scene_exists(STEALTH_ROOM_ALERT_FLASHLIGHT_INTEGRATION_TEST_SCENE)
	)
	_test("Ring visibility policy test scene exists", func():
		return _scene_exists(RING_VISIBILITY_POLICY_TEST_SCENE)
	)
	_test("Shadow zone test scene exists", func():
		return _scene_exists(SHADOW_ZONE_TEST_SCENE)
	)
	_test("Marker semantics mapping test scene exists", func():
		return _scene_exists(MARKER_SEMANTICS_MAPPING_TEST_SCENE)
	)
	_test("Ring visible during decay test scene exists", func():
		return _scene_exists(RING_VISIBLE_DURING_DECAY_TEST_SCENE)
	)
	_test("Weapons startup policy ON test scene exists", func():
		return _scene_exists(WEAPONS_STARTUP_POLICY_ON_TEST_SCENE)
	)
	_test("DebugUI layout no overlap test scene exists", func():
		return _scene_exists(DEBUGUI_LAYOUT_NO_OVERLAP_TEST_SCENE)
	)
	_test("EventBus backpressure test scene exists", func():
		return _scene_exists(EVENT_BUS_BACKPRESSURE_TEST_SCENE)
	)
	_test("3zone combat transition stress test scene exists", func():
		return _scene_exists(COMBAT_TRANSITION_STRESS_3ZONE_TEST_SCENE)
	)
	_test("AI long-run stress test scene exists", func():
		return _scene_exists(AI_LONG_RUN_STRESS_TEST_SCENE)
	)
	_test("Enemy crowd avoidance reduces jams test scene exists", func():
		return _scene_exists(ENEMY_CROWD_AVOIDANCE_REDUCES_JAMS_TEST_SCENE)
	)

	await _run_embedded_scene_suite("Config validator AI balance suite", CONFIG_VALIDATOR_AI_BALANCE_TEST_SCENE)
	await _run_embedded_scene_suite("GameConfig reset consistency (non-layout) suite", GAME_CONFIG_RESET_CONSISTENCY_NON_LAYOUT_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy awareness suite", AWARENESS_TEST_SCENE)
	await _run_embedded_scene_suite("Confirm hostility suite", CONFIRM_HOSTILITY_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy aggro coordinator suite", AGGRO_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy noise alert flow suite", NOISE_FLOW_TEST_SCENE)
	await _run_embedded_scene_suite("Door controller full suite", DOOR_CONTROLLER_TEST_SCENE)
	await _run_embedded_scene_suite("Door interaction flow suite", DOOR_INTERACTION_FLOW_SCENE)
	await _run_embedded_scene_suite("Door selection metric suite", DOOR_SELECTION_METRIC_SCENE)
	await _run_embedded_scene_suite("Enemy alert marker suite", ALERT_MARKER_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy alert system suite", ALERT_SYSTEM_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy squad system suite", SQUAD_SYSTEM_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy utility brain suite", UTILITY_BRAIN_TEST_SCENE)
	await _run_embedded_scene_suite("Pursuit mode selection by context suite", PURSUIT_MODE_SELECTION_BY_CONTEXT_TEST_SCENE)
	await _run_embedded_scene_suite("Mode transition guard no jitter suite", MODE_TRANSITION_GUARD_NO_JITTER_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy behavior integration suite", BEHAVIOR_INTEGRATION_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy runtime budget scheduler suite", RUNTIME_BUDGET_SCHEDULER_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy suspicion suite", ENEMY_SUSPICION_TEST_SCENE)
	await _run_embedded_scene_suite("Suspicion config in stealth canon suite", SUSPICION_CONFIG_IN_STEALTH_CANON_TEST_SCENE)
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
	await _run_embedded_scene_suite("AI long-run stress suite", AI_LONG_RUN_STRESS_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy crowd avoidance reduces jams suite", ENEMY_CROWD_AVOIDANCE_REDUCES_JAMS_TEST_SCENE)

	print("\n--- SECTION 18b: Stealth phases 1-7 suites ---")

	_test("Stealth room combat fire test scene exists", func():
		return _scene_exists(STEALTH_ROOM_COMBAT_FIRE_TEST_SCENE)
	)
	_test("Stealth room LKP search test scene exists", func():
		return _scene_exists(STEALTH_ROOM_LKP_SEARCH_TEST_SCENE)
	)
	_test("Combat room alert sync test scene exists", func():
		return _scene_exists(COMBAT_ROOM_ALERT_SYNC_TEST_SCENE)
	)
	_test("AI transition single owner test scene exists", func():
		return _scene_exists(AI_TRANSITION_SINGLE_OWNER_TEST_SCENE)
	)
	_test("AI no duplicate state change per tick test scene exists", func():
		return _scene_exists(AI_NO_DUPLICATE_STATE_CHANGE_PER_TICK_TEST_SCENE)
	)
	_test("3zone player weapon switch test scene exists", func():
		return _scene_exists(THREE_ZONE_PLAYER_WEAPON_SWITCH_TEST_SCENE)
	)
	_test("3zone player shotgun fire pipeline test scene exists", func():
		return _scene_exists(THREE_ZONE_PLAYER_SHOTGUN_FIRE_PIPELINE_TEST_SCENE)
	)
	_test("3zone each enemy spawn fires shotgun test scene exists", func():
		return _scene_exists(THREE_ZONE_ENEMY_EACH_SPAWN_FIRES_SHOTGUN_TEST_SCENE)
	)
	_test("Enemy shotgun fire block reasons test scene exists", func():
		return _scene_exists(ENEMY_SHOTGUN_FIRE_BLOCK_REASONS_TEST_SCENE)
	)
	_test("Alert->Combat requires 5s confirm test scene exists", func():
		return _scene_exists(ALERT_TO_COMBAT_REQUIRES_5S_CONFIRM_TEST_SCENE)
	)
	_test("Peek corner confirm threshold test scene exists", func():
		return _scene_exists(PEEK_CORNER_CONFIRM_THRESHOLD_TEST_SCENE)
	)
	_test("No combat latch before confirm complete test scene exists", func():
		return _scene_exists(NO_COMBAT_LATCH_BEFORE_CONFIRM_COMPLETE_TEST_SCENE)
	)
	_test("Last seen only in suspicious/alert test scene exists", func():
		return _scene_exists(LAST_SEEN_ONLY_IN_SUSPICIOUS_ALERT_TEST_SCENE)
	)
	_test("Teammate call dedup/cooldown test scene exists", func():
		return _scene_exists(TEAMMATE_CALL_DEDUP_AND_COOLDOWN_TEST_SCENE)
	)
	_test("Alert call only on state entry test scene exists", func():
		return _scene_exists(ALERT_CALL_ONLY_ON_STATE_ENTRY_TEST_SCENE)
	)
	_test("Alert degrade hold/grace/decay test scene exists", func():
		return _scene_exists(ALERT_DEGRADE_HOLD_GRACE_DECAY_TEST_SCENE)
	)
	_test("Suspicion channels vs confirm channel test scene exists", func():
		return _scene_exists(SUSPICION_CHANNELS_VS_CONFIRM_CHANNEL_TEST_SCENE)
	)
	_test("Teammate call room-graph gate test scene exists", func():
		return _scene_exists(TEAMMATE_CALL_ROOM_GRAPH_GATE_TEST_SCENE)
	)
	_test("Combat role lock/reassign triggers test scene exists", func():
		return _scene_exists(COMBAT_ROLE_LOCK_AND_REASSIGN_TRIGGERS_TEST_SCENE)
	)
	_test("Combat search per-room budget/total cap test scene exists", func():
		return _scene_exists(COMBAT_SEARCH_PER_ROOM_BUDGET_AND_TOTAL_CAP_TEST_SCENE)
	)
	_test("Combat next-room scoring test scene exists", func():
		return _scene_exists(COMBAT_NEXT_ROOM_SCORING_NO_LOOPS_TEST_SCENE)
	)
	_test("Combat->Alert search/no-contact gate test scene exists", func():
		return _scene_exists(COMBAT_TO_ALERT_REQUIRES_NO_CONTACT_AND_SEARCH_PROGRESS_TEST_SCENE)
	)
	_test("First-shot-delay on first valid firing solution test scene exists", func():
		return _scene_exists(FIRST_SHOT_DELAY_STARTS_ON_FIRST_VALID_FIRING_SOLUTION_TEST_SCENE)
	)
	_test("First-shot timer starts on first valid contact test scene exists", func():
		return _scene_exists(FIRST_SHOT_TIMER_STARTS_ON_FIRST_VALID_FIRING_SOLUTION_TEST_SCENE)
	)
	_test("First-shot timer pause/reset 2.5s test scene exists", func():
		return _scene_exists(FIRST_SHOT_TIMER_PAUSE_AND_RESET_AFTER_2_5S_TEST_SCENE)
	)
	_test("Telegraph profile production/debug test scene exists", func():
		return _scene_exists(TELEGRAPH_PROFILE_PRODUCTION_VS_DEBUG_TEST_SCENE)
	)
	_test("Enemy damage exactly 1hp per successful shot test scene exists", func():
		return _scene_exists(ENEMY_DAMAGE_IS_EXACTLY_1HP_PER_SUCCESSFUL_SHOT_TEST_SCENE)
	)
	_test("Combat damage escalation pipeline test scene exists", func():
		return _scene_exists(COMBAT_DAMAGE_ESCALATION_PIPELINE_TEST_SCENE)
	)
	_test("Enemy damage API single source test scene exists", func():
		return _scene_exists(ENEMY_DAMAGE_API_SINGLE_SOURCE_TEST_SCENE)
	)
	_test("Enemy fire cooldown min guard test scene exists", func():
		return _scene_exists(ENEMY_FIRE_COOLDOWN_MIN_GUARD_TEST_SCENE)
	)
	_test("Enemy fire decision contract test scene exists", func():
		return _scene_exists(ENEMY_FIRE_DECISION_CONTRACT_TEST_SCENE)
	)
	_test("Enemy fire trace cache runtime test scene exists", func():
		return _scene_exists(ENEMY_FIRE_TRACE_CACHE_RUNTIME_TEST_SCENE)
	)
	_test("Friendly block prevents fire and triggers reposition test scene exists", func():
		return _scene_exists(FRIENDLY_BLOCK_PREVENTS_FIRE_AND_TRIGGERS_REPOSITION_TEST_SCENE)
	)
	_test("Shadow flashlight rule blocks/allows fire test scene exists", func():
		return _scene_exists(SHADOW_FLASHLIGHT_RULE_BLOCKS_OR_ALLOWS_FIRE_TEST_SCENE)
	)
	_test("Shadow single source of truth nav+detection test scene exists", func():
		return _scene_exists(SHADOW_SINGLE_SOURCE_OF_TRUTH_NAV_AND_DETECTION_TEST_SCENE)
	)
	_test("Shadow policy hard block without grant test scene exists", func():
		return _scene_exists(SHADOW_POLICY_HARD_BLOCK_WITHOUT_GRANT_TEST_SCENE)
	)
	_test("Shadow enemy stuck when inside shadow test scene exists", func():
		return _scene_exists(SHADOW_ENEMY_STUCK_WHEN_INSIDE_SHADOW_TEST_SCENE)
	)
	_test("Shadow enemy unstuck after flashlight activation test scene exists", func():
		return _scene_exists(SHADOW_ENEMY_UNSTUCK_AFTER_FLASHLIGHT_ACTIVATION_TEST_SCENE)
	)
	_test("Shadow stall escapes to light test scene exists", func():
		return _scene_exists(SHADOW_STALL_ESCAPES_TO_LIGHT_TEST_SCENE)
	)
	_test("Shadow unreachable canon transition test scene exists", func():
		return _scene_exists(SHADOW_UNREACHABLE_CANON_TEST_SCENE)
	)
	_test("Door enemy oblique open then cross no wall stall test scene exists", func():
		return _scene_exists(DOOR_ENEMY_OBLIQUE_OPEN_THEN_CROSS_NO_WALL_STALL_TEST_SCENE)
	)
	_test("Stall definition reproducible thresholds test scene exists", func():
		return _scene_exists(STALL_DEFINITION_REPRODUCIBLE_THRESHOLDS_TEST_SCENE)
	)
	_test("Alert hold dynamic test scene exists", func():
		return _scene_exists(ALERT_HOLD_DYNAMIC_TEST_SCENE)
	)
	_test("Patrol route variety test scene exists", func():
		return _scene_exists(PATROL_ROUTE_VARIETY_TEST_SCENE)
	)
	_test("Patrol route traversability filter test scene exists", func():
		return _scene_exists(PATROL_ROUTE_TRAVERSABILITY_FILTER_TEST_SCENE)
	)
	_test("Alert investigate anchor test scene exists", func():
		return _scene_exists(ALERT_INVESTIGATE_ANCHOR_TEST_SCENE)
	)
	_test("Alert/combat shadow boundary scan intent test scene exists", func():
		return _scene_exists(ALERT_COMBAT_SHADOW_BOUNDARY_SCAN_INTENT_TEST_SCENE)
	)
	_test("Suspicious shadow scan test scene exists", func():
		return _scene_exists(SUSPICIOUS_SHADOW_SCAN_TEST_SCENE)
	)
	_test("Shadow route filter test scene exists", func():
		return _scene_exists(SHADOW_ROUTE_FILTER_TEST_SCENE)
	)
	_test("Pursuit intent-only runtime test scene exists", func():
		return _scene_exists(PURSUIT_INTENT_ONLY_RUNTIME_TEST_SCENE)
	)
	_test("Pursuit stall/fallback invariants test scene exists", func():
		return _scene_exists(PURSUIT_STALL_FALLBACK_INVARIANTS_TEST_SCENE)
	)
	_test("Pursuit origin target not sentinel test scene exists", func():
		return _scene_exists(PURSUIT_ORIGIN_TARGET_NOT_SENTINEL_TEST_SCENE)
	)
	_test("Alert/combat context never patrol test scene exists", func():
		return _scene_exists(ALERT_COMBAT_CONTEXT_NEVER_PATROL_TEST_SCENE)
	)
	_test("Navigation runtime queries test scene exists", func():
		return _scene_exists(NAVIGATION_RUNTIME_QUERIES_TEST_SCENE)
	)
	_test("Navigation failure reason contract test scene exists", func():
		return _scene_exists(NAVIGATION_FAILURE_REASON_CONTRACT_TEST_SCENE)
	)
	_test("Nav obstacle fallback test scene exists", func():
		return _scene_exists(NAV_OBSTACLE_FALLBACK_TEST_SCENE)
	)
	_test("Nav clearance margin test scene exists", func():
		return _scene_exists(NAV_CLEARANCE_MARGIN_TEST_SCENE)
	)
	_test("Navigation shadow policy runtime test scene exists", func():
		return _scene_exists(NAVIGATION_SHADOW_POLICY_RUNTIME_TEST_SCENE)
	)
	_test("Navigation shot gate parity test scene exists", func():
		return _scene_exists(NAVIGATION_SHOT_GATE_PARITY_TEST_SCENE)
	)
	_test("Navigation path policy parity test scene exists", func():
		return _scene_exists(NAVIGATION_PATH_POLICY_PARITY_TEST_SCENE)
	)
	_test("Navigation policy detour direct-blocked test scene exists", func():
		return _scene_exists(NAVIGATION_POLICY_DETOUR_BLOCKED_TEST_SCENE)
	)
	_test("Navigation policy detour two-waypoint test scene exists", func():
		return _scene_exists(NAVIGATION_POLICY_DETOUR_TWO_WP_TEST_SCENE)
	)
	_test("Navigation shadow cost prefers cover path test scene exists", func():
		return _scene_exists(NAVIGATION_SHADOW_COST_PREFERS_COVER_PATH_TEST_SCENE)
	)
	_test("Navigation shadow cost push-mode shortcut test scene exists", func():
		return _scene_exists(NAVIGATION_SHADOW_COST_PUSH_MODE_SHORTCUT_TEST_SCENE)
	)
	_test("Pursuit plan-lock edge-case test scene exists", func():
		return _scene_exists(PURSUIT_PLAN_LOCK_EDGE_CASE_TEST_SCENE)
	)
	_test("ZoneDirector single-owner transitions test scene exists", func():
		return _scene_exists(ZONE_DIRECTOR_SINGLE_OWNER_TRANSITIONS_TEST_SCENE)
	)
	_test("Zone hysteresis hold/no-event decay test scene exists", func():
		return _scene_exists(ZONE_HYSTERESIS_HOLD_AND_NO_EVENT_DECAY_TEST_SCENE)
	)
	_test("Zone state machine contract test scene exists", func():
		return _scene_exists(ZONE_STATE_MACHINE_CONTRACT_TEST_SCENE)
	)
	_test("Zone reinforcement budget contract test scene exists", func():
		return _scene_exists(ZONE_REINFORCEMENT_BUDGET_CONTRACT_TEST_SCENE)
	)
	_test("Zone profile exact values test scene exists", func():
		return _scene_exists(ZONE_PROFILE_MODIFIERS_EXACT_VALUES_TEST_SCENE)
	)
	_test("Confirm 5s invariant across zone profiles test scene exists", func():
		return _scene_exists(CONFIRM_5S_INVARIANT_ACROSS_ZONE_PROFILES_TEST_SCENE)
	)
	_test("Wave call permission matrix/cooldowns test scene exists", func():
		return _scene_exists(WAVE_CALL_PERMISSION_MATRIX_AND_COOLDOWNS_TEST_SCENE)
	)
	_test("Combat no degrade test scene exists", func():
		return _scene_exists(COMBAT_NO_DEGRADE_TEST_SCENE)
	)
	_test("Combat utility intent aggressive test scene exists", func():
		return _scene_exists(COMBAT_UTILITY_INTENT_AGGRESSIVE_TEST_SCENE)
	)
	_test("Main menu stealth entry test scene exists", func():
		return _scene_exists(MAIN_MENU_STEALTH_ENTRY_TEST_SCENE)
	)
	_test("Enemy latch register/unregister test scene exists", func():
		return _scene_exists(ENEMY_LATCH_REGISTER_UNREGISTER_TEST_SCENE)
	)
	_test("Enemy latch migration test scene exists", func():
		return _scene_exists(ENEMY_LATCH_MIGRATION_TEST_SCENE)
	)
	_test("Combat uses last seen test scene exists", func():
		return _scene_exists(COMBAT_USES_LAST_SEEN_TEST_SCENE)
	)
	_test("Last seen grace window test scene exists", func():
		return _scene_exists(LAST_SEEN_GRACE_WINDOW_TEST_SCENE)
	)
	_test("Combat no LOS never hold range test scene exists", func():
		return _scene_exists(COMBAT_NO_LOS_NEVER_HOLD_RANGE_TEST_SCENE)
	)
	_test("Combat intent push to search test scene exists", func():
		return _scene_exists(COMBAT_INTENT_PUSH_TO_SEARCH_TEST_SCENE)
	)
	_test("Detour side flip on stall test scene exists", func():
		return _scene_exists(DETOUR_SIDE_FLIP_ON_STALL_TEST_SCENE)
	)
	_test("Collision block forces immediate repath test scene exists", func():
		return _scene_exists(COLLISION_BLOCK_FORCES_IMMEDIATE_REPATH_TEST_SCENE)
	)
	_test("Collision block preserves intent context test scene exists", func():
		return _scene_exists(COLLISION_BLOCK_PRESERVES_INTENT_CONTEXT_TEST_SCENE)
	)
	_test("Honest repath without teleport test scene exists", func():
		return _scene_exists(HONEST_REPATH_WITHOUT_TELEPORT_TEST_SCENE)
	)
	_test("Flashlight active in combat test scene exists", func():
		return _scene_exists(FLASHLIGHT_ACTIVE_IN_COMBAT_TEST_SCENE)
	)
	_test("Flashlight single source parity test scene exists", func():
		return _scene_exists(FLASHLIGHT_SINGLE_SOURCE_PARITY_TEST_SCENE)
	)
	_test("Flashlight bonus in combat test scene exists", func():
		return _scene_exists(FLASHLIGHT_BONUS_IN_COMBAT_TEST_SCENE)
	)

	print("\n--- SECTION 18c: Bugfix phase unit tests ---")

	_test("Phase 1: on_heard_shot sets investigate anchor", func():
		var enemy = ENEMY_SCRIPT.new()
		enemy._awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
		enemy._awareness.reset()
		var shot_pos := Vector2(300.0, 200.0)
		enemy.on_heard_shot(0, shot_pos)
		var ok: bool = enemy._investigate_anchor == shot_pos and bool(enemy._investigate_anchor_valid)
		enemy.free()
		return ok
	)

	_test("Phase 2: noise->ALERT resets confirm progress", func():
		var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
		awareness.reset()
		awareness._confirm_progress = 0.5
		awareness._state = ENEMY_AWARENESS_SYSTEM_SCRIPT.State.SUSPICIOUS
		awareness.register_noise()
		return awareness.get_state_name() == "ALERT" and is_equal_approx(awareness._confirm_progress, 0.0)
	)

	_test("Phase 2: COMBAT->ALERT keeps confirm progress", func():
		var awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
		awareness.reset()
		awareness._state = ENEMY_AWARENESS_SYSTEM_SCRIPT.State.COMBAT
		awareness._confirm_progress = 0.8
		var transitions: Array[Dictionary] = []
		awareness._transition_to(ENEMY_AWARENESS_SYSTEM_SCRIPT.State.ALERT, "timer", transitions)
		return awareness.get_state_name() == "ALERT" and is_equal_approx(awareness._confirm_progress, 0.8)
	)

	_test("Phase 3: stuck patrol advances to next waypoint", func():
		var owner := CharacterBody2D.new()
		owner.global_position = Vector2(100.0, 0.0)
		var patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)
		patrol.configure(null, -1)
		var route: Array[Vector2] = [Vector2(500.0, 0.0), Vector2(1000.0, 0.0)]
		patrol._route = route
		patrol._route_index = 0
		patrol._state = ENEMY_PATROL_SYSTEM_SCRIPT.PatrolState.MOVE
		patrol._route_rebuild_timer = 999.0
		patrol._stuck_check_timer = 0.01
		patrol._stuck_check_last_pos = Vector2(100.0, 0.0)
		patrol.update(0.05, Vector2.RIGHT)
		var ok: bool = patrol._route_index == 1 and patrol._state == ENEMY_PATROL_SYSTEM_SCRIPT.PatrolState.PAUSE
		owner.free()
		return ok
	)

	_test("Phase 4: near shot sets flashlight delay in [0.5, 1.2]", func():
		var enemy = ENEMY_SCRIPT.new()
		enemy.global_position = Vector2.ZERO
		enemy.on_heard_shot(0, Vector2(200.0, 0.0))
		var delay := float(enemy._flashlight_activation_delay_timer)
		enemy.free()
		return delay >= 0.5 and delay <= 1.2
	)

	_test("Phase 4: far shot sets flashlight delay in [1.0, 1.8]", func():
		var enemy = ENEMY_SCRIPT.new()
		enemy.global_position = Vector2.ZERO
		enemy.on_heard_shot(0, Vector2(600.0, 0.0))
		var delay := float(enemy._flashlight_activation_delay_timer)
		enemy.free()
		return delay >= 1.0 and delay <= 1.8
	)

	_test("Phase 4: alert flashlight policy blocked while delay > 0", func():
		var enemy = ENEMY_SCRIPT.new()
		enemy._flashlight_activation_delay_timer = 1.0
		var blocked: bool = enemy._flashlight_policy_active_in_alert() == false
		enemy._flashlight_activation_delay_timer = 0.0
		var active: bool = enemy._flashlight_policy_active_in_alert() == true
		enemy.free()
		return blocked and active
	)

	_test("Phase 6: active shadow check returns look_dir and flag", func():
		var owner := CharacterBody2D.new()
		owner.global_position = Vector2.ZERO
		var patrol = ENEMY_PATROL_SYSTEM_SCRIPT.new(owner)
		patrol.configure(null, -1)
		patrol._state = ENEMY_PATROL_SYSTEM_SCRIPT.PatrolState.PAUSE
		patrol._shadow_check_active = true
		patrol._shadow_check_dir = Vector2.RIGHT
		patrol._shadow_check_phase = 0.0
		patrol._shadow_check_timer = 1.0
		var decision := patrol.update(0.1, Vector2.RIGHT)
		var ok: bool = bool(decision.get("waiting", false)) \
			and bool(decision.get("shadow_check", false)) \
			and (decision.get("look_dir", Vector2.ZERO) as Vector2).length_squared() > 0.0001
		owner.free()
		return ok
	)

	_test("Phase 6: calm flashlight override affects navigation flashlight", func():
		var enemy = ENEMY_SCRIPT.new()
		enemy._awareness = ENEMY_AWARENESS_SYSTEM_SCRIPT.new()
		enemy._awareness.reset()
		enemy.set_shadow_check_flashlight(true)
		var override_on := enemy.is_flashlight_active_for_navigation()
		enemy.set_shadow_check_flashlight(false)
		var override_off := not enemy.is_flashlight_active_for_navigation()
		enemy.free()
		return override_on and override_off
	)

	_test("Phase 6: navigation returns nearest shadow direction", func():
		var nav = NAVIGATION_SERVICE_SCRIPT.new()
		add_child(nav)
		var zone := PhaseShadowZoneStub.new()
		zone.global_position = Vector2(64.0, 0.0)
		zone.add_to_group("shadow_zones")
		add_child(zone)
		var nearest := nav.get_nearest_shadow_zone_direction(Vector2.ZERO, 96.0) as Dictionary
		var found: bool = bool(nearest.get("found", false))
		var direction := nearest.get("direction", Vector2.ZERO) as Vector2
		zone.queue_free()
		nav.queue_free()
		return found and direction.dot(Vector2.RIGHT) > 0.9
	)

	await _run_embedded_scene_suite("Stealth room combat fire suite", STEALTH_ROOM_COMBAT_FIRE_TEST_SCENE)
	await _run_embedded_scene_suite("Stealth room LKP search suite", STEALTH_ROOM_LKP_SEARCH_TEST_SCENE)
	await _run_embedded_scene_suite("Combat room alert sync suite", COMBAT_ROOM_ALERT_SYNC_TEST_SCENE)
	await _run_embedded_scene_suite("AI transition single owner suite", AI_TRANSITION_SINGLE_OWNER_TEST_SCENE)
	await _run_embedded_scene_suite("AI no duplicate state change per tick suite", AI_NO_DUPLICATE_STATE_CHANGE_PER_TICK_TEST_SCENE)
	await _run_embedded_scene_suite("3zone player weapon switch suite", THREE_ZONE_PLAYER_WEAPON_SWITCH_TEST_SCENE)
	await _run_embedded_scene_suite("3zone player shotgun fire pipeline suite", THREE_ZONE_PLAYER_SHOTGUN_FIRE_PIPELINE_TEST_SCENE)
	await _run_embedded_scene_suite("3zone each enemy spawn fires shotgun suite", THREE_ZONE_ENEMY_EACH_SPAWN_FIRES_SHOTGUN_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy shotgun fire block reasons suite", ENEMY_SHOTGUN_FIRE_BLOCK_REASONS_TEST_SCENE)
	await _run_embedded_scene_suite("Alert->Combat requires 5s confirm suite", ALERT_TO_COMBAT_REQUIRES_5S_CONFIRM_TEST_SCENE)
	await _run_embedded_scene_suite("Peek corner confirm threshold suite", PEEK_CORNER_CONFIRM_THRESHOLD_TEST_SCENE)
	await _run_embedded_scene_suite("No combat latch before confirm complete suite", NO_COMBAT_LATCH_BEFORE_CONFIRM_COMPLETE_TEST_SCENE)
	await _run_embedded_scene_suite("Last seen only in suspicious/alert suite", LAST_SEEN_ONLY_IN_SUSPICIOUS_ALERT_TEST_SCENE)
	await _run_embedded_scene_suite("Teammate call dedup/cooldown suite", TEAMMATE_CALL_DEDUP_AND_COOLDOWN_TEST_SCENE)
	await _run_embedded_scene_suite("Alert call only on state entry suite", ALERT_CALL_ONLY_ON_STATE_ENTRY_TEST_SCENE)
	await _run_embedded_scene_suite("Alert degrade hold/grace/decay suite", ALERT_DEGRADE_HOLD_GRACE_DECAY_TEST_SCENE)
	await _run_embedded_scene_suite("Suspicion channels vs confirm channel suite", SUSPICION_CHANNELS_VS_CONFIRM_CHANNEL_TEST_SCENE)
	await _run_embedded_scene_suite("Teammate call room-graph gate suite", TEAMMATE_CALL_ROOM_GRAPH_GATE_TEST_SCENE)
	await _run_embedded_scene_suite("Combat role lock/reassign triggers suite", COMBAT_ROLE_LOCK_AND_REASSIGN_TRIGGERS_TEST_SCENE)
	await _run_embedded_scene_suite("Combat search per-room budget/total cap suite", COMBAT_SEARCH_PER_ROOM_BUDGET_AND_TOTAL_CAP_TEST_SCENE)
	await _run_embedded_scene_suite("Combat next-room scoring suite", COMBAT_NEXT_ROOM_SCORING_NO_LOOPS_TEST_SCENE)
	await _run_embedded_scene_suite("Combat->Alert search/no-contact gate suite", COMBAT_TO_ALERT_REQUIRES_NO_CONTACT_AND_SEARCH_PROGRESS_TEST_SCENE)
	await _run_embedded_scene_suite("First-shot-delay on first valid firing solution suite", FIRST_SHOT_DELAY_STARTS_ON_FIRST_VALID_FIRING_SOLUTION_TEST_SCENE)
	await _run_embedded_scene_suite("First-shot timer starts on first valid contact suite", FIRST_SHOT_TIMER_STARTS_ON_FIRST_VALID_FIRING_SOLUTION_TEST_SCENE)
	await _run_embedded_scene_suite("First-shot timer pause/reset 2.5s suite", FIRST_SHOT_TIMER_PAUSE_AND_RESET_AFTER_2_5S_TEST_SCENE)
	await _run_embedded_scene_suite("Telegraph profile production/debug suite", TELEGRAPH_PROFILE_PRODUCTION_VS_DEBUG_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy damage exactly 1hp per successful shot suite", ENEMY_DAMAGE_IS_EXACTLY_1HP_PER_SUCCESSFUL_SHOT_TEST_SCENE)
	await _run_embedded_scene_suite("Combat damage escalation pipeline suite", COMBAT_DAMAGE_ESCALATION_PIPELINE_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy damage API single source suite", ENEMY_DAMAGE_API_SINGLE_SOURCE_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy fire cooldown min guard suite", ENEMY_FIRE_COOLDOWN_MIN_GUARD_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy fire decision contract suite", ENEMY_FIRE_DECISION_CONTRACT_TEST_SCENE)
	await _run_embedded_scene_suite("Enemy fire trace cache runtime suite", ENEMY_FIRE_TRACE_CACHE_RUNTIME_TEST_SCENE)
	await _run_embedded_scene_suite("Friendly block prevents fire + reposition suite", FRIENDLY_BLOCK_PREVENTS_FIRE_AND_TRIGGERS_REPOSITION_TEST_SCENE)
	await _run_embedded_scene_suite("Shadow flashlight rule blocks/allows fire suite", SHADOW_FLASHLIGHT_RULE_BLOCKS_OR_ALLOWS_FIRE_TEST_SCENE)
	await _run_embedded_scene_suite("Shadow single source of truth nav+detection suite", SHADOW_SINGLE_SOURCE_OF_TRUTH_NAV_AND_DETECTION_TEST_SCENE)
	await _run_embedded_scene_suite("Shadow policy hard block without grant suite", SHADOW_POLICY_HARD_BLOCK_WITHOUT_GRANT_TEST_SCENE)
	await _run_embedded_scene_suite("Shadow enemy stuck when inside shadow suite", SHADOW_ENEMY_STUCK_WHEN_INSIDE_SHADOW_TEST_SCENE)
	await _run_embedded_scene_suite("Shadow enemy unstuck after flashlight activation suite", SHADOW_ENEMY_UNSTUCK_AFTER_FLASHLIGHT_ACTIVATION_TEST_SCENE)
	await _run_embedded_scene_suite("Shadow stall escapes to light suite", SHADOW_STALL_ESCAPES_TO_LIGHT_TEST_SCENE)
	await _run_embedded_scene_suite("Shadow unreachable canon transition suite", SHADOW_UNREACHABLE_CANON_TEST_SCENE)
	await _run_embedded_scene_suite("Door enemy oblique open then cross no wall stall suite", DOOR_ENEMY_OBLIQUE_OPEN_THEN_CROSS_NO_WALL_STALL_TEST_SCENE)
	await _run_embedded_scene_suite("Stall definition reproducible thresholds suite", STALL_DEFINITION_REPRODUCIBLE_THRESHOLDS_TEST_SCENE)
	await _run_embedded_scene_suite("Alert hold dynamic suite", ALERT_HOLD_DYNAMIC_TEST_SCENE)
	await _run_embedded_scene_suite("Patrol route variety suite", PATROL_ROUTE_VARIETY_TEST_SCENE)
	await _run_embedded_scene_suite("Patrol route traversability filter suite", PATROL_ROUTE_TRAVERSABILITY_FILTER_TEST_SCENE)
	await _run_embedded_scene_suite("Alert investigate anchor suite", ALERT_INVESTIGATE_ANCHOR_TEST_SCENE)
	await _run_embedded_scene_suite("Alert/combat shadow boundary scan intent suite", ALERT_COMBAT_SHADOW_BOUNDARY_SCAN_INTENT_TEST_SCENE)
	await _run_embedded_scene_suite("Suspicious shadow scan suite", SUSPICIOUS_SHADOW_SCAN_TEST_SCENE)
	await _run_embedded_scene_suite("Shadow route filter suite", SHADOW_ROUTE_FILTER_TEST_SCENE)
	await _run_embedded_scene_suite("Pursuit intent-only runtime suite", PURSUIT_INTENT_ONLY_RUNTIME_TEST_SCENE)
	await _run_embedded_scene_suite("Pursuit stall/fallback invariants suite", PURSUIT_STALL_FALLBACK_INVARIANTS_TEST_SCENE)
	await _run_embedded_scene_suite("Pursuit origin target not sentinel suite", PURSUIT_ORIGIN_TARGET_NOT_SENTINEL_TEST_SCENE)
	await _run_embedded_scene_suite("Alert/combat context never patrol suite", ALERT_COMBAT_CONTEXT_NEVER_PATROL_TEST_SCENE)
	await _run_embedded_scene_suite("Navigation runtime queries suite", NAVIGATION_RUNTIME_QUERIES_TEST_SCENE)
	await _run_embedded_scene_suite("Navigation failure reason contract suite", NAVIGATION_FAILURE_REASON_CONTRACT_TEST_SCENE)
	await _run_embedded_scene_suite("Nav obstacle fallback suite", NAV_OBSTACLE_FALLBACK_TEST_SCENE)
	await _run_embedded_scene_suite("Nav clearance margin suite", NAV_CLEARANCE_MARGIN_TEST_SCENE)
	await _run_embedded_scene_suite("Navigation shadow policy runtime suite", NAVIGATION_SHADOW_POLICY_RUNTIME_TEST_SCENE)
	await _run_embedded_scene_suite("Navigation shot gate parity suite", NAVIGATION_SHOT_GATE_PARITY_TEST_SCENE)
	await _run_embedded_scene_suite("Navigation path policy parity suite", NAVIGATION_PATH_POLICY_PARITY_TEST_SCENE)
	await _run_embedded_scene_suite("Navigation policy detour direct-blocked suite", NAVIGATION_POLICY_DETOUR_BLOCKED_TEST_SCENE)
	await _run_embedded_scene_suite("Navigation policy detour two-waypoint suite", NAVIGATION_POLICY_DETOUR_TWO_WP_TEST_SCENE)
	await _run_embedded_scene_suite("Navigation shadow cost prefers cover path suite", NAVIGATION_SHADOW_COST_PREFERS_COVER_PATH_TEST_SCENE)
	await _run_embedded_scene_suite("Navigation shadow cost push-mode shortcut suite", NAVIGATION_SHADOW_COST_PUSH_MODE_SHORTCUT_TEST_SCENE)
	await _run_embedded_scene_suite("Pursuit plan-lock edge-case suite", PURSUIT_PLAN_LOCK_EDGE_CASE_TEST_SCENE)
	await _run_embedded_scene_suite("ZoneDirector single-owner transitions suite", ZONE_DIRECTOR_SINGLE_OWNER_TRANSITIONS_TEST_SCENE)
	await _run_embedded_scene_suite("Zone hysteresis hold/no-event decay suite", ZONE_HYSTERESIS_HOLD_AND_NO_EVENT_DECAY_TEST_SCENE)
	await _run_embedded_scene_suite("Zone state machine contract suite", ZONE_STATE_MACHINE_CONTRACT_TEST_SCENE)
	await _run_embedded_scene_suite("Zone reinforcement budget contract suite", ZONE_REINFORCEMENT_BUDGET_CONTRACT_TEST_SCENE)
	await _run_embedded_scene_suite("Zone profile exact values suite", ZONE_PROFILE_MODIFIERS_EXACT_VALUES_TEST_SCENE)
	await _run_embedded_scene_suite("Confirm 5s invariant across zone profiles suite", CONFIRM_5S_INVARIANT_ACROSS_ZONE_PROFILES_TEST_SCENE)
	await _run_embedded_scene_suite("Wave call permission matrix/cooldowns suite", WAVE_CALL_PERMISSION_MATRIX_AND_COOLDOWNS_TEST_SCENE)
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
	await _run_embedded_scene_suite("Collision block forces immediate repath suite", COLLISION_BLOCK_FORCES_IMMEDIATE_REPATH_TEST_SCENE)
	await _run_embedded_scene_suite("Collision block preserves intent context suite", COLLISION_BLOCK_PRESERVES_INTENT_CONTEXT_TEST_SCENE)
	await _run_embedded_scene_suite("Honest repath without teleport suite", HONEST_REPATH_WITHOUT_TELEPORT_TEST_SCENE)
	await _run_embedded_scene_suite("Flashlight active in combat suite", FLASHLIGHT_ACTIVE_IN_COMBAT_TEST_SCENE)
	await _run_embedded_scene_suite("Flashlight single source parity suite", FLASHLIGHT_SINGLE_SOURCE_PARITY_TEST_SCENE)
	await _run_embedded_scene_suite("Flashlight bonus in combat suite", FLASHLIGHT_BONUS_IN_COMBAT_TEST_SCENE)

	print("\n--- SECTION 18d: Phase 10 tactic suites ---")

	_test("Tactic contain exit slots test scene exists", func():
		return _scene_exists(TACTIC_CONTAIN_EXIT_SLOTS_TEST_SCENE)
	)
	_test("Tactic flank budget guard test scene exists", func():
		return _scene_exists(TACTIC_FLANK_BUDGET_GUARD_TEST_SCENE)
	)
	_test("Multi-enemy pressure no-patrol regression test scene exists", func():
		return _scene_exists(MULTI_ENEMY_PRESSURE_NO_PATROL_REGRESSION_TEST_SCENE)
	)

	await _run_embedded_scene_suite("Tactic contain exit slots suite", TACTIC_CONTAIN_EXIT_SLOTS_TEST_SCENE)
	await _run_embedded_scene_suite("Tactic flank budget guard suite", TACTIC_FLANK_BUDGET_GUARD_TEST_SCENE)
	await _run_embedded_scene_suite(
		"Multi-enemy pressure no-patrol regression suite",
		MULTI_ENEMY_PRESSURE_NO_PATROL_REGRESSION_TEST_SCENE
	)

	print("\n--- SECTION 18e: Shadow search choreography unit tests ---")

	_test("Shadow search stage transition test scene exists", func():
		return _scene_exists(SHADOW_SEARCH_STAGE_TRANSITION_TEST_SCENE)
	)
	_test("Shadow search progressive coverage test scene exists", func():
		return _scene_exists(SHADOW_SEARCH_PROGRESSIVE_COVERAGE_TEST_SCENE)
	)
	await _run_embedded_scene_suite(
		"Shadow search stage transition suite",
		SHADOW_SEARCH_STAGE_TRANSITION_TEST_SCENE
	)
	await _run_embedded_scene_suite(
		"Shadow search progressive coverage suite",
		SHADOW_SEARCH_PROGRESSIVE_COVERAGE_TEST_SCENE
	)

	print("\n--- SECTION 18f: Flashlight team role policy unit tests ---")

	_test("Flashlight scanner role assignment test scene exists", func():
		return _scene_exists(FLASHLIGHT_SCANNER_ROLE_ASSIGNMENT_TEST_SCENE)
	)
	_test("Team contain flashlight pressure test scene exists", func():
		return _scene_exists(TEAM_CONTAIN_FLASHLIGHT_PRESSURE_TEST_SCENE)
	)
	await _run_embedded_scene_suite(
		"Flashlight scanner role assignment suite",
		FLASHLIGHT_SCANNER_ROLE_ASSIGNMENT_TEST_SCENE
	)
	await _run_embedded_scene_suite(
		"Team contain flashlight pressure suite",
		TEAM_CONTAIN_FLASHLIGHT_PRESSURE_TEST_SCENE
	)

	print("\n--- SECTION 18g: Phase 13 fairness latency/delay/seed tests ---")

	_test("Comm delay prevents telepathy test scene exists", func():
		return _scene_exists(COMM_DELAY_PREVENTS_TELEPATHY_TEST_SCENE)
	)
	_test("Reaction latency window respected test scene exists", func():
		return _scene_exists(REACTION_LATENCY_WINDOW_RESPECTED_TEST_SCENE)
	)
	_test("Seeded variation deterministic per seed test scene exists", func():
		return _scene_exists(SEEDED_VARIATION_DETERMINISTIC_PER_SEED_TEST_SCENE)
	)
	await _run_embedded_scene_suite(
		"Comm delay prevents telepathy suite",
		COMM_DELAY_PREVENTS_TELEPATHY_TEST_SCENE
	)
	await _run_embedded_scene_suite(
		"Reaction latency window respected suite",
		REACTION_LATENCY_WINDOW_RESPECTED_TEST_SCENE
	)
	await _run_embedded_scene_suite(
		"Seeded variation deterministic per seed suite",
		SEEDED_VARIATION_DETERMINISTIC_PER_SEED_TEST_SCENE
	)

	print("\n--- SECTION 18h: Phase 14 blood evidence tests ---")

	_test("Blood evidence investigate-anchor test scene exists", func():
		return _scene_exists(BLOOD_EVIDENCE_INVESTIGATE_ANCHOR_TEST_SCENE)
	)
	_test("Blood evidence no-instant-combat test scene exists", func():
		return _scene_exists(BLOOD_EVIDENCE_NO_INSTANT_COMBAT_TEST_SCENE)
	)
	_test("Blood evidence TTL expiry test scene exists", func():
		return _scene_exists(BLOOD_EVIDENCE_TTL_EXPIRES_TEST_SCENE)
	)
	await _run_embedded_scene_suite(
		"Blood evidence investigate-anchor suite",
		BLOOD_EVIDENCE_INVESTIGATE_ANCHOR_TEST_SCENE
	)
	await _run_embedded_scene_suite(
		"Blood evidence no-instant-combat suite",
		BLOOD_EVIDENCE_NO_INSTANT_COMBAT_TEST_SCENE
	)
	await _run_embedded_scene_suite(
		"Blood evidence TTL expiry suite",
		BLOOD_EVIDENCE_TTL_EXPIRES_TEST_SCENE
	)

	print("\n--- SECTION 19: Level decomposition controller suites ---")

	_test("Level runtime guard test scene exists", func():
		return _scene_exists(LEVEL_RUNTIME_GUARD_TEST_SCENE)
	)
	_test("Level input controller test scene exists", func():
		return _scene_exists(LEVEL_INPUT_CONTROLLER_TEST_SCENE)
	)
	_test("Level HUD controller test scene exists", func():
		return _scene_exists(LEVEL_HUD_CONTROLLER_TEST_SCENE)
	)
	_test("Level camera controller test scene exists", func():
		return _scene_exists(LEVEL_CAMERA_CONTROLLER_TEST_SCENE)
	)
	_test("Level layout regen test scene exists", func():
		return _scene_exists(LEVEL_LAYOUT_REGEN_TEST_SCENE)
	)
	_test("Level layout floor test scene exists", func():
		return _scene_exists(LEVEL_LAYOUT_FLOOR_TEST_SCENE)
	)
	_test("Level transition controller test scene exists", func():
		return _scene_exists(LEVEL_TRANSITION_CONTROLLER_TEST_SCENE)
	)
	_test("Level enemy runtime controller test scene exists", func():
		return _scene_exists(LEVEL_ENEMY_RUNTIME_CONTROLLER_TEST_SCENE)
	)
	_test("Level events controller test scene exists", func():
		return _scene_exists(LEVEL_EVENTS_CONTROLLER_TEST_SCENE)
	)
	_test("Level bootstrap controller test scene exists", func():
		return _scene_exists(LEVEL_BOOTSTRAP_CONTROLLER_TEST_SCENE)
	)
	_test("Mission transition gate test scene exists", func():
		return _scene_exists(MISSION_TRANSITION_GATE_TEST_SCENE)
	)
	_test("Game systems runtime test scene exists", func():
		return _scene_exists(GAME_SYSTEMS_RUNTIME_TEST_SCENE)
	)
	_test("Physics world runtime test scene exists", func():
		return _scene_exists(PHYSICS_WORLD_RUNTIME_TEST_SCENE)
	)
	_test("Refactor KPI contract test scene exists", func():
		return _scene_exists(REFACTOR_KPI_CONTRACT_TEST_SCENE)
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
	await _run_embedded_scene_suite("Game systems runtime suite", GAME_SYSTEMS_RUNTIME_TEST_SCENE)
	await _run_embedded_scene_suite("Physics world runtime suite", PHYSICS_WORLD_RUNTIME_TEST_SCENE)
	await _run_embedded_scene_suite("Refactor KPI contract suite", REFACTOR_KPI_CONTRACT_TEST_SCENE)

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
	if not _scene_exists(scene_path):
		print("[FAIL] %s (scene missing: %s)" % [name, scene_path])
		return
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


func _scene_exists(scene_path: String) -> bool:
	return ResourceLoader.exists(scene_path, "PackedScene")
