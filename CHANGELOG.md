# Arena Shooter Changelog

## 2026-02-07

### 02:57 MSK - PATCH 0.2 Phase 1: Katana Core + Feel
- **Added**: MeleeSystem — full katana state machine (IDLE → WINDUP → ACTIVE → RECOVERY / DASHING)
- **Added**: 3 katana moves: Light Slash (LMB), Heavy Slash (RMB), Dash Slash (Space)
- **Added**: Katana Mode toggle (Q key) — switches between GUN and KATANA modes
- **Added**: All katana tunables in GameConfig (30+ parameters: damage, arc, range, knockback, stagger, hitstop per move)
- **Added**: Input buffer system (0.12s) for responsive move queuing
- **Added**: Hitstop on melee hit (Engine.time_scale brief freeze, safe restore)
- **Added**: Knockback + stagger system on enemies (blocks movement, decays over time)
- **Added**: Dash slash with i-frames (invulnerability window during dash center)
- **Added**: `RuntimeState.katana_mode`, `is_player_invulnerable`, `invuln_timer`
- **Added**: EventBus signals: `katana_mode_changed`, `melee_hit`
- **Added**: InputMap actions: `katana_toggle` (Q), `katana_light` (LMB), `katana_heavy` (RMB), `katana_dash` (Space)
- **Added**: `enemy.apply_damage()`, `enemy.apply_stagger()`, `enemy.apply_knockback()` methods
- **Added**: `boss.apply_damage()` (delegates to take_damage), stagger/knockback immune
- **Added**: Invulnerability guard in CombatSystem and Boss damage pipelines
- **Added**: HUD displays "Mode: GUN / KATANA" with weapon info or slash state
- **Added**: VFX hook — melee hits emit `blood_spawned` + `melee_hit` events
- **Added**: Headless smoke test `test_melee_smoke.tscn` — 7 tests (toggle, slash damage, dash movement)
- **Changed**: Player blocks shooting/weapon switching when katana mode ON
- **Changed**: level_mvp.gd creates and updates MeleeSystem
- **Files**: `src/systems/melee_system.gd` (new), `src/core/game_config.gd`, `src/core/runtime_state.gd`, `src/systems/event_bus.gd`, `src/entities/enemy.gd`, `src/entities/boss.gd`, `src/entities/player.gd`, `src/systems/combat_system.gd`, `src/levels/level_mvp.gd`, `scenes/levels/level_mvp.tscn`, `project.godot`, `tests/test_melee_smoke.gd` (new), `tests/test_melee_smoke.tscn` (new)

## 2026-02-06

### 19:00 MSK - Phase 4: Sound Effects System
- **Added**: SFXSystem — audio player pool (12 channels) with EventBus integration
- **Added**: 14 procedurally generated SFX files via sox (WAV, 44100 Hz, mono):
  - Weapon shots: `pistol_shot`, `auto_shot`, `shotgun_shot`, `plasma_shot`, `rocket_shot`, `chain_lightning`
  - Explosions: `rocket_explosion`
  - Combat: `enemy_death`, `player_hit`, `player_death`
  - UI/events: `weapon_switch`, `wave_start`, `boss_spawn`, `boss_death`
- **Added**: Per-weapon shot sounds via `WEAPON_SFX` mapping
- **Added**: Volume control reads from `GameConfig.sfx_volume` (existing slider in Settings)
- **Files**: `src/systems/sfx_system.gd` (new), `src/app_root.gd`, `assets/audio/sfx/*.wav` (14 files)

### 18:30 MSK - Phase 3: Arena Combat Polish + Full Weapon System

#### PART A — Arena Combat Polish
- **Added**: Camera shake on rocket explosion (A1) — small amplitude, short duration, purely visual
- **Added**: "WAVE X" overlay on wave start (A2) — fade-in/out animation + subtle screen flash
- **Added**: Enemy spawn visual cue (A3) — scale-in animation with white flash
- **Added**: Enemy death feedback (A4) — white flash + scale burst before cleanup
- **Added**: Arena boundary visualization (A5) — darkened border strips beyond play area

#### PART B — Full Weapon System
- **Added**: AbilitySystem — weapon registry with 6 weapons, reads stats from GameConfig (B1)
  - Pistol: single bullet, 180 RPM
  - Automatic: rapid bullet fire, 150 RPM
  - Shotgun: 5-pellet spread, 60 RPM
  - Plasma: slow heavy projectile, 120 RPM
  - Rocket Launcher: explosive + AoE damage on hit/TTL, 30 RPM
  - Chain Lightning: hitscan chaining up to 5 targets, 120 RPM
- **Added**: Weapon switching (B2) — mouse wheel cycle + keys 1-6 direct select
- **Added**: HUD weapon display (B3) — shows current weapon name and slot number
- **Added**: Rocket AoE explosion — damages all enemies/bosses in 7-tile radius
- **Added**: Chain lightning VFX — jagged line arcs between targets

#### Architecture
- **Added**: `GameConfig.weapon_stats` — canonical weapon parameters (no hardcoded stats)
- **Changed**: `ProjectileSystem.WEAPON_STATS` reads from GameConfig on init
- **Added**: 3 new EventBus signals: `weapon_changed`, `rocket_exploded`, `chain_lightning_hit`
- **Added**: 8 input actions: `weapon_next/prev`, `weapon_1` through `weapon_6`

#### New Files
- `src/systems/ability_system.gd` — weapon registry + activation + chain lightning hitscan
- `src/systems/camera_shake.gd` — camera shake utility
- `src/ui/wave_overlay.gd` — wave start announcement overlay
- `src/systems/arena_boundary.gd` — visual arena edge

#### Modified Files
- `src/systems/event_bus.gd` — 3 new signals + emit methods + dispatch cases
- `src/core/game_config.gd` — weapon_stats dict + shake params
- `src/entities/projectile.gd` — rocket AoE explosion
- `src/systems/projectile_system.gd` — reads from GameConfig
- `src/entities/enemy.gd` — spawn animation + death feedback
- `src/entities/player.gd` — AbilitySystem delegation + weapon switching
- `src/systems/vfx_system.gd` — chain lightning arc visuals
- `src/levels/level_mvp.gd` — all systems wired, HUD weapon display
- `scenes/levels/level_mvp.tscn` — WeaponLabel + updated debug hints
- `project.godot` — 8 new input actions

### 13:47 MSK - Reliability & Smoke Tests
- **Fixed**: AppRoot now calls `_pause_level()` before showing UI on GAME_OVER and LEVEL_COMPLETE (guarantees gameplay stop even if nodes skip `is_frozen` check)
- **Fixed**: EventBus `_compare_events` uses bracket access `a["priority"]` instead of dot notation (stable Dictionary key access)
- **Added**: WaveManager subscribes to `state_changed` — disables `_spawning_active` on MAIN_MENU/GAME_OVER/LEVEL_COMPLETE (prevents zombie spawns in dead level)
- **Added**: Headless smoke test (`test_level_smoke.tscn`) — start-delay guard, enemy spawning, boss_killed→LEVEL_COMPLETE (4/4 passing)
- **Removed**: Unused `_is_paused` variable from `level_mvp.gd` (single source of truth: `RuntimeState.is_frozen`)
- **Files**: `src/app_root.gd`, `src/systems/event_bus.gd`, `src/systems/wave_manager.gd`, `src/levels/level_mvp.gd`, `tests/test_level_smoke.gd`, `tests/test_level_smoke.tscn`, `README.md`

## 2026-02-05

### 19:40 MSK - Boss Bug Fix
- **Fixed**: AoE attack now centers on BOSS position instead of player position
- **Fixed**: AoE damage only applies when player is within 8-tile radius
- **Fixed**: Boss spawns >= 10 tiles away from player
- **Added**: `BOSS_MIN_SPAWN_DISTANCE_TILES` constant (10.0)
- **Added**: `Boss.get_safe_spawn_position()` static helper
- **Files**: `src/entities/boss.gd`, `src/systems/wave_manager.gd`

### 19:30 MSK - Typing Warnings Fix
- **Fixed**: `footprint_system.gd:80` - explicit cast for `pop_front()`
- **Fixed**: `footprint_system.gd:128` - explicit float type for `absf()`
- **Files**: `src/systems/footprint_system.gd`

### 19:20 MSK - SFX Volume Slider
- **Added**: `sfx_volume` parameter in GameConfig
- **Added**: SFX Volume slider in Settings menu
- **Files**: `src/core/game_config.gd`, `src/ui/settings_menu.gd`, `scenes/ui/settings_menu.tscn`

### 19:00 MSK - Test Infrastructure
- **Added**: Scene-based test runner (`test_runner.tscn`, `test_runner_node.gd`)
- **Result**: 62/62 tests passing
- **Files**: `tests/test_runner.tscn`, `tests/test_runner_node.gd`

### 18:30 MSK - Initial Commit v0.01
- **Added**: Initial project structure
- **Pushed**: https://github.com/Alex-cat-ui/arena-shooter
- **Files**: all project files
