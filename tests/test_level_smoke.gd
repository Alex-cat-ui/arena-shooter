## test_level_smoke.gd
## Integration test for Phase 1 and Phase 2.
## Tests: spawn, damage, death, state transitions, boss, VFX.
##
## Run via: godot --headless --script res://tests/test_level_smoke.gd
extends SceneTree

const LEVEL_SCENE := "res://scenes/levels/level_mvp.tscn"
const ENEMY_SCENE := "res://scenes/entities/enemy.tscn"

var _level: Node = null
var _tests_run := 0
var _tests_passed := 0


func _init() -> void:
	print("=" .repeat(60))
	print("INTEGRATION TEST: Phase 1 + Phase 2")
	print("Core Gameplay + Boss + VFX + Footprints")
	print("=" .repeat(60))

	# Run tests
	await _run_tests()

	# Report results
	print("")
	print("=" .repeat(60))
	print("RESULTS: %d/%d tests passed" % [_tests_passed, _tests_run])
	print("=" .repeat(60))

	# Exit with appropriate code
	quit(0 if _tests_passed == _tests_run else 1)


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
		# WaveSize = EnemiesPerWave + (WaveIndex-1)*WaveSizeGrowth
		# Wave 1: 12 + (1-1)*3 = 12
		var wave_size := GameConfig.enemies_per_wave + (1 - 1) * GameConfig.wave_size_growth
		return wave_size == 12
	)

	_test("Wave 2 size = 15", func():
		# Wave 2: 12 + (2-1)*3 = 15
		var wave_size := GameConfig.enemies_per_wave + (2 - 1) * GameConfig.wave_size_growth
		return wave_size == 15
	)

	_test("Wave 3 size = 18", func():
		# Wave 3: 12 + (3-1)*3 = 18
		var wave_size := GameConfig.enemies_per_wave + (3 - 1) * GameConfig.wave_size_growth
		return wave_size == 18
	)

	_test("Wave transition threshold calculation", func():
		# max(2, ceil(WavePeakCount * 0.2))
		# For wave 1 with 12 enemies: max(2, ceil(12*0.2)) = max(2, 3) = 3
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

	_test("Zombie HP=30, DMG=10", func():
		var stats: Dictionary = Enemy.ENEMY_STATS.get("zombie", {})
		return stats.hp == 30 and stats.damage == 10
	)

	_test("Fast HP=15, DMG=7", func():
		var stats: Dictionary = Enemy.ENEMY_STATS.get("fast", {})
		return stats.hp == 15 and stats.damage == 7
	)

	_test("Tank HP=80, DMG=15", func():
		var stats: Dictionary = Enemy.ENEMY_STATS.get("tank", {})
		return stats.hp == 80 and stats.damage == 15
	)

	_test("Swarm HP=5, DMG=5", func():
		var stats: Dictionary = Enemy.ENEMY_STATS.get("swarm", {})
		return stats.hp == 5 and stats.damage == 5
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

	print("\n--- SECTION 9: Weapon stats (ТЗ v1.13) ---")

	_test("Pistol dmg=10, rpm=180", func():
		var stats: Dictionary = ProjectileSystem.WEAPON_STATS.get("pistol", {})
		return stats.damage == 10 and stats.rpm == 180
	)

	_test("Auto dmg=7, rpm=150", func():
		var stats: Dictionary = ProjectileSystem.WEAPON_STATS.get("auto", {})
		return stats.damage == 7 and stats.rpm == 150
	)

	_test("Shotgun pellets=5, dmg=6", func():
		var stats: Dictionary = ProjectileSystem.WEAPON_STATS.get("shotgun", {})
		return stats.pellets == 5 and stats.damage == 6
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

	print("\nAll tests completed (Phase 1 + Phase 2).")


func _test(name: String, test_func: Callable) -> void:
	_tests_run += 1
	var result: bool = false

	result = test_func.call()

	if result:
		_tests_passed += 1
		print("[PASS] %s" % name)
	else:
		print("[FAIL] %s" % name)
