# Enemy Deduplication Plan (No Ambiguity)

## 0) Scope and Rules

- Target file: `src/entities/enemy.gd`.
- Goal: remove duplicated/overlapping logic and migrate owners to dedicated runtimes.
- Primary rule: one owner per domain at runtime.
- Secondary rule: remove Enemy test legacy (white-box/private access) in planned phases.
- No behavior changes in structural phases unless phase explicitly allows behavior policy change.

## 1) Hard Preconditions

Before Phase 1 starts, all current regression and gate suites must be green.

Required baseline suites:
- `tests/test_refactor_kpi_contract.tscn`
- `tests/test_extended_stealth_release_gate.tscn`
- `tests/test_runner.tscn`

If baseline fails, refactor does not start.

---

## 2) Mandatory Phase Order

## Phase 0 - Contracts Freeze

**Purpose**
- Freeze observable contracts to prevent accidental API drift.

**Code changes**
- Add/lock contract tests only.
- No runtime logic migration.

**New tests (required)**
- `tests/test_enemy_debug_snapshot_contract.gd`
- `tests/test_enemy_utility_context_contract.gd`
- `tests/test_enemy_confirm_runtime_config_contract.gd`
- `tests/test_enemy_pursuit_exec_result_contract.gd`

**Exit criteria**
- Contract tests pass.
- Baseline suites remain green.

---

## Phase 1 - Mechanical Dedup in `enemy.gd` (Behavior 1:1)

**Purpose**
- Remove direct copy-paste clusters before extraction.

**Code changes**
- Consolidate duplicate noise/call handling into a single helper pipeline.
- Consolidate combat-search current-node clear/apply blocks.
- Consolidate zone lookup into one source helper.
- Consolidate reset bundles (first-shot/role/search/migration).

**New tests**
- None (reuse baseline + Phase 0 contracts).

**Exit criteria**
- Behavior parity with baseline.
- No accidental policy changes.

---

## Phase 2 - Runtime Skeletons + Wiring (No Logic Move Yet)

**Purpose**
- Prepare target architecture with explicit owners.

**Code changes**
- Add skeleton runtime scripts:
  - `src/entities/enemy_combat_search_runtime.gd`
  - `src/entities/enemy_fire_control_runtime.gd`
  - `src/entities/enemy_combat_role_runtime.gd`
  - `src/entities/enemy_alert_latch_runtime.gd`
  - `src/entities/enemy_detection_runtime.gd`
  - `src/entities/enemy_debug_snapshot_runtime.gd`
- Add wiring in Enemy (construction and references).

**New tests (required)**
- `tests/test_enemy_runtime_helpers_exist.gd`

**Exit criteria**
- Project runs.
- Behavior unchanged.

---

## Phase 3 - Combat Search Owner Extraction

**Purpose**
- Move all combat-search state machine ownership out of Enemy.

**Code changes**
- Move search node selection/progress/coverage/recovery logic to `enemy_combat_search_runtime.gd`.
- Enemy keeps orchestration call only.

**New tests (required)**
- `tests/test_enemy_combat_search_runtime_unit.gd`
- `tests/test_enemy_combat_search_recovery_unit.gd`

**Legacy migration required**
- Migrate all Search white-box Enemy tests (full list in section "Legacy Matrix").

**Exit criteria**
- No algorithmic combat-search logic remains in Enemy body.
- Migrated tests pass.

---

## Phase 4 - Fire Control Owner Extraction

**Purpose**
- Move fire gating/first-shot/telegraph/trace cache ownership out of Enemy.

**Code changes**
- Move fire block reason, schedule gate, first-shot timers, and related helpers to `enemy_fire_control_runtime.gd`.

**New tests (required)**
- `tests/test_enemy_fire_control_runtime_unit.gd`
- `tests/test_enemy_fire_first_shot_gate_unit.gd`

**Legacy migration required**
- Migrate all Fire white-box Enemy tests.

**Exit criteria**
- Enemy only orchestrates fire runtime calls.

---

## Phase 5 - Combat Role Owner Extraction

**Purpose**
- Move dynamic role lock/reassign policy ownership out of Enemy.

**Code changes**
- Move role runtime logic to `enemy_combat_role_runtime.gd`.

**New tests (required)**
- `tests/test_enemy_combat_role_runtime_unit.gd`

**Legacy migration required**
- Migrate all Role white-box Enemy tests.

**Exit criteria**
- Enemy no longer owns role policy algorithm.

---

## Phase 6 - Alert Latch + Zone Owner Extraction

**Purpose**
- Move room alert snapshot/latch migration/zone state ownership out of Enemy.

**Code changes**
- Move logic to `enemy_alert_latch_runtime.gd`.

**New tests (required)**
- `tests/test_enemy_alert_latch_runtime_unit.gd`
- `tests/test_enemy_zone_resolution_contract.gd`

**Legacy migration required**
- Remove tests calling `_resolve_room_id_for_events` directly.

**Exit criteria**
- Latch and zone logic resolved by runtime owner only.

---

## Phase 7 - Detection Owner Extraction

**Purpose**
- Move detection/flashlight/last-seen/investigate/utility-context ownership out of Enemy.

**Code changes**
- Move detection and context builders to `enemy_detection_runtime.gd`.

**New tests (required)**
- `tests/test_enemy_detection_runtime_target_context_unit.gd`
- `tests/test_enemy_detection_runtime_flashlight_policy_unit.gd`
- `tests/test_enemy_detection_runtime_reaction_warmup_unit.gd`

**Legacy migration required**
- Remove tests touching `_awareness`, `_last_seen_*`, `_investigate_*`, `_flashlight_*` private fields.

**Exit criteria**
- Detection policy has one runtime owner.

---

## Phase 8 - Debug Snapshot Owner Extraction

**Purpose**
- Move debug snapshot assembly ownership out of Enemy.

**Code changes**
- Move snapshot builder/traces to `enemy_debug_snapshot_runtime.gd`.

**New tests (required)**
- `tests/test_enemy_debug_snapshot_runtime_parity.gd`

**Legacy migration required**
- Replace private debug field reads with public snapshot assertions.

**Exit criteria**
- Snapshot behavior parity preserved.

---

## Phase 9 - Runtime Tick Compression + Soft Legacy Cleanup

**Purpose**
- Turn `runtime_budget_tick` into orchestrator only.

**Code changes**
- Keep phased execution order only.
- Remove direct domain logic from tick body.
- Replace soft legacy use of `enemy.get("_pursuit")` in tests with explicit public/debug API.

**New tests (required)**
- `tests/test_enemy_runtime_orchestrator_single_owner.gd`

**Exit criteria**
- Tick contains orchestration, not domain internals.

---

## Phase 10 - Test Infrastructure Legacy Purge

**Purpose**
- Remove embedded mini-tests and old gate assumptions.

**Code changes**
- Remove Section 18c mini-tests from `tests/test_runner_node.gd`.
- Remove:
  - `tests/test_phase_bugfixes.gd`
  - `tests/test_phase_bugfixes.tscn`
- Update `tests/test_extended_stealth_release_gate.gd` dependency gate commands to runtime files.
- Extend `tests/test_refactor_kpi_contract.gd` with enemy-runtime helper checks and legacy prefix bans.

**New tests (required)**
- `tests/test_enemy_test_legacy_zero_tolerance.gd` (or equivalent KPI extension)

**Exit criteria**
- Runner executes scene suites only.
- No embedded Enemy white-box mini-tests remain.

---

## Phase 11 - Compatibility Wrapper Cleanup

**Purpose**
- Remove temporary forwarding wrappers in Enemy.

**Code changes**
- Delete compatibility wrappers after all dependent tests migrated.

**New tests**
- None.

**Exit criteria**
- Enemy no longer contains temporary wrapper API.

---

## Phase 12 - Final Regression + Release Gate

**Purpose**
- Final acceptance.

**Code changes**
- No functional changes.

**New tests**
- None.

**Exit criteria**
- All gates pass.

---

## 3) Legacy Test Matrix (must be fully migrated)

### A. Search white-box legacy (Phase 3)
- `tests/test_combat_next_room_scoring_no_loops.gd`
- `tests/test_dark_search_graph_progressive_coverage.gd`
- `tests/test_alert_combat_search_session_completion_contract.gd`
- `tests/test_repeated_blocked_point_triggers_scan_then_search.gd`
- `tests/test_unreachable_shadow_node_forces_scan_then_search.gd`
- `tests/test_combat_search_per_room_budget_and_total_cap.gd`

### B. Fire white-box legacy (Phase 4)
- `tests/test_enemy_fire_decision_contract.gd`
- `tests/test_enemy_shotgun_fire_block_reasons.gd`
- `tests/test_enemy_fire_trace_cache_runtime.gd`
- `tests/test_first_shot_delay_starts_on_first_valid_firing_solution.gd`
- `tests/test_first_shot_timer_starts_on_first_valid_firing_solution.gd`
- `tests/test_first_shot_timer_pause_and_reset_after_2_5s.gd`
- `tests/test_friendly_block_prevents_fire_and_triggers_reposition.gd`
- `tests/test_shadow_flashlight_rule_blocks_or_allows_fire.gd`
- `tests/test_telegraph_profile_production_vs_debug.gd`
- `tests/test_enemy_fire_cooldown_min_guard.gd`
- `tests/test_stealth_weapon_pipeline_equivalence.gd`
- `tests/test_enemy_damage_is_exactly_1hp_per_successful_shot.gd`

### C. Role white-box legacy (Phase 5)
- `tests/test_combat_role_lock_and_reassign_triggers.gd`
- `tests/test_tactic_flank_requires_path_and_time_budget.gd`
- `tests/test_combat_flank_requires_eta_and_path_ok.gd`

### D. Detection/awareness white-box legacy (Phase 7)
- `tests/test_state_doctrine_matrix_contract.gd`
- `tests/test_last_seen_used_only_in_suspicious_alert.gd`
- `tests/test_alert_flashlight_detection.gd`
- `tests/test_suspicious_flashlight_30_percent_seeded.gd`
- `tests/test_suspicious_shadow_scan.gd`
- `tests/test_team_contain_with_flashlight_pressure.gd`
- `tests/test_blood_evidence_no_instant_combat_without_confirm.gd`
- `tests/test_blood_evidence_sets_investigate_anchor.gd`
- `tests/test_reaction_latency_window_respected.gd`
- `tests/test_alert_hold_dynamic.gd`
- `tests/test_stealth_room_lkp_search.gd`
- `tests/test_combat_utility_intent_aggressive.gd`
- `tests/test_flashlight_single_source_parity.gd`
- `tests/test_flashlight_active_in_combat_when_latched.gd`

### E. Latch/orchestration white-box legacy (Phase 6)
- `tests/test_zone_enemy_wiring.gd`
- `tests/test_ai_transition_single_owner.gd`
- `tests/test_ai_no_duplicate_state_change_per_tick.gd`
- `tests/test_force_state_path.gd`
- `tests/test_combat_room_alert_sync.gd`
- `tests/test_no_combat_latch_before_confirm_complete.gd`
- `tests/test_stealth_room_alert_flashlight_integration.gd`

### F. Soft legacy (Phase 8-9)
- `tests/test_3zone_combat_transition_stress.gd`
- `tests/test_combat_intent_switches_push_to_search_after_grace.gd`
- `tests/test_detour_side_flip_on_stall.gd`
- `tests/test_honest_repath_without_teleport.gd`
- `tests/test_last_seen_grace_window.gd`
- `tests/test_peek_corner_confirm_threshold.gd`
- `tests/test_flashlight_bonus_applies_in_combat.gd`
- `tests/test_stealth_room_combat_fire.gd`

### G. Infrastructure legacy (Phase 10)
- `tests/test_runner_node.gd` (remove embedded SECTION 18c micro-tests)
- `tests/test_phase_bugfixes.gd`
- `tests/test_phase_bugfixes.tscn`
- `tests/test_extended_stealth_release_gate.gd` (dependency gates target runtime files)
- `tests/test_refactor_kpi_contract.gd` (enemy runtime KPI coverage)

---

## 4) Non-Negotiable Close Gates

After Phase 10:

```bash
rg -n "enemy\._|enemy\.set\(\"_|enemy\.get\(\"_|enemy\.call\(\"_" tests -S
```
Expected:
- `0` matches for Enemy tests (except explicitly approved permanent public API compatibility checks).

```bash
rg -n "SECTION 18c: Bugfix phase unit tests|Phase 1: on_heard_shot|Phase 2: noise->ALERT|Phase 3: stuck patrol" tests/test_runner_node.gd -S
```
Expected:
- `0` matches.

```bash
test -f tests/test_phase_bugfixes.gd && echo "FAIL" || echo "OK"
test -f tests/test_phase_bugfixes.tscn && echo "FAIL" || echo "OK"
```
Expected:
- both `OK`.

All release gates must pass:
- `tests/test_refactor_kpi_contract.tscn`
- `tests/test_extended_stealth_release_gate.tscn`
- `tests/test_ai_performance_gate.tscn`
- `tests/test_replay_baseline_gate.tscn`
- `tests/test_level_stealth_checklist.tscn`

---

## 5) Done Definition

Refactor is done only if all below are true:

- All phases completed in strict order.
- Enemy domains each have a single owner runtime.
- Legacy Enemy white-box test style removed according to matrix.
- Embedded mini-tests removed from runner.
- KPI and release gates are green.
- No prohibited legacy grep matches remain.
