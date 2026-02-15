## test_runner_node.gd
## Test runner node - runs tests when scene loads (autoloads are available).
## Run via: godot --headless res://tests/test_runner.tscn
extends Node

var _tests_run := 0
var _tests_passed := 0


func _ready() -> void:
	print("=" .repeat(60))
	print("INTEGRATION TEST: Phase 1 + Phase 2")
	print("Core Gameplay + Boss + VFX + Footprints")
	print("=" .repeat(60))

	_run_tests()

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

	_test("enemies_per_wave = 12", func():
		return GameConfig.enemies_per_wave == 12
	)

	_test("wave_size_growth = 3", func():
		return GameConfig.wave_size_growth == 3
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

	print("\n--- SECTION 4: Wave calculations (CANON) ---")

	_test("Wave 1 size = 12 (EnemiesPerWave)", func():
		var wave_size := GameConfig.enemies_per_wave + (1 - 1) * GameConfig.wave_size_growth
		return wave_size == 12
	)

	_test("Wave 2 size = 15", func():
		var wave_size := GameConfig.enemies_per_wave + (2 - 1) * GameConfig.wave_size_growth
		return wave_size == 15
	)

	_test("Wave 3 size = 18", func():
		var wave_size := GameConfig.enemies_per_wave + (3 - 1) * GameConfig.wave_size_growth
		return wave_size == 18
	)

	_test("Wave transition threshold calculation", func():
		var wave_peak := 12
		var threshold := maxi(2, ceili(wave_peak * GameConfig.wave_advance_threshold))
		return threshold == 3
	)

	print("\n--- SECTION 5: Config validation ---")

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

	_test("Invalid enemies_per_wave caught", func():
		GameConfig.enemies_per_wave = 0
		var result := ConfigValidator.validate()
		var is_invalid := not result.is_valid
		GameConfig.reset_to_defaults()
		return is_invalid
	)

	print("\n--- SECTION 6: Vector3 utilities (CANON) ---")

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
		var stats: Dictionary = Enemy.ENEMY_STATS.get("zombie", {})
		return stats.hp == 100 and stats.damage == 10
	)

	_test("Fast HP=100, DMG=7", func():
		var stats: Dictionary = Enemy.ENEMY_STATS.get("fast", {})
		return stats.hp == 100 and stats.damage == 7
	)

	_test("Tank HP=100, DMG=15", func():
		var stats: Dictionary = Enemy.ENEMY_STATS.get("tank", {})
		return stats.hp == 100 and stats.damage == 15
	)

	_test("Swarm HP=100, DMG=5", func():
		var stats: Dictionary = Enemy.ENEMY_STATS.get("swarm", {})
		return stats.hp == 100 and stats.damage == 5
	)

	print("\n--- SECTION 8: Projectile TTL (ТЗ v1.13) ---")

	_test("Bullet TTL = 2.0s", func():
		return Projectile.PROJECTILE_TTL.get("bullet", 0) == 2.0
	)

	_test("Rocket TTL = 3.0s", func():
		return Projectile.PROJECTILE_TTL.get("rocket", 0) == 3.0
	)

	_test("Piercing bullet TTL = 2.0s", func():
		return Projectile.PROJECTILE_TTL.get("piercing_bullet", 0) == 2.0
	)

	print("\n--- SECTION 9: Weapon stats (ТЗ v1.13 - from GameConfig) ---")

	_test("Pistol dmg=10, rpm=180", func():
		var stats: Dictionary = GameConfig.weapon_stats.get("pistol", {})
		return stats.damage == 10 and stats.rpm == 180
	)

	_test("Auto dmg=7, rpm=150", func():
		var stats: Dictionary = GameConfig.weapon_stats.get("auto", {})
		return stats.damage == 7 and stats.rpm == 150
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

	# ==========================================================================
	# PHASE 2 TESTS
	# ==========================================================================

	print("\n--- SECTION 11: Boss stats (Phase 2, ТЗ v1.13) ---")

	_test("Boss HP = 500", func():
		return Boss.BOSS_HP == 500
	)

	_test("Boss hitbox = 9 tiles", func():
		return Boss.BOSS_HITBOX_TILES == 9.0
	)

	_test("Boss contact damage = 50% player HP", func():
		return Boss.BOSS_CONTACT_DAMAGE_PERCENT == 0.5
	)

	_test("Boss contact i-frames = 3s", func():
		return Boss.BOSS_CONTACT_IFRAMES == 3.0
	)

	_test("Boss AoE radius = 8 tiles", func():
		return Boss.BOSS_AOE_RADIUS_TILES == 8.0
	)

	_test("Boss AoE cooldown = 1-2s", func():
		return Boss.BOSS_AOE_COOLDOWN_MIN == 1.0 and Boss.BOSS_AOE_COOLDOWN_MAX == 2.0
	)

	_test("Boss min spawn distance = 10 tiles", func():
		return Boss.BOSS_MIN_SPAWN_DISTANCE_TILES == 10.0
	)

	print("\n--- SECTION 12: GameConfig Phase 2 params ---")

	_test("waves_per_level exists and valid", func():
		return GameConfig.waves_per_level >= 1 and GameConfig.waves_per_level <= 200
	)

	_test("boss_contact_iframes_sec = 3.0", func():
		return is_equal_approx(GameConfig.boss_contact_iframes_sec, 3.0)
	)

	print("\n--- SECTION 13: State transitions Phase 2 ---")

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

	print("\n--- SECTION 14: VFX System constants ---")

	_test("Corpse limit = 200", func():
		return VFXSystem.CORPSE_LIMIT == 200
	)

	print("\n--- SECTION 15: Footprint System constants ---")

	_test("Max footprints = 20", func():
		return FootprintSystem.MAX_FOOTPRINTS == 20
	)

	print("\n--- SECTION 16: EventBus Phase 2 signals ---")

	_test("boss_spawned signal exists", func():
		return EventBus.has_signal("boss_spawned")
	)

	_test("boss_killed signal exists", func():
		return EventBus.has_signal("boss_killed")
	)

	_test("boss_damaged signal exists", func():
		return EventBus.has_signal("boss_damaged")
	)

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

	print("\n--- SECTION 17: Visual Polish GameConfig defaults ---")

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

	_test("melee_arc_light_radius = 26.0", func():
		return is_equal_approx(GameConfig.melee_arc_light_radius, 26.0)
	)

	_test("melee_arc_heavy_radius = 30.0", func():
		return is_equal_approx(GameConfig.melee_arc_heavy_radius, 30.0)
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

	print("\n--- SECTION 18: Visual Polish system classes ---")

	_test("MeleeArcSystem class exists", func():
		var inst := MeleeArcSystem.new()
		var exists := inst != null
		inst.free()
		return exists
	)

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

	print("\n--- SECTION 19: Visual Polish reset_to_defaults ---")

	_test("Visual polish values survive reset_to_defaults", func():
		GameConfig.footprint_step_distance_px = 999.0
		GameConfig.reset_to_defaults()
		return is_equal_approx(GameConfig.footprint_step_distance_px, 40.0)
	)

	print("\nAll tests completed (Phase 1 + Phase 2 + Visual Polish).")


func _test(name: String, test_func: Callable) -> void:
	_tests_run += 1
	var result: bool = false

	result = test_func.call()

	if result:
		_tests_passed += 1
		print("[PASS] %s" % name)
	else:
		print("[FAIL] %s" % name)
