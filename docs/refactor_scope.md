# Refactor Scope (Phase 0 Baseline)

## In Scope
- `src/entities/enemy.gd`
- `src/systems/combat_system.gd`
- `src/systems/enemy_pursuit_system.gd`
- `src/systems/navigation_service.gd` (runtime-only decomposition)
- `src/systems/zone_director.gd`
- `src/core/game_config.gd`
- `src/systems/game_systems.gd`
- `src/systems/physics_world.gd`
- `tests/test_runner_node.gd`
- New test scenes/scripts for combat/enemy/pursuit/navigation/zone/config/KPI

## Out of Scope (Do Not Change)
- `src/systems/procedural_layout_v2.gd`
- `src/systems/layout_door_carver.gd`
- `src/systems/layout_door_system.gd`
- `src/systems/layout_geometry_utils.gd`
- `src/systems/layout_room_shapes.gd`
- `src/systems/layout_wall_builder.gd`
- `src/levels/level_layout_controller.gd`
- `tests/test_layout_*`

## Explicit Exclusions
- No changes to layout generation algorithms
- No changes to topology generation contracts
- No changes to door carving/wall building logic
