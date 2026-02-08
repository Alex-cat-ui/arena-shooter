# Arena Shooter MVP

2D top-down roguelike shooter (Crimsonland-like) built in Godot 4.

## Phase 1 - Core Gameplay Boot

This is the Phase 1 implementation containing:
- Full gameplay loop: move, shoot, kill enemies
- Wave system with spawning per ТЗ v1.13
- Combat system with damage pipeline and i-frames
- Projectile system with TTL and collisions
- Enemy AI (move toward player)
- Player death -> GAME_OVER
- Victory condition (all waves cleared) -> LEVEL_COMPLETE
- All UI screens functional

## How to Run

1. Open the project in Godot 4.2+
2. Open `scenes/app_root.tscn`
3. Press F5 or click Play

## Controls

### Menus
- Click buttons to navigate

### In-Game (PLAYING state)
- **WASD** - Move player
- **Mouse** - Aim direction (player sprite rotates)
- **LMB** - Shoot (Pistol)
- **ESC** - Pause/Resume
- **F1** - Force Game Over (debug)
- **F2** - Force Level Complete (debug)

## Gameplay

1. **Start Delay**: After level starts, player can move but enemies don't spawn for `start_delay_sec` (1.5s default)
2. **Waves**: Enemies spawn in waves. Wave size grows: `WaveSize = 12 + (WaveIndex-1)*3`
3. **Combat**:
   - Player shoots with LMB (Pistol: 10 dmg, 180 rpm)
   - Enemies deal contact damage (global i-frames: 0.7s)
   - Player HP: 100
4. **Victory**: Clear all waves to win
5. **Death**: HP reaches 0 -> GAME_OVER

## Project Structure

```
arena-shooter/
├── assets/
│   ├── audio/music/{menu,level}/
│   └── sprites/{player,floor,enemy,projectile}/
├── scenes/
│   ├── app_root.tscn          # Main scene
│   ├── entities/              # Enemy, Projectile scenes
│   ├── levels/level_mvp.tscn  # MVP level
│   └── ui/*.tscn              # UI screens
├── src/
│   ├── core/                  # GameConfig, RuntimeState, StateManager
│   ├── systems/               # WaveManager, CombatSystem, ProjectileSystem
│   ├── entities/              # Player, Enemy, Projectile
│   ├── levels/                # Level scripts
│   └── ui/                    # UI scripts
└── tests/
    └── test_level_smoke.gd    # Integration tests
```

## Systems (Phase 1)

| System | Purpose |
|--------|---------|
| WaveManager | Spawns enemies in waves per ТЗ v1.13 |
| CombatSystem | Damage pipeline, i-frames, GodMode |
| ProjectileSystem | Spawns/manages projectiles, TTL, collisions |
| EventBus | System communication via signals |

## Enemy Stats (ТЗ v1.13)

| Type | HP | Damage | Speed |
|------|-----|--------|-------|
| Zombie | 30 | 10 | 2.0 |
| Fast | 15 | 7 | 4.0 |
| Tank | 80 | 15 | 1.5 |
| Swarm | 5 | 5 | 3.0 |

## Wave System (CANON)

- `WaveSize = EnemiesPerWave + (WaveIndex-1) * WaveSizeGrowth`
- Default: 12 + 3 per wave
- Transition: when `AlivePrevWave <= max(2, ceil(PrevWavePeakCount * 0.2))`
- MaxAliveEnemies: 64

## CANON Rules

- Camera: TOP-DOWN ORTHOGRAPHIC only, `rotation = 0` always
- UI changes ONLY GameConfig
- Positions: Vector3 (z=0) in RuntimeState
- Systems: communicate via EventBus only
- Pause: freezes all gameplay

## Asset Attribution

All external assets are CC0 (Public Domain) licensed. No attribution is legally required,
but we credit authors as good practice.

| Asset | Source | Author | License | Path in Repo |
|-------|--------|--------|---------|--------------|
| Ground 037 (dirt+grass floor texture) | [ambientCG](https://ambientcg.com/view?id=Ground037) | ambientCG | CC0 1.0 | `assets/textures/floor/dirt_grass_01.png` |
| Top-down Shooter (player hitman) | [Kenney](https://kenney.nl/assets/top-down-shooter) | Kenney | CC0 1.0 | `assets/sprites/player/player_idle_0001.png` |
| Top-down Shooter (zombie enemy) | [Kenney](https://kenney.nl/assets/top-down-shooter) | Kenney | CC0 1.0 | `assets/sprites/enemy/enemy_zombie_0001.png` |
| Boss sprite (procedural, robot aesthetic) | — | Project | CC0 1.0 | `assets/sprites/boss/boss_0001.png` |

## Running Tests

```bash
# Unit tests (62 tests, ~instant)
godot --headless res://tests/test_runner.tscn

# Smoke tests (level instantiation + spawn + boss, ~7 seconds)
godot --headless res://tests/test_level_smoke.tscn
```
