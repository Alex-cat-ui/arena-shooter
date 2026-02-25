# PATH FIX V02 Phase 0 Baseline

Date: 2026-02-25
Engine: `/snap/bin/godot-4` (headless, xvfb-run)

## Run Summary

| run_id | scene | exit_code | duration_sec | seed |
|---|---|---:|---:|---|
| 01_level_stealth_checklist | `res://tests/test_level_stealth_checklist.tscn` | 0 | 5.493 | n/a |
| 02_combat_obstacle_chase_basic_r1 | `res://tests/test_combat_obstacle_chase_basic.tscn` | 0 | 10.362 | n/a |
| 03_combat_obstacle_chase_basic_r2 | `res://tests/test_combat_obstacle_chase_basic.tscn` | 0 | 9.080 | n/a |
| 04_combat_obstacle_chase_basic_r3 | `res://tests/test_combat_obstacle_chase_basic.tscn` | 0 | 8.652 | n/a |
| 05_combat_obstacle_chase_basic_r4 | `res://tests/test_combat_obstacle_chase_basic.tscn` | 0 | 7.766 | n/a |
| 06_combat_obstacle_chase_basic_r5 | `res://tests/test_combat_obstacle_chase_basic.tscn` | 0 | 8.402 | n/a |
| 07_3zone_smoke | `res://tests/test_3zone_smoke.tscn` | 0 | 48.064 | n/a |
| 08_ai_long_run_stress | `res://tests/test_ai_long_run_stress.tscn` | 0 | 12.421 | n/a |
| 09_ai_performance_gate | `res://tests/test_ai_performance_gate.tscn` | 0 | 227.172 | 1337 (fixed benchmark config) |

Raw table source: `artifacts/path_fix_v02_baseline/summary.tsv`
Raw logs: `artifacts/path_fix_v02_baseline/logs/*.log`

## Watchdog Snapshot (captured)

From `08_ai_long_run_stress.log`:
- `avg_tick_ms=0.101`
- `replans/sec=0.00`
- `transitions/last_tick=0`

Observed warnings during baseline (not failing gates):
- `AI tick slow: 3.05ms` in `07_3zone_smoke`
- `High repath rate: 15.9/sec` in `09_ai_performance_gate`
- `High repath rate` warnings in 2/5 `combat_obstacle_chase_basic` runs

## Flake Rate

`combat_obstacle_chase_basic` repeated 5x:
- pass: 5
- fail: 0
- flake_rate: `0.00%`

## Baseline Patrol KPI Anchor

Measured via dedicated baseline scene:
- command: `xvfb-run -a /snap/bin/godot-4 --headless --path . --scene res://artifacts/path_fix_v02_baseline/measure_patrol_route_rebuilds_scene.tscn`
- result: `BASELINE_PATROL_ROUTE_REBUILDS_TOTAL=35`
- result: `BASELINE_PATROL_ROUTE_REBUILDS_PER_MIN=35.000`
