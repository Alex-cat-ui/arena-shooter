# LevelMVP Decomposition Contract

Date: 2026-02-15
Project root: `project.godot`
Entry scene/script: `scenes/levels/level_mvp.tscn`, `src/levels/level_mvp.gd`

## Immutable Contracts

1. Decomposition must not change gameplay behavior.
2. Scene `level_mvp.tscn` and entry script `level_mvp.gd` remain.
3. Public effects remain:
   - `door_interact` / `door_kick`
   - `regenerate_layout` (`F4`)
   - `pause()` / `resume()`
   - mission transition flow
   - HUD strings/debug hint format
   - legacy close-combat input remains removed
4. Every phase is accepted only after test gate pass.

## Baseline Gates (Phase 0)

Current baseline gate set for this contract:

1. `test_door_interaction_flow`
   - Command: `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_door_interaction_flow.tscn`
2. `test_level_hud_controller`
   - Command: `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_level_hud_controller.tscn`
3. full `test_runner`
   - Command: `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_runner.tscn`

## Decomposition Target Structure

- `src/levels/level_mvp.gd` orchestrator only.
- `src/levels/level_context.gd` shared references and runtime mutable state.
- `src/levels/level_runtime_guard.gd`
- `src/levels/level_input_controller.gd`
- `src/levels/level_hud_controller.gd`
- `src/levels/level_camera_controller.gd`
- `src/levels/level_layout_controller.gd`
- `src/levels/level_transition_controller.gd`
- `src/levels/level_enemy_runtime_controller.gd`
- `src/levels/level_events_controller.gd`
- `src/levels/level_bootstrap_controller.gd`

## Gate Policy During Migration

- Phase 1+: run full `test_runner` after each accepted phase.
- For targeted phases, additionally run dedicated suites from the plan.
- New controller tests must be added and wired into `test_runner_node.gd`.

## Current Status (2026-02-15)

- Decomposition controllers introduced and wired:
  - `level_context`
  - `level_runtime_guard`
  - `level_input_controller`
  - `level_hud_controller`
  - `level_camera_controller`
  - `level_layout_controller`
  - `level_transition_controller`
  - `level_enemy_runtime_controller`
  - `level_events_controller`
  - `level_bootstrap_controller`
- `src/levels/level_mvp.gd` reduced to orchestration layer (`273` lines).
- Full runner gate after migration:
  - Command: `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_runner.tscn`
  - Result: `101/101 passed`
