# AI Navigation And Stealth Refactor Execution Template

## 1. Goal And Scope

This document defines the exact phased execution plan for navigation + stealth AI refactor.

Primary goal:
- deliver good, fun stealth AI with smart enemies (not AAA complexity)
- keep behavior stable and test-driven
- avoid legacy logic stacking

Out of scope:
- instant kill system
- corpse system

In scope:
- blood evidence integration without corpse system

---

## 2. Non-Negotiable Invariants (All Phases)

1. Single route decision pipeline only:
   - `build_policy_valid_path -> execute_intent -> move/repath`
2. No old/new logic stacking in the same behavior branch.
3. In `ALERT/COMBAT`, if any target context exists (`known_target`, `last_seen`, `investigate_anchor`), transitions to `PATROL` and `RETURN_HOME` are forbidden.
4. Shadow unreachable canon is strict:
   - `SHADOW_BOUNDARY_SCAN -> SEARCH`
   - direct fallback to `PATROL` is forbidden.
5. On non-door collision:
   - immediate repath
   - keep intent and target context
6. A phase is not closed until:
   - legacy identifiers are removed (`rg` gate)
   - phase tests are green
   - mandatory smoke suite is green
7. If new logic does not fully replace legacy logic in phase scope:
   - rollback phase fully
   - no temporary hybrid patches.

### 2.1 Legacy Hotspots Confirmed In Current Repo (Must Be Removed, Not Wrapped)

These are current duplication points discovered in `src` and mapped to mandatory removal phase:

1. `src/systems/enemy_pursuit_system.gd`:
   - `_build_policy_valid_path_fallback_contract`
   - `_build_reachable_path_points_for_enemy`
   - `nav_system.has_method("build_reachable_path_points")` fallback branch
   - `nav_system.has_method("build_path_points")` fallback branch
   - remove in Phase 0 (single contract authority only).
2. `src/systems/enemy_pursuit_system.gd`:
   - `_resolve_nearest_reachable_fallback`
   - `_sample_fallback_candidates`
   - `_policy_fallback_used`, `_policy_fallback_target`
   - `_attempt_shadow_escape_recovery`, `_resolve_shadow_escape_target`, `_sample_shadow_escape_candidates`
   - remove in Phase 2 (replace with strict `unreachable_policy -> SHADOW_BOUNDARY_SCAN -> SEARCH`).
3. `src/systems/enemy_utility_brain.gd`:
   - no-LOS `ALERT/COMBAT` branch can end in `RETURN_HOME`
   - remove in Phase 0/4 via explicit anti-patrol/anti-home guards for active target context.
4. `src/entities/enemy.gd`:
   - `shadow_scan_target` is built only for `SUSPICIOUS`
   - remove in Phase 4 (extend to `ALERT/COMBAT` with strict priority).
5. `src/systems/enemy_patrol_system.gd`:
   - hard fallback route `_route = [fallback, fallback + ...]` bypasses reachability contract
   - remove in Phase 6.

---

## 3. Mandatory Execution Protocol

For every phase:
1. Remove legacy branch first.
2. Implement replacement.
3. Add/update tests and register in `tests/test_runner_node.gd`.
4. Run phase gate.
5. Run mandatory smoke suite.
6. Run full regression: `xvfb-run -a godot-4 --headless res://tests/test_runner.tscn` must exit 0.
   This re-runs ALL tests from ALL previous phases automatically, because every phase test
   is registered in `test_runner_node.gd`. A new phase cannot close if it breaks any prior phase test.

If any step fails:
1. fix in-phase
2. if not possible, rollback phase fully

---

## 4. Mandatory Smoke Suite (After Every Phase)

Two-tier test requirement. Both tiers must pass before a phase closes.

### 4.1 Tier 1 — Smoke Suite (fast, critical invariants only)

Run all:

```bash
xvfb-run -a godot-4 --headless res://tests/test_navigation_path_policy_parity.tscn
xvfb-run -a godot-4 --headless res://tests/test_shadow_policy_hard_block_without_grant.tscn
xvfb-run -a godot-4 --headless res://tests/test_shadow_stall_escapes_to_light.tscn
xvfb-run -a godot-4 --headless res://tests/test_pursuit_stall_fallback_invariants.tscn
xvfb-run -a godot-4 --headless res://tests/test_combat_no_los_never_hold_range.tscn
```

### 4.2 Tier 2 — Full Regression (all phases, cumulative)

```bash
xvfb-run -a godot-4 --headless res://tests/test_runner.tscn
```

Must exit 0. Runs every test registered in `tests/test_runner_node.gd`, including all
tests added in phases 0..N-1. Catches indirect breakage that smoke suite does not cover.
Any failure = phase FAILED. No exceptions.

---

## 5. Phase Checklist Template

Use this template per phase in PR/task notes:

- [ ] Legacy removed first
- [ ] New logic implemented
- [ ] New tests added
- [ ] Legacy tests updated
- [ ] `rg` legacy gate passed
- [ ] Phase-specific tests passed
- [ ] Tier 1 smoke suite passed (section 4.1)
- [ ] Tier 2 full regression passed: `xvfb-run -a godot-4 --headless res://tests/test_runner.tscn` exits 0
- [ ] `tests/test_runner_node.gd` updated for new scenes

---

## 6. Phase 0 - Routing Contract And Anti-Legacy Re-closure

### 6.1 What Now
- contract exists partially
- behavior still has legacy side-effects

### 6.2 What To Change
1. In `src/systems/enemy_pursuit_system.gd`, keep only contract-driven route decision.
2. Remove in-class planner fallbacks:
   - `_build_policy_valid_path_fallback_contract`
   - `_build_reachable_path_points_for_enemy`
   - any `build_reachable_path_points/build_path_points` fallback usage.
3. `_request_path_plan_contract` must return only contract statuses:
   - `ok`
   - `unreachable_policy`
   - `unreachable_geometry`
4. In `src/systems/enemy_utility_brain.gd`, hard-guard:
   - `ALERT/COMBAT + target-context => no PATROL/RETURN_HOME`.
5. In `src/entities/enemy.gd`, stop dropping useful `last_seen` context during combat context build.

### 6.3 Expected Result
- all route decisions flow through contract
- no patrol degradation in active alert/combat target context

### 6.4 Acceptance Criteria
- [ ] no alternate route decision path besides `build_policy_valid_path`
- [ ] no `PATROL/RETURN_HOME` intents in `ALERT/COMBAT` with target context

### 6.5 Tests
New:
- `tests/test_alert_combat_context_never_patrol.gd`

Update:
- `tests/test_navigation_failure_reason_contract.gd`
- `tests/test_pursuit_stall_fallback_invariants.gd`

### 6.6 Legacy Removal Gate
```bash
rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy|nav_system\\.has_method\\(\"build_reachable_path_points\"\\)|nav_system\\.has_method\\(\"build_path_points\"\\)" src/systems/enemy_pursuit_system.gd -S
```
Expected: no matches.

---

## 7. Phase 1 - Detour Planner (Direct, 1 WP, 2 WP)

### 7.1 What Now
- planner mostly validates direct geometry path

### 7.2 What To Change
1. In `src/systems/navigation_runtime_queries.gd`, implement deterministic candidate order:
   - direct
   - 1 waypoint
   - 2 waypoints
2. Generate waypoint candidates via room/door graph.
3. Validate each candidate by policy.
4. Choose shortest nav-length among policy-valid candidates.

### 7.3 Expected Result
- if bypass exists, planner returns `ok` with real route
- if bypass does not exist, returns `unreachable_policy` or `unreachable_geometry`

### 7.4 Acceptance Criteria
- [ ] deterministic output for equal input
- [ ] no delay loops before fallback decision

### 7.5 Tests
New:
- `tests/test_navigation_policy_detour_shadow_blocked_direct.gd`
- `tests/test_navigation_policy_detour_two_waypoints.gd`

Update:
- `tests/test_navigation_runtime_queries.gd`
- `tests/test_navigation_path_policy_parity.gd`

### 7.6 Legacy Removal Gate
```bash
rg -n "direct_only_fallback|legacy_path_selector|old_detour" src tests -S
```
Expected: no matches.

---

## 8. Phase 2 - Detour Integration In Pursuit And Canon Fallback FSM

### 8.1 What Now
- fallback can loop on unreachable target context

### 8.2 What To Change
1. In `src/systems/enemy_pursuit_system.gd`, split:
   - `intent_target`
   - `plan_target`
2. Add plan execution state (`plan_id`) to avoid target oscillation loops.
3. Remove nearest-reachable and shadow-escape fallback branches:
   - `_resolve_nearest_reachable_fallback`
   - `_sample_fallback_candidates`
   - `_policy_fallback_used`, `_policy_fallback_target`
   - `_attempt_shadow_escape_recovery`, `_resolve_shadow_escape_target`, `_sample_shadow_escape_candidates`
4. On `unreachable_policy` in shadow context:
   - force `SHADOW_BOUNDARY_SCAN`
   - then `SEARCH`
5. Keep anti-patrol guard active in `ALERT/COMBAT`.

### 8.3 Expected Result
- no "stuck-jitter-repeat" cycle
- strict `scan -> search` behavior in shadow unreachable flow

### 8.4 Acceptance Criteria
- [ ] runtime no oscillation near policy boundary
- [ ] no direct fallback to patrol in shadow unreachable flow

### 8.5 Tests
New:
- `tests/test_shadow_unreachable_transitions_to_search_not_patrol.gd`

Update:
- `tests/test_shadow_policy_hard_block_without_grant.gd`
- `tests/test_shadow_stall_escapes_to_light.gd`

### 8.6 Legacy Removal Gate
```bash
rg -n "_resolve_nearest_reachable_fallback|_sample_fallback_candidates|_policy_fallback_used|_policy_fallback_target|_attempt_shadow_escape_recovery|_resolve_shadow_escape_target|_sample_shadow_escape_candidates|FALLBACK_RING_|SHADOW_ESCAPE_RING_" src/systems/enemy_pursuit_system.gd -S
```
Expected: no matches.

---

## 9. Phase 3 - Immediate Repath On Non-Door Collision

### 9.1 What Now
- collision handling is door-biased

### 9.2 What To Change
1. In `src/systems/enemy_pursuit_system.gd`, classify slide collision:
   - door
   - non-door
2. On non-door collision:
   - `repath_timer = 0`
   - clear active path cache
   - set reason `collision_blocked`
   - keep intent and target context
3. Replan starts next tick.
4. Remove door-only collision repath helper and replace with unified collision handler.

### 9.3 Expected Result
- enemy keeps current intent after collision
- no early patrol degradation

### 9.4 Acceptance Criteria
- [ ] non-door collision triggers immediate repath
- [ ] intent/target context preserved

### 9.5 Tests
New:
- `tests/test_collision_block_forces_immediate_repath.gd`
- `tests/test_collision_block_preserves_intent_context.gd`

Update:
- `tests/test_honest_repath_without_teleport.gd`

### 9.6 Legacy Removal Gate
```bash
rg -n "_try_open_blocking_door_and_force_repath" src/systems/enemy_pursuit_system.gd -S
```
Expected: no matches (replaced by unified door/non-door collision handler).

---

## 10. Phase 4 - Shadow Scan In ALERT/COMBAT

### 10.1 What Now
- shadow scan is effectively suspicious-only

### 10.2 What To Change
1. In `src/entities/enemy.gd`, build `shadow_scan_target` for `ALERT/COMBAT` with strict priority:
   - `known_target_pos`
   - `last_seen`
   - `investigate_anchor`
2. In `src/systems/enemy_utility_brain.gd`, add rule:
   - `ALERT/COMBAT + no LOS + shadow target => SHADOW_BOUNDARY_SCAN`

### 10.3 Expected Result
- no boundary freeze in alert/combat shadow pursuit

### 10.4 Acceptance Criteria
- [ ] alert/combat shadow target does not degrade to patrol/home
- [ ] scan transitions to search on completion/timeout

### 10.5 Tests
New:
- `tests/test_alert_combat_shadow_boundary_scan_intent.gd`

Update:
- `tests/test_suspicious_shadow_scan.gd`
- `tests/test_combat_no_los_never_hold_range.gd`

### 10.6 Legacy Removal Gate
```bash
rg -n "effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS|alert_level == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS and has_shadow_scan_target" src/entities/enemy.gd src/systems/enemy_utility_brain.gd -S
```
Expected: no matches.

---

## 11. Phase 5 - Navmesh And Obstacles: Mandatory Extraction + Clearance

### 11.1 What Now
- obstacle extraction is not guaranteed in all cases

### 11.2 What To Change
1. In `src/systems/navigation_service.gd`, enforce pipeline:
   - `layout._navigation_obstacles()`
   - fallback scene collider extraction (`StaticBody2D` + obstacle groups)
   - carve
2. Add clearance margin:
   - inset walkable
   - inflate obstacles by `enemy_radius + safety`

### 11.3 Expected Result
- reduced wall hugging
- stable bypass around props/walls

### 11.4 Acceptance Criteria
- [ ] obstacle data exists even when layout API is empty
- [ ] generated paths do not hug colliders tightly

### 11.5 Tests
New:
- `tests/test_nav_obstacle_extraction_fallback.gd`
- `tests/test_nav_clearance_margin_avoids_wall_hugging.gd`

Update:
- `tests/test_navmesh_migration.gd`

### 11.6 Legacy Removal Gate
```bash
rg -n "if not .*_navigation_obstacles.*return|legacy_nav_carve" src tests -S
```
Expected: no matches.

---

## 12. Phase 6 - Patrol Reachability Filter

### 12.1 What Now
- patrol points are filtered by shadow, not guaranteed reachable

### 12.2 What To Change
1. In `src/systems/enemy_patrol_system.gd`, after shadow filter add reachability filter:
   - primary gate: `build_policy_valid_path(...).status == "ok"`
   - optional tie-break only: `nav_path_length`
2. Remove unreachable points from route.
3. Refill with reachable candidates only.

### 12.3 Expected Result
- no patrol dead-end points

### 12.4 Acceptance Criteria
- [ ] all patrol waypoints are policy-valid and reachable
- [ ] no wall-prop stall patrol routes

### 12.5 Tests
New:
- `tests/test_patrol_route_traversability_filter.gd`

Update:
- `tests/test_shadow_route_filter.gd`
- `tests/test_patrol_route_variety.gd`

### 12.6 Legacy Removal Gate
```bash
rg -n "_route = \\[fallback, fallback \\+ Vector2\\(_patrol_cfg_float\\(\"fallback_step_px\"" src/systems/enemy_patrol_system.gd -S
rg -n "build_policy_valid_path\\(|status == \"ok\"" src/systems/enemy_patrol_system.gd -S
```
Expected:
- first command: no matches
- second command: reachability contract checks are present.

---

## 13. Phase 7 - Crowd Avoidance And Core Legacy Cleanup

### 13.1 What Now
- enemy crowd jams in narrow doors/corridors

### 13.2 What To Change
1. Enable `NavigationAgent2D.avoidance_enabled = true` in `scenes/entities/enemy.tscn`.
2. Add runtime avoidance params in enemy initialization.
3. Remove any remaining core legacy replanning branches.

### 13.3 Expected Result
- fewer mutual blocks between enemies

### 13.4 Acceptance Criteria
- [ ] jam rate is <= `KPI_CROWD_JAM_MAX_PERCENT` in stress scenario
- [ ] no core legacy replanning constants/branches left

### 13.5 Tests
New:
- `tests/test_enemy_crowd_avoidance_reduces_jams.gd`

Update:
- `tests/test_honest_repath_without_teleport.gd`
- `tests/test_ai_long_run_stress.gd`

### 13.6 Legacy Removal Gate
```bash
rg -n "_policy_fallback_used|_policy_fallback_target|_resolve_nearest_reachable_fallback|_sample_fallback_candidates|_attempt_shadow_escape_recovery|_resolve_shadow_escape_target|_sample_shadow_escape_candidates" src/systems/enemy_pursuit_system.gd -S
```
Expected: no matches.

---

## 14. Phase 8 - Pursuit Modes (Gameplay Layer)

### 14.1 What Now
- intent logic exists but pursuit modes are not explicit

### 14.2 What To Change
1. Implement explicit pursuit modes:
   - `DirectPressure`
   - `Contain`
   - `ShadowAwareSweep`
   - `LostContactSearch`
2. Define deterministic enter/exit conditions.
3. Add transition guards to prevent mode jitter.

### 14.3 Expected Result
- readable and varied hunt behavior

### 14.4 Acceptance Criteria
- [ ] deterministic mode selection for equal context, equal seed, equal tick index
- [ ] no rapid mode flip jitter

### 14.5 Tests
New:
- `tests/test_pursuit_mode_selection_by_context.gd`
- `tests/test_mode_transition_guard_no_jitter.gd`

### 14.6 Legacy Removal Gate
```bash
rg -n "force_intent_override|legacy_mode_switch" src tests -S
```
Expected: no matches.

---

## 15. Phase 9 - Shadow-Aware Navigation Cost

### 15.1 What Now
- route ranking is mostly path length driven

### 15.2 What To Change
1. Add cost model:
   - light exposure
   - open-space exposure
   - narrow choke penalty
   - crowd density penalty
2. Mode-dependent weight profiles:
   - cautious for `Contain/Search`
   - aggressive for `DirectPressure`

### 15.3 Expected Result
- enemies choose context-smart routes

### 15.4 Acceptance Criteria
- [ ] contain/search prefer safer route when viable (`shadow_cost_delta >= min_shadow_advantage`)
- [ ] direct pressure can choose shorter risky route

### 15.5 Tests
New:
- `tests/test_navigation_shadow_cost_prefers_cover_path.gd`
- `tests/test_navigation_shadow_cost_push_mode_allows_shortcut.gd`

### 15.6 Legacy Removal Gate
```bash
rg -n "best_len_only|ignore_shadow_cost|legacy_costless_planner" src tests -S
```
Expected: no matches.

---

## 16. Phase 10 - Basic Team Tactics

### 16.1 What Now
- limited practical team coordination

### 16.2 What To Change
1. `Contain`:
   - assign enemy slots near exits/chokes
2. `Pressure`:
   - maintain front pressure
3. `Flank`:
   - only when `path_valid + time_budget_ok + flank_distance_ok`
   - otherwise fallback to contain/pressure

### 16.3 Expected Result
- tactical but readable enemy behavior

### 16.4 Acceptance Criteria
- [ ] flank is blocked under invalid constraints
- [ ] contain assigns distinct useful points

### 16.5 Tests
New:
- `tests/test_tactic_contain_assigns_exit_slots.gd`
- `tests/test_tactic_flank_requires_path_and_time_budget.gd`
- `tests/test_multi_enemy_pressure_no_patrol_regression.gd`

### 16.6 Legacy Removal Gate
```bash
rg -n "legacy_flank|old_contain_logic|manual_role_override_legacy" src tests -S
```
Expected: no matches.

---

## 17. Phase 11 - Shadow Search Choreography

### 17.1 What Now
- scan/search exists but lacks staged choreography

### 17.2 What To Change
1. Implement staged shadow search:
   - boundary lock
   - sweep
   - narrowing pockets
2. Add measurable search coverage progression.
3. Keep deterministic transitions.

### 17.3 Expected Result
- deeper and more interesting hide-in-shadow gameplay

### 17.4 Acceptance Criteria
- [ ] search coverage increases over time
- [ ] no idle freeze without progress

### 17.5 Tests
New:
- `tests/test_shadow_search_choreography_progressive_coverage.gd`
- `tests/test_shadow_search_stage_transition_contract.gd`

### 17.6 Legacy Removal Gate
```bash
rg -n "legacy_search_phase|single_stage_search|old_shadow_search_loop" src tests -S
```
Expected: no matches.

---

## 18. Phase 12 - Flashlight Team Role Policy

### 18.1 What Now
- flashlight behavior is mostly individual

### 18.2 What To Change
1. Add role policy:
   - one/few scanners
   - others cover/contain
2. Cap simultaneous scanners by room/zone.
3. Integrate scanner with contain/pressure modes.

### 18.3 Expected Result
- atmospheric pressure without chaotic all-scan behavior

### 18.4 Acceptance Criteria
- [ ] scanner cap enforced
- [ ] role-consistent flashlight behavior

### 18.5 Tests
New:
- `tests/test_flashlight_single_scanner_role_assignment.gd`
- `tests/test_team_contain_with_flashlight_pressure.gd`

### 18.6 Legacy Removal Gate
```bash
rg -n "force_flashlight_all|legacy_flashlight_override|old_scanner_logic" src tests -S
```
Expected: no matches.

---

## 19. Phase 13 - Humanized Imperfection (Fairness Layer)

### 19.1 What Now
- risk of too-dumb or too-cheaty behavior

### 19.2 What To Change
1. Add bounded reaction delay windows.
2. Add communication delay (no telepathy).
3. Add seeded micro-variation in search point choices.

### 19.3 Expected Result
- enemies feel human and fair

### 19.4 Acceptance Criteria
- [ ] no instant global enemy reaction
- [ ] deterministic for fixed seed

### 19.5 Tests
New:
- `tests/test_comm_delay_prevents_telepathy.gd`
- `tests/test_reaction_latency_window_respected.gd`
- `tests/test_seeded_variation_deterministic_per_seed.gd`

### 19.6 Legacy Removal Gate
```bash
rg -n "instant_global_alert|telepathy_call|legacy_reaction_snap" src tests -S
```
Expected: no matches.

---

## 20. Phase 14 - Blood Evidence (Without Corpses)

### 20.1 What Now
- blood exists as effect, not full evidence gameplay flow

### 20.2 What To Change
1. Use fresh blood as evidence signal:
   - set `investigate_anchor`
   - increase alert within room rules
2. Add evidence freshness TTL.
3. Keep awareness canon:
   - no instant combat without confirmation flow

### 20.3 Expected Result
- deeper stealth consequence system without corpse feature

### 20.4 Acceptance Criteria
- [ ] blood triggers investigation, not instant combat bypass
- [ ] TTL expiration disables evidence influence

### 20.5 Tests
New:
- `tests/test_blood_evidence_sets_investigate_anchor.gd`
- `tests/test_blood_evidence_no_instant_combat_without_confirm.gd`
- `tests/test_blood_evidence_ttl_expires.gd`

### 20.6 Legacy Removal Gate
```bash
rg -n "legacy_blood_alert|debug_blood_force_combat|old_blood_hook" src tests -S
```
Expected: no matches.

---

## 21. Final Release Gate

A release candidate is valid only if all are true:
1. All phases 0-14 completed with checklists.
2. All new and updated tests green.
3. Mandatory smoke suite green after final phase.
4. All per-phase `rg` legacy gates pass.
5. No unresolved TODO marked as temporary compatibility logic.
6. Performance Gate passed (`21.5`).
7. Baseline Replay Gate passed (`21.6`).
8. Level Stealth Checklist Gate passed (`21.7`).

Recommended final command set:

```bash
/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_runner.tscn
rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy|_resolve_nearest_reachable_fallback|_sample_fallback_candidates|_policy_fallback_used|_policy_fallback_target|_attempt_shadow_escape_recovery|_resolve_shadow_escape_target|_sample_shadow_escape_candidates|_try_open_blocking_door_and_force_repath|effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS|_route = \\[fallback, fallback \\+ Vector2\\(_patrol_cfg_float\\(\"fallback_step_px\"" src/systems/enemy_pursuit_system.gd src/entities/enemy.gd src/systems/enemy_utility_brain.gd src/systems/enemy_patrol_system.gd -S
```

### 21.1 Formal Definitions (No Interpretation Allowed)

1. `target_context_exists` is true iff at least one condition is true:
   - `has_known_target == true`
   - `has_last_seen == true`
   - `has_investigate_anchor == true`
2. `equal context` means identical:
   - utility input dictionary values
   - RNG seed values
   - tick index
   - active mode/state variables
3. `non-door collision` means:
   - a slide collision exists
   - collider is not recognized by door system and not in door groups
4. `runtime oscillation near boundary` means:
   - >= 3 direction flips in <= 2.0 sec
   - while distance-to-target decreases by < 12 px total in that window
5. `time_budget_ok` for flank means:
   - estimated flank travel time <= `KPI_FLANK_MAX_TIME_SEC`
6. `flank_distance_ok` means:
   - flank path length <= `KPI_FLANK_MAX_PATH_PX`
7. `viable safer route` in Phase 9 means:
   - candidate has `status == ok`
   - `shadow_cost_delta >= min_shadow_advantage`
   - `path_len <= direct_len * KPI_SAFE_ROUTE_MAX_LEN_FACTOR`

### 21.2 Gameplay KPI Targets (Required)

Add these constants and enforce them in acceptance checks:

1. `KPI_CROWD_JAM_MAX_PERCENT = 2.0`
2. `KPI_FLANK_MAX_TIME_SEC = 3.5`
3. `KPI_FLANK_MAX_PATH_PX = 900.0`
4. `KPI_SAFE_ROUTE_MAX_LEN_FACTOR = 1.35`
5. `KPI_SEARCH_COVERAGE_MIN = 0.80` (within 12 sec in staged search test)
6. `KPI_SCAN_TO_SEARCH_MAX_LATENCY_SEC = 0.20`
7. `KPI_ALERT_COMBAT_BAD_PATROL_COUNT = 0` per run
8. `KPI_BLOOD_INSTANT_COMBAT_FALSE_POSITIVE = 0` per run
9. `KPI_AI_MS_AVG_MAX = 1.20`
10. `KPI_AI_MS_P95_MAX = 2.50`
11. `KPI_REPLANS_PER_ENEMY_PER_SEC_MAX = 1.80`
12. `KPI_DETOUR_CANDIDATES_PER_REPLAN_MAX = 24.0`
13. `KPI_HARD_STALLS_PER_MIN_MAX = 1.0`
14. `KPI_SHADOW_POCKET_MIN_AREA_PX2 = 3072.0`
15. `KPI_SHADOW_ESCAPE_MAX_LEN_PX = 960.0`
16. `KPI_ALT_ROUTE_MAX_FACTOR = 1.50`
17. `KPI_SHADOW_SCAN_POINTS_MIN = 3`

### 21.3 Stealth Scenario Regression Pack (Behavioral)

In addition to unit tests, maintain these scenario tests:

1. `Shadow Corridor Pressure`:
   - one enemy scanner, others contain exits
   - no patrol degradation with active target context
2. `Door Choke Crowd`:
   - 6+ enemies crossing narrow chokepoint
   - jam rate <= `KPI_CROWD_JAM_MAX_PERCENT`
3. `Lost Contact In Shadow`:
   - `unreachable_policy` in shadow
   - strict `SHADOW_BOUNDARY_SCAN -> SEARCH`
4. `Collision Integrity`:
   - repeated non-door collisions
   - intent and target context preserved
5. `Blood Evidence`:
   - blood creates investigation without instant combat bypass

Every scenario test must:
1. run with fixed seed
2. emit timeline trace (`intent`, `mode`, `path_status`, `state`)
3. assert KPI thresholds

### 21.4 Tuning Matrix (For Fast Iteration)

Add and maintain a single tuning table in config docs with:

1. pursuit mode weights (`DirectPressure/Contain/ShadowAwareSweep/LostContactSearch`)
2. shadow cost weights (`light`, `open_space`, `choke`, `crowd`)
3. scanner policy (`max_scanners_per_zone`, sweep duration, sweep speed)
4. reaction/communication delays (min/max)
5. blood evidence TTL and alert contribution

Rule:
1. any tuning key used in code must be present in matrix
2. any matrix key removed from code must be removed same phase (no stale config legacy)

### 21.5 Performance Gate (Required)

Purpose:
1. prevent navigation/tactics upgrades from degrading runtime.
2. stop hidden CPU regressions before they reach gameplay.

Required scenario for gate:
1. `tests/test_ai_long_run_stress.gd` (or replacement with identical contract).
2. fixed seed (`seed = 1337`).
3. fixed duration (`duration_sec = 180`).
4. fixed load:
   - `enemy_count = 12`
   - at least 2 narrow chokepoints
   - at least 1 shadow-heavy zone
5. same map/layout must be used for baseline and candidate.

Required emitted metrics:
1. `ai_ms_avg`
2. `ai_ms_p95`
3. `replans_total`
4. `detour_candidates_evaluated_total`
5. `hard_stall_events_total`
6. `collision_repath_events_total`

Mandatory formulas:
1. `replans_per_enemy_per_sec = replans_total / (enemy_count * duration_sec)`
2. `detour_candidates_per_replan = detour_candidates_evaluated_total / max(replans_total, 1)`
3. `hard_stalls_per_min = hard_stall_events_total * 60.0 / duration_sec`

Pass thresholds:
1. `ai_ms_avg <= KPI_AI_MS_AVG_MAX`
2. `ai_ms_p95 <= KPI_AI_MS_P95_MAX`
3. `replans_per_enemy_per_sec <= KPI_REPLANS_PER_ENEMY_PER_SEC_MAX`
4. `detour_candidates_per_replan <= KPI_DETOUR_CANDIDATES_PER_REPLAN_MAX`
5. `hard_stalls_per_min <= KPI_HARD_STALLS_PER_MIN_MAX`
6. `collision_repath_events_total > 0` in stress scene with forced collisions (validates collision repath path is alive).

Fail policy:
1. if any threshold fails, release gate fails.
2. no threshold relaxation in same phase without:
   - tuning rationale in `Notes`
   - updated KPI constant in section `21.2`
   - corresponding test expectation update.

Required test additions/updates:
1. add or update `tests/test_ai_performance_gate.gd`.
2. update `tests/test_ai_long_run_stress.gd` to emit all required metrics.
3. register test scene in `tests/test_runner_node.gd`.

### 21.6 Baseline Replay Gate (Required)

Purpose:
1. detect silent behavior drift.
2. prove that behavior changes are intentional, not accidental.

Replay pack source:
1. use scenarios from `21.3 Stealth Scenario Regression Pack`.
2. each scenario has one baseline trace file:
   - `tests/baselines/replay/<scenario_name>.jsonl`

Trace schema (one record per sampled tick):
1. `tick`
2. `enemy_id`
3. `state`
4. `intent_type`
5. `mode`
6. `path_status`
7. `target_context_exists`
8. `position_x`
9. `position_y`

Sampling rules:
1. fixed tick step: every physics tick.
2. fixed seed: `1337`.
3. fixed duration per scenario: `60 sec` minimum.
4. fixed spawn order and enemy ids.

Comparison rules:
1. exact match required for discrete fields:
   - `state`, `intent_type`, `mode`, `path_status`, `target_context_exists`
2. position tolerance:
   - `abs(dx) <= 6.0 px`
   - `abs(dy) <= 6.0 px`
3. aggregate drift budget:
   - at most `2.0%` of sampled records may exceed position tolerance.

Pass/fail:
1. gate passes only if all scenario comparisons pass.
2. any discrete mismatch beyond first `0.50 sec` warmup fails gate.

Baseline update policy (strict):
1. baseline update allowed only when behavior change is intentional.
2. baseline update must be in same phase commit as code change.
3. commit must include:
   - explicit reason in phase notes
   - list of expected changed fields per scenario.
4. baseline update without rationale is rejected.

Required test additions/updates:
1. add `tests/test_replay_baseline_gate.gd`.
2. add replay capture/compare helpers used by scenario pack tests.
3. register all replay gate scenes in `tests/test_runner_node.gd`.

### 21.7 Level Stealth Checklist Gate (Required)

Purpose:
1. guarantee that AI quality is supported by level topology.
2. avoid maps that force dumb-looking behavior.

Applies to:
1. every playable stealth level.
2. every room tagged as stealth-relevant (critical route, objective zone, or expected patrol zone).

Required automatic checks (hard fail on violation):
1. Patrol Reachability:
   - every patrol waypoint must satisfy `build_policy_valid_path(...).status == "ok"` from previous waypoint.
2. Shadow Pocket Availability:
   - each stealth-relevant room has at least `2` shadow pockets.
   - each pocket area >= `KPI_SHADOW_POCKET_MIN_AREA_PX2`.
3. Shadow Escape Availability:
   - from each shadow pocket, at least `1` policy-valid path to non-shadow boundary exists.
   - escape nav length <= `KPI_SHADOW_ESCAPE_MAX_LEN_PX`.
4. Route Variety:
   - between main entry and objective point, at least `2` policy-valid routes exist.
   - second route length <= `KPI_ALT_ROUTE_MAX_FACTOR * shortest_route_len`.
5. Chokepoint Width Safety:
   - every required chokepoint width >= `2 * enemy_radius + 2 * clearance_margin`.
6. Boundary Scan Support:
   - each shadow-relevant room has >= `KPI_SHADOW_SCAN_POINTS_MIN` valid boundary scan points.

Required manual validation checklist (release artifact):
1. run `10` scripted stealth traversals per level.
2. collect one short capture per traversal with debug overlay (`intent`, `state`, `path_status`).
3. verify:
   - no repeated wall-grind loops
   - no patrol/home drop in active alert/combat target context
   - shadow hideouts produce scan/search pressure, not idle freeze.
4. attach summary file:
   - `docs/qa/stealth_level_checklist_<level_name>.md`

Required KPI constants:
1. use `KPI_SHADOW_POCKET_MIN_AREA_PX2` from `21.2`.
2. use `KPI_SHADOW_ESCAPE_MAX_LEN_PX` from `21.2`.
3. use `KPI_ALT_ROUTE_MAX_FACTOR` from `21.2`.
4. use `KPI_SHADOW_SCAN_POINTS_MIN` from `21.2`.

Pass/fail:
1. all automatic checks pass for all stealth-relevant rooms.
2. manual checklist files exist for all playable stealth levels.
3. any missing artifact or failed room check fails release gate.

Required test additions/updates:
1. add `tests/test_level_stealth_checklist.gd`.
2. update level validation suite to include stealth room tags and objective anchors.
3. register checklist gate scene in `tests/test_runner_node.gd`.

---

## 22. Phase Tracking Table

| Phase | Status | Legacy Removed First | Tests Added/Updated | Phase Gate | Smoke Gate | Notes |
|---|---|---|---|---|---|---|
| 0 | TODO | TODO | TODO | TODO | TODO | |
| 1 | TODO | TODO | TODO | TODO | TODO | |
| 2 | TODO | TODO | TODO | TODO | TODO | |
| 3 | TODO | TODO | TODO | TODO | TODO | |
| 4 | TODO | TODO | TODO | TODO | TODO | |
| 5 | TODO | TODO | TODO | TODO | TODO | |
| 6 | TODO | TODO | TODO | TODO | TODO | |
| 7 | TODO | TODO | TODO | TODO | TODO | |
| 8 | TODO | TODO | TODO | TODO | TODO | |
| 9 | TODO | TODO | TODO | TODO | TODO | |
| 10 | TODO | TODO | TODO | TODO | TODO | |
| 11 | TODO | TODO | TODO | TODO | TODO | |
| 12 | TODO | TODO | TODO | TODO | TODO | |
| 13 | TODO | TODO | TODO | TODO | TODO | |
| 14 | TODO | TODO | TODO | TODO | TODO | |
| 15 | TODO | TODO | TODO | TODO | TODO | |
| 16 | TODO | TODO | TODO | TODO | TODO | |
| 17 | TODO | TODO | TODO | TODO | TODO | |
| 18 | TODO | TODO | TODO | TODO | TODO | |
| 19 | TODO | TODO | TODO | TODO | TODO | |

---

## 23. Execution Plan And Dependency Map

### 23.1 Mandatory Execution Order (Default, Low-Risk Path)

Run phases in this exact order:
1. Phase 0
2. Phase 1
3. Phase 2
4. Phase 3
5. Phase 4
6. Phase 5
7. Phase 6
8. Phase 7
9. Phase 8
10. Phase 9
11. Phase 10
12. Phase 11
13. Phase 12
14. Phase 13
15. Phase 14
16. Phase 15
17. Phase 16
18. Phase 17
19. Phase 18
20. Phase 19

Rule:
1. next phase starts only after current phase passes:
   - phase tests
   - phase `rg` legacy gate
   - mandatory smoke suite.

### 23.2 Dependency Matrix (No Interpretation)

1. Phase 0 depends on: none.
2. Phase 1 depends on: Phase 0.
3. Phase 2 depends on: Phase 0, Phase 1.
4. Phase 3 depends on: Phase 2.
5. Phase 4 depends on: Phase 0, Phase 2.
6. Phase 5 depends on: Phase 1.
7. Phase 6 depends on: Phase 0, Phase 1, Phase 5.
8. Phase 7 depends on: Phase 2, Phase 3, Phase 5.
9. Phase 8 depends on: Phase 2, Phase 4.
10. Phase 9 depends on: Phase 1, Phase 5, Phase 8.
11. Phase 10 depends on: Phase 7, Phase 8, Phase 9.
12. Phase 11 depends on: Phase 4, Phase 8, Phase 9.
13. Phase 12 depends on: Phase 10, Phase 11.
14. Phase 13 depends on: Phase 8, Phase 9, Phase 10, Phase 11, Phase 12.
15. Phase 14 depends on: Phase 4, Phase 11, Phase 13.
16. Phase 15 depends on: Phase 2, Phase 4.
17. Phase 16 depends on: Phase 11, Phase 15.
18. Phase 17 depends on: Phase 3, Phase 16.
19. Phase 18 depends on: Phase 10, Phase 15, Phase 17.
20. Phase 19 depends on: Phase 15, Phase 16, Phase 17, Phase 18.

Release dependencies:
1. Core Final Release Gate depends on: Phase 0-14 complete and all gates from section 21 passed.
2. Extended Stealth Release Gate depends on: Phase 0-19 complete, and section 30 passed.

### 23.3 Critical Path

Critical path for runtime navigation correctness:
1. Phase 0 -> Phase 1 -> Phase 2 -> Phase 3 -> Phase 4 -> Phase 5 -> Phase 6 -> Phase 7.

Critical path for stealth gameplay quality:
1. Phase 8 -> Phase 9 -> Phase 10 -> Phase 11 -> Phase 12 -> Phase 13 -> Phase 14.

Critical path for advanced stealth feel:
1. Phase 15 -> Phase 16 -> Phase 17 -> Phase 18 -> Phase 19.

### 23.4 Allowed Parallel Work (Only Where Safe)

Parallel window A (after Phase 4 complete):
1. implement Phase 5 code branch and tests.
2. prepare Phase 8 scaffolding tests (`mode` trace/assertions).

Parallel window B (after Phase 9 complete):
1. implement Phase 10 and Phase 11 in separate branches.
2. merge only after both pass their own phase gates.

Parallel window C (after Phase 12 complete):
1. implement Phase 13.
2. prepare Phase 14 test fixtures for blood evidence.

Hard restriction:
1. no parallel merge may introduce old/new coexistence in same runtime branch.
2. if coexistence appears, reject merge and rollback branch.

### 23.5 Per-Phase Execution Contract (Single Template)

For each phase `N` run exactly:
1. Remove legacy branch declared for phase `N`.
2. Run phase `N` legacy `rg` gate and verify no matches.
3. Implement new phase `N` logic.
4. Add new tests listed for phase `N`.
5. Update existing tests listed for phase `N`.
6. Run phase-specific tests.
7. Run mandatory smoke suite from section 4.
8. Update `Phase Tracking Table` row `N` with actual status and notes.

Phase close condition:
1. all eight steps above completed.

### 23.6 Blockers And Escalation Rules

Blocking condition:
1. any phase test fails and root cause is unresolved.
2. legacy `rg` gate has any match.
3. smoke suite fails.
4. performance gate, replay gate, or level checklist gate fails.

Escalation action:
1. stop next-phase development immediately.
2. fix in current phase only.
3. if fix cannot preserve invariant set, rollback entire phase.
4. do not patch over blockers with temporary compatibility branch.

### 23.7 Branching And Merge Policy

1. one branch per phase: `phase-<N>-<short-topic>`.
2. one merge per phase only after phase close condition.
3. no cross-phase mixed PR.
4. baseline replay updates are allowed only per section `21.6` policy.
5. KPI threshold edits are allowed only per section `21.5` fail policy.

---


## 25. Phase 15 - State Doctrine Matrix (CALM/SUSPICIOUS/ALERT/COMBAT)

### 25.1 What Now
- state behaviors overlap and create regressions in no-LOS branches

### 25.2 What To Change
1. Define explicit allowed intent matrix per state.
2. Keep strict anti-degrade rule:
   - `ALERT/COMBAT + target_context_exists => no PATROL/RETURN_HOME`.
3. Implement suspicious flashlight policy:
   - move to `last_seen`/`investigate_anchor`
   - `30%` flashlight activation in darkness (seeded deterministic).
4. Extend `shadow_scan_target` selection for `ALERT/COMBAT` with strict priority:
   - `known_target_pos`
   - `last_seen`
   - `investigate_anchor`
5. Remove suspicious-only scan gating in utility context build.

### 25.3 Expected Result
- each state has distinct stealth gameplay role
- no accidental patrol/home degradation in active threat context

### 25.4 Acceptance Criteria
- [ ] intent selection is deterministic for same context/seed/tick
- [ ] suspicious flashlight probability is reproducible and bounded at 30%
- [ ] no patrol/home in alert/combat with active target context

### 25.5 Tests
New:
- `tests/test_state_doctrine_matrix_contract.gd`
- `tests/test_suspicious_flashlight_30_percent_seeded.gd`
- `tests/test_alert_no_los_searches_dark_pockets_not_patrol.gd`

Update:
- `tests/test_suspicious_shadow_scan.gd`
- `tests/test_combat_no_los_never_hold_range.gd`

### 25.6 Legacy Removal Gate
```bash
rg -n "effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT\\.SUSPICIOUS" src/entities/enemy.gd src/systems/enemy_utility_brain.gd -S
```
Expected: no suspicious-only scan restriction.
No invalid no-LOS return-home branch under active alert/combat context is validated by:
1. phase acceptance criteria `25.4`
2. phase tests in `25.5`.

---

## 26. Phase 16 - Full Dark-Zone Search Sessions (ALERT/COMBAT)

### 26.1 What Now
- shadow search exists but lacks full-room coverage progression

### 26.2 What To Change
1. Build per-room `dark_search_nodes` (reachable dark pockets + boundary points).
2. Add search session runtime:
   - start
   - progress tracking
   - completion by coverage or timeout
3. Score next search node by deterministic formula:
   - uncovered score
   - policy-valid path length
   - tactical priority
4. Preserve unreachable shadow canon:
   - `SHADOW_BOUNDARY_SCAN -> SEARCH`
5. Remove single-stage legacy search loop usage.

### 26.3 Expected Result
- enemies sweep dark spaces progressively instead of local oscillation

### 26.4 Acceptance Criteria
- [ ] coverage rises monotonically during active session
- [ ] no freeze at one boundary point without progress
- [ ] no direct patrol fallback while search session active

### 26.5 Tests
New:
- `tests/test_dark_search_graph_progressive_coverage.gd`
- `tests/test_alert_combat_search_session_completion_contract.gd`
- `tests/test_unreachable_shadow_node_forces_scan_then_search.gd`

Update:
- `tests/test_shadow_stall_escapes_to_light.gd`
- `tests/test_shadow_policy_hard_block_without_grant.gd`

### 26.6 Legacy Removal Gate
```bash
rg -n "single_stage_search|legacy_search_phase|old_shadow_search_loop" src tests -S
```
Expected: no matches.

---

## 27. Phase 17 - Anti-Stall Recovery Without Intent Loss

### 27.1 What Now
- repeated collisions/path failures still risk jitter/stall loops

### 27.2 What To Change
1. Add progress watchdog:
   - check displacement over fixed window
   - if below threshold -> force immediate repath
2. Keep non-door collision contract:
   - `repath_timer = 0`
   - clear path cache
   - `reason = collision_blocked`
   - preserve intent and target context
3. Add repeated blocked-point escalation:
   - if blocked same area N times -> next valid search node
4. Remove remaining shadow-escape legacy branches in pursuit.

### 27.3 Expected Result
- no "stuck -> jerk -> stuck" cycles
- pursuit remains stable and intentional after collision

### 27.4 Acceptance Criteria
- [ ] blocked movement triggers next-tick replanning
- [ ] intent/target unchanged after non-door collision
- [ ] hard stalls reduced under stress scenario

### 27.5 Tests
New:
- `tests/test_shadow_stuck_watchdog_escalates_to_next_node.gd`
- `tests/test_repeated_blocked_point_triggers_scan_then_search.gd`

Update:
- `tests/test_shadow_enemy_stuck_when_inside_shadow.gd`
- `tests/test_shadow_enemy_unstuck_after_flashlight_activation.gd`
- `tests/test_collision_block_forces_immediate_repath.gd`

### 27.6 Legacy Removal Gate
```bash
rg -n "_shadow_escape_active|_shadow_escape_target|_attempt_shadow_escape_recovery|_resolve_shadow_escape_target|_sample_shadow_escape_candidates" src/systems/enemy_pursuit_system.gd -S
```
Expected: no matches.

---

## 28. Phase 18 - FEAR-Lite Combat Tactics (Cover/Flank/Pressure)

### 28.1 What Now
- squad roles exist, but cover/flank quality is limited in live combat

### 28.2 What To Change
1. Add cover candidate extraction from nav obstacles/walls.
2. Add cover scoring:
   - LOS break quality
   - path validity
   - distance and angle utility
3. Enforce flank contract:
   - flank only if `path_status == ok`
   - ETA within flank budget
   - fallback to contain/pressure when invalid
4. Update squad slot path validation to policy-valid contract only.
5. Remove legacy `build_path_points` slot validation branch.

### 28.3 Expected Result
- combat becomes tactical and readable without unfair behavior

### 28.4 Acceptance Criteria
- [ ] enemies distribute roles (not all pressure)
- [ ] valid cover points are preferred under fire
- [ ] invalid flank attempts are rejected deterministically

### 28.5 Tests
New:
- `tests/test_combat_cover_selection_prefers_valid_cover.gd`
- `tests/test_combat_flank_requires_eta_and_path_ok.gd`
- `tests/test_combat_role_distribution_not_all_pressure.gd`

Update:
- `tests/test_enemy_squad_system.gd`
- `tests/test_combat_role_lock_and_reassign_triggers.gd`

### 28.6 Legacy Removal Gate
```bash
rg -n "build_path_points\\(" src/systems/enemy_squad_system.gd -S
```
Expected: no matches.

---


## 30. Phase 19 - Extended Stealth Release Gate (Phases 15-19)

### 30.1 Gate Scope
1. applies only after Phase 0-19 completion.
2. includes all section 21 gates plus advanced stealth checks below.

### 30.2 Required KPI Outcomes
1. `hard_stalls_per_min <= KPI_HARD_STALLS_PER_MIN_MAX`
2. `ai_ms_avg <= KPI_AI_MS_AVG_MAX`
3. `ai_ms_p95 <= KPI_AI_MS_P95_MAX`
4. `replans_per_enemy_per_sec <= KPI_REPLANS_PER_ENEMY_PER_SEC_MAX`
5. `KPI_ALERT_COMBAT_BAD_PATROL_COUNT == 0`

### 30.3 Required Test Suite
1. all tests from phases 15-19.
2. full smoke suite from section 4.
3. replay baseline gate from section `21.6`.
4. level stealth checklist gate from section `21.7`.

### 30.4 Legacy Zero-Tolerance Gate
```bash
rg -n "legacy_|temporary_|debug_shadow_override|old_" src tests -S
```
Expected: no matches except explicit allowlist comments approved in same phase notes.

### 30.5 Pass/Fail Rule
1. pass only if every condition in `30.1` to `30.4` is satisfied.
2. if any check fails, release is blocked.
3. no temporary compatibility patches allowed to pass the gate.
