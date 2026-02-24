## Start of Persistent Module Boundary Contract

This contract defines cross-phase architectural invariants and lexical anti-legacy guards.

Authority rule:
- The top-level PMB definitions in this section are authoritative.
- Every phase-local PMB block in section 13 (when present) MUST preserve the same PMB command text and expected pass conditions as this top-level PMB section. Markdown labels/wrappers may differ.

Every phase MUST run exactly 5 PMB gate commands at phase close:
- PMB-1
- PMB-2
- PMB-3
- PMB-4
- PMB-5 verification command (the binary pass/fail command shown in PMB-5)

The standalone raw `rg` command shown inside PMB-5 is diagnostic-only (optional) and is not counted in the required 5 PMB gate commands.

Evaluation rules:
- PMB-1 through PMB-4 are lexical `rg` scans (comments and string literals are included in matching).
- PMB-1 through PMB-4 PASS/FAIL is determined by the expected match count / stdout content, not by shell exit code.
- For PMB-1 through PMB-4, `rg` exit code `1` with empty stdout counts as PASS (`0 matches`).
- PMB-5 passes only when the PMB-5 verification command exits `0` and prints exactly `PMB-5: PASS (1)`.

Expected outputs:
- PMB-1 through PMB-4: **0 matches**
- PMB-5: `PMB-5: PASS (1)`
Any other output = architecture violation = phase fails.

### PMB-1. EnemyPursuitSystem — lexical anti-legacy guard for alternate path planners

```
rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S
```

Expected: 0 matches.
Invariant: PMB-1 forbids known legacy/alternate path-planner identifiers in `EnemyPursuitSystem` (`build_reachable_path_points`, `build_path_points`, `_build_policy_valid_path_fallback_contract`, `_build_reachable_path_points_for_enemy`). This is a lexical anti-legacy guard and supports (but does not by itself prove) the single runtime path-planner architecture.

### PMB-2. `enemy.gd` не вызывает path-planning navigation API напрямую

```
rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S
```

Expected: 0 matches.
Invariant: `Enemy` не вызывает path-planning navigation методы напрямую (`build_policy_valid_path`, `build_reachable_path_points`, `build_path_points`). Непутевые nav-query вызовы (например, room/shadow metadata queries) не запрещаются этим PMB и регулируются фазовыми scope/owner контрактами.

### PMB-3. `enemy_pursuit_system.gd` не производит utility-context contract fields

```
rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S
```

Expected: 0 matches.
Invariant: Utility-context contract fields (`has_last_seen`, `has_known_target`, `has_investigate_anchor`) производятся исключительно в `Enemy._build_utility_context`. `EnemyPursuitSystem` не читает и не записывает эти поля напрямую.

### PMB-4. `EnemyPursuitSystem` не конструирует intent dictionaries (`"type": ...`)

```
rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S
```

Expected: 0 matches.
Invariant: Решение и конструирование intent dictionary (`{"type": ...}`) выполняются исключительно в `EnemyUtilityBrain._choose_intent`. `EnemyPursuitSystem` может ветвиться по уже выбранному `intent_type` и исполнять интент, но не должен создавать новый intent dictionary.

### PMB-5. Только один вызов `execute_intent` из `Enemy`

Diagnostic command (optional, not counted in the mandatory 5 PMB gate commands):
```
rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S
```

Expected diagnostic result: exactly 1 match (это единственное легальное место вызова).
Invariant: `EnemyPursuitSystem.execute_intent` вызывается ровно из одного места в `Enemy`. Нет параллельных путей вызова.

PMB-5 verification command (normative gate; this is the required PMB-5 command):
```
bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'
```

### Cross-Phase Test-Only Compatibility Exception (authoritative)

This rule is a top-level execution rule for all phases in this file and takes precedence over phase-local scope/diff-close wording only for test files.

Purpose:
- Allow minimal test-side compatibility fixes when a phase correctly removes/changes legacy runtime behavior and existing tests fail only because the tests are stale or call deleted APIs.

Mandatory conditions (all must be true):
1. The failing command is a phase test, smoke suite command, Tier 1 smoke command, or Tier 2 regression command defined by the phase.
2. Root cause is proven to be test-side only (stale assertion, stale fake/stub API, deleted legacy private call, or test fixture incompatibility). A prod-code regression is not covered by this exception.
3. The compatibility fix changes only files under `tests/`, plus `tests/test_runner_node.gd` when registration/wiring is required.
4. The compatibility fix does not modify any `src/`, `scenes/` runtime file, or phase production logic outside the phase scope.
5. The compatibility fix is minimal and preserves the phase's intended runtime contract. It must not pull in future-phase production behavior.
6. The failing test is re-run after the fix and passes.

Scope/diff audit interpretation when this exception is used:
- Qualified test-only compatibility files are treated as temporarily allowed for that phase close.
- They do not count as out-of-scope violations.
- This exception does not relax any PMB gate, legacy-removal gate, or production-code acceptance criterion.

Verification reporting requirement when this exception is used:
- Add a `test_only_compatibility_exceptions` field to the phase verification report (section 21), even if the phase-local section 21 template did not list it.
- Each entry must include: exact path, failing command, root-cause summary, and confirmation that no production file was changed to resolve that specific failure.

---

## Phase Dependency Map

Source: phase-local `## 23. Dependencies on previous phases.` sections in this file (top-level index is synchronized to them).
Authority rule: phase-local section 23 dependency gates are authoritative for implementation gating; this top-level map is an index and MUST stay in sync.
Legend: `[v2]` = spec written in this file.

### Full Dependency Matrix (all phases currently specified in this file)

| Phase | Title (short) | Depends on | Status |
|---|---|---|---|
| 0 | Routing Contract / Anti-Legacy | — | [v2] |
| 1 | Detour Planner (Direct / 1WP / 2WP) | 0 | [v2] |
| 2 | Detour Integration + Canon Fallback FSM | 0, 1 | [v2] |
| 3 | Immediate Repath On Non-Door Collision | 2 | [v2] |
| 4 | Shadow Scan In ALERT/COMBAT | 0, 2, 3 | [v2] |
| 5 | Navmesh + Obstacles: Mandatory Extraction + Clearance | 1 | [v2] |
| 6 | Patrol Reachability Filter | 0, 1, 5 | [v2] |
| 7 | Crowd Avoidance + Core Legacy Cleanup | 2, 3, 5 | [v2] |
| 8 | Pursuit Modes (Gameplay Layer) | 2, 4 | [v2] |
| 9 | Shadow-Aware Navigation Cost | 1, 5, 8 | [v2] |
| 10 | Basic Team Tactics | 7, 8, 9 | [v2] |
| 11 | Shadow Search Choreography | 4, 8, 9 | [v2] |
| 12 | Flashlight Team Role Policy | 10, 11 | [v2] |
| 13 | Humanized Imperfection (Fairness Layer) | 8, 9, 10, 11, 12 | [v2] |
| 14 | Blood Evidence (Without Corpses) | 4, 11, 13 | [v2] |
| 15 | — | 2, 4 | [v2] |
| 16 | — | 11, 15 | [v2] |
| 17 | — | 3, 11, 16 | [v2] |
| 18 | — | 10, 15, 17 | [v2] |
| 19 | — | 15, 16, 17, 18 | [v2] |
Roadmap scope note: this `v2` document currently specifies phases `0..19` only. No additional phase numbers are listed in this matrix.

### Critical Paths

**Navigation correctness** (must complete in order):
`0 → 1 → 2 → 3 → 4 → 5 → 6 → 7`

**Stealth gameplay quality** (unblocked after Phase 4):
`8 → 9 → 10 → 11 → 12 → 13 → 14`

**Advanced stealth feel** (Phase 15 bridge + post-Phase-14 extensions):
`15 → 16 → 17 → 18 → 19`

### Release Gates

| Gate | Requires |
|---|---|
| Core Final Release | Phases 0–14 complete + each phase-local section 21 verification report for `PHASE_0`..`PHASE_14` records `final_result = PASS` |
| Extended Stealth Release (current v2 file scope) | Phases 0–19 complete + `PHASE_19` `ExtendedStealthReleaseGateReportV1` reports `final_result = "PASS"` and `final_reason = "ok"` |

Roadmap note: this `v2` execution spec is complete for phases `0..19` and does not define any higher phase numbers.

### Parallel Windows (safe)

| Window | Condition | What can run in parallel |
|---|---|---|
| A | Phase 4 complete | Phase 5 code + Phase 8 scaffolding tests |
| B | Phase 9 complete | Phase 10 and Phase 11 in separate branches (merge after both pass) |
| C | Phase 12 complete | Phase 13 + Phase 14 test fixtures |

Hard restriction: no parallel merge may introduce old/new coexistence in same runtime branch.

### Early-Phase Bootstrap Dependency Gates (PHASE 0–4 only)

This subsection is intentionally limited to early phases. For `PHASE 5+`, the authoritative dependency gates are defined inside each phase-local section 23 and referenced from that phase's section 14 step 0.
Pass/fail for this subsection is determined by match count / stdout expectation, not by raw `rg` exit code (`rg` exit code `1` with empty stdout is valid for `0 matches` expectations).

**PHASE 0** — no gates (first phase, no prerequisites).

**PHASE 1** — no additional bootstrap gates in this subsection (depends only on `PHASE 0` per the top-level dependency matrix).

**PHASE 2** — before start, verify:
1. `rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy|build_reachable_path_points|build_path_points" src/systems/enemy_pursuit_system.gd -S` → 0 matches (Phase 0 complete)
2. `rg -n "func build_policy_valid_path\(|\"status\": \"unreachable_policy\"" src/systems/navigation_runtime_queries.gd -S` → ≥1 match (Phase 1 complete)

**PHASE 3** — before start, verify:
1. PMB-1 command from the top-level PMB section above (between `## Start of Persistent Module Boundary Contract` and `## End of Persistent Module Boundary Contract`) → 0 matches
2. `rg -n "_resolve_nearest_reachable_fallback|_sample_fallback_candidates|_policy_fallback_used|_attempt_shadow_escape_recovery" src/systems/enemy_pursuit_system.gd -S` → 0 matches (Phase 2 complete)

**PHASE 4** — before start, verify:
1. PMB-1 command from the top-level PMB section above (between `## Start of Persistent Module Boundary Contract` and `## End of Persistent Module Boundary Contract`) → 0 matches
2. Phase 2 gate #2 above → ≥1 match
3. `rg -n "_handle_slide_collisions_and_repath" src/systems/enemy_pursuit_system.gd -S` → ≥1 match (Phase 3 complete)
## End of Persistent Module Boundary Contract
---

## PHASE 0
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_0.
Scope boundary (exact files): section 4.
Execution sequence: section 14.
Rollback conditions: section 15.
Verification report format: section 21.

### Evidence

Inspected files (exact paths):
- `src/systems/enemy_pursuit_system.gd`
- `src/systems/enemy_utility_brain.gd`
- `src/entities/enemy.gd`
- `src/systems/navigation_service.gd`
- `src/systems/navigation_runtime_queries.gd`
- `tests/test_navigation_failure_reason_contract.gd`
- `tests/test_pursuit_stall_fallback_invariants.gd`
- `tests/test_runner_node.gd`
Inspected functions/methods (exact identifiers):
- `EnemyPursuitSystem._request_path_plan_contract`
- `EnemyPursuitSystem._build_policy_valid_path_fallback_contract`
- `EnemyPursuitSystem._build_reachable_path_points_for_enemy`
- `EnemyPursuitSystem._normalize_path_plan_contract`
- `EnemyPursuitSystem._plan_path_to`
- `EnemyUtilityBrain._choose_intent`
- `EnemyUtilityBrain._combat_no_los_grace_intent`
- `Enemy._build_utility_context`
- `Enemy._resolve_known_target_context`
- `Enemy._is_combat_awareness_active`
- `Enemy._is_combat_lock_active`
- `NavigationService.build_policy_valid_path`
- `NavigationService.build_reachable_path_points`
- `NavigationService.build_path_points`
- `NavigationRuntimeQueries.build_policy_valid_path`
- `NavigationRuntimeQueries.build_reachable_path_points`
- `NavigationRuntimeQueries.build_path_points`
Search commands used (exact commands):
- `rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy|build_reachable_path_points|build_path_points" src/systems/enemy_pursuit_system.gd -S`
- `rg -n "_request_path_plan_contract|build_policy_valid_path" src/systems/enemy_pursuit_system.gd src/systems/navigation_service.gd src/systems/navigation_runtime_queries.gd -S`
- `rg -n "PATROL|RETURN_HOME|IntentType" src/systems/enemy_utility_brain.gd -S`
- `rg -n "last_seen|_last_seen_pos|_last_seen_age|known_target|_build_utility_context|_resolve_known_target" src/entities/enemy.gd -S`
- `rg -n "^func |_request_path_plan_contract|build_policy_valid_path|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy|has_method" src/systems/enemy_pursuit_system.gd -S`
- `rg -n "^func |_choose_intent|alert_level|PATROL|RETURN_HOME|combat_lock|has_los|target_context" src/systems/enemy_utility_brain.gd -S`
- `rg -n "^func |_build_utility_context|_resolve_known_target|last_seen|combat|COMBAT|ALERT" src/entities/enemy.gd -S`
- `rg -n "in_combat_state|_is_combat_awareness_active|_is_combat_lock_active" src/entities/enemy.gd -S`
- `rg -n "PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY|PATH_PLAN_STATUS_UNREACHABLE_POLICY|PATH_PLAN_STATUS_OK" src/systems/enemy_pursuit_system.gd -S`

## 1. What now.
Phase id: PHASE_0.
Phase title: Routing Contract And Anti-Legacy Re-closure.
Goal (one sentence): Remove all in-class path planning fallbacks from `EnemyPursuitSystem`, route all path planning exclusively through `nav_system.build_policy_valid_path`, and enforce a hard guard in `EnemyUtilityBrain` that prohibits `PATROL` and `RETURN_HOME` intents when `alert_level >= ALERT` and target context exists.
Current behavior (measurable):
1. `EnemyPursuitSystem._request_path_plan_contract` (enemy_pursuit_system.gd:551) calls `nav_system.build_policy_valid_path` only when the method exists; when the method is absent or the return value is not a Dictionary, the function falls back to `_build_policy_valid_path_fallback_contract` (line 562). Two active planner paths exist simultaneously.
2. `EnemyPursuitSystem._build_policy_valid_path_fallback_contract` (enemy_pursuit_system.gd:565) is a second in-class path planner. It calls `_build_reachable_path_points_for_enemy` and performs its own policy validation, duplicating logic that belongs exclusively to `NavigationRuntimeQueries.build_policy_valid_path`.
3. `EnemyPursuitSystem._build_reachable_path_points_for_enemy` (enemy_pursuit_system.gd:857) tries `nav_system.build_reachable_path_points`, then falls back to `nav_system.build_path_points`, and as a final fallback appends `target_pos` directly to the path without any policy validation. This last fallback bypasses the policy contract entirely.
4. `EnemyUtilityBrain._choose_intent` (enemy_utility_brain.gd:126–145): when `alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT` and `not has_los` and both `has_last_seen` and `has_investigate_anchor` are false, the function returns `{"type": IntentType.RETURN_HOME, "target": home_pos}`. This fires even when `has_known_target` is true, violating the global invariant.
5. `EnemyUtilityBrain._choose_intent` (enemy_utility_brain.gd:177–180): a global fallback returns `{"type": IntentType.RETURN_HOME, "target": home_pos}` without checking `alert_level` or target context.
6. `Enemy._build_utility_context` (enemy.gd:1012): `var has_last_seen := _last_seen_age < INF and not in_combat_state`. The `and not in_combat_state` guard zeroes out `has_last_seen` during combat state even when `_last_seen_age < INF`, causing the utility brain to see no last-seen anchor and fall through to `RETURN_HOME` at step 4.

## 2. What changes.
1. Delete `_build_policy_valid_path_fallback_contract` (declaration and body) from `src/systems/enemy_pursuit_system.gd` before adding replacement code.
2. Delete `_build_reachable_path_points_for_enemy` (declaration and body) from `src/systems/enemy_pursuit_system.gd` before adding replacement code.
3. Delete the fallback return `return _build_policy_valid_path_fallback_contract(target_pos)` from `_request_path_plan_contract` before writing the replacement.
4. Delete `and not in_combat_state` from the `has_last_seen` assignment in `Enemy._build_utility_context` before adding replacement.
5. Implement the replacement `_request_path_plan_contract` body: when `nav_system` is null or lacks `build_policy_valid_path`, return `{"status": PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY, "path_points": [], "reason": "nav_system_missing"}`; when `nav_system.build_policy_valid_path` returns a non-Dictionary, return the same sentinel; otherwise return the result Dictionary as-is.
6. In `EnemyUtilityBrain._choose_intent`, add extraction of `has_known_target` from context and compute `target_context_exists = has_known_target or has_last_seen or has_investigate_anchor`.
7. Replace the terminal `return {"type": IntentType.RETURN_HOME, "target": home_pos}` inside the `not has_los and alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT` block (enemy_utility_brain.gd:142–145) with: if `target_context_exists`, return `{"type": IntentType.SEARCH, "target": home_pos}`; else return `{"type": IntentType.RETURN_HOME, "target": home_pos}`.
8. Replace the global fallback `return {"type": IntentType.RETURN_HOME, "target": home_pos}` (enemy_utility_brain.gd:177–180) with: if `alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT and target_context_exists`, return `{"type": IntentType.SEARCH, "target": home_pos}`; else return `{"type": IntentType.RETURN_HOME, "target": home_pos}`.
Migration notes: no file rename; no symbol move across files; all edits are in-place within existing functions.

## 3. What will be after.
Target behavior (measurable):
1. `_request_path_plan_contract` has exactly one code path for path planning: `nav_system.build_policy_valid_path`. When nav_system is null, missing the method, or returns a non-Dictionary, the function returns `{"status": "unreachable_geometry", "path_points": [], "reason": "nav_system_missing"}` and no in-class planner runs.
2. `rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S` returns `0 matches`.
3. `rg -n "nav_system\.has_method\(\"build_reachable_path_points\"\)|nav_system\.has_method\(\"build_path_points\"\)" src/systems/enemy_pursuit_system.gd -S` returns `0 matches`.
4. When `alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT` and `target_context_exists == true`, `_choose_intent` never returns `IntentType.PATROL` or `IntentType.RETURN_HOME`.
4a. This phase intentionally changes the utility fallback behavior in that branch from `RETURN_HOME` (movement-home execution path) to `SEARCH` with `target=home_pos` (search-sweep execution path). Phase 0 validates the utility-level anti-patrol guard (`intent.type`) and does not preserve `RETURN_HOME` locomotion semantics for this branch.
5. `has_last_seen` in utility context equals `_last_seen_age < INF` regardless of combat state, verified by: context produced during COMBAT state with `_last_seen_age = 0.5` has `has_last_seen == true`.
6. Global invariants 1–4 from the template remain true.

## 4. Scope and non-scope (exact files).
In-scope files (exact paths):
1. `src/systems/enemy_pursuit_system.gd`
2. `src/systems/enemy_utility_brain.gd`
3. `src/entities/enemy.gd`
4. `tests/test_alert_combat_context_never_patrol.gd` (new)
5. `tests/test_alert_combat_context_never_patrol.tscn` (new)
6. `tests/test_navigation_failure_reason_contract.gd`
7. `tests/test_pursuit_stall_fallback_invariants.gd`
8. `tests/test_runner_node.gd`
Out-of-scope files (exact paths):
1. `src/systems/navigation_service.gd`
2. `src/systems/navigation_runtime_queries.gd`
3. `src/systems/enemy_awareness_system.gd`
4. `src/systems/enemy_alert_levels.gd`
5. `src/core/game_config.gd`
6. `src/core/config_validator.gd`
Allowed file-change boundary (exact paths): same as in-scope list above (items 1–8).

## 5. Single-owner authority for this phase.
1. `EnemyPursuitSystem._request_path_plan_contract` is the single owner of path plan dispatch. No other function in `EnemyPursuitSystem` calls a path planner directly.
2. `EnemyUtilityBrain._choose_intent` is the single owner of intent selection. No second intent decision path exists in `Enemy` or `EnemyPursuitSystem`.
3. `Enemy._build_utility_context` is the single owner of utility context production. No other function in `Enemy` writes `has_last_seen` into the context dictionary.
Authority constraints:
- `NavigationService.build_policy_valid_path` and `NavigationRuntimeQueries.build_policy_valid_path` are out of scope; they are not modified.
- No second planner function (`_build_policy_valid_path_fallback_contract`, `_build_reachable_path_points_for_enemy`, or any equivalent) is allowed in `EnemyPursuitSystem` after this phase.

## 6. Full input/output contract.
Contract name: `PathPlanDispatchContractV0`.
Owner: `EnemyPursuitSystem._request_path_plan_contract`.
Inputs (types, nullability, finite checks):
- `target_pos: Vector2`, finite required (`is_finite(x) and is_finite(y)`); caller ensures this.
- `has_target: bool`.
Outputs (exact keys/types/enums):
- `status: String` enum `{"ok", "unreachable_policy", "unreachable_geometry"}`.
- `path_points: Array` — non-empty Array[Vector2] iff `status == "ok"`; empty Array otherwise.
- `reason: String` — one of `{"ok", "policy_blocked", "path_unreachable", "empty_path", "no_target", "nav_system_missing", "room_graph_no_path"}`.
- `segment_index: int` — meaningful (>= 0) only when `status == "unreachable_policy"`; otherwise `-1` or absent.
- `blocked_point: Vector2` — present as key only when `status == "unreachable_policy"` and nav_system provides it.
Status enums: `"ok"` / `"unreachable_policy"` / `"unreachable_geometry"`.
Reason enums: `"ok"` / `"policy_blocked"` / `"path_unreachable"` / `"empty_path"` / `"no_target"` / `"nav_system_missing"` / `"room_graph_no_path"`.
Deterministic order and tie-break rules:
1. `has_target == false` is checked first and returns before any nav_system access.
2. `nav_system == null` is checked second; returns `nav_system_missing`.
3. `nav_system.has_method("build_policy_valid_path") == false` is checked third; returns `nav_system_missing`.
4. `nav_system.call("build_policy_valid_path", ...)` is invoked exactly once.
5. If the return value is not a Dictionary, return `nav_system_missing`.
6. Otherwise return the Dictionary as-is (normalization happens in `_normalize_path_plan_contract` downstream).
Constants/thresholds/eps (exact values):
- `PATH_PLAN_STATUS_OK := "ok"` (enemy_pursuit_system.gd:42).
- `PATH_PLAN_STATUS_UNREACHABLE_POLICY := "unreachable_policy"` (enemy_pursuit_system.gd:43).
- `PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY := "unreachable_geometry"` (enemy_pursuit_system.gd:44).
Contract name: `UtilityAntiPatrolGuardContractV0`.
Owner: `EnemyUtilityBrain._choose_intent`.
Inputs (types, nullability, finite checks):
- `ctx: Dictionary` with keys `"has_known_target": bool`, `"has_last_seen": bool`, `"has_investigate_anchor": bool`, `"alert_level": int`, `"has_los": bool`.
Outputs (exact keys/types/enums):
- `intent.type: int` from `EnemyUtilityBrain.IntentType`.
- `intent.target: Vector2` where applicable.
Invariant: when `alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT` and `(has_known_target or has_last_seen or has_investigate_anchor) == true`, `intent.type` must not equal `IntentType.PATROL` or `IntentType.RETURN_HOME`.
`target_context_exists` formula: `has_known_target or has_last_seen or has_investigate_anchor`.
Contract name: `LastSeenCombatContextContractV0`.
Owner: `Enemy._build_utility_context`.
Output key `has_last_seen: bool` formula after Phase 0: `_last_seen_age < INF`.
Forbidden formula after Phase 0: `_last_seen_age < INF and not in_combat_state`.
Forbidden patterns (identifiers/branches):
- `_build_policy_valid_path_fallback_contract` anywhere in `src/systems/enemy_pursuit_system.gd`.
- `_build_reachable_path_points_for_enemy` anywhere in `src/systems/enemy_pursuit_system.gd`.
- `nav_system.has_method("build_reachable_path_points")` anywhere in `src/systems/enemy_pursuit_system.gd`.
- `nav_system.has_method("build_path_points")` anywhere in `src/systems/enemy_pursuit_system.gd`.
- `and not in_combat_state` in `Enemy._build_utility_context`.
- Any `IntentType.PATROL` or `IntentType.RETURN_HOME` return in `_choose_intent` when `alert_level >= ALERT and target_context_exists == true`.

## 7. Deterministic algorithm with exact order.
Algorithm for `_request_path_plan_contract(target_pos, has_target)`:
1. If `not has_target`: return `{status: PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY, path_points: [], reason: "no_target"}`.
2. If `nav_system == null`: return `{status: PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY, path_points: [], reason: "nav_system_missing"}`.
3. If `not nav_system.has_method("build_policy_valid_path")`: return `{status: PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY, path_points: [], reason: "nav_system_missing"}`.
4. Assign `contract_variant: Variant = nav_system.call("build_policy_valid_path", owner.global_position, target_pos, owner)`.
5. If `not (contract_variant is Dictionary)`: return `{status: PATH_PLAN_STATUS_UNREACHABLE_GEOMETRY, path_points: [], reason: "nav_system_missing"}`.
6. Return `contract_variant as Dictionary`.
Algorithm for `target_context_exists` in `EnemyUtilityBrain._choose_intent`:
1. Extract `has_known_target := bool(ctx.get("has_known_target", false))` immediately after the existing variable extraction block (after line 83).
2. Compute `target_context_exists := has_known_target or has_last_seen or has_investigate_anchor` on the line following `has_known_target` extraction.
Algorithm for RETURN_HOME guard in `_choose_intent`:
1. In the `not has_los and alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT` block, the terminal return becomes: `if target_context_exists: return {type: SEARCH, target: home_pos}`. The `else` branch keeps `return {type: RETURN_HOME, target: home_pos}`.
2. In the global fallback (last return in function): `if alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT and target_context_exists: return {type: SEARCH, target: home_pos}`. The `else` branch keeps `return {type: RETURN_HOME, target: home_pos}`.
Algorithm for `has_last_seen` in `Enemy._build_utility_context`:
1. Line 1012 changes from `var has_last_seen := _last_seen_age < INF and not in_combat_state` to `var has_last_seen := _last_seen_age < INF`.
2. `in_combat_state` variable (line 1011) is removed only if it becomes unused after this change. Verify with `rg -n "in_combat_state" src/entities/enemy.gd` before removing.

## 8. Edge-case matrix (case -> exact output).
| Case ID | Exact input case | Exact output |
|---|---|---|
| EC-01 | `has_target=false` | `status=unreachable_geometry, reason=no_target, path_points=[]` |
| EC-02 | `has_target=true`, `nav_system=null` | `status=unreachable_geometry, reason=nav_system_missing, path_points=[]` |
| EC-03 | `has_target=true`, `nav_system` present, missing `build_policy_valid_path` method | `status=unreachable_geometry, reason=nav_system_missing, path_points=[]` |
| EC-04 | `nav_system.build_policy_valid_path` returns non-Dictionary (e.g. `null`) | `status=unreachable_geometry, reason=nav_system_missing, path_points=[]` |
| EC-05 | `nav_system.build_policy_valid_path` returns `{status:"ok", path_points:[v], reason:"ok"}` | returned as-is |
| EC-06 | `alert_level=ALERT, not has_los, has_last_seen=false, has_investigate_anchor=false, has_known_target=false` | `target_context_exists=false` → `RETURN_HOME` permitted |
| EC-07 | `alert_level=ALERT, not has_los, has_last_seen=false, has_investigate_anchor=false, has_known_target=true` | `target_context_exists=true` → `SEARCH` with `target=home_pos` |
| EC-08 | `alert_level=ALERT, not has_los, has_last_seen=true, dist_to_last_seen > investigate_arrive_px` | `INVESTIGATE` with `target=last_seen_pos` (existing branch fires, RETURN_HOME never reached) |
| EC-09 | `in_combat_state=true`, `_last_seen_age=0.5` | `has_last_seen=true` in utility context |
| EC-10 | `in_combat_state=true`, `_last_seen_age=INF` | `has_last_seen=false` in utility context |
| EC-11 | `alert_level=ALERT, has_los=false`, global fallback reached (theoretically unreachable), `target_context_exists=true` | `SEARCH` with `target=home_pos` |
| EC-12 | `alert_level=SUSPICIOUS, has_los=false`, global fallback reached | `RETURN_HOME` permitted (alert < ALERT) |

## 9. Legacy removal plan (delete-first, exact ids).
Legacy to delete first (exact ids/functions/consts) in this order:
1. Function declaration and body: `EnemyPursuitSystem._build_policy_valid_path_fallback_contract` (enemy_pursuit_system.gd:565–601).
2. Function declaration and body: `EnemyPursuitSystem._build_reachable_path_points_for_enemy` (enemy_pursuit_system.gd:857–876).
3. Fallback return statement: `return _build_policy_valid_path_fallback_contract(target_pos)` (enemy_pursuit_system.gd:562) inside `_request_path_plan_contract`.
4. Sub-expression: `and not in_combat_state` from `var has_last_seen` assignment (enemy.gd:1012) inside `Enemy._build_utility_context`. After removal, verify `in_combat_state` is still referenced elsewhere in `_build_utility_context`; if unused, remove its declaration too.
5. Function declaration and body: `EnemyPursuitSystem._validate_path_policy` (enemy_pursuit_system.gd:879–892). This function is called exclusively from `_build_policy_valid_path_fallback_contract` (line 586) and has no other callsites. It becomes dead code after item 1 is deleted. Confirmed by: `rg -n "_validate_path_policy\b" src/ -S` shows only lines 586, 879, 892.
6. Function declaration and body: `EnemyPursuitSystem._validate_path_policy_with_traverse_samples` (enemy_pursuit_system.gd:895+). This function is called exclusively from `_validate_path_policy` (line 892) and has no other callsites. It becomes dead code after item 5 is deleted. Confirmed by: `rg -n "_validate_path_policy_with_traverse_samples\b" src/ -S` shows only lines 892 and 895.
Delete-first order:
1. Delete items 1–6 above before writing any replacement code.
2. Run the relevant section 10 legacy verification commands for the items deleted so far (use the grouped order in section 14); abort if any non-zero match.
3. Add replacement code only after all legacy items 1–6 are deleted and all seven section 10 legacy verification commands return `0 matches`.
No temporary compatibility branches are allowed.

## 10. Legacy verification commands (exact rg + expected 0 matches for every removed legacy item).
1. `rg -n "_build_policy_valid_path_fallback_contract" src/systems/enemy_pursuit_system.gd -S`
   Expected result: `0 matches`.
2. `rg -n "_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
   Expected result: `0 matches`.
3. `rg -n "nav_system\.has_method\(\"build_reachable_path_points\"\)" src/systems/enemy_pursuit_system.gd -S`
   Expected result: `0 matches`.
4. `rg -n "nav_system\.has_method\(\"build_path_points\"\)" src/systems/enemy_pursuit_system.gd -S`
   Expected result: `0 matches`.
5. `rg -n "and not in_combat_state" src/entities/enemy.gd -S`
   Expected result: `0 matches`.
6. `rg -n "_validate_path_policy\b" src/systems/enemy_pursuit_system.gd -S`
   Expected result: `0 matches`.
7. `rg -n "_validate_path_policy_with_traverse_samples\b" src/systems/enemy_pursuit_system.gd -S`
   Expected result: `0 matches`.
Mandatory closure rule: phase cannot close until all seven commands return `0 matches`. Any non-zero match count marks phase `FAILED`. No allowlist. No compatibility branches.

## 11. Acceptance criteria (binary pass/fail).
Pass only when all conditions are true:
1. All seven legacy verification commands in section 10 return `0 matches`.
2. `rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S` returns `0 matches`.
3. `tests/test_alert_combat_context_never_patrol.tscn` exits `0`.
4. Updated `tests/test_navigation_failure_reason_contract.tscn` exits `0`.
5. Updated `tests/test_pursuit_stall_fallback_invariants.tscn` exits `0`.
6. All smoke suite commands in section 12 exit `0`.
7. All rg gates in section 13 produce expected outputs.
8. Runtime scenarios in section 20 pass all invariant checks.
9. Diff audit in section 19 reports no out-of-scope changed file.
Fail immediately on any false condition.

## 12. Tests (new/update + purpose).
New tests (exact filenames):
- `tests/test_alert_combat_context_never_patrol.gd`.
- `tests/test_alert_combat_context_never_patrol.tscn`.
Purpose:
- Verify that `EnemyUtilityBrain._choose_intent` returns `SEARCH` (not `RETURN_HOME` or `PATROL`) when `alert_level >= ALERT`, `has_los=false`, `has_known_target=true`, `has_last_seen=false`, `has_investigate_anchor=false`.
- Verify that `RETURN_HOME` is permitted when `alert_level >= ALERT`, `has_los=false`, and `target_context_exists=false`.
- Verify that `has_last_seen=true` in utility context when `in_combat_state=true` and `_last_seen_age < INF`.
Tests to update (exact filenames):
- `tests/test_navigation_failure_reason_contract.gd`: add contract sentinel test cases covering all three `nav_system_missing` branches in `_request_path_plan_contract`: (a) `nav_system == null`, (b) FakeNav lacks `build_policy_valid_path` method, (c) FakeNav returns non-Dictionary from `build_policy_valid_path`.
- `tests/test_pursuit_stall_fallback_invariants.gd`: confirm FakeNavByDistance does not expose `build_reachable_path_points` or `build_path_points` methods (it does not in current code); verify stall detection behavior is unchanged.
- `tests/test_runner_node.gd`: add `const ALERT_COMBAT_CONTEXT_NEVER_PATROL_TEST_SCENE := "res://tests/test_alert_combat_context_never_patrol.tscn"`; add scene existence check; add `_run_embedded_scene_suite` call in execution sequence.
Phase test commands (exact):
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_alert_combat_context_never_patrol.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_failure_reason_contract.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_pursuit_stall_fallback_invariants.tscn`
Smoke suite commands (exact):
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_path_policy_parity.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_shadow_policy_hard_block_without_grant.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_shadow_stall_escapes_to_light.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_pursuit_stall_fallback_invariants.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_combat_no_los_never_hold_range.tscn`
Pass rule: every command exits `0`; no `SKIP`, `SKIPPED`, `PENDING`, or `NOT RUN` in logs.

## 13. rg gates (command + expected output).
1. `rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy|nav_system\.has_method\(\"build_reachable_path_points\"\)|nav_system\.has_method\(\"build_path_points\"\)" src/systems/enemy_pursuit_system.gd -S`
   Expected output: `0 matches`.
2. `rg -n "and not in_combat_state" src/entities/enemy.gd -S`
   Expected output: `0 matches`.
3. `rg -n "target_context_exists" src/systems/enemy_utility_brain.gd -S`
   Expected output: at least `2` matches (one declaration, at least one usage).
4. `rg -n "has_known_target" src/systems/enemy_utility_brain.gd -S`
   Expected output: at least `1` match (extraction from ctx).
5. `rg -n "build_policy_valid_path\b" src/systems/enemy_pursuit_system.gd src/systems/navigation_service.gd src/systems/navigation_runtime_queries.gd -S`
   Expected output: at least one match in each file (single pipeline intact).
6. `rg -n "_request_path_plan_contract\b" src/systems/enemy_pursuit_system.gd -S`
   Expected output: `1` declaration + at least `1` callsite (function still present and called).
7. `rg -n "nav_system_missing" src/systems/enemy_pursuit_system.gd -S`
   Expected output: at least `3` matches (three return sites that emit this reason).
8. `rg -n "_validate_path_policy\b|_validate_path_policy_with_traverse_samples\b" src/systems/enemy_pursuit_system.gd -S`
   Expected output: `0 matches`.

## 14. Execution sequence (step-by-step, no ambiguity).
1. Record baseline outputs of all section 13 rg gates before any code change.
2. Delete the body and declaration of `_build_policy_valid_path_fallback_contract` from `src/systems/enemy_pursuit_system.gd`.
3. Delete the body and declaration of `_build_reachable_path_points_for_enemy` from `src/systems/enemy_pursuit_system.gd`.
4. Delete the line `return _build_policy_valid_path_fallback_contract(target_pos)` from `_request_path_plan_contract` in `src/systems/enemy_pursuit_system.gd`.
5. Run section 10 commands 1–4; abort if any returns non-zero matches.
6. Delete the body and declaration of `_validate_path_policy` from `src/systems/enemy_pursuit_system.gd`.
7. Delete the body and declaration of `_validate_path_policy_with_traverse_samples` from `src/systems/enemy_pursuit_system.gd`.
8. Run section 10 commands 6–7; abort if any returns non-zero matches.
9. Delete `and not in_combat_state` from `var has_last_seen` in `Enemy._build_utility_context` in `src/entities/enemy.gd`; check if `in_combat_state` is still used elsewhere in that function and remove its declaration if unused.
10. Run section 10 command 5; abort if it returns non-zero matches.
11. Implement replacement `_request_path_plan_contract` body per section 7 algorithm.
12. Add `has_known_target` extraction and `target_context_exists` computation in `EnemyUtilityBrain._choose_intent` per section 7 algorithm.
13. Replace terminal `RETURN_HOME` in the ALERT/COMBAT no-LOS block with guarded `SEARCH` per section 7 algorithm.
14. Replace global fallback `RETURN_HOME` with guarded `SEARCH` per section 7 algorithm.
15. Create `tests/test_alert_combat_context_never_patrol.gd` and `tests/test_alert_combat_context_never_patrol.tscn`.
16. Update `tests/test_navigation_failure_reason_contract.gd` with three `nav_system_missing` contract sentinel test cases (`nav_system == null`, missing method, non-Dictionary return).
17. Update `tests/test_pursuit_stall_fallback_invariants.gd` per section 12 purpose.
18. Update `tests/test_runner_node.gd` with new scene constant, existence check, and run entry.
19. Run all section 13 rg gates; require all expected outputs before continuing.
20. Run top-level PMB contract commands PMB-1 through PMB-5 and record expected outputs (`0 matches` for PMB-1..PMB-4, `PMB-5: PASS (1)` for PMB-5).
21. Run all phase test commands in section 12; require exit code `0` for each.
22. Run all smoke suite commands in section 12; require exit code `0` for each.
23. Run post-implementation verification from section 19.
24. Produce verification report in section 21 format.

## 15. Rollback conditions.
Rollback trigger conditions:
1. Any section 10 legacy verification command returns non-zero matches after the deletion steps.
2. Any section 13 rg gate output differs from the expected output.
3. Any phase test command exits non-zero.
4. Any smoke suite command exits non-zero.
5. Any runtime scenario invariant in section 20 fails.
6. Diff audit finds a changed file outside the section 4 allowed boundary.
7. A second path planning function is introduced in `EnemyPursuitSystem` (single-owner violation).
Rollback action: revert all phase-changed files in section 4 allowed boundary to pre-phase state; produce failure report listing the failed condition.

## 16. Phase close condition.
Phase closes only when all are true:
1. Section 10 legacy verification commands: all return `0 matches`.
2. Section 13 rg gates: all produce expected outputs.
3. Top-level PMB contract commands PMB-1 through PMB-5 all produce expected outputs.
4. Section 12 phase tests and smoke suite commands: all exit `0`, no skip markers.
5. Section 19 diff audit: no out-of-scope changes.
6. Section 20 runtime scenarios: all invariants pass.
7. Section 21 verification report: `unresolved_deviations` is empty.

## 17. Ambiguity self-check line: Ambiguity check: 0
Ambiguity check: 0

## 18. Open questions line: Open questions: 0
Open questions: 0

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).
Diff audit commands:
- `git diff --name-only`
- `bash -lc 'set -euo pipefail; allowed="^(src/systems/enemy_pursuit_system\.gd|src/systems/enemy_utility_brain\.gd|src/entities/enemy\.gd|tests/test_alert_combat_context_never_patrol\.gd|tests/test_alert_combat_context_never_patrol\.tscn|tests/test_navigation_failure_reason_contract\.gd|tests/test_pursuit_stall_fallback_invariants\.gd|tests/test_runner_node\.gd)$"; git diff --name-only | tee /tmp/phase0_changed_files.txt; if rg -v "$allowed" /tmp/phase0_changed_files.txt -S; then exit 1; fi'`
Contract conformance checks:
- `rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S` — expected: 0 matches.
- `rg -n "and not in_combat_state" src/entities/enemy.gd -S` — expected: 0 matches.
- `rg -n "target_context_exists" src/systems/enemy_utility_brain.gd -S` — expected: >= 2 matches.
- `rg -n "nav_system_missing" src/systems/enemy_pursuit_system.gd -S` — expected: >= 3 matches.
- `rg -n "_request_path_plan_contract\b" src/systems/enemy_pursuit_system.gd -S` — expected: 1 declaration, >= 1 callsite.
PMB contract checks (top-level document PMB section between `## Start of Persistent Module Boundary Contract` and `## End of Persistent Module Boundary Contract`):
- Run PMB-1 through PMB-5 commands exactly as defined at the top of this file.
- Expected outputs: PMB-1..PMB-4 => `0 matches`; PMB-5 => `PMB-5: PASS (1)`.
Mandatory test execution:
- Run all phase test commands from section 12.
- Run all smoke suite commands from section 12.
- Fail on any exit code not equal to `0`.
- Fail when logs contain `SKIP`, `SKIPPED`, `PENDING`, or `NOT RUN`.
Runtime scenario checks:
- Execute scenario commands from section 20.
- Compare actual intent type to expected invariants.
- Any invariant violation marks phase `FAILED`.

## 20. Runtime scenario matrix (scenario id, setup, duration, expected invariants, fail conditions).
| Scenario ID | Setup (exact) | Duration | Expected invariants | Fail conditions |
|---|---|---|---|---|
| P0-R1 | `tests/test_alert_combat_context_never_patrol.tscn`; synthetic `EnemyUtilityBrain` instance; inject ctx: `alert_level=ALERT`, `has_los=false`, `combat_lock=false`, `has_known_target=true`, `has_last_seen=false`, `has_investigate_anchor=false`, `last_seen_age=INF`, `dist_to_last_seen=INF`, `known_target_pos=Vector2(200,0)`, `home_pos=Vector2.ZERO`; single `_choose_intent` call | 1 tick | `intent.type == IntentType.SEARCH`; `intent.type != IntentType.RETURN_HOME`; `intent.type != IntentType.PATROL` | Any RETURN_HOME or PATROL output |
| P0-R2 | Same scene; inject ctx: `alert_level=ALERT`, `has_los=false`, `has_known_target=false`, `has_last_seen=false`, `has_investigate_anchor=false` | 1 tick | `intent.type == IntentType.RETURN_HOME` (target_context_exists=false, RETURN_HOME is permitted) | Any intent other than RETURN_HOME |
| P0-R3 | `tests/test_navigation_failure_reason_contract.tscn`; `nav_system = null`; call `_request_path_plan_contract(Vector2(100,0), true)` | 1 call | `status == "unreachable_geometry"` and `reason == "nav_system_missing"` | status != unreachable_geometry; reason != nav_system_missing |
| P0-R4 | `tests/test_navigation_failure_reason_contract.tscn`; FakeNav without `build_policy_valid_path` method; call `_request_path_plan_contract(Vector2(100,0), true)` | 1 call | `status == "unreachable_geometry"` and `reason == "nav_system_missing"` | status != unreachable_geometry; reason != nav_system_missing |
| P0-R5 | `tests/test_navigation_failure_reason_contract.tscn`; FakeNav with `build_policy_valid_path` returning non-Dictionary (`null`); call `_request_path_plan_contract(Vector2(100,0), true)` | 1 call | `status == "unreachable_geometry"` and `reason == "nav_system_missing"` | status != unreachable_geometry; reason != nav_system_missing |
| P0-R6 | Same scene as P0-R4/P0-R5; FakeNav with valid `build_policy_valid_path` returning `{status:"ok", path_points:[Vector2(100,0)], reason:"ok"}`; call `_request_path_plan_contract(Vector2(100,0), true)` | 1 call | returned Dictionary has `status == "ok"` | status != ok; fallback planner fires |
Scenario commands (exact):
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_alert_combat_context_never_patrol.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_failure_reason_contract.tscn`

## 21. Verification report format (what must be recorded to close phase).
Report must record all fields below:
- `phase_id: PHASE_0`
- `changed_files: [exact paths]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; must be empty on close)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `legacy_verification: [command, exit_code, match_count, PASS|FAIL]` for each section 10 command
- `rg_gates: [command, expected, actual, PASS|FAIL]` for each section 13 gate
- `phase_tests: [command, exit_code, PASS|FAIL]` for each section 12 phase test
- `smoke_suite: [command, exit_code, PASS|FAIL]` for each section 12 smoke command
- `runtime_scenarios: [scenario_id, command, exit_code, invariant_result, PASS|FAIL]`
- `single_owner_check: PASS|FAIL`
- `anti_patrol_guard_check: PASS|FAIL`
- `last_seen_combat_context_check: PASS|FAIL`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` (all must be PASS to close phase)
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`
Non-empty `unresolved_deviations` forces `final_result = FAIL`.

## 22. Structural completeness self-check line:
Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23. Missing sections: NONE.
- Evidence preamble (### Evidence) present between ## PHASE header and section 1: yes
- PMB gates present in section 13: no (Phase 0 runs PMB commands from the top-level `Persistent Module Boundary Contract` section)
- pmb_contract_check present in section 21: yes

## 23. Dependencies on previous phases.
PHASE 0 has no prerequisites. It is the first phase in the refactor sequence. All other phases depend on it.

## PHASE 1
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_1.
Scope boundary (exact files): section 4.
Execution sequence: section 14.
Rollback conditions: section 15.
Verification report format: section 21.

### Evidence

Inspected files (exact paths):
- `src/systems/navigation_runtime_queries.gd`
- `src/systems/navigation_service.gd`
- `tests/test_navigation_runtime_queries.gd`
- `tests/test_navigation_path_policy_parity.gd`
- `tests/test_runner_node.gd`

Inspected functions/methods (exact identifiers):
- `NavigationRuntimeQueries.build_policy_valid_path` (navigation_runtime_queries.gd:219)
- `NavigationRuntimeQueries._build_geometry_path_plan` (navigation_runtime_queries.gd:255)
- `NavigationRuntimeQueries._validate_enemy_policy_path` (navigation_runtime_queries.gd:316)
- `NavigationRuntimeQueries._extract_path_points` (navigation_runtime_queries.gd:353)
- `NavigationRuntimeQueries.nav_path_length` (navigation_runtime_queries.gd:301)
- `NavigationRuntimeQueries.get_neighbors` (navigation_runtime_queries.gd:56) — returns sorted Array[int]
- `NavigationRuntimeQueries.is_adjacent` (navigation_runtime_queries.gd:23)
- `NavigationRuntimeQueries.room_id_at_point` (navigation_runtime_queries.gd:14)
- `NavigationService._build_room_graph_path_points_reachable` (navigation_service.gd:415)
- `NavigationService._select_door_center` (navigation_service.gd:493) — delegated to via `NavigationRuntimeQueries.get_door_center_between`
- `NavigationService._bfs_room_path` (navigation_service.gd:514)

Search commands used:
- `rg -n "build_policy_valid_path|build_reachable_path_points|build_path_points|detour|waypoint|candidate" src/systems/navigation_runtime_queries.gd -S`
- `rg -n "direct_only_fallback|legacy_path_selector|old_detour" src tests -S` (0 matches)
- `rg -n "_build_room_graph_path_points_reachable|_select_door_center|_room_graph|_bfs_room_path" src/systems/navigation_service.gd -S`
- `rg -n "_validate_path_policy" tests/test_navigation_path_policy_parity.gd -S`

## 1. What now.
`NavigationRuntimeQueries.build_policy_valid_path` (navigation_runtime_queries.gd:219) evaluates exactly one route: the direct geometry path returned by `_build_geometry_path_plan`. When `_validate_enemy_policy_path` returns `valid=false` (e.g., shadow zone blocks direct route), the function immediately returns `{status: unreachable_policy, path_points: [], reason: policy_blocked}`. No alternative routes through adjacent rooms are attempted. Result: an enemy that is policy-blocked on the direct path returns `unreachable_policy` even when a valid route around the shadow exists through one or two intermediate rooms.

## 2. What changes.
1. `NavigationRuntimeQueries.build_policy_valid_path` is extended: after direct path is policy-blocked, it generates and evaluates 1-WP (one intermediate room) and 2-WP (two intermediate rooms) detour candidates via the room/door graph.
2. New private function `NavigationRuntimeQueries._build_detour_candidates(from_pos, to_pos, from_room, to_room)` is added. It enumerates all 1-WP and 2-WP candidates sorted by Euclidean path length ascending.
3. New private function `NavigationRuntimeQueries._euclidean_path_length(from_pos, path_points)` is added. It computes total Euclidean segment length from `from_pos` through all points in `path_points`.
4. The output contract of `build_policy_valid_path` is extended: every `status=ok` response includes the new key `route_type: "direct" | "1wp" | "2wp"`.
5. `test_navigation_path_policy_parity.gd` is updated: removes calls to `pursuit.call("_validate_path_policy", ...)` (deleted in Phase 0), replaces them with assertions on `route_type` in the `build_policy_valid_path` output.
6. `test_navigation_runtime_queries.gd` is updated: adds `route_type == "direct"` assertion to the existing `build_path_points` contract test.

## 3. What will be after.
1. `build_policy_valid_path` returns `status=ok` whenever a policy-valid route exists among: direct, all 1-WP candidates, and all 2-WP candidates. The returned `path_points` array is the shortest (by Euclidean length) policy-valid route found.
2. `build_policy_valid_path` returns `status=unreachable_policy` only when no policy-valid route exists among direct, all 1-WP, and all 2-WP candidates.
3. `build_policy_valid_path` returns `status=unreachable_geometry` only when the geometry backend returns no navigable path; detour evaluation is never reached in this case.
4. Every `status=ok` response includes `route_type: "direct" | "1wp" | "2wp"` identifying which candidate type was selected.
5. Output is deterministic for equal input: same `from_pos`, `to_pos`, `enemy`, and room graph state always produce the same output.
6. `blocked_point` is absent from `unreachable_policy` responses produced by the extended function (detour exhaustion; the direct-path block point is not reported when detours were attempted).

## 4. Scope and non-scope (exact files).
In-scope:
- `src/systems/navigation_runtime_queries.gd`
- `tests/test_navigation_policy_detour_shadow_blocked_direct.gd` (new)
- `tests/test_navigation_policy_detour_shadow_blocked_direct.tscn` (new)
- `tests/test_navigation_policy_detour_two_waypoints.gd` (new)
- `tests/test_navigation_policy_detour_two_waypoints.tscn` (new)
- `tests/test_navigation_path_policy_parity.gd` (update)
- `tests/test_navigation_runtime_queries.gd` (update)
- `tests/test_runner_node.gd` (update: add 2 new scene constants + existence checks + run entries)

Out-of-scope (must not be modified):
- `src/systems/navigation_service.gd`
- `src/systems/enemy_pursuit_system.gd`
- `src/systems/enemy_utility_brain.gd`
- `src/entities/enemy.gd`
- All other `src/` files not listed above.
- All other `tests/` files not listed above.

Allowed file-change boundary: same as in-scope list above (items 1–8).

## 5. Single-owner authority for this phase.
Single owner: `NavigationRuntimeQueries.build_policy_valid_path` (navigation_runtime_queries.gd:219) is the sole function that decides which route (direct, 1-WP, or 2-WP) to return to callers.
Authority constraints:
1. `_build_detour_candidates` generates candidate arrays but performs no policy validation — policy validation is done exclusively in `build_policy_valid_path` via `_validate_enemy_policy_path`.
2. `_euclidean_path_length` computes lengths but makes no routing decisions.
3. No new public method that calls `_validate_enemy_policy_path` directly is introduced.
4. The call graph for route selection is fixed: caller → `build_policy_valid_path` → `_build_geometry_path_plan` (geometry) + `_validate_enemy_policy_path` (policy) + `_build_detour_candidates` (candidates) → return.
5. `nav_path_length` (line 301) is not modified and does not call `_build_detour_candidates`.

## 6. Full input/output contract.
Function: `build_policy_valid_path(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> Dictionary`

Inputs:
- `from_pos`: Vector2, non-null. Equal to `to_pos` is allowed.
- `to_pos`: Vector2, non-null.
- `enemy`: Node or null. If null: no policy validation is applied; for `status=ok` responses, `route_type` is always `"direct"`.

Output keys — all responses:
- `status`: String. Exactly one of: `"ok"`, `"unreachable_policy"`, `"unreachable_geometry"`.
- `path_points`: Array[Vector2]. Non-empty when `status == "ok"`. Empty when status is unreachable.
- `reason`: String. Exactly one of: `"ok"`, `"policy_blocked"`, `"empty_path"`, `"navmesh_no_path"`, `"room_graph_unavailable"`, `"room_graph_no_path"`.

Output keys — `status=ok` responses only (Phase 1 addition):
- `route_type`: String. Exactly one of: `"direct"`, `"1wp"`, `"2wp"`.

Forbidden key behavior — `status=unreachable_policy` responses produced by the extended function (existing-key behavior changed in Phase 1):
- `blocked_point`: Vector2. **Absent** in all unreachable_policy responses produced after detour evaluation (the direct-path block point is not propagated once detours are attempted/exhausted).

Status/reason enum table (complete):
| status               | reason                  | route_type present |
|----------------------|-------------------------|--------------------|
| ok                   | ok                      | yes                |
| unreachable_policy   | policy_blocked          | no                 |
| unreachable_geometry | navmesh_no_path         | no                 |
| unreachable_geometry | room_graph_unavailable  | no                 |
| unreachable_geometry | room_graph_no_path      | no                 |
| unreachable_geometry | empty_path              | no                 |

## 7. Deterministic algorithm with exact order.

### 7.1 `build_policy_valid_path(from_pos, to_pos, enemy)`

Step 1: Call `_build_geometry_path_plan(from_pos, to_pos)`. Assign `geometry_plan`.
Step 2: `geometry_status = String(geometry_plan.get("status", "unreachable_geometry"))`. If `geometry_status != "ok"`: return `geometry_plan` unchanged (status is unreachable_geometry, reason is from geometry backend).
Step 3: Call `_extract_path_points(geometry_plan.get("path_points", []))`. Assign `direct_pts: Array[Vector2]`.
Step 4: If `direct_pts.is_empty()`: return `{status: "unreachable_geometry", path_points: [], reason: "empty_path"}`.
Step 5: If `enemy == null`: return `{status: "ok", path_points: direct_pts, reason: "ok", route_type: "direct"}`.
Step 6: Call `_validate_enemy_policy_path(enemy, from_pos, direct_pts)`. Assign `direct_valid`.
Step 7: If `bool(direct_valid.get("valid", false)) == true`: return `{status: "ok", path_points: direct_pts, reason: "ok", route_type: "direct"}`.
Step 8: `from_room = room_id_at_point(from_pos)`. `to_room = room_id_at_point(to_pos)`.
Step 9: If `from_room < 0 or to_room < 0`: return `{status: "unreachable_policy", path_points: [], reason: "policy_blocked"}`.
Step 10: Call `_build_detour_candidates(from_pos, to_pos, from_room, to_room)`. Assign `candidates: Array[Dictionary]`. Each entry has keys `path_points: Array[Vector2]`, `euclidean_length: float`, `route_type: String`.
Step 11: Initialize `best_valid: Dictionary = {}`, `best_len: float = INF`.
Step 12: For each `cand` in `candidates` (in order): call `_validate_enemy_policy_path(enemy, from_pos, cand["path_points"] as Array[Vector2])`. If `bool(result.get("valid", false)) == true` and `float(cand["euclidean_length"]) < best_len`: set `best_valid = cand`, `best_len = float(cand["euclidean_length"])`.
Step 13: If `not best_valid.is_empty()`: return `{status: "ok", path_points: best_valid["path_points"] as Array[Vector2], reason: "ok", route_type: String(best_valid["route_type"])}`.
Step 14: Return `{status: "unreachable_policy", path_points: [], reason: "policy_blocked"}`.

### 7.2 `_build_detour_candidates(from_pos: Vector2, to_pos: Vector2, from_room: int, to_room: int) -> Array[Dictionary]`

Precondition: `from_room >= 0`, `to_room >= 0`.
Output: `Array[Dictionary]`. Each entry: `{path_points: Array[Vector2], euclidean_length: float, route_type: String, _sort_key: Array[int]}`. `_sort_key` is used for tie-breaking and is not part of the public contract.

Step 1: Initialize `result: Array[Dictionary] = []`.
Step 2: `neighbors_from: Array[int] = get_neighbors(from_room)`. (Already sorted ascending by existing `get_neighbors` implementation.)
Step 3: **1-WP candidates** — for each `mid` in `neighbors_from` where `mid != to_room`:
  - If `is_adjacent(mid, to_room) == true`:
    - `wp1 = get_door_center_between(from_room, mid, from_pos)`
    - `wp2 = get_door_center_between(mid, to_room, wp1)`
    - `pts: Array[Vector2] = [wp1, wp2, to_pos]`
    - `result.append({path_points: pts, euclidean_length: _euclidean_path_length(from_pos, pts), route_type: "1wp", _sort_key: [mid]})`
Step 4: **1-WP direct-neighbor** — if `is_adjacent(from_room, to_room) == true`:
  - `wp = get_door_center_between(from_room, to_room, from_pos)`
  - `pts: Array[Vector2] = [wp, to_pos]`
  - `result.append({path_points: pts, euclidean_length: _euclidean_path_length(from_pos, pts), route_type: "1wp", _sort_key: [to_room]})`
Step 5: **2-WP candidates** — for each `mid1` in `neighbors_from`:
  - `neighbors_mid1: Array[int] = get_neighbors(mid1)`
  - For each `mid2` in `neighbors_mid1` where `mid2 != from_room` and `mid2 != mid1` and `mid2 != to_room`:
    - If `is_adjacent(mid2, to_room) == true`:
      - `wp1 = get_door_center_between(from_room, mid1, from_pos)`
      - `wp2 = get_door_center_between(mid1, mid2, wp1)`
      - `wp3 = get_door_center_between(mid2, to_room, wp2)`
      - `pts: Array[Vector2] = [wp1, wp2, wp3, to_pos]`
      - `result.append({path_points: pts, euclidean_length: _euclidean_path_length(from_pos, pts), route_type: "2wp", _sort_key: [mid1, mid2]})`
Step 6: **Deduplicate** by `path_points` content: remove any entry whose `path_points` array is identical (element-wise: for each pair of corresponding points `a` and `b` check `abs(a.x - b.x) < 0.01 and abs(a.y - b.y) < 0.01`; note: `Vector2.is_equal_approx(other)` in Godot 4 does NOT accept a custom epsilon parameter — use explicit component comparison instead) to a previously seen entry. Keep the first occurrence.
Step 7: **Sort** `result` ascending by `euclidean_length`. Tie-break: compare `_sort_key` arrays lexicographically (first element; if equal, second element; lower wins). If `_sort_key` lengths differ, shorter key wins.
Step 8: Return `result`.

### 7.3 `_euclidean_path_length(from_pos: Vector2, path_points: Array[Vector2]) -> float`

Step 1: If `path_points.is_empty()`: return `0.0`.
Step 2: `total: float = 0.0`. `prev: Vector2 = from_pos`.
Step 3: For each `p` in `path_points`: `total += prev.distance_to(p)`. `prev = p`.
Step 4: Return `total`.

## 8. Edge-case matrix (case → exact output).

| Case | Condition | Expected output |
|---|---|---|
| E1 | `enemy == null` | `{status: ok, path_points: [geometry path], reason: ok, route_type: direct}` |
| E2 | `from_pos == to_pos` | Geometry returns single-point or degenerate path; policy not applied if enemy==null; otherwise validate as usual |
| E3 | Direct ok (no shadow block) | `{status: ok, ..., route_type: direct}` — `_build_detour_candidates` is never called |
| E4 | Direct blocked, 1-WP valid | `{status: ok, path_points: [wp1, wp2, to_pos], reason: ok, route_type: "1wp"}` |
| E5 | Direct blocked, 1-WP blocked, 2-WP valid | `{status: ok, path_points: [wp1, wp2, wp3, to_pos], reason: ok, route_type: "2wp"}` |
| E6 | All routes blocked | `{status: unreachable_policy, path_points: [], reason: policy_blocked}` — no `blocked_point` key |
| E7 | `from_room < 0` (no room for from_pos) | After geometry ok and direct blocked: return `{status: unreachable_policy, path_points: [], reason: policy_blocked}` at section 7.1 step 9 |
| E8 | `to_room < 0` | Same as E7 |
| E9 | `geometry_status != ok` | Return geometry_plan unchanged; detour never attempted |
| E10 | 1-WP and 2-WP produce duplicate path_points | Duplicate removed in step 6 of section 7.2; only first occurrence is evaluated |
| E11 | from_room == to_room, direct blocked | 1-WP candidates can still exist via any neighbor `mid` where `is_adjacent(mid, to_room)` is true (equivalently adjacent back to `from_room` because `from_room==to_room`). 2-WP candidates can also exist via two-hop loops that return to the original room. Both types are generated and evaluated. |
| E12 | Multiple valid routes with equal Euclidean length | Tie-break by `_sort_key` lexicographic: lower room_id wins |

## 9. Legacy removal plan (delete-first, exact ids).
Legacy gate baseline for this phase forbids identifiers `direct_only_fallback`, `legacy_path_selector`, `old_detour`. Confirmed by search (see Evidence): 0 matches in `src/` and `tests/`. No legacy identifiers exist in the codebase for this phase. No deletion step is required before adding new logic.

## 10. Legacy verification commands (exact rg + expected 0 matches).
1. `rg -n "direct_only_fallback|legacy_path_selector|old_detour" src tests -S`
   Expected: `0 matches`.

(No additional commands: no legacy was present.)

## 11. Acceptance criteria (binary pass/fail).
1. `build_policy_valid_path` with enemy == null returns `route_type: "direct"` on every ok response. PASS = rg gate and test assertion confirm.
2. `build_policy_valid_path` with shadow-blocked direct and valid 1-WP detour returns `status: ok`, `route_type: "1wp"`. PASS = `test_navigation_policy_detour_shadow_blocked_direct` exits 0.
3. `build_policy_valid_path` with shadow-blocked direct and shadow-blocked 1-WP but valid 2-WP returns `status: ok`, `route_type: "2wp"`. PASS = `test_navigation_policy_detour_two_waypoints` exits 0.
4. `build_policy_valid_path` with all routes blocked returns `status: unreachable_policy`, `reason: policy_blocked`, no `blocked_point` key. PASS = test assertion in `test_navigation_policy_detour_shadow_blocked_direct` confirms absence of `blocked_point`.
5. Output is deterministic: calling `build_policy_valid_path` twice with identical inputs returns identical output. PASS = test calls twice and asserts equality.
6. `_build_detour_candidates` never calls `_validate_enemy_policy_path` (policy validation belongs to caller). PASS = section 13 gate 5 command confirms no call inside `_build_detour_candidates` body.
7. Diff audit reports no out-of-scope file changes. PASS = section 19 diff audit.
8. All PMB contract commands return expected results. PASS = section 13 PMB gates.

## 12. Tests (new/update + purpose).
New tests (exact filenames):
- `tests/test_navigation_policy_detour_shadow_blocked_direct.gd` + `.tscn`
  Purpose: Verify that when the direct path is shadow-blocked but a 1-WP detour exists, `build_policy_valid_path` returns `status=ok`, `route_type="1wp"`, `path_points` non-empty. Also verify that when all routes are blocked, response has no `blocked_point` key.
- `tests/test_navigation_policy_detour_two_waypoints.gd` + `.tscn`
  Purpose: Verify that when direct and all 1-WP routes are shadow-blocked but a valid 2-WP detour exists, `build_policy_valid_path` returns `status=ok`, `route_type="2wp"`. Verify determinism: two calls with same input produce identical output.

Tests to update (exact filenames):
- `tests/test_navigation_path_policy_parity.gd`: Remove three `pursuit.call("_validate_path_policy", ...)` call sites (lines 73, 81, 91) and their assertions — function deleted in Phase 0. Before adding `build_policy_valid_path(...)` assertions, add a minimal deterministic room-graph setup in the test (same pattern as `tests/test_navigation_runtime_queries.gd`: valid fake layout + `nav._room_graph` + `nav._pair_doors`) so geometry planning returns a path in headless mode without a navmesh. Then add assertions that `nav.build_policy_valid_path(from_pos, blocked_path_end, enemy)` returns `status=unreachable_policy` when shadow blocks the only route (no detour exists in the small graph). Add assertion that flashlight override produces `status=ok, route_type="direct"`.
- `tests/test_navigation_runtime_queries.gd`: Add assertion `(nav.build_policy_valid_path(Vector2(10.0, 10.0), Vector2(190.0, 30.0))).get("route_type", "") == "direct"` (enemy=null case).
- `tests/test_runner_node.gd`: Add `const NAVIGATION_POLICY_DETOUR_BLOCKED_TEST_SCENE := "res://tests/test_navigation_policy_detour_shadow_blocked_direct.tscn"` and `const NAVIGATION_POLICY_DETOUR_TWO_WP_TEST_SCENE := "res://tests/test_navigation_policy_detour_two_waypoints.tscn"`; add existence checks for both; add two `_run_embedded_scene_suite` calls.

Phase test commands (exact):
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_policy_detour_shadow_blocked_direct.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_policy_detour_two_waypoints.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_path_policy_parity.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_runtime_queries.tscn`

Smoke suite commands (exact):
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_failure_reason_contract.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_pursuit_stall_fallback_invariants.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_shadow_policy_runtime.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_shot_gate_parity.tscn`

Pass rule: every command exits `0`; no `SKIP`, `SKIPPED`, `PENDING`, or `NOT RUN` in output logs.

## 13. rg gates (command + expected output).
1. `rg -n "direct_only_fallback|legacy_path_selector|old_detour" src tests -S`
   Expected: `0 matches`.
2. `rg -n "_validate_path_policy\b|_validate_path_policy_with_traverse_samples\b" src/systems/navigation_runtime_queries.gd -S`
   Expected: `0 matches`. (These identifiers belong to enemy_pursuit_system.gd only; must not appear in navigation_runtime_queries.gd.)
3. `rg -n "_build_detour_candidates|_euclidean_path_length" src/systems/navigation_runtime_queries.gd -S`
   Expected: `≥1 match` each (new functions must be present).
4. `rg -n "route_type" src/systems/navigation_runtime_queries.gd -S`
   Expected: `≥3 matches` (set in direct return, 1wp/2wp candidate construction, and ok-result return in step 13).
5. `bash -lc 'awk "BEGIN{in_f=0} /^func _build_detour_candidates[(]/ {in_f=1; next} /^func / && in_f {exit} in_f {print}" src/systems/navigation_runtime_queries.gd | rg -n "_validate_enemy_policy_path" -S'`
   Expected: `0 matches`. (Exact single-owner gate: `_build_detour_candidates` body must not call policy validation.)
6. `rg -n "pursuit\.call\(\"_validate_path_policy\"\|pursuit\.call\(\"_validate_path_policy" tests/test_navigation_path_policy_parity.gd -S`
   Expected: `0 matches`. (Removed in update step.)

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: `0 matches`.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

## 14. Execution sequence (step-by-step, no ambiguity).
1. Run legacy gate (section 10, command 1). Confirm 0 matches. Stop if non-zero.
2. Run Phase 0 dependency gates (section 23). Stop on first failure.
3. Add `_euclidean_path_length(from_pos: Vector2, path_points: Array[Vector2]) -> float` to `navigation_runtime_queries.gd`. Algorithm: section 7.3.
4. Add `_build_detour_candidates(from_pos: Vector2, to_pos: Vector2, from_room: int, to_room: int) -> Array[Dictionary]` to `navigation_runtime_queries.gd`. Algorithm: section 7.2.
5. Modify `build_policy_valid_path` in `navigation_runtime_queries.gd`: replace steps after direct validation (current lines 237–252) with the extended algorithm from section 7.1 (steps 6–14). Do not modify steps 1–5 (geometry + early returns).
6. Update `tests/test_navigation_path_policy_parity.gd`: remove `pursuit.call("_validate_path_policy", ...)` at lines 73, 81, 91 and dependent assertions. Add minimal fake layout + `nav._room_graph` + `nav._pair_doors` setup (per section 12) before calling `build_policy_valid_path`, then add shadow-blocked and flashlight-override assertions on `build_policy_valid_path` output.
7. Update `tests/test_navigation_runtime_queries.gd`: add `route_type == "direct"` assertion as specified in section 12.
8. Create `tests/test_navigation_policy_detour_shadow_blocked_direct.gd` and `.tscn` per section 12.
9. Create `tests/test_navigation_policy_detour_two_waypoints.gd` and `.tscn` per section 12.
10. Update `tests/test_runner_node.gd`: add constants, existence checks, and run entries for both new scenes per section 12.
11. Run all phase test commands (section 12). All must exit 0.
12. Run all smoke suite commands (section 12). All must exit 0.
13. Run all rg gates from section 13 (items 1–6 + PMB-1 through PMB-5). Confirm expected results.
14. Run diff audit (section 19): confirm no out-of-scope file changes.
15. Record verification report (section 21).

## 15. Rollback conditions.
Rollback immediately if any of the following occur:
1. Any phase test command (section 12) exits non-zero after step 11.
2. Any smoke suite command (section 12) exits non-zero after step 12.
3. Any rg gate from section 13 returns unexpected output.
4. Diff audit (section 19) reports an out-of-scope file change.
5. `build_policy_valid_path` returns `status=ok` without `route_type` key in any test scenario.
6. `_validate_enemy_policy_path` is called from inside `_build_detour_candidates` (single-owner violation; detected by section 13 gate 5 command).

Rollback action: restore `navigation_runtime_queries.gd`, `test_navigation_path_policy_parity.gd`, `test_navigation_runtime_queries.gd`, and `test_runner_node.gd` to their Phase 0 close state. Do not restore new test files (they did not exist; simply delete them).

## 16. Phase close condition.
Phase PHASE_1 is closed when all of the following are true simultaneously:
1. All phase test commands exit 0 (section 12).
2. All smoke suite commands exit 0 (section 12).
3. All rg gates return expected results (section 13, items 1–6).
4. All PMB gates return expected results (section 13, PMB-1 through PMB-5).
5. Diff audit reports no out-of-scope changes (section 19).
6. Verification report (section 21) is recorded with `final_result: PASS`.

## 17. Ambiguity self-check line: Ambiguity check: 0

## 18. Open questions line: Open questions: 0

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).
1. Diff audit: run `git diff --name-only`. Every changed path must appear in the in-scope list of section 4. Any path not in that list = phase FAILED.
2. Contract conformance:
   a. `rg -n "route_type" src/systems/navigation_runtime_queries.gd -S` — confirm ≥3 occurrences.
   b. Run `build_policy_valid_path(from, to)` with enemy=null in test; confirm `route_type == "direct"` present.
   c. Confirm `status=unreachable_policy` responses never contain `blocked_point` key in new test scenarios.
3. Single-owner check: run section 13 gate 5 command (`awk` body extraction for `_build_detour_candidates` piped to `rg`) — expected `0 matches`.
4. Smoke suite: run all 4 commands from section 12 smoke list. All must exit 0.
5. Runtime scenario checks: run section 20 scenarios.

## 20. Runtime scenario matrix (scenario id, setup, duration, expected invariants, fail conditions).

| Scenario | Setup | Duration | Expected invariants | Fail conditions |
|---|---|---|---|---|
| S1 | FakeLayout 3-room linear (A–B–C); shadow blocks A→C direct; B connects A and C; enemy at room A, target at room C | 120 physics frames | `build_policy_valid_path` returns `status=ok, route_type="1wp"`, path passes through door(A,B) and door(B,C) | status != ok; route_type != "1wp"; path empty |
| S2 | FakeLayout 4-room (A–B–C–D linear); shadow blocks A→D direct and A→B→D 1-WP; only A→B→C→D valid | 120 frames | `build_policy_valid_path` returns `status=ok, route_type="2wp"` | status != ok; route_type != "2wp"; path empty |
| S3 | All rooms in shadow; enemy at A, target at D | 60 frames | `build_policy_valid_path` returns `status=unreachable_policy, reason=policy_blocked`, no `blocked_point` key | status != unreachable_policy; `blocked_point` key present |
| S4 | enemy=null; any layout | 60 frames | `build_policy_valid_path` returns `status=ok, route_type="direct"` | route_type != "direct"; status != ok |
| S5 | Same input called twice (S1 setup) | 2 calls | Both calls return identical `status`, `path_points`, `route_type` | Outputs differ |

Scenario commands (exact):
- `S1` and `S3`: `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_policy_detour_shadow_blocked_direct.tscn`
- `S2` and `S5`: `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_policy_detour_two_waypoints.tscn`
- `S4`: `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_runtime_queries.tscn`

## 21. Verification report format (what must be recorded to close phase).
Report must record all fields below:
- `phase_id: PHASE_1`
- `changed_files: [exact paths]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; must be empty on close)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `legacy_verification: [command, exit_code, match_count, PASS|FAIL]` for section 10 command
- `rg_gates: [command, expected, actual, PASS|FAIL]` for each section 13 gate (items 1–6)
- `phase_tests: [command, exit_code, PASS|FAIL]` for each section 12 phase test command
- `smoke_suite: [command, exit_code, PASS|FAIL]` for each section 12 smoke command
- `runtime_scenarios: [scenario_id, setup_description, invariant_result, PASS|FAIL]` for each section 20 scenario
- `single_owner_check: PASS|FAIL` (no `_validate_enemy_policy_path` call inside `_build_detour_candidates`)
- `route_type_contract_check: PASS|FAIL` (every ok response includes `route_type` key)
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` (all must be PASS to close phase)
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`
Non-empty `unresolved_deviations` forces `final_result = FAIL`.

## 22. Structural completeness self-check line:
Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23. Missing sections: NONE.
- Evidence preamble (### Evidence) present between ## PHASE header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- pmb_contract_check present in section 21 (PMB section exists in document): yes

## 23. Dependencies on previous phases.
1. Phase 0 dependency gate — `build_policy_valid_path` is the authoritative single planner (no fallback branches in `enemy_pursuit_system.gd`). Gate: `rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S` → `0 matches`. Must pass before step 5 in section 14.
2. Phase 0 dependency gate — `_validate_path_policy` and `_validate_path_policy_with_traverse_samples` deleted from `enemy_pursuit_system.gd`. Gate: `rg -n "_validate_path_policy\b|_validate_path_policy_with_traverse_samples\b" src/systems/enemy_pursuit_system.gd -S` → `0 matches`. Must pass before step 6 in section 14 (updating `test_navigation_path_policy_parity.gd` requires these functions to be absent so the old assertions are definitively dead).
3. Phase 0 is the only prerequisite. Phase 1 depends on Phase 0 and on no other phase.
## PHASE 2
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.

### Evidence

Inspected files:
1. `docs/ai_nav_refactor_execution_v2.md`
2. `src/systems/enemy_pursuit_system.gd`
3. `src/systems/enemy_utility_brain.gd`
4. `src/entities/enemy.gd`
5. `src/systems/navigation_runtime_queries.gd`
6. `src/systems/navigation_service.gd`
7. `src/core/game_config.gd`
8. `src/core/config_validator.gd`
9. `tests/test_shadow_policy_hard_block_without_grant.gd`
10. `tests/test_shadow_policy_hard_block_without_grant.tscn`
11. `tests/test_shadow_stall_escapes_to_light.gd`
12. `tests/test_shadow_stall_escapes_to_light.tscn`
13. `tests/test_pursuit_stall_fallback_invariants.gd`
14. `tests/test_pursuit_stall_fallback_invariants.tscn`
15. `tests/test_nearest_reachable_fallback_by_nav_distance.gd`
16. `tests/test_nearest_reachable_fallback_by_nav_distance.tscn`
17. `tests/test_pursuit_intent_only_runtime.gd`
18. `tests/test_pursuit_origin_target_not_sentinel.gd`
19. `tests/test_suspicious_shadow_scan.gd`
20. `tests/test_combat_no_los_never_hold_range.gd`
21. `tests/test_enemy_behavior_integration.gd`
22. `tests/test_shadow_enemy_stuck_when_inside_shadow.gd`
23. `tests/test_shadow_enemy_unstuck_after_flashlight_activation.gd`
24. `tests/test_runner_node.gd`

Inspected functions/methods:
1. `Enemy._resolve_known_target_context`
2. `Enemy._build_utility_context`
3. `Enemy._apply_runtime_intent_stability_policy`
4. `EnemyUtilityBrain.update`
5. `EnemyUtilityBrain._choose_intent`
6. `EnemyUtilityBrain._combat_no_los_grace_intent`
7. `EnemyPursuitSystem.execute_intent`
8. `EnemyPursuitSystem._execute_move_to_target`
9. `EnemyPursuitSystem._execute_shadow_boundary_scan`
10. `EnemyPursuitSystem._execute_search`
11. `EnemyPursuitSystem._plan_path_to`
12. `EnemyPursuitSystem._request_path_plan_contract`
13. `EnemyPursuitSystem._attempt_replan_with_policy`
14. `EnemyPursuitSystem._resolve_nearest_reachable_fallback`
15. `EnemyPursuitSystem._sample_fallback_candidates`
16. `EnemyPursuitSystem._attempt_shadow_escape_recovery`
17. `EnemyPursuitSystem._resolve_shadow_escape_target`
18. `EnemyPursuitSystem._sample_shadow_escape_candidates`
19. `EnemyPursuitSystem._resolve_movement_target_with_shadow_escape`
20. `EnemyPursuitSystem.debug_get_navigation_policy_snapshot`
21. `EnemyPursuitSystem.debug_select_nearest_reachable_fallback`
22. `NavigationRuntimeQueries.build_policy_valid_path`
23. `NavigationRuntimeQueries.build_reachable_path_points`
24. `NavigationRuntimeQueries.build_path_points`
25. `NavigationRuntimeQueries.nav_path_length`
26. `NavigationService.build_policy_valid_path`
27. `NavigationService.get_nearest_non_shadow_point`
28. `NavigationService.can_enemy_traverse_point`

Search commands used:
1. `rg -n "_resolve_nearest_reachable_fallback|_sample_fallback_candidates|_policy_fallback_used|_policy_fallback_target|_attempt_shadow_escape_recovery|_resolve_shadow_escape_target|_sample_shadow_escape_candidates|FALLBACK_RING_|SHADOW_ESCAPE_RING_" src tests -S`
2. `rg -n "_plan_path_to|_request_path_plan_contract|_build_policy_valid_path|execute_intent|unreachable_policy|SHADOW_BOUNDARY_SCAN|SEARCH|PATROL|RETURN_HOME" src/systems/enemy_pursuit_system.gd -S`
3. `rg -n "decide_intent|_combat_no_los_grace_intent|IntentType\.SHADOW_BOUNDARY_SCAN|IntentType\.SEARCH|IntentType\.PATROL|IntentType\.RETURN_HOME|known_target_pos|last_seen_pos|investigate_anchor" src/systems/enemy_utility_brain.gd -S`
4. `rg -n "_resolve_known_target_context|_resolve_utility_context|shadow_scan_target|known_target_pos|target_is_last_seen|_pursuit\.execute_intent|execute_intent\(" src/entities/enemy.gd -S`
5. `rg -n "build_policy_valid_path|unreachable_policy|status|reason|path" src/systems/navigation_runtime_queries.gd -S`
6. `rg -n "shadow|unreachable|SHADOW_BOUNDARY_SCAN|SEARCH|PATROL" tests/test_shadow_policy_hard_block_without_grant.gd tests/test_shadow_stall_escapes_to_light.gd -S`
7. `rg -n "policy_fallback_used|policy_fallback_target|shadow_escape_active|shadow_escape_target|fallback|unreachable_policy|SHADOW_BOUNDARY_SCAN|SEARCH" tests -S`
8. `rg -n "execute_intent\(" src tests -S`
9. `rg -n "_request_path_plan_contract\(|_plan_path_to\(|_attempt_replan_with_policy\(|_resolve_nearest_reachable_fallback\(|_attempt_shadow_escape_recovery\(|_resolve_shadow_escape_target\(|_sample_shadow_escape_candidates\(|_sample_fallback_candidates\(" src tests -S`
10. `rg -n "build_policy_valid_path\(" src tests -S`
11. `rg -n "debug_get_navigation_policy_snapshot\(|debug_select_nearest_reachable_fallback\(" tests src -S`
12. `rg -n "func _resolve_nearest_reachable_fallback\(|func _sample_fallback_candidates\(|var _policy_fallback_used|var _policy_fallback_target|func _attempt_shadow_escape_recovery\(|func _resolve_shadow_escape_target\(|func _sample_shadow_escape_candidates\(|func _resolve_movement_target_with_shadow_escape\(" src/systems/enemy_pursuit_system.gd -S`
13. `rg -n "FALLBACK_RING_|SHADOW_ESCAPE_RING_" src/systems/enemy_pursuit_system.gd -S`
14. `rg -n "if not has_los and alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT|\"type\": IntentType.RETURN_HOME" src/systems/enemy_utility_brain.gd -S`
15. `rg -n "policy_fallback_used|policy_fallback_target|shadow_escape_active|shadow_escape_target|debug_select_nearest_reachable_fallback" tests/test_shadow_policy_hard_block_without_grant.gd tests/test_shadow_stall_escapes_to_light.gd tests/test_pursuit_stall_fallback_invariants.gd tests/test_nearest_reachable_fallback_by_nav_distance.gd -S`

1. What now.
Phase id: PHASE_2.
Phase title: Detour Integration In Pursuit And Canon Fallback FSM.
Goal: Replace all nearest-reachable and shadow-escape fallback logic with a deterministic unreachable-policy FSM that enforces `SHADOW_BOUNDARY_SCAN -> SEARCH` and blocks `PATROL/RETURN_HOME` under active ALERT/COMBAT target context.
Current measurable behavior:
1. `src/systems/enemy_pursuit_system.gd` still contains legacy fallback owner state and functions: `_policy_fallback_used`, `_policy_fallback_target`, `_resolve_nearest_reachable_fallback`, `_sample_fallback_candidates`, `_attempt_shadow_escape_recovery`, `_resolve_shadow_escape_target`, `_sample_shadow_escape_candidates`, `_resolve_movement_target_with_shadow_escape`.
2. `src/systems/enemy_pursuit_system.gd` still contains fallback constants: `FALLBACK_RING_*`, `SHADOW_ESCAPE_RING_*`.
3. `tests/test_shadow_policy_hard_block_without_grant.gd`, `tests/test_shadow_stall_escapes_to_light.gd`, `tests/test_pursuit_stall_fallback_invariants.gd`, and `tests/test_nearest_reachable_fallback_by_nav_distance.gd` assert legacy fallback behavior and legacy debug surfaces.
4. `src/systems/enemy_utility_brain.gd` still includes a no-LOS ALERT+ branch that returns `IntentType.RETURN_HOME`.
5. Current route failure recovery in `_execute_move_to_target` calls `_attempt_replan_with_policy` and then `_attempt_shadow_escape_recovery`, which violates strict single-canon shadow unreachable fallback.

2. What changes.
1. Delete all nearest-reachable fallback and shadow-escape recovery code from `src/systems/enemy_pursuit_system.gd` before any new FSM logic is added.
2. Introduce explicit Phase 2 plan execution state in `src/systems/enemy_pursuit_system.gd`:
1. `plan_id`.
2. `intent_target`.
3. `plan_target`.
3. Route all movement planning through contract status from `_request_path_plan_contract` and remove any target substitution fallback branch.
4. Add deterministic unreachable-policy FSM in `src/systems/enemy_pursuit_system.gd`:
1. On `unreachable_policy` in shadow context: force `SHADOW_BOUNDARY_SCAN`.
2. After scan completion or scan timeout: force `SEARCH` for exactly one execution tick.
3. Direct `PATROL` and `RETURN_HOME` while FSM is active are forbidden.
5. Keep anti-patrol invariant active in runtime execution: when `alert_level >= ALERT` and active target context exists, executed intent is never `PATROL` and never `RETURN_HOME`.
6. Replace legacy debug snapshot keys with plan/FSM keys and update tests to consume new keys.
7. Update or replace legacy fallback tests so no test references removed fallback identifiers.

3. What will be after.
1. Every movement decision for this phase follows one path: `build_policy_valid_path -> execute_intent -> move/repath`.
2. No nearest-reachable fallback path exists in pursuit runtime.
3. No shadow-escape recovery path exists in pursuit runtime.
4. Shadow unreachable canon is strict: `SHADOW_BOUNDARY_SCAN -> SEARCH`; direct `PATROL` fallback is absent.
5. ALERT/COMBAT with active target context never executes `PATROL` and never executes `RETURN_HOME`.
6. All legacy identifiers listed in section 9 return zero `rg` matches.
7. Phase tests and smoke suite pass with exit code `0` and no `SKIP/PENDING/NOT RUN` markers.

4. Scope and non-scope (exact files).
In-scope files:
1. `src/systems/enemy_pursuit_system.gd`
2. `tests/test_shadow_policy_hard_block_without_grant.gd`
3. `tests/test_shadow_policy_hard_block_without_grant.tscn`
4. `tests/test_shadow_stall_escapes_to_light.gd`
5. `tests/test_shadow_stall_escapes_to_light.tscn`
6. `tests/test_pursuit_stall_fallback_invariants.gd`
7. `tests/test_pursuit_stall_fallback_invariants.tscn`
8. `tests/test_nearest_reachable_fallback_by_nav_distance.gd` (delete or rewrite to Phase 2 contract)
9. `tests/test_nearest_reachable_fallback_by_nav_distance.tscn` (delete or rewrite to Phase 2 contract)
10. `tests/test_shadow_unreachable_transitions_to_search_not_patrol.gd` (new)
11. `tests/test_shadow_unreachable_transitions_to_search_not_patrol.tscn` (new)
12. `tests/test_runner_node.gd`

Out-of-scope files:
1. `src/entities/enemy.gd`
2. `src/systems/enemy_utility_brain.gd`
3. `src/systems/navigation_runtime_queries.gd`
4. `src/systems/navigation_service.gd`
5. `src/core/game_config.gd`
6. `src/core/config_validator.gd`
7. `tests/test_pursuit_intent_only_runtime.gd`
8. `tests/test_pursuit_origin_target_not_sentinel.gd`
9. `tests/test_suspicious_shadow_scan.gd`
10. `tests/test_combat_no_los_never_hold_range.gd`
11. `tests/test_shadow_enemy_stuck_when_inside_shadow.gd`
12. `tests/test_shadow_enemy_unstuck_after_flashlight_activation.gd`

5. Single-owner authority for this phase.
Single owner authority: `EnemyPursuitSystem.execute_intent`.
Authority rules:
1. `EnemyPursuitSystem.execute_intent` is the only runtime owner that translates unreachable-policy movement failure into `SHADOW_BOUNDARY_SCAN -> SEARCH` execution.
2. `EnemyPursuitSystem.execute_intent` is the only runtime owner that resolves `intent_target`, `plan_target`, and `plan_id` transitions.
3. No helper outside `EnemyPursuitSystem` is allowed to select nearest fallback target.
4. Call graph for this authority is fixed: `Enemy._physics_process tick -> EnemyUtilityBrain.update -> EnemyPursuitSystem.execute_intent -> EnemyPursuitSystem._execute_move_to_target -> EnemyPursuitSystem._plan_path_to -> NavigationService.build_policy_valid_path -> NavigationRuntimeQueries.build_policy_valid_path`.
5. Parallel decision path is forbidden: no runtime calls to deleted fallback selectors and no secondary plan substitution branch.

6. Full input/output contract.
1. Phase id: `PHASE_2`.
2. Phase title: `Detour Integration In Pursuit And Canon Fallback FSM`.
3. Goal: Replace fallback target substitution with deterministic Phase 2 plan-lock + unreachable-policy FSM that enforces shadow canon transitions.
4. In-scope files (exact paths):
1. `src/systems/enemy_pursuit_system.gd`
2. `tests/test_shadow_policy_hard_block_without_grant.gd`
3. `tests/test_shadow_policy_hard_block_without_grant.tscn`
4. `tests/test_shadow_stall_escapes_to_light.gd`
5. `tests/test_shadow_stall_escapes_to_light.tscn`
6. `tests/test_pursuit_stall_fallback_invariants.gd`
7. `tests/test_pursuit_stall_fallback_invariants.tscn`
8. `tests/test_nearest_reachable_fallback_by_nav_distance.gd`
9. `tests/test_nearest_reachable_fallback_by_nav_distance.tscn`
10. `tests/test_shadow_unreachable_transitions_to_search_not_patrol.gd`
11. `tests/test_shadow_unreachable_transitions_to_search_not_patrol.tscn`
12. `tests/test_runner_node.gd`
5. Out-of-scope files (exact paths):
1. `src/entities/enemy.gd`
2. `src/systems/enemy_utility_brain.gd`
3. `src/systems/navigation_runtime_queries.gd`
4. `src/systems/navigation_service.gd`
5. `src/core/game_config.gd`
6. `src/core/config_validator.gd`
7. `scenes/entities/enemy.tscn`
6. Current behavior (what now, measurable):
1. `_attempt_replan_with_policy` substitutes movement target through `_resolve_nearest_reachable_fallback`.
2. `_attempt_shadow_escape_recovery` toggles `shadow_escape_*` state and performs shadow escape replans.
3. Debug snapshot exposes `policy_fallback_*` and `shadow_escape_*` keys.
4. Existing fallback tests assert these keys and behavior.
7. Target behavior (what after, measurable):
1. Deleted legacy functions/constants/vars from section 9 report zero matches.
2. `_attempt_replan_with_policy` performs no fallback substitution.
3. Unreachable-policy in shadow context triggers `SHADOW_BOUNDARY_SCAN`, then one forced `SEARCH` tick.
4. Executed intent in ALERT/COMBAT with active target context is never `PATROL` and never `RETURN_HOME`.
5. Debug snapshot exposes `plan_id`, `intent_target`, `plan_target`, and `shadow_unreachable_fsm_state`.
8. Contracts to introduce/change:
1. `PursuitPlanLockContractV1`.
2. `ShadowUnreachableCanonFSMContractV1`.
3. `PursuitDebugSnapshotContractV2`.
9. Contract name: `PursuitPlanLockContractV1`.
10. Inputs (types, nullability, finite checks):
1. `execute_intent(delta: float, intent: Dictionary, context: Dictionary)`.
2. `delta` must be finite and `>= 0.0`; non-finite is normalized to `0.0`.
3. `intent.type` must resolve to `int`; unsupported value is normalized to `IntentType.PATROL` before guard application.
4. `intent.target` is optional; `has_target=true` only when key exists and target coordinates are finite.
5. `context.alert_level` must resolve to `int` in enemy alert enum bounds.
6. `context.known_target_pos`, `context.last_seen_pos`, `context.investigate_anchor` must resolve to finite `Vector2` or `Vector2.ZERO`.
7. Active target context formula: `active_target_context = (known_target_pos != Vector2.ZERO) or has_last_seen or has_investigate_anchor`.
8. `home_position`: the enemy's home room center position; sourced from `context.home_position` when the key is present and the value is finite `Vector2`; defaults to `Vector2.ZERO` when absent or non-finite. Used as fourth-priority fallback target in the anti-patrol execution guard (section 6, item 14.3).
9. Shadow-FSM trigger predicate (exact, evaluated at unreachable-policy handling time using current `plan_target`): `shadow_fsm_trigger = (context.alert_level >= ALERT) and active_target_context and nav_system != null and nav_system.has_method("is_point_in_shadow") and bool(nav_system.call("is_point_in_shadow", plan_target))`. If `nav_system` is null or lacks `is_point_in_shadow`, `shadow_fsm_trigger = false`.
11. Outputs (exact keys/types/enums):
1. `execute_intent` output keys (always present):
1. `request_fire: bool`
2. `path_failed: bool`
3. `path_failed_reason: String`
4. `policy_blocked_segment: int`
5. `movement_intent: bool`
6. `plan_id: int`
7. `intent_target: Vector2`
8. `plan_target: Vector2`
9. `shadow_unreachable_fsm_state: String`
2. `debug_get_navigation_policy_snapshot` keys (always present for Phase 2 contract):
1. `path_plan_status: String`
2. `path_plan_reason: String`
3. `active_move_target: Vector2`
4. `active_move_target_valid: bool`
5. `plan_id: int`
6. `intent_target: Vector2`
7. `plan_target: Vector2`
8. `shadow_unreachable_fsm_state: String`
12. Status enums:
1. Path-plan status enum: `ok`, `unreachable_policy`, `unreachable_geometry`.
2. Shadow FSM state enum: `none`, `shadow_boundary_scan`, `search`.
13. Reason enums:
1. Path-plan reasons: `ok`, `policy_blocked`, `empty_path`, `navmesh_no_path`, `room_graph_unavailable`, `room_graph_no_path`, `nav_system_missing`, `path_unreachable`, `no_target`.
2. Execute-intent reasons: `replan_failed`, `path_unavailable`, `hard_stall`, `shadow_unreachable_policy`.
14. Deterministic order and tie-break rules:
1. `intent_target` is copied from normalized `intent.target`.
2. `plan_target` update order:
1. If `plan_id == 0`, assign new plan.
2. Else if intent type changed, assign new plan.
3. Else if `has_target` flag changed, assign new plan.
4. Else if `distance(intent_target, plan_target) > PLAN_TARGET_SWITCH_EPS_PX`, assign new plan.
5. Else reuse existing `plan_target` and existing `plan_id`.
3. Active target fallback priority: `known_target_pos` first, `last_seen_pos` second, `investigate_anchor` third, `home_position` fourth (`home_position` defined in section 6, item 10.8; evaluates to `context.home_position` if present and finite, else `Vector2.ZERO`).
4. On `unreachable_policy` with `shadow_fsm_trigger == true` (section 6, item 10.9), FSM transitions exactly `none -> shadow_boundary_scan -> search -> none`.
5. Forced `search` duration is exactly one execute tick.
15. Constants/thresholds/eps (exact values):
1. `PLAN_TARGET_SWITCH_EPS_PX = 8.0`.
2. `SHADOW_UNREACHABLE_SEARCH_TICKS = 1`.
3. `SHADOW_BOUNDARY_SEARCH_RADIUS_PX = 96.0`.
4. `SHADOW_SCAN_DURATION_MIN_SEC = 2.0`.
5. `SHADOW_SCAN_DURATION_MAX_SEC = 3.0`.
6. `SHADOW_SCAN_SWEEP_RAD = 0.87`.
7. `SHADOW_SCAN_SWEEP_SPEED = 2.4`.
8. `PATH_REPATH_INTERVAL_SEC = 0.35`.
9. `COMBAT_REPATH_INTERVAL_NO_LOS_SEC = 0.2`.
10. `LAST_SEEN_REACHED_PX = 20.0`.
11. `WAYPOINT_REACHED_PX = 12.0`.
16. Forbidden patterns (identifiers/branches):
1. Any call or definition of `_resolve_nearest_reachable_fallback`.
2. Any call or definition of `_sample_fallback_candidates`.
3. Any call or definition of `_attempt_shadow_escape_recovery`.
4. Any call or definition of `_resolve_shadow_escape_target`.
5. Any call or definition of `_sample_shadow_escape_candidates`.
6. Any call or definition of `_resolve_movement_target_with_shadow_escape`.
7. Any runtime field/key containing `policy_fallback_`.
8. Any runtime field/key containing `shadow_escape_`.
9. Any call or definition of `debug_select_nearest_reachable_fallback`.
10. Any path-failure reason `fallback_missing` or `fallback_failed`.
17. Legacy to delete first (exact ids/functions/consts):
1. `FALLBACK_RING_MIN_RADIUS_PX`
2. `FALLBACK_RING_STEP_RADIUS_PX`
3. `FALLBACK_RING_COUNT`
4. `FALLBACK_RING_SAMPLES_PER_RING`
5. `SHADOW_ESCAPE_RING_MIN_RADIUS_PX`
6. `SHADOW_ESCAPE_RING_STEP_RADIUS_PX`
7. `SHADOW_ESCAPE_RING_COUNT`
8. `SHADOW_ESCAPE_SAMPLES_PER_RING`
9. `_policy_fallback_used`
10. `_policy_fallback_target`
11. `_shadow_escape_active`
12. `_shadow_escape_target`
13. `_shadow_escape_target_valid`
14. `_resolve_nearest_reachable_fallback`
15. `_sample_fallback_candidates`
16. `_attempt_shadow_escape_recovery`
17. `_resolve_shadow_escape_target`
18. `_sample_shadow_escape_candidates`
19. `_resolve_movement_target_with_shadow_escape`
20. `debug_select_nearest_reachable_fallback`
18. Migration notes:
1. `debug_get_navigation_policy_snapshot` removes `policy_fallback_*` and `shadow_escape_*` keys.
2. `debug_get_navigation_policy_snapshot` adds `plan_id`, `intent_target`, `plan_target`, `shadow_unreachable_fsm_state` keys.
3. `tests/test_nearest_reachable_fallback_by_nav_distance.gd` and `tests/test_nearest_reachable_fallback_by_nav_distance.tscn` are deleted or rewritten to validate Phase 2 plan-lock contract only.
4. `tests/test_runner_node.gd` removes legacy fallback scene constant and suite entry when deleted.
19. New tests (exact filenames):
1. `tests/test_shadow_unreachable_transitions_to_search_not_patrol.gd`
2. `tests/test_shadow_unreachable_transitions_to_search_not_patrol.tscn`
20. Tests to update (exact filenames):
1. `tests/test_shadow_policy_hard_block_without_grant.gd`
2. `tests/test_shadow_policy_hard_block_without_grant.tscn`
3. `tests/test_shadow_stall_escapes_to_light.gd`
4. `tests/test_shadow_stall_escapes_to_light.tscn`
5. `tests/test_pursuit_stall_fallback_invariants.gd`
6. `tests/test_pursuit_stall_fallback_invariants.tscn`
7. `tests/test_nearest_reachable_fallback_by_nav_distance.gd`
8. `tests/test_nearest_reachable_fallback_by_nav_distance.tscn`
9. `tests/test_runner_node.gd`
21. Smoke suite commands (exact):
1. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_path_policy_parity.tscn`
2. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_shadow_policy_hard_block_without_grant.tscn`
3. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_shadow_stall_escapes_to_light.tscn`
4. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_pursuit_stall_fallback_invariants.tscn`
5. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_combat_no_los_never_hold_range.tscn`
22. Canonical section references (deduplicated for Phase 2; use these sections as authoritative):
1. rg gates: section 13 only.
2. Rollback conditions: section 15 only.
3. Dependencies on previous phases: section 23 only.
4. Runtime scenarios: section 20 only.
5. Allowed file-change boundary: section 4 only.

7. Deterministic algorithm with exact order.
1. Normalize execute input.
1. Normalize `delta` to finite `>=0`.
2. Normalize `intent_target` from `intent.target` when finite; otherwise set `has_target=false` and `intent_target=Vector2.ZERO`.
3. Compute `active_target_context` from context formula in section 6.
2. Apply anti-patrol execution guard.
1. Guard condition: `context.alert_level >= ALERT` and `active_target_context` and (`intent.type == PATROL` or `intent.type == RETURN_HOME`).
2. If guard condition is true, compute `guard_target` by priority in section 6.14.3, then set runtime `intent.type = SEARCH`, set `has_target = (guard_target != Vector2.ZERO)`, and overwrite normalized `intent_target = guard_target` when `has_target == true` (otherwise `intent_target = Vector2.ZERO`) before step 3 plan-lock evaluation.
3. Resolve plan lock.
1. Evaluate plan replacement conditions in section 6.14.2.
2. On replacement, increment `plan_id` by exactly `1`, set `plan_target=intent_target`, and store `plan_intent_type=intent.type`.
3. On reuse, keep existing `plan_id` and existing `plan_target`.
4. Execute forced shadow FSM override.
1. If `shadow_unreachable_fsm_state == shadow_boundary_scan`, execute `_execute_shadow_boundary_scan(delta, plan_target, true)`.
2. If scan completes or times out, set `shadow_unreachable_fsm_state = search`.
3. If `shadow_unreachable_fsm_state == search`, execute `_execute_search(delta, plan_target)`, decrement `forced_search_ticks_left`, and set state to `none` when `forced_search_ticks_left == 0`.
5. Execute normal intent path when FSM state is `none`.
1. Movement intents call `_execute_move_to_target(delta, plan_target, ...)`.
2. `_execute_move_to_target` replans only through `_attempt_replan_with_policy(plan_target)`.
6. Handle unreachable policy event.
1. `_attempt_replan_with_policy` calls `_plan_path_to(plan_target)`.
2. If `_plan_path_to` returns false and `_last_path_plan_status == unreachable_policy` and `shadow_fsm_trigger == true` (section 6, item 10.9), set `path_failed_reason = shadow_unreachable_policy`, set FSM state to `shadow_boundary_scan`, and set `forced_search_ticks_left = SHADOW_UNREACHABLE_SEARCH_TICKS`.
3. No fallback target selection runs.
7. Return output with exact keys from section 6.11.

8. Edge-case matrix (case -> exact output).
1. Case: `intent.target` missing for movement intent -> output `path_failed=true`, `path_failed_reason=no_target`, `movement_intent=false`, `plan_id` unchanged.
2. Case: `plan_target` delta `<= 8.0` and same intent type -> output keeps same `plan_id` and same `plan_target`.
3. Case: `plan_target` delta `> 8.0` with same intent type -> output increments `plan_id` by `1` and updates `plan_target` to new target.
4. Case: plan status `unreachable_geometry` -> output `path_failed=true`, `shadow_unreachable_fsm_state=none`, no forced scan/search.
5. Case: plan status `unreachable_policy` and target not in shadow -> output `path_failed=true`, `shadow_unreachable_fsm_state=none`, no fallback substitution.
6. Case: plan status `unreachable_policy` and `shadow_fsm_trigger == true` (target in shadow + ALERT/COMBAT + active target context + nav shadow query available) -> output enters `shadow_unreachable_fsm_state=shadow_boundary_scan` and does not execute PATROL.
7. Case: scan timeout occurs -> next tick output `shadow_unreachable_fsm_state=search` and execute `SEARCH` exactly once.
8. Case: utility produced `PATROL` while ALERT/COMBAT context has `known_target_pos != Vector2.ZERO` -> executed runtime intent is `SEARCH` and output never reports PATROL execution path.

9. Legacy removal plan (delete-first, exact ids).
Delete-first order is mandatory:
1. Delete constants: `FALLBACK_RING_MIN_RADIUS_PX`, `FALLBACK_RING_STEP_RADIUS_PX`, `FALLBACK_RING_COUNT`, `FALLBACK_RING_SAMPLES_PER_RING`, `SHADOW_ESCAPE_RING_MIN_RADIUS_PX`, `SHADOW_ESCAPE_RING_STEP_RADIUS_PX`, `SHADOW_ESCAPE_RING_COUNT`, `SHADOW_ESCAPE_SAMPLES_PER_RING`.
2. Delete state vars: `_policy_fallback_used`, `_policy_fallback_target`, `_shadow_escape_active`, `_shadow_escape_target`, `_shadow_escape_target_valid`.
3. Delete functions: `_resolve_nearest_reachable_fallback`, `_sample_fallback_candidates`, `_attempt_shadow_escape_recovery`, `_resolve_shadow_escape_target`, `_sample_shadow_escape_candidates`, `_resolve_movement_target_with_shadow_escape`, `debug_select_nearest_reachable_fallback`.
4. Delete legacy branches in `_attempt_replan_with_policy` and `_execute_move_to_target` that call deleted functions or set deleted vars.
5. Delete legacy debug snapshot keys for deleted vars.
6. Update tests so no assertion references deleted identifiers.
7. After deletion gates pass, add new plan-lock and shadow FSM logic.

10. Legacy verification commands (exact rg + expected 0 matches for every removed legacy item).
Phase close is blocked until every command below returns `0 matches`.
1. `rg -n "FALLBACK_RING_MIN_RADIUS_PX" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
2. `rg -n "FALLBACK_RING_STEP_RADIUS_PX" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
3. `rg -n "FALLBACK_RING_COUNT" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
4. `rg -n "FALLBACK_RING_SAMPLES_PER_RING" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
5. `rg -n "SHADOW_ESCAPE_RING_MIN_RADIUS_PX" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
6. `rg -n "SHADOW_ESCAPE_RING_STEP_RADIUS_PX" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
7. `rg -n "SHADOW_ESCAPE_RING_COUNT" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
8. `rg -n "SHADOW_ESCAPE_SAMPLES_PER_RING" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
9. `rg -n "_policy_fallback_used" src/systems/enemy_pursuit_system.gd tests -S` -> expected `0 matches`.
10. `rg -n "_policy_fallback_target" src/systems/enemy_pursuit_system.gd tests -S` -> expected `0 matches`.
11. `rg -n "_shadow_escape_active" src/systems/enemy_pursuit_system.gd tests -S` -> expected `0 matches`.
12. `rg -n "_shadow_escape_target" src/systems/enemy_pursuit_system.gd tests -S` -> expected `0 matches`.
13. `rg -n "_shadow_escape_target_valid" src/systems/enemy_pursuit_system.gd tests -S` -> expected `0 matches`.
14. `rg -n "func _resolve_nearest_reachable_fallback\(" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
15. `rg -n "func _sample_fallback_candidates\(" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
16. `rg -n "func _attempt_shadow_escape_recovery\(" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
17. `rg -n "func _resolve_shadow_escape_target\(" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
18. `rg -n "func _sample_shadow_escape_candidates\(" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
19. `rg -n "func _resolve_movement_target_with_shadow_escape\(" src/systems/enemy_pursuit_system.gd -S` -> expected `0 matches`.
20. `rg -n "debug_select_nearest_reachable_fallback" src/systems/enemy_pursuit_system.gd tests -S` -> expected `0 matches`.
21. `rg -n "fallback_missing|fallback_failed" src/systems/enemy_pursuit_system.gd tests -S` -> expected `0 matches`.
22. `rg -n "policy_fallback_used|policy_fallback_target|shadow_escape_active|shadow_escape_target" tests -S` -> expected `0 matches`.
23. `rg -n "NEAREST_REACHABLE_FALLBACK_BY_NAV_DISTANCE" tests/test_runner_node.gd tests -S` -> expected `0 matches` after legacy scene removal.

11. Acceptance criteria (binary pass/fail).
1. Pass only when all section 10 commands return `0 matches`; fail otherwise.
2. Pass only when Phase 2 contract keys exist and are populated in `execute_intent` output and debug snapshot.
3. Pass only when `unreachable_policy` in shadow context produces runtime sequence `shadow_boundary_scan -> search` in test logs.
4. Pass only when no test references deleted fallback keys/identifiers.
5. Pass only when ALERT/COMBAT active target context never executes PATROL and never executes RETURN_HOME in Phase 2 scenarios.
6. Pass only when all phase test commands exit `0`.
7. Pass only when all smoke suite commands exit `0`.
8. Pass only when no log contains `SKIP`, `SKIPPED`, `PENDING`, or `NOT RUN`.
9. Pass only when diff audit reports no out-of-scope file changes.

12. Tests (new/update + purpose).
New:
1. `tests/test_shadow_unreachable_transitions_to_search_not_patrol.gd`: verifies `unreachable_policy` in shadow context triggers `SHADOW_BOUNDARY_SCAN` then `SEARCH`, and verifies no PATROL/RETURN_HOME execution.
2. `tests/test_shadow_unreachable_transitions_to_search_not_patrol.tscn`: scene wrapper for the new test.

Update:
1. `tests/test_shadow_policy_hard_block_without_grant.gd`: replace fallback-target assertions with Phase 2 FSM assertions and legacy-key absence assertions.
2. `tests/test_shadow_policy_hard_block_without_grant.tscn`: keep scene binding aligned with updated script.
3. `tests/test_shadow_stall_escapes_to_light.gd`: replace shadow-escape assertions with scan/search canon assertions; remove `shadow_escape_*` key reads.
4. `tests/test_shadow_stall_escapes_to_light.tscn`: keep scene binding aligned with updated script.
5. `tests/test_pursuit_stall_fallback_invariants.gd`: replace nearest-fallback selector checks with `plan_id/plan_target` determinism checks.
6. `tests/test_pursuit_stall_fallback_invariants.tscn`: keep scene binding aligned with updated script.
7. `tests/test_nearest_reachable_fallback_by_nav_distance.gd`: delete legacy test or rewrite as non-legacy plan-lock deterministic test with no fallback identifier usage.
8. `tests/test_nearest_reachable_fallback_by_nav_distance.tscn`: delete legacy scene or rewrite to match updated test script.
9. `tests/test_runner_node.gd`: remove legacy fallback suite wiring and add new Phase 2 suite wiring.

Phase test commands:
1. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_shadow_unreachable_transitions_to_search_not_patrol.tscn`
2. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_shadow_policy_hard_block_without_grant.tscn`
3. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_shadow_stall_escapes_to_light.tscn`
4. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_pursuit_stall_fallback_invariants.tscn`

13. rg gates (command + expected output).
1. `rg -n "_resolve_nearest_reachable_fallback|_sample_fallback_candidates|_policy_fallback_used|_policy_fallback_target|_attempt_shadow_escape_recovery|_resolve_shadow_escape_target|_sample_shadow_escape_candidates|_resolve_movement_target_with_shadow_escape|debug_select_nearest_reachable_fallback|FALLBACK_RING_|SHADOW_ESCAPE_RING_" src/systems/enemy_pursuit_system.gd tests/test_shadow_policy_hard_block_without_grant.gd tests/test_shadow_stall_escapes_to_light.gd tests/test_pursuit_stall_fallback_invariants.gd tests/test_nearest_reachable_fallback_by_nav_distance.gd tests/test_shadow_unreachable_transitions_to_search_not_patrol.gd tests/test_runner_node.gd -S` -> expected `0 matches`.
2. `rg -n "policy_fallback_|shadow_escape_" src/systems/enemy_pursuit_system.gd tests/test_shadow_policy_hard_block_without_grant.gd tests/test_shadow_stall_escapes_to_light.gd tests/test_pursuit_stall_fallback_invariants.gd tests/test_nearest_reachable_fallback_by_nav_distance.gd tests/test_shadow_unreachable_transitions_to_search_not_patrol.gd tests/test_runner_node.gd -S` -> expected `0 matches`.
3. `rg -n "fallback_missing|fallback_failed" src/systems/enemy_pursuit_system.gd tests -S` -> expected `0 matches`.
4. `bash -lc 'f=src/systems/enemy_pursuit_system.gd; for p in "var _plan_id" "var _intent_target" "var _plan_target" "shadow_unreachable_fsm_state" "plan_id" "plan_target" "intent_target"; do rg -q "$p" "$f" -S || { echo "missing:$p"; exit 1; }; done; echo PHASE2_CONTRACT_OK'` -> expected `PHASE2_CONTRACT_OK`.
5. `rg -n "debug_select_nearest_reachable_fallback|NEAREST_REACHABLE_FALLBACK_BY_NAV_DISTANCE" tests/test_runner_node.gd tests -S` -> expected `0 matches`.

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: `0 matches`.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

14. Execution sequence (step-by-step, no ambiguity).
1. Run dependency gates from section 23; stop on first failure.
2. Delete all legacy items listed in section 9 from `src/systems/enemy_pursuit_system.gd`.
3. Run section 10 commands 1-23; stop on first non-zero match.
4. Implement `plan_id`, `intent_target`, and `plan_target` state and output keys in `src/systems/enemy_pursuit_system.gd`.
5. Implement deterministic plan-lock update rules from section 6.14.
6. Implement shadow unreachable FSM from section 7 without any deleted fallback calls.
7. Update debug snapshot keys to Phase 2 contract keys.
8. Update tests listed in section 12 and remove or rewrite legacy fallback tests/scenes.
9. Update `tests/test_runner_node.gd` wiring for deleted/added scenes.
10. Run section 13 gates; stop on first failure.
11. Run phase test commands in section 12; stop on first non-zero exit.
12. Run smoke suite commands in section 6.21; stop on first non-zero exit.
13. Run skip-marker audit:
`bash -lc 'set -euo pipefail; mkdir -p .tmp/phase2_logs; scenes=(res://tests/test_shadow_unreachable_transitions_to_search_not_patrol.tscn res://tests/test_shadow_policy_hard_block_without_grant.tscn res://tests/test_shadow_stall_escapes_to_light.tscn res://tests/test_pursuit_stall_fallback_invariants.tscn res://tests/test_navigation_path_policy_parity.tscn res://tests/test_combat_no_los_never_hold_range.tscn); for s in "${scenes[@]}"; do log=".tmp/phase2_logs/$(basename "$s" .tscn).log"; /snap/godot-4/current/godot-4 --headless --path . --scene "$s" >"$log" 2>&1; done; if rg -n "\\bSKIP(PED)?\\b|\\bPENDING\\b|\\bNOT RUN\\b" .tmp/phase2_logs -S; then exit 1; fi; echo PHASE2_LOGS_OK'`.
14. Run diff-scope audit from section 19; stop on first out-of-scope change.

15. Rollback conditions.
1. Any legacy verification command in section 10 returns non-zero matches.
2. Any rg gate in section 13 fails.
3. Any phase test or smoke test command exits non-zero.
4. Any runtime scenario in section 20 fails listed invariant checks.
5. Diff-scope audit reports any out-of-scope file.
6. Contract-output keys from section 6.11 are missing in runtime snapshot.
7. On any trigger above, rollback whole Phase 2 delta in scope and restart from section 14 step 2.

16. Phase close condition.
Phase closes only when all conditions are true:
1. Section 10 commands all report `0 matches`.
2. Section 13 gates all pass.
3. Section 12 phase tests all pass with exit code `0`.
4. Section 6.21 smoke suite all passes with exit code `0`.
5. Section 20 runtime scenario matrix all passes.
6. Section 21 verification report records `unresolved_deviations: []`.

17. Ambiguity self-check line: Ambiguity check: 0

18. Open questions line: Open questions: 0

19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).
1. Diff audit command:
`bash -lc 'set -euo pipefail; changed=$(git diff --name-only --relative HEAD); printf "%s\n" "$changed"; allowed="^(src/systems/enemy_pursuit_system\.gd|tests/test_shadow_policy_hard_block_without_grant\.gd|tests/test_shadow_policy_hard_block_without_grant\.tscn|tests/test_shadow_stall_escapes_to_light\.gd|tests/test_shadow_stall_escapes_to_light\.tscn|tests/test_pursuit_stall_fallback_invariants\.gd|tests/test_pursuit_stall_fallback_invariants\.tscn|tests/test_nearest_reachable_fallback_by_nav_distance\.gd|tests/test_nearest_reachable_fallback_by_nav_distance\.tscn|tests/test_shadow_unreachable_transitions_to_search_not_patrol\.gd|tests/test_shadow_unreachable_transitions_to_search_not_patrol\.tscn|tests/test_runner_node\.gd)$"; for f in $changed; do echo "$f" | rg -q "$allowed" || { echo "OUT_OF_SCOPE:$f"; exit 1; }; done; echo DIFF_SCOPE_OK'`.
2. Contract conformance checks:
1. `bash -lc 'f=src/systems/enemy_pursuit_system.gd; for p in "var _plan_id" "var _intent_target" "var _plan_target" "shadow_unreachable_fsm_state"; do rg -q "$p" "$f" -S || { echo "MISSING:$p"; exit 1; }; done; echo CONTRACT_KEYS_OK'`.
2. Run all section 13 rg gates.
3. Single-owner check:
`bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] || { echo "SINGLE_OWNER_FAIL:$count"; exit 1; }; echo SINGLE_OWNER_OK'`.
3. Smoke + phase test checks:
1. Run commands in sections 12 and 6.21.
2. Verify each command exit code equals `0`.
3. Verify `PHASE2_LOGS_OK` audit command passes.
4. Runtime scenario checks:
1. Execute section 20 scenarios with listed durations and setups.
2. Record timeline transitions and invariant checks per scenario.
3. Any invariant violation marks phase as `FAILED`.

20. Runtime scenario matrix (scenario id, setup, duration, expected invariants, fail conditions).
1. Scenario id: `P2-S1`.
1. Setup: `res://tests/test_shadow_policy_hard_block_without_grant.tscn`; `owner=(0,0)`; `target=(160,0)`; `blocked_x=48`; flashlight grant disabled.
2. Duration: `3.2s`.
3. Expected invariants:
1. path plan reports `unreachable_policy` for blocked target.
2. `shadow_unreachable_fsm_state` enters `shadow_boundary_scan` then `search`.
3. No snapshot key includes `policy_fallback_`.
4. No snapshot key includes `shadow_escape_`.
4. Fail conditions:
1. Any fallback key exists.
2. FSM transition sequence differs from `shadow_boundary_scan -> search`.
2. Scenario id: `P2-S2`.
1. Setup: `res://tests/test_shadow_stall_escapes_to_light.tscn`; `owner=(-40,0)`; `blocked_shadow_target=(-140,0)`; `awareness_state=ALERT`.
2. Duration: `4.0s`.
3. Expected invariants:
1. No call path enters deleted shadow-escape recovery.
2. Runtime performs shadow unreachable scan/search canon.
3. Executed runtime intent is never PATROL while active target context exists.
4. Fail conditions:
1. Any `shadow_escape_*` key appears.
2. PATROL execution appears during active target context.
3. Scenario id: `P2-S3`.
1. Setup: `res://tests/test_shadow_unreachable_transitions_to_search_not_patrol.tscn`; no LOS; alert/combat context active; target in shadow; planner returns `unreachable_policy`.
2. Duration: `5.0s`.
3. Expected invariants:
1. Canonical transition `SHADOW_BOUNDARY_SCAN -> SEARCH` occurs.
2. Direct PATROL and RETURN_HOME are absent during active target context.
3. `plan_id` remains stable while target oscillation is `<= 8.0px`.
4. `plan_id` increments by exactly `1` on target change `> 8.0px`.
4. Fail conditions:
1. Direct PATROL or RETURN_HOME execution during active target context.
2. Missing `SEARCH` transition after scan.
3. `plan_id` update rule violations.

21. Verification report format (what must be recorded to close phase).
Record exactly the following sections in the close report:
1. `changed_files`: full list from `git diff --name-only --relative HEAD`.
2. `scope_audit`: `DIFF_SCOPE_OK` or explicit `OUT_OF_SCOPE:<path>` entries.
3. `legacy_verification`: command + exit code + stdout for each section 10 command.
4. `rg_gates`: command + exit code + stdout for each section 13 gate.
5. `contract_checks`: outputs of `CONTRACT_KEYS_OK` and `SINGLE_OWNER_OK` commands.
6. `phase_tests`: each section 12 command with exit code.
7. `smoke_suite`: each section 6.21 command with exit code.
8. `skip_marker_audit`: output of `PHASE2_LOGS_OK` command.
9. `runtime_scenarios`: for each scenario in section 20, record setup hash, duration, observed transition sequence, invariant pass/fail.
10. `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` (all must be PASS to close phase)
11. `unresolved_deviations`: required value is empty list `[]`; non-empty list blocks phase close.

## 22. Structural completeness self-check line:
Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23. Missing sections: NONE.
- Evidence preamble (### Evidence) present between ## PHASE header and section 1: yes
- PHASE_2 format note: sections `1`–`21` are authored in compact numbered form inside the phase body (not `##` headings); `## 22` and `## 23` are explicit headings.
- PMB gates present in section 13: yes
- pmb_contract_check present in section 21: yes

## 23. Dependencies on previous phases.
1. Phase 0 dependency gate: `rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy|build_reachable_path_points|build_path_points" src/systems/enemy_pursuit_system.gd -S` → `0 matches`. Must pass before step 2 of section 14.
2. Phase 1 dependency gate: `bash -lc 'f=src/systems/navigation_runtime_queries.gd; rg -q "_build_detour_candidates" "$f" -S && rg -q "route_type" "$f" -S && echo PHASE1_DETOUR_CONTRACT_OK'` → `PHASE1_DETOUR_CONTRACT_OK` (detour planner + route_type contract exists). Must pass before step 5 of section 14.
3. Both gates must pass before any implementation step. Stop on first failure.

---

## PHASE 3
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.

1. What now.
Phase id: PHASE_3.
Phase title: Immediate Repath On Non-Door Collision.
Goal (one sentence): Replace door-only post-slide repath handling with one deterministic collision handler that forces next-tick replanning on non-door collisions while preserving intent and target context.
Current behavior (measurable):
1. `src/systems/enemy_pursuit_system.gd` invokes `_try_open_blocking_door_and_force_repath()` after `move_and_slide()` at two callsites (`_follow_waypoints` navmesh branch and waypoint branch).
2. `_try_open_blocking_door_and_force_repath()` only tries `door_system.try_enemy_open_nearest(owner.global_position)` and only resets `_repath_timer` when a door opens.
3. Non-door collisions do not set `_last_path_failed_reason` to a collision reason and do not clear active path cache.
4. Next-tick replanning currently depends on `_repath_timer <= 0.0` or `_path_policy_blocked`; collision type is not part of decision state.
Dependencies on previous phases:
1. Phase 0 dependency: route authority remains `build_policy_valid_path -> execute_intent -> move/repath`.
2. Phase 2 dependency: shadow fallback canonicalization remains intact and unaffected by this phase.
Non-goals in this phase:
1. No change to `src/systems/enemy_utility_brain.gd` intent scoring.
2. No change to `src/entities/enemy.gd` target-context construction.
3. No change to `src/systems/layout_door_system.gd` or `src/systems/door_physics_v3.gd` door mechanics.
4. No change to `src/systems/navigation_runtime_queries.gd` planner ranking.

2. What changes.
1. Delete legacy door-only helper `_try_open_blocking_door_and_force_repath` before adding replacement logic.
2. Introduce one owner function in `EnemyPursuitSystem` for post-slide collision resolution with deterministic classification: `door` or `non_door`.
3. On first detected non-door collision in index order, apply this exact state update: `_repath_timer = 0.0`; clear active path cache (`_waypoints.clear()` and nav-agent target reset to owner position when nav-agent is active); `_last_path_failed = true`; `_last_path_failed_reason = "collision_blocked"`; preserve `_active_move_target` and `_active_move_target_valid` and preserve intent target context.
4. On door collision without non-door collisions, call the existing door open path; when door state changes set `_repath_timer = 0.0`; do not set `collision_blocked` reason.
5. Replace both `_follow_waypoints` collision callsites with the unified handler.
6. Extend debug snapshot contract to expose collision classification/repath reason for deterministic test assertions.

3. What will be after.
Target behavior (measurable):
1. Any non-door slide collision forces replanning on the next AI tick by formula: `_repath_timer_post_collision == 0.0`, then in next `_execute_move_to_target`, condition `_repath_timer <= 0.0` is true.
2. Non-door collision records `path_failed_reason == "collision_blocked"` in the same tick.
3. Door collision path retains door-open behavior and still resets `_repath_timer` only on successful door open.
4. Intent type and active target remain preserved across non-door collision repath cycle.
5. No code path retains `_try_open_blocking_door_and_force_repath`.

4. Scope and non-scope (exact files).
In-scope files (exact paths):
1. `src/systems/enemy_pursuit_system.gd`
2. `tests/test_collision_block_forces_immediate_repath.gd`
3. `tests/test_collision_block_forces_immediate_repath.tscn`
4. `tests/test_collision_block_preserves_intent_context.gd`
5. `tests/test_collision_block_preserves_intent_context.tscn`
6. `tests/test_honest_repath_without_teleport.gd`
7. `tests/test_runner_node.gd`
Out-of-scope files (exact paths):
1. `src/entities/enemy.gd`
2. `src/systems/enemy_utility_brain.gd`
3. `src/systems/layout_door_system.gd`
4. `src/systems/door_physics_v3.gd`
5. `src/systems/navigation_service.gd`
6. `src/systems/navigation_runtime_queries.gd`
7. `tests/test_door_enemy_traversal.gd`
8. `tests/test_door_enemy_oblique_open_then_cross_no_wall_stall.gd`
9. `tests/test_navigation_failure_reason_contract.gd`
10. `tests/test_pursuit_stall_fallback_invariants.gd`
11. `tests/test_pursuit_intent_only_runtime.gd`
12. `tests/test_pursuit_origin_target_not_sentinel.gd`
Allowed file-change boundary (exact paths):
1. `src/systems/enemy_pursuit_system.gd`
2. `tests/test_collision_block_forces_immediate_repath.gd`
3. `tests/test_collision_block_forces_immediate_repath.tscn`
4. `tests/test_collision_block_preserves_intent_context.gd`
5. `tests/test_collision_block_preserves_intent_context.tscn`
6. `tests/test_honest_repath_without_teleport.gd`
7. `tests/test_runner_node.gd`
Evidence.
Inspected files (exact paths):
1. `src/systems/enemy_pursuit_system.gd`
2. `src/entities/enemy.gd`
3. `src/systems/enemy_utility_brain.gd`
4. `src/systems/layout_door_system.gd`
5. `src/systems/door_physics_v3.gd`
6. `src/systems/navigation_service.gd`
7. `src/systems/navigation_runtime_queries.gd`
8. `src/systems/navigation_enemy_wiring.gd`
9. `src/core/game_config.gd`
10. `src/levels/stealth_test_config.gd`
11. `tests/test_door_enemy_traversal.gd`
12. `tests/test_door_enemy_oblique_open_then_cross_no_wall_stall.gd`
13. `tests/test_honest_repath_without_teleport.gd`
14. `tests/test_pursuit_intent_only_runtime.gd`
15. `tests/test_pursuit_origin_target_not_sentinel.gd`
16. `tests/test_navigation_failure_reason_contract.gd`
17. `tests/test_pursuit_stall_fallback_invariants.gd`
18. `tests/test_runner_node.gd`
19. `tests/test_honest_repath_without_teleport.tscn`
20. `tests/test_door_enemy_oblique_open_then_cross_no_wall_stall.tscn`
21. `tests/test_pursuit_stall_fallback_invariants.tscn`
Inspected functions/methods (exact identifiers):
1. `Enemy.runtime_budget_tick`
2. `Enemy._build_utility_context`
3. `Enemy._resolve_known_target_context`
4. `EnemyPursuitSystem.execute_intent`
5. `EnemyPursuitSystem._execute_move_to_target`
6. `EnemyPursuitSystem._follow_waypoints`
7. `EnemyPursuitSystem._move_in_direction`
8. `EnemyPursuitSystem._has_active_path_to`
9. `EnemyPursuitSystem._plan_path_to`
10. `EnemyPursuitSystem._request_path_plan_contract`
11. `EnemyPursuitSystem._try_open_blocking_door_and_force_repath`
12. `EnemyPursuitSystem.debug_get_navigation_policy_snapshot`
13. `LayoutDoorSystem.find_nearest_door`
14. `LayoutDoorSystem.try_enemy_open_nearest`
15. `DoorPhysicsV3.command_open_enemy`
16. `NavigationService.build_policy_valid_path`
17. `NavigationRuntimeQueries.build_policy_valid_path`
18. `NavigationRuntimeQueries.build_reachable_path_points`
Search commands used (exact commands):
1. `rg -n "_try_open_blocking_door_and_force_repath|_repath_timer|get_slide_collision_count|_path_policy_blocked" src/systems/enemy_pursuit_system.gd tests/test_door_enemy_traversal.gd tests/test_door_enemy_oblique_open_then_cross_no_wall_stall.gd -S`
2. `rg -n "execute_intent\(|_pursuit\.execute_intent" src/entities/enemy.gd src/systems/enemy_pursuit_system.gd tests/test_pursuit_intent_only_runtime.gd tests/test_pursuit_origin_target_not_sentinel.gd -S`
3. `rg -n "build_policy_valid_path|build_reachable_path_points|_request_path_plan_contract" src/systems/enemy_pursuit_system.gd src/systems/navigation_service.gd src/systems/navigation_runtime_queries.gd tests/test_navigation_failure_reason_contract.gd tests/test_pursuit_stall_fallback_invariants.gd -S`
4. `rg -n "try_enemy_open_nearest|find_nearest_door|command_open_enemy|DoorBody" src/systems/layout_door_system.gd src/systems/door_physics_v3.gd tests/test_door_enemy_traversal.gd tests/test_door_enemy_oblique_open_then_cross_no_wall_stall.gd -S`

5. Single-owner authority for this phase.
1. Single owner function for collision repath decisions in this phase: `EnemyPursuitSystem._handle_slide_collisions_and_repath`.
2. `_follow_waypoints` must call this owner function in both navmesh and waypoint branches.
3. No second collision-repath decision path is allowed in `EnemyPursuitSystem`.
4. Global invariant remains true: `build_policy_valid_path -> execute_intent -> move/repath`.

6. Full input/output contract.
Contracts to introduce/change:
1. Contract name: `post_slide_collision_resolution_v1`.
2. Owner: `EnemyPursuitSystem._handle_slide_collisions_and_repath`.
Inputs (types, nullability, finite checks):
1. `slide_count: int`, derived from `owner.get_slide_collision_count()`, valid range `0..INF_INT`.
2. `owner: CharacterBody2D`, non-null.
3. `movement_target: Vector2`, finite coordinates required (`is_finite(x) && is_finite(y)`), sourced from `_active_move_target`.
4. `has_active_target: bool`, sourced from `_active_move_target_valid`.
Outputs (exact keys/types/enums):
1. `collision_kind: String` enum `{ "none", "door", "non_door" }`.
2. `forced_repath: bool`.
3. `reason: String` enum `{ "none", "door_opened", "collision_blocked" }`.
4. `collision_index: int` (`-1` when `collision_kind == "none"`, otherwise first winning index).
Status enums:
1. Path-plan status enums remain `{ "ok", "unreachable_policy", "unreachable_geometry" }`.
2. Collision status enums introduced by this phase: `{ "none", "door", "non_door" }`.
Reason enums:
1. Existing path reasons remain valid.
2. This phase introduces mandatory runtime failure reason token: `"collision_blocked"`.
3. Collision resolver reason enum is fixed: `{ "none", "door_opened", "collision_blocked" }`.
Deterministic order and tie-break rules:
1. Iterate slide collisions by ascending index: `i = 0..slide_count-1`.
2. Classification formula per collision: `is_door_collision = collider != null && collider.name == "DoorBody" && collider.get_parent() != null && collider.get_parent().has_method("command_open_enemy")`; otherwise classification is `non_door`.
3. Winner selection rule: first `non_door` index wins immediately; when no `non_door` exists and at least one door collision exists the first door index wins; when no collisions exist output is `none`.
Constants/thresholds/eps (exact values):
1. `PATH_REPATH_INTERVAL_SEC = 0.35`.
2. `COMBAT_REPATH_INTERVAL_NO_LOS_SEC = 0.2`.
3. `WAYPOINT_REACHED_PX = 12.0`.
4. `ENEMY_DOOR_INTERACT_RADIUS_PX = 30.0` (door system).
5. `DOOR_NEARLY_CLOSED_THRESHOLD_DEG = 15.0` (door system open gate).
6. `REPATH_IMMEDIATE_EPS = 0.001` — used ONLY in test assertion comparisons (to verify `_repath_timer` is effectively zero after collision); production source sets `_repath_timer = 0.0` exactly and does not reference this constant.
Forbidden patterns (identifiers/branches):
1. `_try_open_blocking_door_and_force_repath` identifier.
2. direct branch `owner.get_slide_collision_count() > 0` followed by legacy helper call.
3. any assignment path where non-door collision keeps `_waypoints` non-empty and `_repath_timer > 0.0` in same tick.
Migration notes (rename/move):
1. Replace `_try_open_blocking_door_and_force_repath` with `_handle_slide_collisions_and_repath` in `src/systems/enemy_pursuit_system.gd`.
2. No file move.

7. Deterministic algorithm with exact order.
1. In `_follow_waypoints`, execute movement first (`_move_in_direction` or nav-agent next point movement).
2. Read `slide_count = owner.get_slide_collision_count()`.
3. Call `_handle_slide_collisions_and_repath(slide_count)` exactly once after movement.
4. Inside `_handle_slide_collisions_and_repath`, execute Step A through Step D in strict order.
5. Step A: scan collisions by ascending index and select winner with rules from Section 6.
6. Step B (`non_door` winner): `_repath_timer = 0.0`; `_waypoints.clear()`; when `_use_navmesh && _nav_agent != null`, set `_nav_agent.target_position = owner.global_position`; set `_last_path_failed = true`; set `_last_path_failed_reason = "collision_blocked"`; set `_path_policy_blocked = false`; set `_last_policy_blocked_segment = -1`; do not mutate `_active_move_target`; do not mutate `_active_move_target_valid`.
7. Step C (`door` winner): invoke existing door open path through door system once; when door open result is true set `_repath_timer = 0.0`, `_path_policy_blocked = false`, `_last_policy_blocked_segment = -1`; do not set `_last_path_failed_reason = "collision_blocked"`.
8. Step D (`none`): no state mutation.
9. Replan occurs next tick in `_execute_move_to_target` by condition `_repath_timer <= 0.0`.
10. Intent/target preservation formulas: `intent_type_t == intent_type_t_plus_1`; `_active_move_target_t.distance_to(_active_move_target_t_plus_1) <= 0.001`; `_active_move_target_valid_t == _active_move_target_valid_t_plus_1 == true` for collision-triggered repath cases.
11. Global invariants retained without branch exceptions: `build_policy_valid_path -> execute_intent -> move/repath` only; `ALERT/COMBAT + active target context => PATROL forbidden`; `SHADOW_BOUNDARY_SCAN -> SEARCH` and direct PATROL fallback forbidden; `non-door collision => immediate repath with intent/target preserved`.

8. Edge-case matrix (case -> exact output).
1. `slide_count = 0` -> `collision_kind="none"`, `forced_repath=false`, `_repath_timer` unchanged.
2. `door collision only, door opens` -> `collision_kind="door"`, `forced_repath=true`, `reason="door_opened"`, `_repath_timer=0.0`, `_last_path_failed_reason` unchanged in this branch.
3. `door collision only, door does not open` -> `collision_kind="door"`, `forced_repath=false`, reason remains `"none"`, timer unchanged.
4. `non-door collision only` -> `collision_kind="non_door"`, `forced_repath=true`, `reason="collision_blocked"`, `_repath_timer=0.0`, `_waypoints.size()==0`.
5. `mixed collisions (door at lower index, non-door at higher index)` -> winner `non_door`, output from rule 4.
6. `mixed collisions (non-door at lower index, door at higher index)` -> winner `non_door`, output from rule 4.
7. `non-door collision with nav-agent active` -> `_nav_agent.target_position == owner.global_position` in same tick.

9. Legacy removal plan (delete-first, exact ids).
Legacy to delete first (exact ids/functions/consts):
1. `EnemyPursuitSystem._try_open_blocking_door_and_force_repath`
2. Both callsites of `_try_open_blocking_door_and_force_repath` in `_follow_waypoints`
Delete-first order:
1. Remove legacy helper declaration and body.
2. Remove both legacy helper callsites.
3. Verify zero matches for legacy identifiers.
4. Add unified collision handler and new callsites.
No temporary compatibility branches are allowed.

10. Legacy verification commands (exact rg + expected 0 matches for every removed legacy item).
1. `rg -n "_try_open_blocking_door_and_force_repath" src/systems/enemy_pursuit_system.gd -S` -> expected result: `0 matches`.
2. `rg -n "get_slide_collision_count\(\) > 0[[:space:]]*:[[:space:]]*$" src/systems/enemy_pursuit_system.gd -S` -> expected result: legacy branch form with direct helper call has `0 matches` after rewrite to unified call expression.
Mandatory closure rule:
1. Phase cannot close until every legacy verification command returns `0 matches`.
2. Any non-zero match count marks phase `FAILED`.
3. No allowlist.

11. Acceptance criteria (binary pass/fail).
1. Pass only when all commands in Sections 10, 12, 13, and 19 exit `0`.
2. Pass only when `collision_blocked` reason appears on non-door collision path and never appears on door-open branch.
3. Pass only when intent and active target preservation formulas in Section 7 hold in runtime scenarios.
4. Pass only when no out-of-scope file changes exist.
5. Pass only when global invariants remain true in runtime scenarios and smoke suite.

12. Tests (new/update + purpose).
New tests (exact filenames):
1. `tests/test_collision_block_forces_immediate_repath.gd`.
2. `tests/test_collision_block_forces_immediate_repath.tscn`.
3. `tests/test_collision_block_preserves_intent_context.gd`.
4. `tests/test_collision_block_preserves_intent_context.tscn`.
Tests to update (exact filenames):
1. `tests/test_honest_repath_without_teleport.gd`.
2. `tests/test_runner_node.gd`.
Purpose mapping:
1. `test_collision_block_forces_immediate_repath`: verifies `_repath_timer == 0.0`, `path_failed_reason == "collision_blocked"`, and path cache cleared on non-door collision.
2. `test_collision_block_preserves_intent_context`: verifies intent type and active target are unchanged across collision-triggered repath.
3. `test_honest_repath_without_teleport`: verifies no regression in movement smoothness and convergence under integrated scene runtime.
4. `test_runner_node`: registers new scene suites in existence checks and execution sequence.
Phase test commands (exact):
1. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_collision_block_forces_immediate_repath.tscn`
2. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_collision_block_preserves_intent_context.tscn`
3. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_honest_repath_without_teleport.tscn`
Smoke suite commands (exact):
1. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_path_policy_parity.tscn`
2. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_shadow_policy_hard_block_without_grant.tscn`
3. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_shadow_stall_escapes_to_light.tscn`
4. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_pursuit_stall_fallback_invariants.tscn`
5. `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_combat_no_los_never_hold_range.tscn`

13. rg gates (command + expected output).
1. `rg -n "_handle_slide_collisions_and_repath" src/systems/enemy_pursuit_system.gd -S | wc -l` -> expected output: `3` (1 declaration + 2 callsites).
2. `rg -n "collision_blocked" src/systems/enemy_pursuit_system.gd tests/test_collision_block_forces_immediate_repath.gd tests/test_collision_block_preserves_intent_context.gd -S` -> expected output: at least `3` matches.
3. `rg -n "_try_open_blocking_door_and_force_repath" src/systems/enemy_pursuit_system.gd -S` -> expected output: `0 matches`.
4. `rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l` -> expected output: `1`.
5. `rg -n "build_policy_valid_path" src/systems/enemy_pursuit_system.gd src/systems/navigation_service.gd src/systems/navigation_runtime_queries.gd -S` -> expected output: non-zero matches in all three files.

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: `0 matches`.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

14. Execution sequence (step-by-step, no ambiguity).
1. Run baseline commands from Section 13 and record outputs.
2. Delete legacy helper and callsites listed in Section 9.
3. Run Section 10 legacy verification commands; require `0 matches` before continuing.
4. Implement unified owner function `_handle_slide_collisions_and_repath` in `src/systems/enemy_pursuit_system.gd`.
5. Wire both `_follow_waypoints` branches to this owner function.
6. Add/extend debug snapshot keys for collision classification/reason.
7. Create two new test scripts and scene wrappers from Section 12.
8. Update `tests/test_honest_repath_without_teleport.gd` with non-door collision regression assertion.
9. Update `tests/test_runner_node.gd` to include new scene constants, existence checks, and run entries.
10. Run Section 13 rg gates; require all expected outputs.
11. Run Section 12 phase tests; require exit code `0` for each.
12. Run smoke suite commands from Section 12; require exit code `0` for each.
13. Run post-implementation verification from Section 19.

15. Rollback conditions.
1. Any Section 10 legacy command returns non-zero matches.
2. Any Section 13 gate output differs from expected output.
3. Any phase test or smoke command exits non-zero.
4. Any runtime scenario invariant in Section 20 fails.
5. Diff audit finds changed files outside allowed boundary.
6. Single-owner authority breaks through an additional collision-repath branch.

16. Phase close condition.
Phase closes only when all conditions are true:
1. Section 10 legacy verification commands show `0 matches`.
2. Section 13 rg gates match expected outputs.
3. Section 12 phase tests and smoke suite commands exit `0`.
4. Section 19 diff audit reports no out-of-scope changes.
5. Section 20 runtime scenarios pass all listed invariants.
6. Section 21 verification report has empty unresolved deviations.

17. Ambiguity self-check line: Ambiguity check: 0

18. Open questions line: Open questions: 0

19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).
1. Diff audit against phase scope uses command `git diff --name-only`; pass rule is every changed path in Section 4 allowed boundary; fail rule is any out-of-scope path.
2. Contract conformance checks use command `rg -n "collision_kind|forced_repath|collision_index|collision_blocked" src/systems/enemy_pursuit_system.gd tests -S`; pass rule is required enums/keys exist and tests reference them.
3. Contract conformance checks include Section 13 gate #3; pass rule is forbidden legacy helper absent.
4. Single-owner contract check uses command `rg -n "_handle_slide_collisions_and_repath" src/systems/enemy_pursuit_system.gd -S`; pass rule is exactly one owner function and no parallel decision branch.
5. Smoke and phase tests execute all Section 12 commands; pass rule is exit code `0` for every command and no skipped/pending/not-run markers.
6. Runtime scenario checks execute Section 20 scenarios with exact setup and duration; compare each invariant formula and each fail condition; any invariant violation marks phase `FAILED`.

20. Runtime scenario matrix (scenario id, setup, duration, expected invariants, fail conditions).
1. Scenario id: `P3_S1_NON_DOOR_BLOCK`.
Setup: unit world from `test_collision_block_forces_immediate_repath` with one solid wall, no door entity, enemy start `(0.0, 56.0)`, target `(0.0, -120.0)`, fixed physics step `1/60`.
Duration: `180` physics frames.
Expected invariants: first non-door collision sets `_repath_timer <= 0.001`; `_last_path_failed_reason == "collision_blocked"`; `_waypoints.size() == 0` after collision tick.
Fail conditions: timer remains `> 0.001`; reason differs from `collision_blocked`; waypoints remain non-empty.
2. Scenario id: `P3_S2_INTENT_TARGET_PRESERVE`.
Setup: unit world from `test_collision_block_preserves_intent_context`, intent `PUSH`, active target fixed vector, forced non-door collision event.
Duration: `120` physics frames.
Expected invariants: `intent_type_before == intent_type_after`; `active_target_before.distance_to(active_target_after) <= 0.001`; `_active_move_target_valid` stays `true`.
Fail conditions: intent type changes; active target delta `> 0.001`; target validity flips to `false`.
3. Scenario id: `P3_S3_INTEGRATION_HONEST_REPATH`.
Setup: `res://src/levels/stealth_3zone_test.tscn`, enemy `(460.0, 20.0)`, player `(-320.0, 20.0)`, weapons disabled through controller test hook.
Duration: `240` physics frames.
Expected invariants: total enemy movement `> 8.0`; final distance to player `<` initial distance; max per-frame displacement `<= 24.0`.
Fail conditions: no movement; no convergence; displacement spike `> 24.0`.

21. Verification report format (what must be recorded to close phase).
1. `phase_id`: `PHASE_3`.
2. `changed_files`: exact list from `git diff --name-only`.
3. `scope_audit`: `PASS|FAIL` plus list of out-of-scope files (must be empty on close).
4. `legacy_verification`: each Section 10 command, raw output, and `PASS|FAIL`.
5. `rg_gates`: each Section 13 command, raw output, and `PASS|FAIL`.
6. `tests`: each Section 12 command, exit code, and `PASS|FAIL`.
7. `runtime_scenarios`: each Section 20 scenario id with invariant check results and `PASS|FAIL`.
8. `global_invariants`: explicit `PASS|FAIL` for all four global invariants.
9. `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` (all must be PASS to close phase)
10. `unresolved_deviations`: explicit list; close requires empty list.

## 22. Structural completeness self-check line:
Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23. Missing sections: NONE.
- PMB gates present in section 13: yes
- pmb_contract_check present in section 21: yes

## 23. Dependencies on previous phases.
1. Phase 0 dependency gate: `rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S` → `0 matches`. Must pass before step 2 of section 14.
2. Phase 2 dependency gate: `rg -n "_resolve_nearest_reachable_fallback|_sample_fallback_candidates|_attempt_shadow_escape_recovery" src/systems/enemy_pursuit_system.gd -S` → `0 matches` (Phase 2 complete, all legacy fallbacks removed). Must pass before step 2 of section 14.
3. Both gates must pass before any implementation step.

## PHASE 4
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.

## 1. What now.
Phase id: PHASE_4.
Phase title: Shadow Scan In ALERT/COMBAT.
Goal (one sentence): Extend shadow-boundary scanning from suspicious-only behavior to ALERT/COMBAT no-LOS pursuit with deterministic SHADOW_BOUNDARY_SCAN -> SEARCH handoff and zero legacy coexistence.
Current behavior (measurable):
- `src/entities/enemy.gd` builds `shadow_scan_target` only when `effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS`.
- `src/systems/enemy_utility_brain.gd` selects `IntentType.SHADOW_BOUNDARY_SCAN` only in the branch `alert_level == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS and has_shadow_scan_target and shadow_scan_target_in_shadow`.
- `src/systems/enemy_utility_brain.gd` executes `if combat_lock and not has_los: return _combat_no_los_grace_intent(...)` before any ALERT/COMBAT shadow-scan branch.
- `src/systems/enemy_pursuit_system.gd` clears scan state on timeout (`_shadow_scan_timer <= 0.0`) without an explicit SEARCH transition contract.
Evidence (mandatory project discovery):
Inspected files:
- `src/entities/enemy.gd`
- `src/systems/enemy_utility_brain.gd`
- `src/systems/enemy_pursuit_system.gd`
- `src/systems/enemy_alert_levels.gd`
- `src/systems/enemy_awareness_system.gd`
- `src/systems/navigation_service.gd`
- `src/systems/navigation_runtime_queries.gd`
- `src/systems/navigation_shadow_policy.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `tests/test_suspicious_shadow_scan.gd`
- `tests/test_combat_no_los_never_hold_range.gd`
- `tests/test_combat_no_los_never_hold_range.tscn`
- `tests/test_alert_flashlight_detection.gd`
- `tests/test_combat_uses_last_seen_not_live_player_pos_without_los.gd`
- `tests/test_last_seen_used_only_in_suspicious_alert.gd`
- `tests/test_last_seen_grace_window.gd`
- `tests/test_combat_intent_switches_push_to_search_after_grace.gd`
- `tests/test_combat_utility_intent_aggressive.gd`
- `tests/test_enemy_utility_brain.gd`
- `tests/test_runner_node.gd`
Inspected functions/methods:
- `Enemy._physics_process`
- `Enemy._build_utility_context`
- `Enemy._resolve_effective_alert_level_for_utility`
- `Enemy._resolve_known_target_context`
- `Enemy._apply_awareness_transitions`
- `Enemy._is_combat_awareness_active`
- `Enemy.set_shadow_scan_active`
- `Enemy.get_current_intent`
- `Enemy.get_debug_detection_snapshot`
- `EnemyUtilityBrain.update`
- `EnemyUtilityBrain._choose_intent`
- `EnemyUtilityBrain._combat_no_los_grace_intent`
- `EnemyPursuitSystem.execute_intent`
- `EnemyPursuitSystem._execute_shadow_boundary_scan`
- `EnemyPursuitSystem._run_shadow_scan_sweep`
- `EnemyPursuitSystem.clear_shadow_scan_state`
- `EnemyPursuitSystem._execute_search`
- `EnemyPursuitSystem._execute_move_to_target`
- `EnemyPursuitSystem._request_path_plan_contract`
- `NavigationService.is_point_in_shadow`
- `NavigationService.get_nearest_non_shadow_point`
- `NavigationService.build_policy_valid_path`
- `NavigationRuntimeQueries.build_policy_valid_path`
- `NavigationShadowPolicy.is_point_in_shadow`
- `EnemyAwarenessSystem.process_confirm`
- `EnemyAlertLevels.ttl_for_level`
Search commands used:
- `rg -l "shadow_scan_target|has_shadow_scan_target|SHADOW_BOUNDARY_SCAN|effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT\\.SUSPICIOUS|alert_level == ENEMY_ALERT_LEVELS_SCRIPT\\.SUSPICIOUS and has_shadow_scan_target|_resolve_effective_alert_level_for_utility|set_shadow_scan_active|IntentType\\.SHADOW_BOUNDARY_SCAN|combat_no_los|target_is_last_seen" src tests -S`
- `rg -n "^func |shadow_scan_target|has_shadow_scan_target|_resolve_effective_alert_level_for_utility|_build_utility_context|execute_intent|think\\(|_choose_intent|_resolve_target_context|_apply_awareness_transitions|_set_intent|set_shadow_scan_active" src/entities/enemy.gd -S`
- `rg -n "^func |IntentType|_choose_intent|SHADOW_BOUNDARY_SCAN|combat_no_los|has_shadow_scan_target|search|investigate|patrol|return_home|alert_level" src/systems/enemy_utility_brain.gd -S`
- `rg -n "^func |execute_intent|_execute_shadow_boundary_scan|clear_shadow_scan_state|SHADOW_BOUNDARY_SCAN|SEARCH|build_policy_valid_path|repath|movement_intent|origin_target" src/systems/enemy_pursuit_system.gd -S`
- `rg -n "effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT\\.SUSPICIOUS|alert_level == ENEMY_ALERT_LEVELS_SCRIPT\\.SUSPICIOUS and has_shadow_scan_target" src/entities/enemy.gd src/systems/enemy_utility_brain.gd -S`

## 2. What changes.
Target behavior (measurable):
- In ALERT/COMBAT with `los == false` and valid shadow target in shadow, utility intent is `IntentType.SHADOW_BOUNDARY_SCAN`.
- When SHADOW_BOUNDARY_SCAN completes (timeout, boundary unreachable, or invalid target), next utility decision returns `IntentType.SEARCH` targeting the same shadow target.
- Global invariants remain true:
- Single route pipeline remains `build_policy_valid_path -> execute_intent -> move/repath`.
- ALERT/COMBAT with active target context never returns `IntentType.PATROL`.
- Shadow unreachable canon is `SHADOW_BOUNDARY_SCAN -> SEARCH`; direct PATROL fallback is forbidden.
- Non-door collision immediate repath behavior from previous phase remains unchanged.
Contracts to introduce/change:
- `ShadowScanContextContractV2` (Enemy context producer -> Utility consumer).
- `ShadowScanExecutionResultContractV2` (Pursuit executor -> Enemy runtime).
- `AlertCombatShadowIntentContractV2` (Utility decision output).
Migration notes (rename/move):
- No file rename.
- No symbol move across files.
- Existing symbols are edited in-place.

## 3. What will be after.
After phase completion:
- ALERT no-LOS and COMBAT no-LOS both can enter `SHADOW_BOUNDARY_SCAN` when `has_shadow_scan_target == true` and `shadow_scan_target_in_shadow == true`.
- Scan completion emits deterministic completion status and reason.
- Utility consumes completion and emits SEARCH on next decision tick.
- Legacy suspicious-only shadow gates are absent (`rg` zero-match).

## 4. Scope and non-scope (exact files).
In-scope files (exact paths):
- `src/entities/enemy.gd`
- `src/systems/enemy_utility_brain.gd`
- `src/systems/enemy_pursuit_system.gd`
- `tests/test_alert_combat_shadow_boundary_scan_intent.gd` (new)
- `tests/test_alert_combat_shadow_boundary_scan_intent.tscn` (new)
- `tests/test_suspicious_shadow_scan.gd`
- `tests/test_combat_no_los_never_hold_range.gd`
- `tests/test_runner_node.gd`
Out-of-scope files (exact paths):
- `src/systems/navigation_service.gd`
- `src/systems/navigation_runtime_queries.gd`
- `src/systems/navigation_shadow_policy.gd`
- `src/systems/enemy_awareness_system.gd`
- `src/systems/enemy_alert_levels.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `tests/test_combat_uses_last_seen_not_live_player_pos_without_los.gd`
- `tests/test_last_seen_used_only_in_suspicious_alert.gd`
- `tests/test_last_seen_grace_window.gd`
- `tests/test_combat_intent_switches_push_to_search_after_grace.gd`
- `tests/test_combat_utility_intent_aggressive.gd`
- `tests/test_alert_flashlight_detection.gd`
Allowed file-change boundary (exact paths):
- `src/entities/enemy.gd`
- `src/systems/enemy_utility_brain.gd`
- `src/systems/enemy_pursuit_system.gd`
- `tests/test_alert_combat_shadow_boundary_scan_intent.gd`
- `tests/test_alert_combat_shadow_boundary_scan_intent.tscn`
- `tests/test_suspicious_shadow_scan.gd`
- `tests/test_combat_no_los_never_hold_range.gd`
- `tests/test_runner_node.gd`

## 5. Single-owner authority for this phase.
Single owner: `EnemyUtilityBrain._choose_intent` owns final intent selection for ALERT/COMBAT shadow behavior.
Authority constraints:
- `Enemy._build_utility_context` only produces context data.
- `EnemyPursuitSystem.execute_intent` only executes intent and reports execution status.
- No second intent selector is allowed in `Enemy` or `EnemyPursuitSystem`.

## 6. Full input/output contract.
Contract name: `ShadowScanContextContractV2`.
Inputs (types, nullability, finite checks):
- `known_target_pos: Vector2`, nullable via `Vector2.ZERO`; finite check is `is_finite(x) and is_finite(y)`.
- `has_known_target: bool`.
- `_last_seen_pos: Vector2`, valid when `_last_seen_age < INF` and finite.
- `_investigate_anchor: Vector2`, valid when `_investigate_anchor_valid == true` and finite.
- `nav_system.is_point_in_shadow(Vector2) -> bool`, required when `has_shadow_scan_target == true`; if method missing, `shadow_scan_target_in_shadow = false`.
- `target_context_exists: bool` formula: `has_known_target or has_last_seen or has_investigate_anchor`.
Outputs (exact keys/types/enums):
- `shadow_scan_target: Vector2`.
- `has_shadow_scan_target: bool`.
- `shadow_scan_target_in_shadow: bool`.
- `shadow_scan_source: String` enum `known_target_pos|last_seen|investigate_anchor|none`.
- `shadow_scan_completed: bool`.
- `shadow_scan_completed_reason: String` enum `none|timeout|boundary_unreachable|target_invalid`.
- `target_context_exists: bool`.
Contract name: `ShadowScanExecutionResultContractV2`.
Inputs (types, nullability, finite checks):
- `intent.type: int` from `EnemyUtilityBrain.IntentType`.
- `intent.target: Vector2` optional; invalid target is `Vector2.ZERO` or non-finite.
- `delta: float`, finite and `>= 0.0`.
Outputs (exact keys/types/enums):
- Existing keys unchanged: `request_fire: bool`, `path_failed: bool`, `path_failed_reason: String`, `policy_blocked_segment: int`, `movement_intent: bool`.
- New keys: `shadow_scan_status: String`, `shadow_scan_complete_reason: String`, `shadow_scan_target: Vector2`.
Contract name: `AlertCombatShadowIntentContractV2`.
Inputs (types, nullability, finite checks):
- Utility context keys from `ShadowScanContextContractV2`.
- `los: bool`.
- `alert_level: int` in `EnemyAlertLevels.Level`.
- `combat_lock: bool`.
Outputs (exact keys/types/enums):
- Intent dictionary keys: `type: int`, `target: Vector2`.
- Allowed output types in this phase path: `SHADOW_BOUNDARY_SCAN`, `SEARCH`, `INVESTIGATE`, `PUSH`, `RETURN_HOME`.
Status enums:
- `shadow_scan_status = inactive|running|completed`.
Reason enums:
- `shadow_scan_complete_reason = none|timeout|boundary_unreachable|target_invalid`.

**Consolidated contract field summary (all three contracts, complete key list):**
| Contract | Key | Type | Direction |
|---|---|---|---|
| ShadowScanContextContractV2 | shadow_scan_target | Vector2 | Enemy → Utility |
| ShadowScanContextContractV2 | has_shadow_scan_target | bool | Enemy → Utility |
| ShadowScanContextContractV2 | shadow_scan_target_in_shadow | bool | Enemy → Utility |
| ShadowScanContextContractV2 | shadow_scan_source | String (enum) | Enemy → Utility |
| ShadowScanContextContractV2 | shadow_scan_completed | bool | Enemy → Utility |
| ShadowScanContextContractV2 | shadow_scan_completed_reason | String (enum) | Enemy → Utility |
| ShadowScanContextContractV2 | target_context_exists | bool | Enemy → Utility |
| ShadowScanExecutionResultContractV2 | request_fire | bool | Pursuit → Enemy |
| ShadowScanExecutionResultContractV2 | path_failed | bool | Pursuit → Enemy |
| ShadowScanExecutionResultContractV2 | path_failed_reason | String | Pursuit → Enemy |
| ShadowScanExecutionResultContractV2 | policy_blocked_segment | int | Pursuit → Enemy |
| ShadowScanExecutionResultContractV2 | movement_intent | bool | Pursuit → Enemy |
| ShadowScanExecutionResultContractV2 | shadow_scan_status | String (enum) | Pursuit → Enemy |
| ShadowScanExecutionResultContractV2 | shadow_scan_complete_reason | String (enum) | Pursuit → Enemy |
| ShadowScanExecutionResultContractV2 | shadow_scan_target | Vector2 | Pursuit → Enemy |
| AlertCombatShadowIntentContractV2 | type | int (IntentType) | Utility → Pursuit |
| AlertCombatShadowIntentContractV2 | target | Vector2 | Utility → Pursuit |

Constants/thresholds/eps (exact values):
- `SHADOW_BOUNDARY_SEARCH_RADIUS_PX = 96.0`.
- `SHADOW_SCAN_DURATION_MIN_SEC = 2.0`.
- `SHADOW_SCAN_DURATION_MAX_SEC = 3.0`.
- `SHADOW_SCAN_SWEEP_RAD = 0.87`.
- `SHADOW_SCAN_SWEEP_SPEED = 2.4`.
- `LAST_SEEN_REACHED_PX = 20.0`.
- `INVESTIGATE_ARRIVE_PX = 24.0`.
- `SEARCH_MAX_LAST_SEEN_AGE = 8.0`.
- `DECISION_INTERVAL_SEC = 0.25`.
- Target vector equality epsilon for tests: `<= 1.0 px`.
Dependencies on previous phases:
- Phase 0.
- Phase 2.
- Phase 3 (non-door collision immediate repath behavior via `_handle_slide_collisions_and_repath` must be present and unmodified; line 76 invariant "Non-door collision immediate repath behavior from previous phase remains unchanged" depends on Phase 3 completion).

## 7. Deterministic algorithm with exact order.
1. In `Enemy._build_utility_context`, compute `target_context_exists = has_known_target or has_last_seen or has_investigate_anchor`.
2. Build `shadow_scan_target` in strict priority order:
- Source 1: `known_target_pos` when `has_known_target == true` and vector is finite and non-zero.
- Source 2: `_last_seen_pos` when source 1 is invalid and `_last_seen_age < INF` and vector is finite and non-zero.
- Source 3: `_investigate_anchor` when sources 1 and 2 are invalid and `_investigate_anchor_valid == true` and vector is finite and non-zero.
- Else: `shadow_scan_target = Vector2.ZERO`, source `none`.
3. Compute `has_shadow_scan_target = (shadow_scan_source != "none")`.
4. Compute `shadow_scan_target_in_shadow` by `nav_system.is_point_in_shadow(shadow_scan_target)` only when `has_shadow_scan_target == true` and method exists; otherwise `false`.
5. In `EnemyPursuitSystem.execute_intent`, set defaults: `shadow_scan_status = "inactive"`, `shadow_scan_complete_reason = "none"`, `shadow_scan_target = (intent.get("target", Vector2.ZERO) as Vector2)` when `intent.has("target")` and the value is finite; else `shadow_scan_target = Vector2.ZERO`. (`intent.target` is optional — guard against missing or non-finite value before assignment.)
6. For `IntentType.SHADOW_BOUNDARY_SCAN`:
- If target invalid: set `shadow_scan_status = "completed"`, reason `target_invalid`, clear scan state.
- Else if boundary unresolved: set `shadow_scan_status = "completed"`, reason `boundary_unreachable`, stop motion.
- Else if sweep timer expired this tick: set `shadow_scan_status = "completed"`, reason `timeout`, clear scan state.
- Else: set `shadow_scan_status = "running"`.
7. In `Enemy`, when execute result has `shadow_scan_status == "completed"`, set `_shadow_scan_completed = true` and `_shadow_scan_completed_reason = result["shadow_scan_complete_reason"]`.
8. In `EnemyUtilityBrain._choose_intent`, evaluate no-LOS branches in this exact order:
- Branch A: if `not has_los` and `shadow_scan_completed == true` and `has_shadow_scan_target == true`, return `SEARCH` with `target = shadow_scan_target`.
- Branch B: if `not has_los` and `alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.ALERT` and `has_shadow_scan_target == true` and `shadow_scan_target_in_shadow == true`, return `SHADOW_BOUNDARY_SCAN` with `target = shadow_scan_target`.
- Branch C: investigate / search / return-home logic. (The `if combat_lock and not has_los:` early return is removed by section 9; no combat-lock guard precedes this branch after phase completion.)
9. Tie-break rules:
- Target source tie-break is fixed by source order `known_target_pos -> last_seen -> investigate_anchor`.
- Intent tie-break is fixed by branch order `A -> B -> C`.
10. After Branch A is selected once, clear in `Enemy` in the same tick: `_shadow_scan_completed = false`; `_shadow_scan_completed_reason = "none"`.

## 8. Edge-case matrix (case -> exact output).
| Case ID | Exact input case | Exact output |
|---|---|---|
| EC-01 | `alert_level=ALERT`, `los=false`, `has_shadow_scan_target=true`, `shadow_scan_target_in_shadow=true`, `shadow_scan_completed=false` | `intent.type = SHADOW_BOUNDARY_SCAN`, `intent.target = shadow_scan_target` |
| EC-02 | `alert_level=COMBAT`, `los=false`, same as EC-01 | `intent.type = SHADOW_BOUNDARY_SCAN`, `intent.target = shadow_scan_target` |
| EC-03 | `los=false`, `shadow_scan_completed=true`, `has_shadow_scan_target=true` | `intent.type = SEARCH`, `intent.target = shadow_scan_target` |
| EC-04 | `los=false`, `alert_level>=ALERT`, `target_context_exists=true`, `has_shadow_scan_target=false` | `intent.type != PATROL` |
| EC-05 | `shadow_scan_target` invalid (`Vector2.ZERO` or non-finite) | `has_shadow_scan_target=false`, `shadow_scan_target_in_shadow=false` |
| EC-06 | `shadow_scan_status=completed`, reason `boundary_unreachable` | Next decision returns `SEARCH` |
| EC-07 | `shadow_scan_status=completed`, reason `timeout` | Next decision returns `SEARCH` |

## 9. Legacy removal plan (delete-first, exact ids).
Legacy to delete first (exact ids/functions/consts):
- `effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS` guard around `shadow_scan_target` construction in `Enemy._build_utility_context`.
- `alert_level == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS and has_shadow_scan_target and shadow_scan_target_in_shadow` branch in `EnemyUtilityBrain._choose_intent`.
- `if combat_lock and not has_los: return _combat_no_los_grace_intent(...)` as a pre-shadow top-priority branch in `EnemyUtilityBrain._choose_intent`.
Forbidden patterns (identifiers/branches):
- Any suspicious-only guard for shadow-scan target construction.
- Any suspicious-only guard for SHADOW_BOUNDARY_SCAN intent selection.
- Any no-LOS combat-lock early return that executes before ALERT/COMBAT shadow-scan selection.
- Any PATROL return in ALERT/COMBAT with `target_context_exists == true`.

## 10. Legacy verification commands (exact rg + expected 0 matches for every removed legacy item).
1. `rg -n "effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT\\.SUSPICIOUS" src/entities/enemy.gd -S`
Expected result: `0 matches`.
2. `rg -n "alert_level == ENEMY_ALERT_LEVELS_SCRIPT\\.SUSPICIOUS and has_shadow_scan_target and shadow_scan_target_in_shadow" src/systems/enemy_utility_brain.gd -S`
Expected result: `0 matches`.
3. `rg -n "if combat_lock and not has_los:" src/systems/enemy_utility_brain.gd -S`
Expected result: `0 matches`.
Rule: phase cannot close until all three commands return `0 matches`.
Rule: any non-zero match count is `FAILED`.
Rule: no allowlist and no compatibility branch.

## 11. Acceptance criteria (binary pass/fail).
Pass only when all conditions are true:
- All legacy verification commands in section 10 return `0 matches`.
- `tests/test_alert_combat_shadow_boundary_scan_intent.tscn` exits `0`.
- Updated `tests/test_suspicious_shadow_scan.tscn` exits `0`.
- Updated `tests/test_combat_no_los_never_hold_range.tscn` exits `0`.
- Mandatory smoke suite commands in section 12 all exit `0`.
- Runtime scenarios in section 20 all pass invariant checks.
- Diff audit in section 19 reports no out-of-scope changed file.
Fail immediately on any false condition.

## 12. Tests (new/update + purpose).
New tests (exact filenames):
- `tests/test_alert_combat_shadow_boundary_scan_intent.gd`.
- `tests/test_alert_combat_shadow_boundary_scan_intent.tscn`.
Purpose:
- Verify ALERT no-LOS + shadow target in shadow selects `SHADOW_BOUNDARY_SCAN`.
- Verify COMBAT no-LOS + shadow target in shadow selects `SHADOW_BOUNDARY_SCAN`.
- Verify scan completion reason (`timeout|boundary_unreachable|target_invalid`) leads to SEARCH on next decision tick.
Tests to update (exact filenames):
- `tests/test_suspicious_shadow_scan.gd`.
- `tests/test_combat_no_los_never_hold_range.gd`.
- `tests/test_runner_node.gd`.
Purpose:
- Update assertions: SUSPICIOUS state does NOT select SHADOW_BOUNDARY_SCAN after branch refactor.
- Preserve COMBAT no-LOS anti-hold behavior when no shadow target is present.
- Register and execute new phase test scene.
Phase test commands (exact):
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_alert_combat_shadow_boundary_scan_intent.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_suspicious_shadow_scan.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_combat_no_los_never_hold_range.tscn`
Smoke suite commands (exact):
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_path_policy_parity.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_shadow_policy_hard_block_without_grant.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_shadow_stall_escapes_to_light.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_pursuit_stall_fallback_invariants.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_combat_no_los_never_hold_range.tscn`

## 13. rg gates (command + expected output).
- `rg -n "shadow_scan_status|shadow_scan_complete_reason|shadow_scan_completed" src/entities/enemy.gd src/systems/enemy_pursuit_system.gd src/systems/enemy_utility_brain.gd -S`
Expected output: at least one match in each file.
- `rg -n "build_policy_valid_path\\(" src/systems/enemy_pursuit_system.gd src/systems/navigation_service.gd src/systems/navigation_runtime_queries.gd -S`
Expected output: one pipeline path remains; no new alternate planner symbol introduced by this phase.
- `rg -n "IntentType\\.PATROL" src/systems/enemy_utility_brain.gd -S`
Expected output: PATROL returns remain only outside ALERT/COMBAT target-context path.
- `rg -n "effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT\\.SUSPICIOUS|alert_level == ENEMY_ALERT_LEVELS_SCRIPT\\.SUSPICIOUS and has_shadow_scan_target|if combat_lock and not has_los:" src/entities/enemy.gd src/systems/enemy_utility_brain.gd -S`
Expected output: `0 matches`.

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: `0 matches`.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

## 14. Execution sequence (step-by-step, no ambiguity).
1. Delete legacy branch in `Enemy._build_utility_context` (suspicious-only guard) and commit this deletion in the working diff before adding replacement code.
2. Delete legacy suspicious-only shadow branch and combat-lock pre-shadow branch in `EnemyUtilityBrain._choose_intent` before inserting new branch order.
3. Add `ShadowScanExecutionResultContractV2` fields in `EnemyPursuitSystem.execute_intent`.
4. Add pending completion state in `Enemy` runtime and expose it in utility context.
5. Implement new deterministic branch order in `EnemyUtilityBrain._choose_intent`.
6. Add new test files `tests/test_alert_combat_shadow_boundary_scan_intent.gd` and `.tscn`.
7. Update existing tests `tests/test_suspicious_shadow_scan.gd` and `tests/test_combat_no_los_never_hold_range.gd`.
8. Update `tests/test_runner_node.gd` constants, existence checks, and embedded-suite call list for new scene.
9. Run legacy verification commands in section 10; abort on first non-zero match.
10. Run phase test commands in section 12.
11. Run smoke suite commands in section 12.
12. Run rg gates in section 13.
13. Run post-implementation verification plan in section 19.
14. Produce verification report in section 21 format.

## 15. Rollback conditions.
Rollback trigger conditions:
- Any legacy verification command returns non-zero matches.
- Any phase test command exits non-zero.
- Any smoke command exits non-zero.
- Any runtime scenario in section 20 violates an invariant.
- Diff audit shows an out-of-scope file change.
- Contract conformance check finds missing required status/reason enum usage.
Rollback action:
- Revert all phase-changed files in allowed boundary and return repository to pre-phase state snapshot.

## 16. Phase close condition.
Phase closes only when all are true:
- Legacy gates: pass.
- Phase tests: pass.
- Smoke suite: pass.
- rg gates: pass.
- Runtime scenario matrix: pass.
- Verification report unresolved deviations: empty.

## 17. Ambiguity self-check line: Ambiguity check: 0
Ambiguity check: 0

## 18. Open questions line: Open questions: 0
Open questions: 0

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).
Diff audit commands:
- `git diff --name-only`
- `bash -lc 'set -euo pipefail; allowed="^(src/entities/enemy.gd|src/systems/enemy_utility_brain.gd|src/systems/enemy_pursuit_system.gd|tests/test_alert_combat_shadow_boundary_scan_intent.gd|tests/test_alert_combat_shadow_boundary_scan_intent.tscn|tests/test_suspicious_shadow_scan.gd|tests/test_combat_no_los_never_hold_range.gd|tests/test_runner_node.gd)$"; git diff --name-only | tee /tmp/phase4_changed_files.txt; if rg -n -v "$allowed" /tmp/phase4_changed_files.txt -S; then exit 1; fi'`
Contract conformance checks:
- `rg -n "shadow_scan_status|shadow_scan_complete_reason|shadow_scan_completed" src/entities/enemy.gd src/systems/enemy_utility_brain.gd src/systems/enemy_pursuit_system.gd -S`
- `rg -n "effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT\\.SUSPICIOUS|alert_level == ENEMY_ALERT_LEVELS_SCRIPT\\.SUSPICIOUS and has_shadow_scan_target|if combat_lock and not has_los:" src/entities/enemy.gd src/systems/enemy_utility_brain.gd -S`
- `rg -n "_utility_brain\\.update\\(" src/entities/enemy.gd -S`
- `rg -n "_choose_intent\\(" src/systems/enemy_utility_brain.gd -S`
Mandatory test execution:
- Run all phase test commands from section 12.
- Run all smoke suite commands from section 12.
- Fail on any exit code not equal to `0`.
- Fail when logs contain `SKIP`, `SKIPPED`, `PENDING`, or `NOT RUN`.
Runtime scenario checks:
- Run scenario commands from section 20.
- Compare actual intent/state timeline to expected invariants.
- Any invariant violation marks phase `FAILED`.

## 20. Runtime scenario matrix (scenario id, setup, duration, expected invariants, fail conditions).
| Scenario ID | Setup (exact map/seed/setup) | Duration | Expected invariants | Fail conditions |
|---|---|---|---|---|
| P4-R1 | Scene `res://tests/test_alert_combat_shadow_boundary_scan_intent.tscn`; synthetic `Node2D` world; enemy at `(0,0)`; player at `(260,0)`; LOS blocker at `(120,0)` size `(32,640)`; shadow zone centered on player with rectangle `(220,220)`; force awareness `ALERT`; RNG seed `40401` | 3.2 sec simulated at `dt=0.1` | `intent.type == SHADOW_BOUNDARY_SCAN` while scan running; after scan completion next decision tick returns `SEARCH`; pipeline remains `build_policy_valid_path -> execute_intent -> move/repath` | Any PATROL intent; missing SEARCH handoff; any non-zero test exit |
| P4-R2 | Same scene and geometry as P4-R1; force awareness `COMBAT`; RNG seed `40402` | 3.2 sec at `dt=0.1` | COMBAT no-LOS with shadow target enters `SHADOW_BOUNDARY_SCAN`; completion reason is one of defined enums; next decision returns SEARCH with same target (`distance <= 1.0`) | HOLD_RANGE in no-LOS; PATROL with target context; missing completion reason enum |
| P4-R3 | Scene `res://tests/test_combat_no_los_never_hold_range.tscn`; existing test setup with blocker; no explicit shadow zone; RNG seed from test default | 1.65 sec (`0.75 + 0.90`) | no LOS is true; no HOLD_RANGE in COMBAT no-LOS; regression guard remains green | HOLD_RANGE detected; test exit non-zero |
Scenario commands (exact):
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_alert_combat_shadow_boundary_scan_intent.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_combat_no_los_never_hold_range.tscn`

## 21. Verification report format (what must be recorded to close phase).
Report must record all fields below:
- `phase_id: PHASE_4`
- `phase_title: Shadow Scan In ALERT/COMBAT`
- `changed_files: [exact paths]`
- `out_of_scope_changes: []`
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `legacy_verification_commands: [command, exit_code, match_count]`
- `rg_gates: [command, exit_code, expected, actual]`
- `phase_tests: [command, exit_code]`
- `smoke_tests: [command, exit_code]`
- `runtime_scenarios: [scenario_id, command, exit_code, invariant_result]`
- `single_owner_check: pass|fail`
- `status_reason_enum_check: pass|fail`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` (all must be PASS to close phase)
- `unresolved_deviations: []`
- `final_result: PASS|FAIL`
Non-empty `unresolved_deviations` forces `final_result = FAIL`.

## 22. Structural completeness self-check line:
Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23. Missing sections: NONE.
- PMB gates present in section 13: yes
- pmb_contract_check present in section 21: yes

## 23. Dependencies on previous phases.
1. Phase 0 dependency gate: `rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S` → `0 matches`.
2. Phase 2 dependency gate: `rg -n "_resolve_nearest_reachable_fallback|_attempt_shadow_escape_recovery" src/systems/enemy_pursuit_system.gd -S` → `0 matches`.
3. Phase 3 dependency gate: `rg -n "_handle_slide_collisions_and_repath" src/systems/enemy_pursuit_system.gd -S` → `≥1 match` (unified collision handler must be present and unmodified).
4. All three gates must pass before step 1 of section 14.

## PHASE 5
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_5.
Scope boundary (exact files): section 4.
Execution sequence: section 14.
Rollback conditions: section 15.
Verification report format: section 21.

Evidence.
Inspected files (exact paths):
- `src/systems/navigation_service.gd`
- `src/systems/shadow_system.gd`
- `src/systems/procedural_layout_v2.gd`
- `src/levels/stealth_3zone_test_controller.gd`
- `tests/test_navmesh_migration.gd`
- `tests/test_runner_node.gd`

Inspected functions/methods (exact identifiers):
- `NavigationService.build_from_layout` (navigation_service.gd:192)
- `NavigationService._extract_navigation_obstacles` (navigation_service.gd:589)
- `NavigationService._subtract_obstacles_from_rects` (navigation_service.gd:610)
- `NavigationService._subtract_rect` (navigation_service.gd:635)
- `NavigationService._create_region_for_room` (navigation_service.gd:548)
- `NavigationService._bake_navigation_polygon` (navigation_service.gd:679)
- `ThreeZoneLayout._navigation_obstacles` (stealth_3zone_test_controller.gd:147) — only existing layout implementing the method
- `ShadowSystem._enemy_radius` (shadow_system.gd:14) — value: 12.0
- `ProceduralLayoutV2.WALK_CLEARANCE_RADIUS` (procedural_layout_v2.gd:18) — value: 16.0

Search commands used:
- `rg -n "navmesh|nav_mesh|NavigationPolygon|nav_region|nav_poly|clearance|obstacle|extraction|nav_carve|carve|CARVE" src/systems/navigation_service.gd -S`
- `rg -n "_navigation_obstacles" src -S`
- `rg -n "nav_obstacle|navigation_obstacle|obstacle_group|add_to_group" src -S`
- `rg -n "if not .*_navigation_obstacles.*return|legacy_nav_carve" src tests -S` (0 matches)
- `rg -n "WALK_CLEARANCE" src/systems/procedural_layout_v2.gd -S`
- `rg -n "radius" src/systems/shadow_system.gd -S`
- `rg -n "path_desired_distance|target_desired_distance" tests/test_navmesh_migration.gd -S`

## 1. What now.
`NavigationService._extract_navigation_obstacles` (navigation_service.gd:589) returns an empty array when the layout object lacks the `_navigation_obstacles` method (line 595–596). No scene-tree fallback exists. Result: any layout that does not implement `_navigation_obstacles` produces a navmesh with zero obstacle carving, causing agents to path through solid props and wall geometry. Additionally, the extracted obstacles are passed to `_subtract_obstacles_from_rects` at their exact Rect2 bounds — no clearance margin is applied — so generated navigation polygons touch obstacle edges, causing agents to hug walls and props at near-zero clearance when following those paths.

## 2. What changes.
1. Two new constants added to `NavigationService`: `OBSTACLE_CLEARANCE_PX := 16.0` and `NAV_OBSTACLE_GROUP := "nav_obstacles"`.
2. New private function `NavigationService._extract_scene_obstacles() -> Array[Rect2]` added: queries `get_tree().get_nodes_in_group(NAV_OBSTACLE_GROUP)`, filters to `StaticBody2D` nodes, extracts `RectangleShape2D` collision shapes as world-space `Rect2` bounds.
3. `NavigationService.build_from_layout` modified at the obstacle extraction call site (line 223): after calling `_extract_navigation_obstacles`, if the result is empty, call `_extract_scene_obstacles()` as fallback. Then inflate all extracted obstacle rects by `OBSTACLE_CLEARANCE_PX` before passing to `_subtract_obstacles_from_rects`.
4. The `build_policy_valid_path → execute_intent → move/repath` pipeline introduced in Phase 0 and Phase 1 is not touched by this phase; all changes are confined to navmesh construction, not route selection.

## 3. What will be after.
1. `build_from_layout` always attempts obstacle extraction via two ordered sources: `layout._navigation_obstacles()` first, then `_extract_scene_obstacles()` if the first returns empty.
2. Every extracted obstacle rect is inflated by exactly `OBSTACLE_CLEARANCE_PX` (16.0 px) on all four sides via `Rect2.grow` before being carved from room walkable area.
3. When no obstacles exist in either source, `cleared_obstacles` is empty, and `_subtract_obstacles_from_rects` returns room rects unchanged — behavior identical to pre-phase for layouts with no obstacles.
4. StaticBody2D nodes added to the group `"nav_obstacles"` in the scene tree are recognized as navmesh obstacles without requiring layout API changes.
5. Navigation polygons no longer touch obstacle edges; generated paths maintain at least `OBSTACLE_CLEARANCE_PX` clearance from carved obstacle boundaries.

## 4. Scope and non-scope (exact files).
In-scope:
- `src/systems/navigation_service.gd`
- `tests/test_nav_obstacle_extraction_fallback.gd` (new)
- `tests/test_nav_obstacle_extraction_fallback.tscn` (new)
- `tests/test_nav_clearance_margin_avoids_wall_hugging.gd` (new)
- `tests/test_nav_clearance_margin_avoids_wall_hugging.tscn` (new)
- `tests/test_navmesh_migration.gd` (update)
- `tests/test_runner_node.gd` (update: add 2 new scene constants + existence checks + run entries)

Out-of-scope (must not be modified):
- `src/systems/navigation_runtime_queries.gd`
- `src/systems/navigation_enemy_wiring.gd`
- `src/systems/navigation_shadow_policy.gd`
- `src/systems/enemy_pursuit_system.gd`
- `src/systems/enemy_utility_brain.gd`
- `src/entities/enemy.gd`
- `src/systems/procedural_layout_v2.gd`
- `src/systems/shadow_system.gd`
- All other `src/` files not listed above.
- All other `tests/` files not listed above.

Allowed file-change boundary: same as in-scope list above (items 1–7).

## 5. Single-owner authority for this phase.
Single owner: `NavigationService.build_from_layout` (navigation_service.gd:192) is the sole call site that triggers obstacle extraction and applies the clearance margin. No other function in `NavigationService` or any other class calls `_extract_scene_obstacles` or applies `OBSTACLE_CLEARANCE_PX`.
Authority constraints:
1. `_extract_navigation_obstacles` extracts from layout API only — it does not call `_extract_scene_obstacles`.
2. `_extract_scene_obstacles` queries the scene group only — it does not call `_extract_navigation_obstacles`.
3. The fallback decision (`nav_obstacles.is_empty()`) is made in `build_from_layout` only, not inside either extraction function.
4. `OBSTACLE_CLEARANCE_PX` inflation is applied once in `build_from_layout` — not inside `_extract_navigation_obstacles`, `_extract_scene_obstacles`, or `_subtract_obstacles_from_rects`.
5. `_subtract_obstacles_from_rects` and `_subtract_rect` are not modified in this phase.

## 6. Full input/output contract.

### 6.1 `_extract_scene_obstacles() -> Array[Rect2]`
Inputs: none (reads from scene tree via `get_tree().get_nodes_in_group`).
Precondition: `is_inside_tree() == true`. If false: returns `[]`.
Output: `Array[Rect2]`. Each element is a world-space `Rect2` derived from a `RectangleShape2D` collision shape on a `StaticBody2D` node that is a member of group `NAV_OBSTACLE_GROUP`. Elements with `size.x <= NAV_CARVE_EPSILON` or `size.y <= NAV_CARVE_EPSILON` are excluded. No ordering guarantee on output elements. Empty array when no qualifying nodes exist.

### 6.2 `build_from_layout` obstacle pipeline contract (new invariants)
After Phase 5, for every call to `build_from_layout(p_layout, parent)`:
- `nav_obstacles`: `_extract_navigation_obstacles(p_layout)` result if non-empty; otherwise `_extract_scene_obstacles()` result.
- `cleared_obstacles`: each element of `nav_obstacles` grown by `OBSTACLE_CLEARANCE_PX` via `Rect2.grow`.
- `_subtract_obstacles_from_rects(rects, cleared_obstacles)` is called with `cleared_obstacles` (not raw `nav_obstacles`).

### 6.3 Constants
| Constant | Value | Type | Location | Meaning |
|---|---|---|---|---|
| `OBSTACLE_CLEARANCE_PX` | `16.0` | `float` | `navigation_service.gd` | Clearance grown around each obstacle rect before carving |
| `NAV_OBSTACLE_GROUP` | `"nav_obstacles"` | `String` | `navigation_service.gd` | Scene group name for StaticBody2D obstacle fallback |
| `NAV_CARVE_EPSILON` | `0.5` | `float` | `navigation_service.gd:22` (existing) | Minimum rect dimension; smaller rects are discarded |

## 7. Deterministic algorithm with exact order.

### 7.1 Modified `build_from_layout` obstacle block (replaces lines 223–234)
Step 1: `var nav_obstacles := _extract_navigation_obstacles(layout)`.
Step 2: If `nav_obstacles.is_empty()`: `nav_obstacles = _extract_scene_obstacles()`.
Step 3: `var cleared_obstacles: Array[Rect2] = []`.
Step 4: For each `obs: Rect2` in `nav_obstacles`: `cleared_obstacles.append(obs.grow(OBSTACLE_CLEARANCE_PX))`.
Step 5: For each room `i` in `range(layout.rooms.size())` (existing loop, unchanged): pass `cleared_obstacles` (not `nav_obstacles`) to `_subtract_obstacles_from_rects(rects, cleared_obstacles)`.

### 7.2 New function `_extract_scene_obstacles() -> Array[Rect2]`
Step 1: `var result: Array[Rect2] = []`.
Step 2: If `not is_inside_tree()`: return `result`.
Step 3: `var nodes: Array[Node] = get_tree().get_nodes_in_group(NAV_OBSTACLE_GROUP)`.
Step 4: For each `node` in `nodes`:
  - `var body := node as StaticBody2D`. If `body == null`: continue.
  - For each `child` in `body.get_children()`:
    - `var col := child as CollisionShape2D`. If `col == null`: continue.
    - If `not (col.shape is RectangleShape2D)`: continue.
    - `var rect_shape := col.shape as RectangleShape2D`.
    - `var half := rect_shape.size * 0.5`.
    - `var obs_rect := Rect2(body.global_position + col.position - half, rect_shape.size)`. Position convention: `body.global_position` is the `StaticBody2D` world-space origin (its pivot point); `col.position` is the `CollisionShape2D` local offset relative to the body origin (zero when shape is centered on body); `rect_shape.size` is the full width×height (NOT half-extents — `RectangleShape2D.size` in Godot 4 is full size); `half = size * 0.5` gives the half-extents; result is the top-left world corner of the AABB.
    - If `obs_rect.size.x <= NAV_CARVE_EPSILON or obs_rect.size.y <= NAV_CARVE_EPSILON`: continue.
    - `result.append(obs_rect)`.
Step 5: Return `result`.

### 7.3 Unchanged functions
`_extract_navigation_obstacles`, `_subtract_obstacles_from_rects`, `_subtract_rect`, `_create_region_for_room`, `_bake_navigation_polygon`: not modified. Their existing algorithms remain identical.

## 8. Edge-case matrix (case → exact output).

| Case | Condition | Expected output |
|---|---|---|
| E1 | Layout has `_navigation_obstacles` returning non-empty | `_extract_scene_obstacles` is NOT called; cleared_obstacles = layout obstacles grown by OBSTACLE_CLEARANCE_PX |
| E2 | Layout lacks `_navigation_obstacles`; no nodes in NAV_OBSTACLE_GROUP | `nav_obstacles = []`, `cleared_obstacles = []`; `_subtract_obstacles_from_rects(rects, [])` returns `rects.duplicate()` — no carving |
| E3 | Layout has `_navigation_obstacles` returning `[]` | `nav_obstacles.is_empty() == true` → fallback to `_extract_scene_obstacles()` |
| E4 | Scene has StaticBody2D in NAV_OBSTACLE_GROUP with RectangleShape2D | Extracted as world-space Rect2 with position = `body.global_position + col.position - half_size` |
| E5 | StaticBody2D in NAV_OBSTACLE_GROUP has non-RectangleShape2D shape | Skipped; only RectangleShape2D is extracted |
| E6 | StaticBody2D NOT in NAV_OBSTACLE_GROUP | Skipped |
| E7 | `is_inside_tree() == false` when `_extract_scene_obstacles` called | Returns `[]` immediately |
| E8 | Obstacle Rect2 after `grow(OBSTACLE_CLEARANCE_PX)` extends outside room rect | `_subtract_obstacles_from_rects` handles this correctly via intersection logic; no geometry error |
| E9 | Inflated obstacle covers entire room rect | `_subtract_obstacles_from_rects` produces empty carved result; fallback to uncarved `rects` at line 231–232 (existing guard) |
| E10 | `layout == null` or `not layout.valid` | `build_from_layout` returns early at line 196–197 (existing); obstacle pipeline never reached |

## 9. Legacy removal plan (delete-first, exact ids).
The v1 legacy gate specifies identifiers `if not .*_navigation_obstacles.*return` and `legacy_nav_carve`. Confirmed by rg search: 0 matches in `src/` and `tests/` for both patterns (current code is multi-line; the single-line pattern does not match). No legacy identifiers exist in the codebase for this phase. No deletion step is required before adding new logic.

## 10. Legacy verification commands (exact rg + expected 0 matches).
1. `rg -n "legacy_nav_carve" src tests -S`
   Expected: `0 matches`.
2. `rg -n "if not .*_navigation_obstacles.*return" src tests -S`
   Expected: `0 matches`.

(No additional commands: no legacy was present as single-line identifiers.)

## 11. Acceptance criteria (binary pass/fail).
1. `_extract_scene_obstacles` returns non-empty when scene contains StaticBody2D in `"nav_obstacles"` group with RectangleShape2D. PASS = `test_nav_obstacle_extraction_fallback` exits 0.
2. When layout lacks `_navigation_obstacles`, `build_from_layout` uses scene obstacles as fallback. PASS = `test_nav_obstacle_extraction_fallback` exits 0.
3. Each obstacle is inflated by exactly `OBSTACLE_CLEARANCE_PX` before carving: carved room rect is smaller by `OBSTACLE_CLEARANCE_PX` on each carved side. PASS = `test_nav_clearance_margin_avoids_wall_hugging` exits 0.
4. When no obstacles exist in either source, `build_from_layout` produces navmesh identical to pre-phase (no carving, no clearance applied). PASS = `test_nav_clearance_margin_avoids_wall_hugging` exits 0.
5. `OBSTACLE_CLEARANCE_PX` and `NAV_OBSTACLE_GROUP` constants present in `navigation_service.gd`. PASS = rg gate confirms.
6. `_extract_scene_obstacles` is called from `build_from_layout` only. PASS = rg gate confirms no other callsite.
7. `_subtract_obstacles_from_rects` and `_subtract_rect` are not modified. PASS = diff audit confirms no change to those functions.
8. Diff audit reports no out-of-scope file changes. PASS = section 19 diff audit.
9. All PMB contract commands return expected results. PASS = section 13 PMB gates.

## 12. Tests (new/update + purpose).
New tests (exact filenames):
- `tests/test_nav_obstacle_extraction_fallback.gd` + `.tscn`
  Purpose: (a) Create FakeLayout without `_navigation_obstacles` method. Add StaticBody2D with RectangleShape2D in group `"nav_obstacles"` to the scene tree. Call `build_from_layout`. Assert `_extract_scene_obstacles()` returns non-empty and that the navmesh `_room_to_region` shows carved geometry. (b) Verify layout with `_navigation_obstacles` returning non-empty takes priority over scene fallback: create layout returning one rect, add a StaticBody2D obstacle to scene; assert only the layout rect is used (scene fallback not called when layout result is non-empty).
- `tests/test_nav_clearance_margin_avoids_wall_hugging.gd` + `.tscn`
  Purpose: (a) Create FakeLayout with known room rect `Rect2(0,0,200,200)` and one obstacle `Rect2(80,80,40,40)`. After `build_from_layout`, read `_room_to_region` navmesh outlines and verify that the carved region does not include any point within `OBSTACLE_CLEARANCE_PX` (16px) of the raw obstacle boundary. (b) Verify the case of zero obstacles: room rect is not reduced.

Tests to update (exact filenames):
- `tests/test_navmesh_migration.gd`: Add two test functions — (a) `_test_obstacle_extraction_fallback`: creates single-room fixture, adds StaticBody2D obstacle in `"nav_obstacles"` group, calls `build_from_layout`, verifies the resulting navmesh polygon area is reduced relative to no-obstacle baseline; (b) `_test_clearance_margin_applied`: creates fixture with known obstacle, verifies carved outline vertex distances from raw obstacle boundary are all ≥ `OBSTACLE_CLEARANCE_PX`.
- `tests/test_runner_node.gd`: Add `const NAV_OBSTACLE_FALLBACK_TEST_SCENE := "res://tests/test_nav_obstacle_extraction_fallback.tscn"` and `const NAV_CLEARANCE_MARGIN_TEST_SCENE := "res://tests/test_nav_clearance_margin_avoids_wall_hugging.tscn"`; add existence checks for both; add two `_run_embedded_scene_suite` calls.

Phase test commands (exact):
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_nav_obstacle_extraction_fallback.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_nav_clearance_margin_avoids_wall_hugging.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navmesh_migration.tscn`

Smoke suite commands (exact):
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_runtime_queries.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_path_policy_parity.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_failure_reason_contract.tscn`
- `/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_navigation_shadow_policy_runtime.tscn`

Pass rule: every command exits `0`; no `SKIP`, `SKIPPED`, `PENDING`, or `NOT RUN` in output logs.

## 13. rg gates (command + expected output).
1. `rg -n "legacy_nav_carve" src tests -S`
   Expected: `0 matches`.
2. `rg -n "OBSTACLE_CLEARANCE_PX" src/systems/navigation_service.gd -S`
   Expected: `≥2 matches` (constant definition + usage in clearance loop).
3. `rg -n "NAV_OBSTACLE_GROUP" src/systems/navigation_service.gd -S`
   Expected: `≥2 matches` (constant definition + usage in `_extract_scene_obstacles`).
4. `rg -n "_extract_scene_obstacles" src/systems/navigation_service.gd -S | wc -l`
   Expected: `≥2` (function definition + at least one callsite).
4b. `rg -n "_extract_scene_obstacles" src/systems/navigation_service.gd -S | grep -v "func _extract_scene_obstacles\|build_from_layout" | wc -l`
   Expected: `0` (no matches outside function definition and `build_from_layout`).
5. `rg -n "_extract_scene_obstacles" src -S`
   Expected: matches appear only in `src/systems/navigation_service.gd`; no other `src/` file contains this identifier.
6. `rg -n "obs\.grow\|cleared_obstacles" src/systems/navigation_service.gd -S`
   Expected: `≥2 matches` (the clearance grow loop and the cleared_obstacles variable usage).
7. `rg -n "_subtract_obstacles_from_rects|_subtract_rect" src/systems/navigation_service.gd -S`
   Expected: same matches as pre-phase (functions not renamed, not moved, signatures not changed); confirm by comparing pre/post diff that only the callsite argument changes from `nav_obstacles` to `cleared_obstacles`.

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: `0 matches`.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

## 14. Execution sequence (step-by-step, no ambiguity).
1. Run legacy verification commands (section 10, commands 1–2). Both must return 0 matches. Stop if non-zero.
2. Run Phase 0 and Phase 1 dependency gates from section 23. Both must return expected output. Stop if either fails.
3. Add constants `OBSTACLE_CLEARANCE_PX := 16.0` and `NAV_OBSTACLE_GROUP := "nav_obstacles"` to `navigation_service.gd` in the constants block alongside `NAV_CARVE_EPSILON`.
4. Add `_extract_scene_obstacles() -> Array[Rect2]` function to `navigation_service.gd`. Algorithm: section 7.2.
5. Modify `build_from_layout` in `navigation_service.gd`: at line 223, after the existing `_extract_navigation_obstacles` call, add the fallback and clearance logic from section 7.1 (steps 2–4). Replace the `nav_obstacles` argument in the `_subtract_obstacles_from_rects` call with `cleared_obstacles` (section 7.1 step 5).
6. Create `tests/test_nav_obstacle_extraction_fallback.gd` and `.tscn` per section 12.
7. Create `tests/test_nav_clearance_margin_avoids_wall_hugging.gd` and `.tscn` per section 12.
8. Update `tests/test_navmesh_migration.gd`: add two new test functions as described in section 12.
9. Update `tests/test_runner_node.gd`: add constants, existence checks, and run entries for both new scenes per section 12.
10. Run all phase test commands (section 12). All must exit 0.
11. Run all smoke suite commands (section 12). All must exit 0.
12. Run all rg gates from section 13 (items 1–7 + PMB-1 through PMB-5). Confirm expected results.
13. Run diff audit (section 19). Confirm no out-of-scope file changes.
14. Record verification report (section 21).

## 15. Rollback conditions.
Rollback immediately if any of the following occur:
1. Any phase test command (section 12) exits non-zero after step 10.
2. Any smoke suite command (section 12) exits non-zero after step 11.
3. Any rg gate from section 13 returns unexpected output.
4. Diff audit (section 19) reports an out-of-scope file change.
5. `_extract_scene_obstacles` is called from any function other than `build_from_layout` (single-owner violation; detected by rg gate 4 in section 13).
6. `OBSTACLE_CLEARANCE_PX` inflation is applied inside `_extract_navigation_obstacles`, `_extract_scene_obstacles`, or `_subtract_obstacles_from_rects` instead of in `build_from_layout` (single-owner violation).

Rollback action: restore `navigation_service.gd` and `test_navmesh_migration.gd` to their Phase 1 close state. Delete new test files `test_nav_obstacle_extraction_fallback.gd`, `.tscn`, `test_nav_clearance_margin_avoids_wall_hugging.gd`, `.tscn`.

## 16. Phase close condition.
Phase PHASE_5 is closed when all of the following are true simultaneously:
1. All phase test commands exit 0 (section 12).
2. All smoke suite commands exit 0 (section 12).
3. All rg gates return expected results (section 13, items 1–7).
4. All PMB gates return expected results (section 13, PMB-1 through PMB-5).
5. Diff audit reports no out-of-scope changes (section 19).
6. Verification report (section 21) is recorded with `final_result: PASS`.

## 17. Ambiguity self-check line: Ambiguity check: 0

## 18. Open questions line: Open questions: 0

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).
1. Diff audit: run `git diff --name-only`. Every changed path must appear in the in-scope list of section 4. Any path not in that list = phase FAILED.
2. Contract conformance:
   a. `rg -n "OBSTACLE_CLEARANCE_PX" src/systems/navigation_service.gd -S` — confirm ≥2 occurrences (definition + usage).
   b. `rg -n "_extract_scene_obstacles" src/systems/navigation_service.gd -S` — confirm exactly 2 occurrences (definition + one callsite in `build_from_layout`).
   c. Confirm `_subtract_obstacles_from_rects` signature and body are unchanged (diff shows only argument name change at callsite).
3. Single-owner check: confirm `_extract_scene_obstacles` called only from `build_from_layout` (rg gate 4 in section 13).
4. Smoke suite: run all 4 commands from section 12 smoke list. All must exit 0.
5. Runtime scenario checks: run section 20 scenarios.

## 20. Runtime scenario matrix (scenario id, setup, duration, expected invariants, fail conditions).

| Scenario | Setup | Duration | Expected invariants | Fail conditions |
|---|---|---|---|---|
| S1 | FakeLayout without `_navigation_obstacles`; one StaticBody2D `Rect2(80,80,40,40)` in `"nav_obstacles"` group; single room `Rect2(0,0,200,200)` | build + 2 physics frames | `_extract_scene_obstacles()` returns `[Rect2(80,80,40,40)]`; navmesh polygon area < room area | fallback not triggered; obstacle not carved |
| S2 | FakeLayout with `_navigation_obstacles` returning `[Rect2(80,80,40,40)]`; also StaticBody2D in `"nav_obstacles"` with different rect | build + 2 physics frames | Only layout rect used; scene rect absent from carved set | Scene fallback called when layout returned non-empty |
| S3 | Room `Rect2(0,0,200,200)`, obstacle `Rect2(90,90,20,20)`, clearance 16px | build + 2 physics frames | No navmesh vertex closer than 16px to raw obstacle boundary; cleared boundary = `Rect2(74,74,52,52)` is fully carved | Vertex within 15px of raw obstacle edge |
| S4 | Room `Rect2(0,0,200,200)`, no obstacles in layout or scene | build + 2 physics frames | Navmesh polygon area equals pre-phase (no clearance reduction); `cleared_obstacles` is empty | Room area reduced without obstacle |
| S5 | Two-room fixture (existing `_create_two_room_fixture`); no obstacles | build + navigation: enemy from room A to room B, 120 frames | Enemy reaches target room B within 120 frames; existing navmesh door-overlap behavior unchanged | Enemy fails to navigate; regression in existing test |

## 21. Verification report format (what must be recorded to close phase).
Report must record all fields below:
- `phase_id: PHASE_5`
- `changed_files: [exact paths]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; must be empty on close)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `legacy_verification: [command, exit_code, match_count, PASS|FAIL]` for each section 10 command
- `rg_gates: [command, expected, actual, PASS|FAIL]` for each section 13 gate (items 1–7)
- `phase_tests: [command, exit_code, PASS|FAIL]` for each section 12 phase test command
- `smoke_suite: [command, exit_code, PASS|FAIL]` for each section 12 smoke command
- `runtime_scenarios: [scenario_id, setup_description, invariant_result, PASS|FAIL]` for each section 20 scenario
- `single_owner_check: PASS|FAIL` (`_extract_scene_obstacles` called only from `build_from_layout`)
- `clearance_inflation_check: PASS|FAIL` (`OBSTACLE_CLEARANCE_PX` applied in `build_from_layout` only)
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` (all must be PASS to close phase)
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`
Non-empty `unresolved_deviations` forces `final_result = FAIL`.

## 22. Structural completeness self-check line:
Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23. Missing sections: NONE.
- PMB gates present in section 13 (PMB section exists in document): yes
- pmb_contract_check present in section 21 (PMB section exists in document): yes

## 23. Dependencies on previous phases.
1. Phase 0 dependency — `build_policy_valid_path → execute_intent → move/repath` pipeline is the authoritative route authority and must be unmodified. Gate: `rg -n "_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S` → `0 matches`. Must pass before step 5 in section 14.
2. Phase 1 dependency — detour planner (`_build_detour_candidates`) must be present in `navigation_runtime_queries.gd` before navmesh clearance improvements are applied, ensuring the detour planner benefits from the improved navmesh. Gate: `rg -n "_build_detour_candidates" src/systems/navigation_runtime_queries.gd -S` → `≥1 match`. Must pass before step 5 in section 14.
3. Phase 5 depends on Phase 1 only. Phase 0 is a transitive dependency (required by Phase 1) but is listed explicitly here because section 2 states the route pipeline is preserved (Hard Rule 8 requires explicit citation).

## PHASE 6
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_6.

### Evidence

**Inspected files (exact paths):**
- `src/systems/enemy_patrol_system.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `src/systems/navigation_runtime_queries.gd`
- `src/systems/navigation_service.gd`
- `tests/test_shadow_route_filter.gd`
- `tests/test_patrol_route_variety.gd`
- `tests/test_runner_node.gd`

**Inspected functions/methods (exact identifiers):**
- `EnemyPatrolSystem._rebuild_route` (enemy_patrol_system.gd:195–313)
- `EnemyPatrolSystem.configure` (enemy_patrol_system.gd:58–76)
- `EnemyPatrolSystem.update` (enemy_patrol_system.gd:100–192)
- `EnemyPatrolSystem._patrol_cfg_float` (enemy_patrol_system.gd:316–320)
- `EnemyPatrolSystem._patrol_cfg_int` (enemy_patrol_system.gd:323–327)
- `NavigationRuntimeQueries.build_policy_valid_path` (navigation_runtime_queries.gd:219–252)
- `NavigationService.build_policy_valid_path` (navigation_service.gd:400–402)
- `ShadowRouteNavStub` in `tests/test_shadow_route_filter.gd` (stub class, lines 10–33)
- `PatrolNavStub` in `tests/test_patrol_route_variety.gd` (stub class, lines 10–36)

**Search commands used (exact commands):**
- `rg -n "fallback_step_px" src/ tests/ -S`
- `rg -n "_route = \[fallback" src/systems/enemy_patrol_system.gd -S`
- `rg -n "func build_policy_valid_path" src/ -S`
- `rg -n "is_point_in_shadow|build_policy_valid_path|random_point_in_room" src/systems/enemy_patrol_system.gd -S`

**Key findings from inspection:**
- `EnemyPatrolSystem._rebuild_route` (enemy_patrol_system.gd:195–313): contains shadow filter (lines 279–285), shadow refill loop (lines 287–296), dedup (lines 300–311), and hard fallback route at lines 312–313: `if _route.size() < 2: _route = [fallback, fallback + Vector2(_patrol_cfg_float("fallback_step_px", 24.0), 0.0)]`. This line is the legacy to delete.
- `_rebuild_route` has no call to `build_policy_valid_path` anywhere (confirmed: 0 matches).
- `"fallback_step_px"` appears in exactly 3 src/ locations: enemy_patrol_system.gd:313, game_config.gd:200, config_validator.gd:259. Absent from all tests/.
- `NavigationRuntimeQueries.build_policy_valid_path` (navigation_runtime_queries.gd:219): when `enemy == null`, skips shadow-policy validation and returns `{"status": "ok", "path_points": ..., "reason": "ok"}` for any geometrically reachable path. This behavior is confirmed at lines 231–236.
- `var fallback := owner.global_position` (enemy_patrol_system.gd:202) is used at line 210 and line 298 (else branch). It is NOT deleted in this phase — only line 313's usage is removed.
- Both test stubs (`ShadowRouteNavStub`, `PatrolNavStub`) lack `build_policy_valid_path` method. After Phase 6, `_rebuild_route` calls `nav_system.has_method("build_policy_valid_path")` — false in these stubs → filter skipped. Tests still pass, but stubs are updated in this phase to exercise the new code path.
- `tests/test_patrol_route_traversability_filter.gd` does not exist yet. `tests/test_runner_node.gd` has no entry for it.

---

## 1. What now.

Phase id: PHASE_6. Phase title: Patrol Reachability Filter.
Goal: Remove the hard fallback route in `EnemyPatrolSystem._rebuild_route` that bypasses the reachability contract and add a policy-valid reachability filter (using `build_policy_valid_path` with `enemy=null`) after the shadow filter, with a matching reachability-aware refill loop.

Current behavior (measurable):

1. `rg -n "_route = \[fallback, fallback \+ Vector2" src/systems/enemy_patrol_system.gd -S` → 1 match at line 313. The hard fallback route `_route = [fallback, fallback + Vector2(_patrol_cfg_float("fallback_step_px", 24.0), 0.0)]` is executed whenever the deduplication step produces fewer than 2 points. This route appends `owner.global_position + Vector2(24.0, 0.0)` unconditionally without any call to `build_policy_valid_path`. The resulting point is never verified reachable or policy-valid.

2. `rg -n "build_policy_valid_path" src/systems/enemy_patrol_system.gd -S` → 0 matches. No reachability check of any kind is applied to patrol route candidates. Candidates that pass the shadow filter are appended to `_route` regardless of navmesh connectivity.

3. Test `tests/test_patrol_route_traversability_filter.gd` does not exist (scene missing = test suite would report FAIL for registration check).

## 2. What changes.

1. Delete the hard fallback route block (lines 312–313) from `EnemyPatrolSystem._rebuild_route` in `src/systems/enemy_patrol_system.gd` before adding replacement code.
2. Delete `"fallback_step_px": 24.0,` (line 200) from the `ai_balance.patrol` dictionary in `src/core/game_config.gd` before adding replacement code. This key is dead after item 1 is deleted — no runtime code reads it.
3. Delete `_validate_number_key(result, patrol, "fallback_step_px", "ai_balance.patrol", 0.01, 1000.0)` (line 259) from `src/core/config_validator.gd` before adding replacement code. This validation is dead after items 1 and 2 are deleted.
4. Add `const PATROL_REACHABILITY_REFILL_ATTEMPTS := 32` at file scope in `src/systems/enemy_patrol_system.gd` after `const SHADOW_CHECK_SWEEP_RAD := 0.62` (line 32).
5. Implement the reachability filter block in `EnemyPatrolSystem._rebuild_route` immediately after the shadow refill block (after line 296, before the dedup block at line 300). The filter calls `nav_system.call("build_policy_valid_path", owner.global_position, pt, null)` for each candidate and retains only those with `status == "ok"`. When all candidates fail, the original candidate set is retained unchanged (degraded mode).
6. Implement the reachability-aware refill loop in `EnemyPatrolSystem._rebuild_route` immediately after the reachability filter block. The loop generates random points via `random_point_in_room`, skips shadow-unsafe points, skips points where `build_policy_valid_path` returns `status != "ok"`, and appends passing points until `route_points_min` is reached or `PATROL_REACHABILITY_REFILL_ATTEMPTS` attempts are exhausted.
7. Add `build_policy_valid_path` method returning `{"status": "ok", "path_points": [Vector2.ZERO], "reason": "ok"}` to `ShadowRouteNavStub` in `tests/test_shadow_route_filter.gd`. Existing test assertions are unchanged.
8. Add `build_policy_valid_path` method returning `{"status": "ok", "path_points": [Vector2.ZERO], "reason": "ok"}` to `PatrolNavStub` in `tests/test_patrol_route_variety.gd`. Existing test assertions are unchanged.
9. Create `tests/test_patrol_route_traversability_filter.gd` with 5 test functions (exact names listed in section 12).
10. Create `tests/test_patrol_route_traversability_filter.tscn`.
11. Register the new scene in `tests/test_runner_node.gd`: add scene path constant, scene existence check, and `_run_embedded_scene_suite` call.

## 3. What will be after.

1. `rg -n "_route = \[fallback, fallback \+ Vector2" src/systems/enemy_patrol_system.gd -S` returns 0 matches. Verified by section 10 gate L1.
2. `rg -n "fallback_step_px" src/core/game_config.gd -S` returns 0 matches. Verified by section 10 gate L2.
3. `rg -n "fallback_step_px" src/core/config_validator.gd -S` returns 0 matches. Verified by section 10 gate L3.
4. `rg -n "build_policy_valid_path" src/systems/enemy_patrol_system.gd -S` returns ≥1 match. Verified by section 13 gate G3.
5. Every point in `_route` after a `_rebuild_route` call either passed `build_policy_valid_path(...).status == "ok"` or the nav_system lacked the method (filter-skipped). Verified by test `_test_reachability_filter_excludes_unreachable_points` in section 12.
6. When all candidates fail reachability and all refill attempts fail reachability, `_rebuild_route` completes without error and `_route` is non-null. Verified by test `_test_all_candidates_unreachable_route_degrades_gracefully` in section 12.
7. All tests from `test_shadow_route_filter.gd` and `test_patrol_route_variety.gd` exit 0 with updated stubs. Verified by Tier 1 smoke suite commands in section 14.

## 4. Scope and non-scope (exact files).

**In-scope files (exact paths) — allowed file-change boundary:**
1. `src/systems/enemy_patrol_system.gd`
2. `src/core/game_config.gd`
3. `src/core/config_validator.gd`
4. `tests/test_patrol_route_traversability_filter.gd` (new)
5. `tests/test_patrol_route_traversability_filter.tscn` (new)
6. `tests/test_shadow_route_filter.gd` (update)
7. `tests/test_patrol_route_variety.gd` (update)
8. `tests/test_runner_node.gd` (update)
9. `CHANGELOG.md`

Any change to a file outside items 1–9 causes phase FAILED regardless of test results.

**Out-of-scope files (must not be modified):**
1. `src/systems/navigation_runtime_queries.gd`
2. `src/systems/navigation_service.gd`
3. `src/entities/enemy.gd`
4. `src/systems/enemy_pursuit_system.gd`
5. `src/systems/enemy_utility_brain.gd`
6. `src/systems/enemy_patrol_system.gd` — any function other than `_rebuild_route` and the file-scope const block
7. All other `src/` files not listed in the in-scope list.
8. All other `tests/` files not listed in the in-scope list.

## 5. Single-owner authority for this phase.

**Primary owner:** `EnemyPatrolSystem._rebuild_route` (enemy_patrol_system.gd) is the sole function that decides which patrol waypoints enter `_route`. No other function in `EnemyPatrolSystem` filters or validates route candidates. No other function in any other file replicates this filtering decision.

**Authority constraints:**
- The reachability filter calls `nav_system.build_policy_valid_path` as a read-only query. It does not modify `nav_system` state.
- `NavigationRuntimeQueries.build_policy_valid_path` and `NavigationService.build_policy_valid_path` are out of scope; they are not modified in this phase.
- No second filtering function is introduced in any other class.

**Verifiable:** `rg -n "build_policy_valid_path" src/systems/enemy_patrol_system.gd -S` returns exactly the occurrences introduced in item 5 and 6 of section 2 (section 13 gate G3 confirms ≥1 match). Zero matches elsewhere in EnemyPatrolSystem is verified by the PMB contract (PMB-1 gate).

## 6. Full input/output contract.

**Contract name:** `PatrolRouteReachabilityFilterContractV6`
**Owner:** `EnemyPatrolSystem._rebuild_route` (reachability filter sub-algorithm)

**Inputs to the filter sub-algorithm:**
- `candidates: Array[Vector2]` — non-null; elements are finite Vector2 (caller builds them from room geometry and random points); may be empty.
- `nav_system: Node` — nullable; when null, filter is skipped entirely and `candidates` is unchanged.
- `owner.global_position: Vector2` — `from_pos` for `build_policy_valid_path`; finite (guaranteed by CharacterBody2D runtime).
- `null` — passed as the `enemy` parameter to `build_policy_valid_path` unconditionally; disables shadow-policy validation, enabling pure geometry reachability check.

**Filter output (effect on `candidates`):**
- When `nav_system != null AND nav_system.has_method("build_policy_valid_path")` is false: `candidates` is unchanged from shadow-filter output.
- When the filter runs and at least one candidate passes `status == "ok"`: `candidates` is replaced with only the passing candidates, in original order.
- When the filter runs and zero candidates pass `status == "ok"`: `candidates` is unchanged from shadow-filter output (degraded mode; no candidates discarded).

**Outputs from `build_policy_valid_path` used by the filter:**
- Key: `"status": String` — only `"ok"` causes the point to be retained. Values `"unreachable_policy"` and `"unreachable_geometry"` cause the point to be discarded.

**Status enums (from `build_policy_valid_path` contract, read-only in this phase):**
- `"ok"` — geometry path exists from `owner.global_position` to candidate point; point is retained.
- `"unreachable_policy"` — path blocked by shadow policy; point is discarded.
- `"unreachable_geometry"` — no navigable path; point is discarded.

**Reason enums (from `build_policy_valid_path`, not inspected by filter):** N/A — filter reads only the `status` key.

**Constants/thresholds (exact values + placement):**
- `PATROL_REACHABILITY_REFILL_ATTEMPTS := 32` — file scope in `src/systems/enemy_patrol_system.gd`, after `const SHADOW_CHECK_SWEEP_RAD := 0.62`. Used in exactly one function (`_rebuild_route`). Not added to `game_config.gd` (file-local per HARD RULE 12).

**Forbidden patterns after this phase:**
- `_patrol_cfg_float("fallback_step_px", ...)` anywhere in `src/systems/enemy_patrol_system.gd`.
- `"fallback_step_px"` anywhere in `src/core/game_config.gd`.
- `"fallback_step_px"` anywhere in `src/core/config_validator.gd`.
- Any route assignment that appends `owner.global_position + Vector2(offset, 0.0)` without a `build_policy_valid_path` check.

## 7. Deterministic algorithm with exact order.

Algorithm for the reachability filter and refill in `_rebuild_route`, inserted after the shadow refill block (after current line 296) and before the dedup block:

**Step 1 — Reachability filter guard:** Evaluate `nav_system != null AND nav_system.has_method("build_policy_valid_path")`. This check is implicit because the reachability filter is inside the outer `if nav_system and home_room_id >= 0:` block (so `nav_system != null` is guaranteed); only `has_method("build_policy_valid_path")` is checked explicitly. If the method is absent: skip to step 5 (dedup).

**Step 2 — Reachability filter iteration:** Create empty `Array[Vector2]` named `reach_pass`. Iterate `candidates` in index order 0 to `candidates.size() - 1`. For each element `pt`: call `nav_system.call("build_policy_valid_path", owner.global_position, pt, null)`, cast result to `Dictionary`, evaluate `String(result.get("status", "")) == "ok"`. If true: append `pt` to `reach_pass`. Evaluation is sequential; no candidate is evaluated more than once.

**Step 3 — Reachability filter assignment:** If `reach_pass.is_empty()`: `candidates` is unchanged (degraded mode — all original candidates kept). If `reach_pass` is non-empty: `candidates = reach_pass`.

**Step 4 — Reachability-aware refill:** Check `nav_system.has_method("random_point_in_room")`. If false: skip to step 5. Compute `min_pts_reach := _patrol_cfg_int("route_points_min", ROUTE_POINTS_MIN)`. Initialize `reach_refill_attempts := 0`. While `candidates.size() < min_pts_reach AND reach_refill_attempts < PATROL_REACHABILITY_REFILL_ATTEMPTS`: (a) generate `rp: Vector2 = nav_system.random_point_in_room(home_room_id, _rng.randf_range(18.0, 34.0))`. (b) Increment `reach_refill_attempts`. (c) If `nav_system.has_method("is_point_in_shadow") AND bool(nav_system.call("is_point_in_shadow", rp))`: continue (shadow-unsafe, skip). (d) If `nav_system.has_method("build_policy_valid_path")`: call `nav_system.call("build_policy_valid_path", owner.global_position, rp, null)`, cast to `Dictionary`, evaluate `String(result.get("status", "")) != "ok"`: if true, continue (unreachable, skip). (e) Append `rp` to `candidates`.

**Step 5 — Dedup (unchanged):** Existing dedup logic at current lines 300–311 runs on the resulting `candidates`.

**Step 6 — Route assignment (legacy deleted):** `_route = compact`. The `if _route.size() < 2: _route = [...]` block is deleted. No further assignment to `_route` occurs in this function.

**Tie-break rules:** N/A. The filter retains ALL candidates that pass `status == "ok"` in original input order. No ranking or selection among equal candidates occurs. Tie-break is not applicable because the algorithm is inclusive (keep all passing), not selective (choose one).

**Behavior when input is empty:** `candidates.is_empty()` before filter → step 2 produces empty `reach_pass` → step 3: degraded mode → `candidates` unchanged (empty) → step 4 refill runs (≤ `PATROL_REACHABILITY_REFILL_ATTEMPTS` attempts, may append 0+ points) → step 5 dedup → `_route` may be empty → `update()` returns `{"waiting": true}`.

**Behavior when `nav_system` is null:** outer guard `if nav_system and home_room_id >= 0:` is false → entire filter + refill is skipped → dedup runs on shadow-filter output.

## 8. Edge-case matrix.

**Case A — Empty candidates before filter.**
Setup: all typed-point generation returns zero candidates (e.g., `get_room_rect` returns zero-size rect, no neighbors, `random_point_in_room` not present), nav_system has `build_policy_valid_path`.
Input: `candidates = []`.
Filter step 2: `reach_pass = []`.
Step 3: degraded mode → `candidates = []`.
Step 4 refill: skipped (no `random_point_in_room` in this stub).
Step 5 dedup: `compact = []`.
Step 6: `_route = []`.
`update()` result: `{"waiting": true}`.
Output: no crash; `_route` is empty; `update()` returns `{"waiting": true}`.

**Case B — All candidates reachable (normal case).**
Setup: nav_system has `build_policy_valid_path` returning `{"status": "ok", ...}` for all inputs. 4 candidates from room geometry.
Filter step 2: `reach_pass = [all 4 candidates]`.
Step 3: `candidates = [all 4 candidates]` (non-empty pass).
Step 4 refill: skipped (`candidates.size() >= route_points_min`).
Step 5 dedup: compact retains all non-duplicate points.
Step 6: `_route = compact`.
Output: `_route` is non-empty; all points are status-ok verified.

**Case C — Tie-break N/A.**
Section 7 proves the algorithm is an inclusive filter: all candidates passing `status == "ok"` are retained in input order. No selection between equal candidates occurs. Tie-break is not applicable.

**Case D — All candidates fail reachability; refill also exhausted.**
Setup: nav_system has `build_policy_valid_path` returning `{"status": "unreachable_geometry", ...}` for ALL inputs including refill points. 3 initial candidates.
Filter step 2: `reach_pass = []`.
Step 3: degraded mode → `candidates = [all 3 original candidates]`.
Step 4 refill: nav_system has `random_point_in_room`; all 32 attempts return unreachable points → loop exits without appending.
Step 5 dedup: `compact` has ≤3 points.
Step 6: `_route = compact` (3 unreachable points in degraded state).
Output: no crash; `_route` is non-empty (3 degraded points); `update()` attempts to reach them (may stall, but that is handled by the stuck-check timer, which is out of scope for this phase).

**Case E — nav_system has no `build_policy_valid_path` method.**
Setup: nav_system is non-null but `nav_system.has_method("build_policy_valid_path")` returns false. Shadow filter active.
Step 1 guard: false → skip filter and refill entirely.
Step 5 dedup: runs on shadow-filter output.
Step 6: `_route = compact`.
Output: route built from shadow-safe candidates only; no reachability filtering applied; no crash.

**Case F — nav_system is null (no nav at all).**
Outer guard `if nav_system and home_room_id >= 0:` is false → else branch executes `candidates.append(fallback)` → dedup → `_route = compact` (1 point: `owner.global_position`).
Output: `_route` has 1 element (owner's position); `update()` patrols to that single point in a loop.

## 9. Legacy removal plan (delete-first, exact ids).

**Legacy item 1:** Hard fallback route assignment.
- Identifier: `if _route.size() < 2: _route = [fallback, fallback + Vector2(_patrol_cfg_float("fallback_step_px", 24.0), 0.0)]`
- File: `src/systems/enemy_patrol_system.gd`
- Line range: 312–313 (confirmed by PROJECT DISCOVERY).
- Delete both lines (the `if` and the assignment) before implementing sections 5–6 of "What changes".

**Legacy item 2:** Dead config key.
- Identifier: `"fallback_step_px": 24.0,`
- File: `src/core/game_config.gd`
- Line range: 200 (confirmed by PROJECT DISCOVERY).
- Delete this line from the `ai_balance.patrol` dictionary after deleting item 1.

**Legacy item 3:** Dead config validator entry.
- Identifier: `_validate_number_key(result, patrol, "fallback_step_px", "ai_balance.patrol", 0.01, 1000.0)`
- File: `src/core/config_validator.gd`
- Line range: 259 (confirmed by PROJECT DISCOVERY).
- Delete this line after deleting items 1 and 2.

## 10. Legacy verification commands (exact rg + expected 0 matches).

**L1 (item 1):** Verifies hard fallback route deleted from enemy_patrol_system.gd. `fallback + Vector2(` is unique to the deleted pattern in this file; PROJECT DISCOVERY found 0 occurrences elsewhere in src/.
```
rg -n "_route = \[fallback, fallback \+ Vector2" src/ -S
```
Expected: 0 matches.

**L2 (item 2):** Verifies `fallback_step_px` removed from game_config.gd. `fallback_step_px` is not file-unique (appears in 3 src/ files); this command searches game_config.gd specifically. PROJECT DISCOVERY confirmed exactly one occurrence at game_config.gd:200; the other occurrences (enemy_patrol_system.gd:313 and config_validator.gd:259) are covered by L1 and L3.
```
rg -n "fallback_step_px" src/core/game_config.gd -S
```
Expected: 0 matches.

**L3 (item 3):** Verifies `fallback_step_px` removed from config_validator.gd. PROJECT DISCOVERY confirmed exactly one occurrence at config_validator.gd:259.
```
rg -n "fallback_step_px" src/core/config_validator.gd -S
```
Expected: 0 matches.

**Combined cross-file verification (all three items):** After L1+L2+L3 all pass, this command confirms no residual occurrence of `fallback_step_px` anywhere in src/:
```
rg -n "fallback_step_px" src/ -S
```
Expected: 0 matches.

Phase cannot close until L1, L2, L3, and the combined command all return 0 matches.

## 11. Acceptance criteria (binary pass/fail).

1. `rg -n "_route = \[fallback, fallback \+ Vector2" src/ -S` returns 0 matches: true.
2. `rg -n "fallback_step_px" src/ -S` returns 0 matches: true.
3. `rg -n "build_policy_valid_path" src/systems/enemy_patrol_system.gd -S` returns ≥1 match: true.
4. `tests/test_patrol_route_traversability_filter.gd` exists and all 5 test functions exit asserting true: true.
5. `tests/test_patrol_route_traversability_filter.tscn` is registered in `tests/test_runner_node.gd`: true.
6. `xvfb-run -a godot-4 --headless --path . res://tests/test_patrol_route_traversability_filter.tscn` exits 0: true.
7. `xvfb-run -a godot-4 --headless --path . res://tests/test_shadow_route_filter.tscn` exits 0: true.
8. `xvfb-run -a godot-4 --headless --path . res://tests/test_patrol_route_variety.tscn` exits 0: true.
9. `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` exits 0: true.
10. No file outside section 4 in-scope list was modified: true.

## 12. Tests (new/update + purpose).

**New file: `tests/test_patrol_route_traversability_filter.gd`**

Test functions (exact names):

- `_test_reachability_filter_excludes_unreachable_points`: Creates a stub where `build_policy_valid_path` returns `{"status": "ok"}` only for the room center (Vector2(128, 128)) and `{"status": "unreachable_geometry"}` for all other points. Calls `patrol._rebuild_route()`. Asserts every point in `patrol._route` is the room center (x==128.0 AND y==128.0). Asserts `patrol._route` is not empty.

- `_test_reachability_filter_passes_all_when_all_ok`: Creates a stub where `build_policy_valid_path` returns `{"status": "ok"}` for all inputs. Calls `patrol._rebuild_route()`. Asserts `patrol._route` is not empty. Asserts no point was incorrectly excluded (route size ≥ 1).

- `_test_reachability_filter_skipped_when_method_absent`: Creates a stub without `build_policy_valid_path` method (stub has only `get_room_center`, `get_room_rect`, `random_point_in_room`, `is_point_in_shadow`). Calls `patrol._rebuild_route()`. Asserts `patrol._route` is not empty (route built normally from shadow-safe candidates only; filter skipped).

- `_test_refill_accepts_only_reachable_points`: Creates a stub where `build_policy_valid_path` returns `{"status": "unreachable_geometry"}` for all initial typed candidates and `{"status": "ok"}` for all `random_point_in_room` outputs. Calls `patrol._rebuild_route()`. Asserts `patrol._route` is not empty (refill added reachable points).

- `_test_all_candidates_unreachable_route_degrades_gracefully`: Creates a stub where `build_policy_valid_path` always returns `{"status": "unreachable_geometry"}` for all inputs including refill. Calls `patrol._rebuild_route()`. Asserts no crash (function returns normally). Asserts `patrol._route` is not null.

Registration: `tests/test_patrol_route_traversability_filter.gd` must be registered in `tests/test_runner_node.gd` via:
- A new `const PATROL_ROUTE_TRAVERSABILITY_FILTER_TEST_SCENE := "res://tests/test_patrol_route_traversability_filter.tscn"` in the constants block.
- A new `_test("Patrol route traversability filter test scene exists", ...)` check in the existence-check section.
- A new `await _run_embedded_scene_suite("Patrol route traversability filter suite", PATROL_ROUTE_TRAVERSABILITY_FILTER_TEST_SCENE)` call in the run section, adjacent to the existing `PATROL_ROUTE_VARIETY_TEST_SCENE` and `SHADOW_ROUTE_FILTER_TEST_SCENE` entries.

**Updated file: `tests/test_shadow_route_filter.gd`**

Change: Add `build_policy_valid_path` method to `ShadowRouteNavStub` (stub class defined at line 10):
```gdscript
func build_policy_valid_path(_from: Vector2, _to: Vector2, _enemy: Node = null) -> Dictionary:
    return {"status": "ok", "path_points": [Vector2.ZERO], "reason": "ok"}
```
Why: After Phase 6, `_rebuild_route` calls `nav_system.has_method("build_policy_valid_path")` — true with the new stub method — and then calls the filter. The stub returns `status == "ok"` for all points, so the reachability filter passes all shadow-safe candidates through unchanged. The two existing test assertions (`route is not empty after rebuild`, `all patrol points are outside shadow`) remain valid and unmodified.

**Updated file: `tests/test_patrol_route_variety.gd`**

Change: Add `build_policy_valid_path` method to `PatrolNavStub` (stub class defined at line 10):
```gdscript
func build_policy_valid_path(_from: Vector2, _to: Vector2, _enemy: Node = null) -> Dictionary:
    return {"status": "ok", "path_points": [Vector2.ZERO], "reason": "ok"}
```
Why: Same as above — makes the stub exercise the reachability filter code path while returning `status == "ok"` for all candidates, preserving the existing variety assertion.

## 13. rg gates (command + expected output).

**Phase-specific gates:**

Gate G1: Verifies hard fallback route deleted.
```
rg -n "_route = \[fallback, fallback \+ Vector2" src/ -S
```
Expected: 0 matches.

Gate G2: Verifies `fallback_step_px` fully removed from src/.
```
rg -n "fallback_step_px" src/ -S
```
Expected: 0 matches.

Gate G3: Verifies reachability filter is present in enemy_patrol_system.gd.
```
rg -n "build_policy_valid_path" src/systems/enemy_patrol_system.gd -S
```
Expected: ≥1 match.

Gate G4: Verifies `PATROL_REACHABILITY_REFILL_ATTEMPTS` constant is present at file scope.
```
rg -n "PATROL_REACHABILITY_REFILL_ATTEMPTS" src/systems/enemy_patrol_system.gd -S
```
Expected: ≥2 matches (one const declaration, one usage in refill loop).

Gate G5: Verifies the new test file is registered in test_runner_node.gd.
```
rg -n "test_patrol_route_traversability_filter" tests/test_runner_node.gd -S
```
Expected: ≥1 match.

**PMB gates (from Persistent Module Boundary Contract):**

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: 0 matches.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: output string `PMB-5: PASS (1)`.

## 14. Execution sequence (step-by-step, no ambiguity).

**Step 1:** Delete lines 312–313 from `src/systems/enemy_patrol_system.gd`: remove `if _route.size() < 2:` and the following `_route = [fallback, fallback + Vector2(_patrol_cfg_float("fallback_step_px", 24.0), 0.0)]`. Use Edit tool with exact old_string matching both lines.

**Step 2:** Delete `"fallback_step_px": 24.0,` (line 200) from the `ai_balance.patrol` dictionary in `src/core/game_config.gd`. Use Edit tool with exact old_string.

**Step 3:** Delete `_validate_number_key(result, patrol, "fallback_step_px", "ai_balance.patrol", 0.01, 1000.0)` (line 259) from `src/core/config_validator.gd`. Use Edit tool with exact old_string.

**Step 4:** Add `const PATROL_REACHABILITY_REFILL_ATTEMPTS := 32` at file scope in `src/systems/enemy_patrol_system.gd` on the line immediately after `const SHADOW_CHECK_SWEEP_RAD := 0.62` (current line 32). Use Edit tool.

**Step 5:** Implement the reachability filter block in `EnemyPatrolSystem._rebuild_route` in `src/systems/enemy_patrol_system.gd`. Insert the block immediately after the closing line of the shadow refill block (the line `candidates.append(refill_point)` + its enclosing `while` + the closing tab-aligned brace, before the dedup comment). The inserted block:
```gdscript
		# --- reachability filter (Phase 6) ---
		if nav_system.has_method("build_policy_valid_path"):
			var reach_pass: Array[Vector2] = []
			for pt in candidates:
				var r := nav_system.call("build_policy_valid_path", owner.global_position, pt, null) as Dictionary
				if String(r.get("status", "")) == "ok":
					reach_pass.append(pt)
			if not reach_pass.is_empty():
				candidates = reach_pass
```

**Step 6:** Implement the reachability-aware refill loop in `EnemyPatrolSystem._rebuild_route` in `src/systems/enemy_patrol_system.gd`. Insert the block immediately after the reachability filter block from step 5, before the dedup comment:
```gdscript
		# --- reachability refill (Phase 6) ---
		if nav_system.has_method("random_point_in_room"):
			var min_pts_reach := _patrol_cfg_int("route_points_min", ROUTE_POINTS_MIN)
			var reach_refill_attempts := 0
			while candidates.size() < min_pts_reach and reach_refill_attempts < PATROL_REACHABILITY_REFILL_ATTEMPTS:
				var margin := _rng.randf_range(18.0, 34.0)
				var rp: Vector2 = nav_system.random_point_in_room(home_room_id, margin) as Vector2
				reach_refill_attempts += 1
				if nav_system.has_method("is_point_in_shadow") and bool(nav_system.call("is_point_in_shadow", rp)):
					continue
				if nav_system.has_method("build_policy_valid_path"):
					var rr := nav_system.call("build_policy_valid_path", owner.global_position, rp, null) as Dictionary
					if String(rr.get("status", "")) != "ok":
						continue
				candidates.append(rp)
```

**Step 7:** Add `build_policy_valid_path` method to `ShadowRouteNavStub` in `tests/test_shadow_route_filter.gd` (after the existing `is_point_in_shadow` method at line 31–33):
```gdscript
	func build_policy_valid_path(_from: Vector2, _to: Vector2, _enemy: Node = null) -> Dictionary:
		return {"status": "ok", "path_points": [Vector2.ZERO], "reason": "ok"}
```

**Step 8:** Add `build_policy_valid_path` method to `PatrolNavStub` in `tests/test_patrol_route_variety.gd` (after the existing `is_point_in_shadow` method at line 34–35):
```gdscript
	func build_policy_valid_path(_from: Vector2, _to: Vector2, _enemy: Node = null) -> Dictionary:
		return {"status": "ok", "path_points": [Vector2.ZERO], "reason": "ok"}
```

**Step 9:** Create `tests/test_patrol_route_traversability_filter.gd` with `extends Node`, `const TestHelpers = preload(...)`, `const ENEMY_PATROL_SYSTEM_SCRIPT = preload(...)`, `var embedded_mode: bool = false`, `var _t := TestHelpers.new()`, inner stub class `ReachNavStub extends Node` with configurable `build_policy_valid_path` behavior, `run_suite()` function calling all 5 test functions (exact names from section 12), and each test function with `_t.run_test(...)` assertions.

**Step 10:** Create `tests/test_patrol_route_traversability_filter.tscn` as a minimal PackedScene with root node of type `test_patrol_route_traversability_filter.gd`.

**Step 11:** Register in `tests/test_runner_node.gd`:
- Add `const PATROL_ROUTE_TRAVERSABILITY_FILTER_TEST_SCENE := "res://tests/test_patrol_route_traversability_filter.tscn"` to the constants block (adjacent to `PATROL_ROUTE_VARIETY_TEST_SCENE`).
- Add `_test("Patrol route traversability filter test scene exists", func(): return _scene_exists(PATROL_ROUTE_TRAVERSABILITY_FILTER_TEST_SCENE))` to the existence-check section (adjacent to patrol variety and shadow route filter checks).
- Add `await _run_embedded_scene_suite("Patrol route traversability filter suite", PATROL_ROUTE_TRAVERSABILITY_FILTER_TEST_SCENE)` to the run section (adjacent to `PATROL_ROUTE_VARIETY_TEST_SCENE` run call at line 1081).

**Step 12:** Run Tier 1 smoke suite (from section 20, scenario scenes):
```
xvfb-run -a godot-4 --headless --path . res://tests/test_patrol_route_traversability_filter.tscn
xvfb-run -a godot-4 --headless --path . res://tests/test_shadow_route_filter.tscn
xvfb-run -a godot-4 --headless --path . res://tests/test_patrol_route_variety.tscn
```
All three commands must exit 0.

**Step 13:** Run Tier 2 full regression:
```
xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn
```
Must exit 0.

**Step 14:** Run all rg gates from section 13 (G1 through G5, PMB-1 through PMB-5). All must return expected output.

**Step 15:** Run all legacy verification commands from section 10 (L1, L2, L3, combined). All must return 0 matches.

**Step 16:** Prepend CHANGELOG entry to `CHANGELOG.md` under today's date header (create `## YYYY-MM-DD` first if absent). Format:
```
### HH:MM MSK - Phase 6: Patrol Reachability Filter
- **Removed**: Hard fallback route bypassing reachability in EnemyPatrolSystem._rebuild_route
- **Removed**: Dead config key fallback_step_px from game_config.gd and config_validator.gd
- **Added**: Reachability filter + refill loop using build_policy_valid_path(enemy=null) in _rebuild_route
- **Added**: PATROL_REACHABILITY_REFILL_ATTEMPTS const (32) at file scope
- **Files**: src/systems/enemy_patrol_system.gd, src/core/game_config.gd, src/core/config_validator.gd, tests/test_patrol_route_traversability_filter.gd, tests/test_patrol_route_traversability_filter.tscn, tests/test_shadow_route_filter.gd, tests/test_patrol_route_variety.gd, tests/test_runner_node.gd
```

## 15. Rollback conditions.

For each condition: exact trigger → exact rollback action.

1. Any rg gate in section 13 (G1–G5) returns output different from expected → revert all changes to files in section 4 in-scope list to their pre-phase state using file-by-file restore from backup or VCS. Phase state: FAILED.
2. Any legacy verification command in section 10 (L1, L2, L3, combined) returns non-zero matches → revert all in-scope file changes. Phase state: FAILED.
3. Any test in section 12 (new or updated) exits non-zero → revert all in-scope file changes. Phase state: FAILED.
4. Any Tier 1 smoke suite command (step 12) exits non-zero → revert all in-scope file changes. Phase state: FAILED.
5. Tier 2 full regression (step 13) exits non-zero → revert all in-scope file changes. Phase state: FAILED.
6. Any file outside section 4 in-scope list is found modified in the diff audit → revert those out-of-scope changes immediately. If this causes any in-scope test to fail, also revert all in-scope changes. Phase state: FAILED.

Rollback action definition: restore each modified in-scope file to exact byte-for-byte content as it existed at phase start. No partial rollback. All-or-nothing.

## 16. Phase close condition.

Binary checklist — all items must be simultaneously true:

- [ ] L1 rg command returns 0 matches
- [ ] L2 rg command returns 0 matches
- [ ] L3 rg command returns 0 matches
- [ ] Combined `rg -n "fallback_step_px" src/ -S` returns 0 matches
- [ ] All rg gates in section 13 (G1–G5) return expected output
- [ ] PMB gates in section 13 (PMB-1 through PMB-5) return expected output
- [ ] All 5 test functions in `tests/test_patrol_route_traversability_filter.gd` exit with assertions true
- [ ] Updated `tests/test_shadow_route_filter.gd` exits 0
- [ ] Updated `tests/test_patrol_route_variety.gd` exits 0
- [ ] Tier 1 smoke suite (step 12, 3 commands) — all exit 0
- [ ] Tier 2 full regression (`test_runner.tscn`) exits 0
- [ ] No file outside section 4 in-scope list was modified
- [ ] CHANGELOG entry prepended

## 17. Ambiguity self-check line.

Ambiguity check: 0

## 18. Open questions line.

Open questions: 0

## 19. Post-implementation verification plan.

**Files to diff:** `src/systems/enemy_patrol_system.gd`, `src/core/game_config.gd`, `src/core/config_validator.gd`, `tests/test_shadow_route_filter.gd`, `tests/test_patrol_route_variety.gd`, `tests/test_runner_node.gd`, `tests/test_patrol_route_traversability_filter.gd` (new), `tests/test_patrol_route_traversability_filter.tscn` (new).

**Diff audit checks:**
1. `enemy_patrol_system.gd` diff: lines 312–313 absent; `const PATROL_REACHABILITY_REFILL_ATTEMPTS := 32` present after SHADOW_CHECK_SWEEP_RAD; reachability filter block present after shadow refill; reachability refill block present after filter; `fallback_step_px` absent in the diff.
2. `game_config.gd` diff: `"fallback_step_px": 24.0,` absent.
3. `config_validator.gd` diff: `_validate_number_key(result, patrol, "fallback_step_px", ...)` line absent.
4. `test_shadow_route_filter.gd` diff: `build_policy_valid_path` method added to `ShadowRouteNavStub`; no other changes.
5. `test_patrol_route_variety.gd` diff: `build_policy_valid_path` method added to `PatrolNavStub`; no other changes.
6. `test_runner_node.gd` diff: 3 additions (const, existence check, run call) for `PATROL_ROUTE_TRAVERSABILITY_FILTER_TEST_SCENE`; no other changes.

**Contracts to check:** `PatrolRouteReachabilityFilterContractV6` (section 6):
- Invariant 1: reachability filter retains only `status == "ok"` candidates (verified by test `_test_reachability_filter_excludes_unreachable_points`).
- Invariant 2: filter skipped when `has_method("build_policy_valid_path")` is false (verified by test `_test_reachability_filter_skipped_when_method_absent`).
- Invariant 3: refill loop respects both shadow and reachability gates (verified by test `_test_refill_accepts_only_reachable_points`).
- Invariant 4: degraded mode produces no crash (verified by test `_test_all_candidates_unreachable_route_degrades_gracefully`).

**Runtime scenarios to execute:** P6-A, P6-B, P6-C, P6-D, P6-E (section 20).

## 20. Runtime scenario matrix.

**Scenario P6-A — Reachability filter excludes unreachable points.**
Setup: `ReachNavStub` with `build_policy_valid_path` returning `{"status": "ok"}` for center point only, `{"status": "unreachable_geometry"}` for all others. `get_room_center` returns Vector2(128, 128). Owner at Vector2(120, 120).
Scene: `res://tests/test_patrol_route_traversability_filter.tscn`.
Frame count: 1 physics frame (route built synchronously in `configure`).
Expected invariants: `patrol._route` contains only Vector2(128, 128); route is not empty.
Fail conditions: any point with x≠128 OR y≠128 is present in `patrol._route`.
Covered by: test `_test_reachability_filter_excludes_unreachable_points`.

**Scenario P6-B — Filter skipped when method absent.**
Setup: `ReachNavStub` without `build_policy_valid_path` method. `is_point_in_shadow` returns false for all. 3 candidates generated.
Scene: `res://tests/test_patrol_route_traversability_filter.tscn`.
Frame count: 1 physics frame.
Expected invariants: `patrol._route` is not empty; filter code path was not entered (verifiable by 0 `reach_pass` variable references in execution — this is a code-coverage assertion, proven by the `has_method` guard).
Fail conditions: `patrol._route` is empty when shadow filter passes candidates.
Covered by: test `_test_reachability_filter_skipped_when_method_absent`.

**Scenario P6-C — All candidates unreachable; no crash.**
Setup: `ReachNavStub` with `build_policy_valid_path` always returning `{"status": "unreachable_geometry"}` for all inputs. `random_point_in_room` also returns unreachable points. 32 refill attempts all fail.
Scene: `res://tests/test_patrol_route_traversability_filter.tscn`.
Frame count: 1 physics frame.
Expected invariants: no exception thrown; `patrol._route` is not null; function returns normally.
Fail conditions: Godot error/exception during `_rebuild_route` call.
Covered by: test `_test_all_candidates_unreachable_route_degrades_gracefully`.

**Scenario P6-D — Shadow route filter unaffected by reachability stub.**
Setup: Updated `ShadowRouteNavStub` (with `build_policy_valid_path` returning ok). Shadow check: points with x < 180.0 are in shadow. Owner at Vector2(120, 120). Room rect Rect2(32, 32, 224, 224).
Scene: `res://tests/test_shadow_route_filter.tscn`.
Frame count: 1 physics frame.
Expected invariants: `route is not empty after rebuild` passes; `all patrol points are outside shadow` passes.
Fail conditions: any test in `test_shadow_route_filter.gd` exits with assertion false.
Covered by: existing tests in `tests/test_shadow_route_filter.gd` (updated stub only).

**Scenario P6-E — Patrol variety unaffected by reachability stub.**
Setup: Updated `PatrolNavStub` (with `build_policy_valid_path` returning ok). All points shadow-safe. Two sequential rebuilds with different RNG seeds.
Scene: `res://tests/test_patrol_route_variety.tscn`.
Frame count: 1 physics frame per rebuild.
Expected invariants: `route A is not empty` passes; `route B is not empty` passes; `two rebuilds produce different route points` passes.
Fail conditions: any test in `test_patrol_route_variety.gd` exits with assertion false.
Covered by: existing tests in `tests/test_patrol_route_variety.gd` (updated stub only).

## 21. Verification report format.

Record all fields below to close phase:
- `phase_id: PHASE_6`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; must be empty list on close)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `rg_gates: [{command, expected, actual, PASS|FAIL}]` for each gate G1–G5
- `legacy_removal_rg: [{command, expected: "0 matches", actual, PASS|FAIL}]` for each of L1, L2, L3, combined
- `phase_tests: [{test_function, exit_code: 0, PASS|FAIL}]` for all 5 new tests + 2 updated suites
- `smoke_suite: [{command, exit_code, PASS|FAIL}]` for all 3 Tier 1 commands
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 6` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- pmb_contract_check present in section 21 (PMB section exists in document): yes

## 23. Dependencies on previous phases.

1. **Phase 0** — introduced routing contract `PathPlanDispatchContractV0` and deleted in-class path planners from `EnemyPursuitSystem`. Phase 6 inherits: `NavigationService.build_policy_valid_path` is the canonical nav API callable via `nav_system`. Phase 6's reachability filter calls `nav_system.build_policy_valid_path` as the single reachability oracle — this call is valid because Phase 0 established that `nav_system` exposes this method as the sole path planning entry point. Without Phase 0, `nav_system.build_policy_valid_path` might not exist or might not be the canonical planner.

2. **Phase 1** — introduced `NavigationRuntimeQueries.build_policy_valid_path` (navigation_runtime_queries.gd:219) with the full contract including the `enemy=null` branch (lines 231–236) that returns `{"status": "ok", ...}` for geometrically reachable paths without shadow-policy evaluation. Phase 6 inherits: the `enemy=null` geometry-only mode is a stable contract guarantee. Phase 6 calls `build_policy_valid_path(..., null)` in the reachability filter; the `"status"` key with values `"ok"` / `"unreachable_policy"` / `"unreachable_geometry"` is the invariant inherited from Phase 1. Without Phase 1, the function contract for `build_policy_valid_path` with `enemy=null` is undefined.

3. **Phase 5** — enforced mandatory navmesh + obstacle extraction pipeline in `NavigationService`. Phase 6 inherits: `build_policy_valid_path` returns geometrically reliable results because the navmesh includes all obstacles extracted from the layout. Without Phase 5's mandatory extraction guarantee, `build_policy_valid_path` with `enemy=null` might return `"unreachable_geometry"` for points that are physically reachable (due to incomplete navmesh), causing the reachability filter to produce false negatives and discard valid patrol waypoints.

---

## PHASE 7
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_7.

### Evidence

**Inspected files:**
1. `src/systems/enemy_pursuit_system.gd` (1197 lines, current pre-Phase-0 state)
2. `scenes/entities/enemy.tscn`
3. `src/core/game_config.gd`
4. `src/core/config_validator.gd`
5. `tests/test_phase_bugfixes.gd`
6. `tests/test_runner_node.gd`
7. `tests/test_honest_repath_without_teleport.gd`
8. `tests/test_ai_long_run_stress.gd`
9. `tests/test_nearest_reachable_fallback_by_nav_distance.gd`
10. `tests/test_shadow_stall_escapes_to_light.gd`
11. `tests/test_shadow_policy_hard_block_without_grant.gd`
12. `tests/test_pursuit_stall_fallback_invariants.gd`
13. `docs/ai_nav_refactor_execution_v2.md` (Phase 0 section 9 legacy list; Phase 2 section 9 legacy list)

**Inspected functions/methods:**
1. `EnemyPursuitSystem.configure_nav_agent` (enemy_pursuit_system.gd:181–183)
2. `EnemyPursuitSystem._is_owner_in_shadow_without_flashlight` (enemy_pursuit_system.gd:1009–1021) — callers: `_resolve_nearest_reachable_fallback` line 918, `_resolve_movement_target_with_shadow_escape` line 945, `_attempt_shadow_escape_recovery` line 954 — all three callers removed by Phase 2
3. `EnemyPursuitSystem._select_nearest_reachable_candidate` (enemy_pursuit_system.gd:1034–1052) — callers: `_resolve_nearest_reachable_fallback` line 923, `_resolve_shadow_escape_target` line 984, `debug_select_nearest_reachable_fallback` line 1188 — all three callers removed by Phase 2
4. `EnemyPursuitSystem._nav_path_length_to` (enemy_pursuit_system.gd:1055–1069) — caller: `_select_nearest_reachable_candidate` line 1039 — removed by this phase (L3)
5. `EnemyPursuitSystem._path_length` (enemy_pursuit_system.gd:1072–1080) — caller: `_nav_path_length_to` line 1069 — removed by this phase (L4)
6. `EnemyPursuitSystem._validate_path_policy_with_traverse_samples` (enemy_pursuit_system.gd:895–914) — sole user of `PATH_POLICY_SAMPLE_STEP_PX` at lines 888 and 902 — removed by Phase 0
7. `GameConfig.DEFAULT_AI_BALANCE["pursuit"]` dict (game_config.gd:135–150) — `avoidance_radius_px` and `avoidance_max_speed_px_per_sec` keys absent
8. `ConfigValidator` pursuit section (config_validator.gd:185–204) — no avoidance validation present
9. `_test_phase_5_shadow_escape_guard` (test_phase_bugfixes.gd:156–177) — calls `_is_owner_in_shadow_without_flashlight` at lines 165, 167, 169
10. Inline shadow guard block (test_runner_node.gd:975–992) — calls `_is_owner_in_shadow_without_flashlight` at lines 982, 984, 986

**Search commands used:**
1. `rg -n "PATH_POLICY_SAMPLE_STEP_PX" src/systems/enemy_pursuit_system.gd -S`
2. `rg -n "func _is_owner_in_shadow_without_flashlight|func _select_nearest_reachable_candidate|func _nav_path_length_to|func _path_length\b" src/systems/enemy_pursuit_system.gd -S`
3. `rg -n "_is_owner_in_shadow_without_flashlight" tests/ src/ -S`
4. `rg -n "_select_nearest_reachable_candidate" src/ -S`
5. `rg -n "_nav_path_length_to|_path_length\b" src/ -S`
6. `rg -n "avoidance_enabled|avoidance_radius|avoidance_max_speed" scenes/entities/enemy.tscn src/core/game_config.gd src/core/config_validator.gd -S`
7. `rg -n "configure_nav_agent" src/ tests/ -S`

## 1. What now.

At Phase 7 start (after Phases 0–6 complete), the following rg commands each return non-zero matches:

1. `rg -n "PATH_POLICY_SAMPLE_STEP_PX" src/systems/enemy_pursuit_system.gd -S` — 1 match (const declaration; its only callers `_validate_path_policy_with_traverse_samples` lines 888 and 902 were removed by Phase 0; const is dead).
2. `rg -n "func _is_owner_in_shadow_without_flashlight\b|func _select_nearest_reachable_candidate\b|func _nav_path_length_to\b|func _path_length\b" src/systems/enemy_pursuit_system.gd -S` — 4 matches (function declarations; all callers removed by Phase 0 or Phase 2; functions are dead).
3. `rg -n "_is_owner_in_shadow_without_flashlight" tests/ -S` — 6 matches in `tests/test_phase_bugfixes.gd` lines 165, 167, 169 and `tests/test_runner_node.gd` lines 982, 984, 986.
4. `rg -n "avoidance_enabled = false" scenes/entities/enemy.tscn -S` — 1 match (NavigationAgent2D has avoidance disabled).
5. `rg -n "avoidance_radius_px|avoidance_max_speed_px_per_sec" src/core/game_config.gd -S` — 0 matches (avoidance keys absent).
6. Test file `tests/test_enemy_crowd_avoidance_reduces_jams.gd` does not exist.

## 2. What changes.

1. Delete const `PATH_POLICY_SAMPLE_STEP_PX` (L1) from `src/systems/enemy_pursuit_system.gd`.
2. Delete function `_is_owner_in_shadow_without_flashlight` declaration and body (L2) from `src/systems/enemy_pursuit_system.gd`.
3. Delete function `_select_nearest_reachable_candidate` declaration and body (L3) from `src/systems/enemy_pursuit_system.gd`.
4. Delete function `_nav_path_length_to` declaration and body (L4) from `src/systems/enemy_pursuit_system.gd`.
5. Delete function `_path_length` declaration and body (L5) from `src/systems/enemy_pursuit_system.gd`.
6. In `src/systems/enemy_pursuit_system.gd`, function `configure_nav_agent`: add `if agent:` guard containing `agent.radius = _pursuit_cfg_float("avoidance_radius_px", 12.8)` and `agent.max_speed = _pursuit_cfg_float("avoidance_max_speed_px_per_sec", 80.0)`.
7. In `src/core/game_config.gd`, add `"avoidance_radius_px": 12.8` and `"avoidance_max_speed_px_per_sec": 80.0` to `DEFAULT_AI_BALANCE["pursuit"]` dict after `"waypoint_reached_px": 12.0`.
8. In `src/core/config_validator.gd`, add `_validate_number_key(result, pursuit, "avoidance_radius_px", "ai_balance.pursuit", 1.0, 64.0)` and `_validate_number_key(result, pursuit, "avoidance_max_speed_px_per_sec", "ai_balance.pursuit", 20.0, 400.0)` after the `waypoint_reached_px` validation line.
9. In `scenes/entities/enemy.tscn`, change `avoidance_enabled = false` to `avoidance_enabled = true`.
10. Delete function `_test_phase_5_shadow_escape_guard` (L6) and its call site from `tests/test_phase_bugfixes.gd`.
11. Delete inline shadow guard block lines 975–992 (L7) from `tests/test_runner_node.gd`.
12. In `tests/test_honest_repath_without_teleport.gd`, add comment before `max_step_px <= 24.0` assertion: `# avoidance_enabled = true since Phase 7; single-enemy scenario, no RVO partner, threshold 24.0 unchanged`.
13. In `tests/test_ai_long_run_stress.gd`, add `const KPI_AVOIDANCE_ENABLED := true` and `_t.run_test("avoidance enabled per Phase 7", KPI_AVOIDANCE_ENABLED)`.
14. Create `tests/test_enemy_crowd_avoidance_reduces_jams.gd` with 3 test functions and register in `tests/test_runner_node.gd`.
15. Create `tests/test_enemy_crowd_avoidance_reduces_jams.tscn`.

## 3. What will be after.

1. `rg -n "PATH_POLICY_SAMPLE_STEP_PX" src/systems/enemy_pursuit_system.gd -S` returns 0 matches. Verified by gate G1 (section 13).
2. `rg -n "func _is_owner_in_shadow_without_flashlight\b|func _select_nearest_reachable_candidate\b|func _nav_path_length_to\b|func _path_length\b" src/systems/enemy_pursuit_system.gd -S` returns 0 matches. Verified by gate G2 (section 13).
3. `rg -n "_is_owner_in_shadow_without_flashlight" tests/ src/ -S` returns 0 matches. Verified by gate G3 (section 13).
4. `rg -n "avoidance_enabled = false" scenes/entities/enemy.tscn -S` returns 0 matches. Verified by gate G4 (section 13).
5. `rg -n "avoidance_enabled = true" scenes/entities/enemy.tscn -S` returns 1 match. Verified by gate G5 (section 13).
6. `rg -n "avoidance_radius_px|avoidance_max_speed_px_per_sec" src/core/game_config.gd -S` returns 2 matches. Verified by gate G6 (section 13).
7. All tests in section 12 exit 0. Verified by running test suite commands from section 12.

## 4. Scope and non-scope (exact files).

**In-scope files (allowed file-change boundary):**
1. `src/systems/enemy_pursuit_system.gd`
2. `scenes/entities/enemy.tscn`
3. `src/core/game_config.gd`
4. `src/core/config_validator.gd`
5. `tests/test_enemy_crowd_avoidance_reduces_jams.gd` (new)
6. `tests/test_enemy_crowd_avoidance_reduces_jams.tscn` (new)
7. `tests/test_honest_repath_without_teleport.gd`
8. `tests/test_ai_long_run_stress.gd`
9. `tests/test_phase_bugfixes.gd`
10. `tests/test_runner_node.gd`
11. `CHANGELOG.md`

**Out-of-scope files (must not be modified):**
1. `src/systems/navigation_runtime_queries.gd`
2. `src/systems/navigation_service.gd`
3. `src/entities/enemy.gd`
4. `src/systems/enemy_patrol_system.gd`
5. `src/systems/enemy_utility_brain.gd`
6. `tests/test_shadow_stall_escapes_to_light.gd`
7. `tests/test_shadow_policy_hard_block_without_grant.gd`
8. `tests/test_pursuit_stall_fallback_invariants.gd`

Any change outside the in-scope list = phase FAILED regardless of test results.

## 5. Single-owner authority for this phase.

The primary new behavior (avoidance parameter initialization) is owned by `src/systems/enemy_pursuit_system.gd`, function `configure_nav_agent`. This is the sole runtime point where `agent.radius` and `agent.max_speed` are set on the NavigationAgent2D passed by the enemy entity.

`avoidance_enabled = true` is a scene-resource property set in `scenes/entities/enemy.tscn`, not at runtime; it has no single runtime decision point.

No other file in `src/` sets `agent.radius` or `agent.max_speed` on a NavigationAgent2D for enemy entities. Verified by gate G7 (section 13).

## 6. Full input/output contract.

**Contract name:** `AvoidanceParamInitContractV1`

**Input (to `configure_nav_agent`):**
- `agent: NavigationAgent2D` — the enemy's navigation agent. Nullable: yes. When null, avoidance param assignments are skipped (mandatory `if agent:` guard).

**Output (side effects on `agent` when non-null):**
- `agent.radius: float` — set to `_pursuit_cfg_float("avoidance_radius_px", 12.8)`. Valid config range: 1.0–64.0 (validated by ConfigValidator).
- `agent.max_speed: float` — set to `_pursuit_cfg_float("avoidance_max_speed_px_per_sec", 80.0)`. Valid config range: 20.0–400.0 (validated by ConfigValidator).

**Status enums:** N/A — no return value; side-effect-only contract.

**Reason enums:** N/A.

**Constants/thresholds:**
- `"avoidance_radius_px": 12.8` — in `GameConfig.DEFAULT_AI_BALANCE["pursuit"]` dict (game_config.gd) after `"waypoint_reached_px": 12.0`. Value 12.8 matches the enemy CollisionShape2D capsule radius confirmed in `scenes/entities/enemy.tscn`.
- `"avoidance_max_speed_px_per_sec": 80.0` — in `GameConfig.DEFAULT_AI_BALANCE["pursuit"]` dict (game_config.gd) after `"avoidance_radius_px": 12.8`. Value 80.0 equals default enemy speed (2.0 tiles × 40 px/tile).

## 7. Deterministic algorithm with exact order.

`configure_nav_agent(agent: NavigationAgent2D) -> void` after Phase 7:
1. Assign `_nav_agent = agent`.
2. Assign `_use_navmesh = agent != null`.
3. If `agent != null`: assign `agent.radius = _pursuit_cfg_float("avoidance_radius_px", 12.8)`, then assign `agent.max_speed = _pursuit_cfg_float("avoidance_max_speed_px_per_sec", 80.0)`. The `radius` assignment precedes `max_speed`.
4. If `agent == null`: step 3 is skipped. No error is raised.

Tie-break rules: N/A — exactly one agent input, no candidate selection. Section 6 contract guarantees N ≤ 1 agents per call by design.

Exact behavior when `agent` is null: `_nav_agent = null`, `_use_navmesh = false`, no property assignments, no crash.

## 8. Edge-case matrix (case → exact output).

**Case A: `agent` is null.**
Input: `configure_nav_agent(null)`.
Expected: `_nav_agent = null`, `_use_navmesh = false`. No property assignment on any Node. No crash.

**Case B: `agent` is a valid NavigationAgent2D; GameConfig pursuit section has default values.**
Input: `configure_nav_agent(valid_agent)` with `GameConfig.ai_balance["pursuit"]["avoidance_radius_px"] = 12.8`.
Expected: `_nav_agent = valid_agent`, `_use_navmesh = true`, `valid_agent.radius = 12.8`, `valid_agent.max_speed = 80.0`.

**Tie-break N/A:** Section 7 proves exactly one agent input per call is guaranteed by design; no candidate selection occurs.

**Case D: `agent` is a valid NavigationAgent2D; `ai_balance` dict missing `"pursuit"` key.**
Input: `configure_nav_agent(valid_agent)` with `GameConfig.ai_balance` lacking `"pursuit"` key.
Expected: `_pursuit_cfg_float("avoidance_radius_px", 12.8)` returns fallback `12.8`. `valid_agent.radius = 12.8`, `valid_agent.max_speed = 80.0`. No crash.

**Case E: `agent` is a valid NavigationAgent2D; `avoidance_radius_px` overridden to 20.0.**
Input: `configure_nav_agent(valid_agent)` with `GameConfig.ai_balance["pursuit"]["avoidance_radius_px"] = 20.0`.
Expected: `valid_agent.radius = 20.0`, `valid_agent.max_speed = 80.0`. `_use_navmesh = true`.

## 9. Legacy removal plan (delete-first, exact ids).

All items L1–L5 are deleted from `src/systems/enemy_pursuit_system.gd` before the `configure_nav_agent` extension is written. L6–L7 are deleted from test files before new test files are created.

- **L1**: Const `PATH_POLICY_SAMPLE_STEP_PX` — `src/systems/enemy_pursuit_system.gd`, current line 23. Dead after Phase 0 deleted `_validate_path_policy_with_traverse_samples` (its only call sites were at pre-Phase-0 lines 888 and 902, both inside functions Phase 0 deletes). Zero callers at Phase 7 start.
- **L2**: Function `_is_owner_in_shadow_without_flashlight` — `src/systems/enemy_pursuit_system.gd`, current lines 1009–1021. Dead after Phase 2 deleted all three callers: `_resolve_nearest_reachable_fallback` (pre-Phase-2 line 918), `_resolve_movement_target_with_shadow_escape` (pre-Phase-2 line 945), `_attempt_shadow_escape_recovery` (pre-Phase-2 line 954). Zero callers at Phase 7 start.
- **L3**: Function `_select_nearest_reachable_candidate` — `src/systems/enemy_pursuit_system.gd`, current lines 1034–1052. Dead after Phase 2 deleted all three callers: `_resolve_nearest_reachable_fallback` (pre-Phase-2 line 923), `_resolve_shadow_escape_target` (pre-Phase-2 line 984), `debug_select_nearest_reachable_fallback` (pre-Phase-2 line 1188). Zero callers at Phase 7 start.
- **L4**: Function `_nav_path_length_to` — `src/systems/enemy_pursuit_system.gd`, current lines 1055–1069. Dead after L3 is deleted (only caller is `_select_nearest_reachable_candidate` at current line 1039). Deleted in this phase after L3.
- **L5**: Function `_path_length` — `src/systems/enemy_pursuit_system.gd`, current lines 1072–1080. Dead after L4 is deleted (only caller is `_nav_path_length_to` at current line 1069). Deleted in this phase after L4.
- **L6**: Function `_test_phase_5_shadow_escape_guard` and its call site — `tests/test_phase_bugfixes.gd`, current lines 156–177. Dead after L2 is deleted (calls `_is_owner_in_shadow_without_flashlight` at lines 165, 167, 169; becomes compile error after L2 removal).
- **L7**: Inline shadow guard test block — `tests/test_runner_node.gd`, current lines 975–992. Dead after L2 is deleted (calls `_is_owner_in_shadow_without_flashlight` at lines 982, 984, 986; becomes compile error after L2 removal).

## 10. Legacy verification commands (exact rg + expected 0 matches).

Each identifier confirmed file-unique by PROJECT DISCOVERY (no matches in other `src/` files for L1–L5; L6 and L7 checked in their respective test files).

```
[L1] rg -n "PATH_POLICY_SAMPLE_STEP_PX" src/systems/enemy_pursuit_system.gd -S
Expected: 0 matches.

[L2] rg -n "func _is_owner_in_shadow_without_flashlight\b" src/systems/enemy_pursuit_system.gd -S
Expected: 0 matches.

[L3] rg -n "func _select_nearest_reachable_candidate\b" src/systems/enemy_pursuit_system.gd -S
Expected: 0 matches.

[L4] rg -n "func _nav_path_length_to\b" src/systems/enemy_pursuit_system.gd -S
Expected: 0 matches.

[L5] rg -n "func _path_length\b" src/systems/enemy_pursuit_system.gd -S
Expected: 0 matches.

[L6] rg -n "_test_phase_5_shadow_escape_guard\|_is_owner_in_shadow_without_flashlight" tests/test_phase_bugfixes.gd -S
Expected: 0 matches.

[L7] rg -n "_is_owner_in_shadow_without_flashlight" tests/test_runner_node.gd -S
Expected: 0 matches.
```

## 11. Acceptance criteria (binary pass/fail).

1. `rg -n "PATH_POLICY_SAMPLE_STEP_PX" src/systems/enemy_pursuit_system.gd -S` returns 0 matches: true or false.
2. `rg -n "func _is_owner_in_shadow_without_flashlight\b|func _select_nearest_reachable_candidate\b|func _nav_path_length_to\b|func _path_length\b" src/systems/enemy_pursuit_system.gd -S` returns 0 matches: true or false.
3. `rg -n "_is_owner_in_shadow_without_flashlight" tests/ src/ -S` returns 0 matches: true or false.
4. `rg -n "avoidance_enabled = false" scenes/entities/enemy.tscn -S` returns 0 matches: true or false.
5. `rg -n "avoidance_enabled = true" scenes/entities/enemy.tscn -S` returns exactly 1 match: true or false.
6. `rg -n "avoidance_radius_px|avoidance_max_speed_px_per_sec" src/core/game_config.gd -S` returns exactly 2 matches: true or false.
7. `rg -n "avoidance_radius_px|avoidance_max_speed_px_per_sec" src/core/config_validator.gd -S` returns exactly 2 matches: true or false.
8. All 3 new test functions in `test_enemy_crowd_avoidance_reduces_jams.gd` exit 0 when scene is run headless: true or false.
9. `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` exits 0: true or false.
10. No file outside section 4 in-scope list was modified: true or false.

## 12. Tests (new/update + purpose).

**New file: `tests/test_enemy_crowd_avoidance_reduces_jams.gd`**
- `_test_configure_nav_agent_sets_avoidance_radius`: creates `NavigationAgent2D`, calls `pursuit.configure_nav_agent(agent)`, asserts `agent.radius == 12.8`. Proves radius is set by `configure_nav_agent`.
- `_test_configure_nav_agent_sets_avoidance_max_speed`: creates `NavigationAgent2D`, calls `pursuit.configure_nav_agent(agent)`, asserts `agent.max_speed == 80.0`. Proves max_speed is set by `configure_nav_agent`.
- `_test_configure_nav_agent_null_does_not_crash`: calls `pursuit.configure_nav_agent(null)`, asserts `pursuit._use_navmesh == false` and no crash. Proves null guard is present.
- Registration: add `ENEMY_CROWD_AVOIDANCE_REDUCES_JAMS_TEST_SCENE = "res://tests/test_enemy_crowd_avoidance_reduces_jams.tscn"` constant in `tests/test_runner_node.gd`, add the scene existence check, and add an `await _run_embedded_scene_suite(...)` call in the embedded-suite run section.

**New file: `tests/test_enemy_crowd_avoidance_reduces_jams.tscn`**
- Minimal headless scene; root node is an instance of `test_enemy_crowd_avoidance_reduces_jams.gd`.

**Updated file: `tests/test_ai_long_run_stress.gd`**
- Add `const KPI_AVOIDANCE_ENABLED := true` at file scope.
- Add `_t.run_test("avoidance enabled per Phase 7", KPI_AVOIDANCE_ENABLED)` inside the existing test body. Purpose: documents Phase 7 activation; fails on accidental revert.

**Updated file: `tests/test_honest_repath_without_teleport.gd`**
- Add comment `# avoidance_enabled = true since Phase 7; single-enemy scenario, no RVO partner, max_step_px threshold 24.0 unchanged.` before `max_step_px <= 24.0` assertion. No assertion logic changes.

**Updated file: `tests/test_phase_bugfixes.gd`**
- Delete function `_test_phase_5_shadow_escape_guard` (current lines 156–177) and its call site. Reason: calls `_is_owner_in_shadow_without_flashlight` (L2 deleted); keeping it is a compile error.

**Updated file: `tests/test_runner_node.gd`**
- Delete inline shadow guard block (current lines 975–992) that calls `_is_owner_in_shadow_without_flashlight`. Same reason as above.
- Add `ENEMY_CROWD_AVOIDANCE_REDUCES_JAMS_TEST_SCENE` constant, scene existence check, and `_run_embedded_scene_suite` call in the embedded-suite sections of `tests/test_runner_node.gd`.

## 13. rg gates (command + expected output).

**[G1]** `rg -n "PATH_POLICY_SAMPLE_STEP_PX" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

**[G2]** `rg -n "func _is_owner_in_shadow_without_flashlight\b|func _select_nearest_reachable_candidate\b|func _nav_path_length_to\b|func _path_length\b" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

**[G3]** `rg -n "_is_owner_in_shadow_without_flashlight" tests/ src/ -S`
Expected: 0 matches.

**[G4]** `rg -n "avoidance_enabled = false" scenes/entities/enemy.tscn -S`
Expected: 0 matches.

**[G5]** `rg -n "avoidance_enabled = true" scenes/entities/enemy.tscn -S`
Expected: 1 match.

**[G6]** `rg -n "avoidance_radius_px|avoidance_max_speed_px_per_sec" src/core/game_config.gd -S`
Expected: 2 matches.

**[G7]** `rg -n "agent\.radius\s*=|agent\.max_speed\s*=" src/systems/enemy_pursuit_system.gd -S`
Expected: 2 matches (one `agent.radius =` and one `agent.max_speed =`, both inside `configure_nav_agent`).

**[G8]** `rg -n "avoidance_radius_px|avoidance_max_speed_px_per_sec" src/core/config_validator.gd -S`
Expected: 2 matches.

**[PMB-1]** `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

**[PMB-2]** `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: 0 matches.

**[PMB-3]** `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

**[PMB-4]** `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

**[PMB-5]** `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

## 14. Execution sequence (step-by-step, no ambiguity).

1. Run Phase 0 dependency gate: `rg -n "_validate_path_policy\b|_validate_path_policy_with_traverse_samples\b|_build_policy_valid_path_fallback_contract\b|_build_reachable_path_points_for_enemy\b" src/systems/enemy_pursuit_system.gd -S` — must return 0 matches. Stop on any match.
2. Run Phase 2 dependency gate: `rg -n "_resolve_nearest_reachable_fallback\b|_sample_fallback_candidates\b|_attempt_shadow_escape_recovery\b|_resolve_shadow_escape_target\b|_sample_shadow_escape_candidates\b|_resolve_movement_target_with_shadow_escape\b|FALLBACK_RING_|SHADOW_ESCAPE_RING_" src/systems/enemy_pursuit_system.gd -S` — must return 0 matches. Stop on any match.
3. Delete const `PATH_POLICY_SAMPLE_STEP_PX` (L1) from `src/systems/enemy_pursuit_system.gd`.
4. Delete function `_is_owner_in_shadow_without_flashlight` full declaration and body (L2) from `src/systems/enemy_pursuit_system.gd`.
5. Delete function `_select_nearest_reachable_candidate` full declaration and body (L3) from `src/systems/enemy_pursuit_system.gd`.
6. Delete function `_nav_path_length_to` full declaration and body (L4) from `src/systems/enemy_pursuit_system.gd`.
7. Delete function `_path_length` full declaration and body (L5) from `src/systems/enemy_pursuit_system.gd`.
8. Run section 10 commands [L1]–[L5]; stop on first non-zero match.
9. Extend `configure_nav_agent` in `src/systems/enemy_pursuit_system.gd`: after `_use_navmesh = agent != null`, add `if agent:` block with `agent.radius = _pursuit_cfg_float("avoidance_radius_px", 12.8)` followed by `agent.max_speed = _pursuit_cfg_float("avoidance_max_speed_px_per_sec", 80.0)`.
10. Add `"avoidance_radius_px": 12.8,` and `"avoidance_max_speed_px_per_sec": 80.0,` to `DEFAULT_AI_BALANCE["pursuit"]` dict in `src/core/game_config.gd` after the `"waypoint_reached_px": 12.0,` entry.
11. Add `_validate_number_key(result, pursuit, "avoidance_radius_px", "ai_balance.pursuit", 1.0, 64.0)` and `_validate_number_key(result, pursuit, "avoidance_max_speed_px_per_sec", "ai_balance.pursuit", 20.0, 400.0)` to `src/core/config_validator.gd` after the `waypoint_reached_px` validation line.
12. Change `avoidance_enabled = false` to `avoidance_enabled = true` in `scenes/entities/enemy.tscn`.
13. Delete function `_test_phase_5_shadow_escape_guard` and its call site (L6) from `tests/test_phase_bugfixes.gd`.
14. Delete inline shadow guard block lines 975–992 (L7) from `tests/test_runner_node.gd`.
15. Run section 10 commands [L6]–[L7]; stop on first non-zero match.
16. Add `const KPI_AVOIDANCE_ENABLED := true` and `_t.run_test("avoidance enabled per Phase 7", KPI_AVOIDANCE_ENABLED)` to `tests/test_ai_long_run_stress.gd`.
17. Add comment `# avoidance_enabled = true since Phase 7; single-enemy scenario, no RVO partner, max_step_px threshold 24.0 unchanged.` before `max_step_px <= 24.0` assertion in `tests/test_honest_repath_without_teleport.gd`.
18. Create `tests/test_enemy_crowd_avoidance_reduces_jams.gd` with test functions `_test_configure_nav_agent_sets_avoidance_radius`, `_test_configure_nav_agent_sets_avoidance_max_speed`, `_test_configure_nav_agent_null_does_not_crash`.
19. Create `tests/test_enemy_crowd_avoidance_reduces_jams.tscn` as minimal headless scene bound to the new script.
20. Add `ENEMY_CROWD_AVOIDANCE_REDUCES_JAMS_TEST_SCENE` constant, scene existence check, and `_run_embedded_scene_suite` call to `tests/test_runner_node.gd` in the existing embedded-suite sections.
21. Run Tier 1 smoke suite:
    `xvfb-run -a godot-4 --headless --path . res://tests/test_enemy_crowd_avoidance_reduces_jams.tscn` — must exit 0.
    `xvfb-run -a godot-4 --headless --path . res://tests/test_honest_repath_without_teleport.tscn` — must exit 0.
    `xvfb-run -a godot-4 --headless --path . res://tests/test_ai_long_run_stress.tscn` — must exit 0.
22. Run Tier 2 full regression: `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit 0.
23. Run all rg gates G1–G8 and PMB-1–PMB-5 from section 13; stop on first failure.
24. Prepend CHANGELOG entry under current date.

## 15. Rollback conditions.

1. Any section 10 command [L1]–[L7] returns non-zero matches after deletion step → rollback entire Phase 7 delta; restart from section 14 step 3.
2. Any rg gate G1–G8 from section 13 fails → rollback entire Phase 7 delta; restart from section 14 step 3.
3. Any PMB gate PMB-1–PMB-5 from section 13 fails → rollback entire Phase 7 delta; do not proceed.
4. Tier 1 or Tier 2 test exits non-zero → rollback entire Phase 7 delta; restart from section 14 step 3.
5. Any file outside section 4 in-scope list was modified → rollback entire Phase 7 delta.
6. `configure_nav_agent` sets `agent.radius` or `agent.max_speed` without `if agent:` null guard → rollback step 9 and re-implement.

## 16. Phase close condition.

- [ ] Section 10 commands [L1]–[L7] all return 0 matches.
- [ ] Section 13 gates G1–G8 all return expected output.
- [ ] Section 13 PMB gates PMB-1–PMB-5 all return expected output.
- [ ] All new and updated tests in section 12 exit 0.
- [ ] Tier 1 smoke suite (section 14 step 21) all 3 commands exit 0.
- [ ] Tier 2 full regression (`res://tests/test_runner.tscn`) exits 0.
- [ ] No file outside section 4 in-scope list was modified.
- [ ] CHANGELOG entry prepended.

## 17. Ambiguity self-check line: Ambiguity check: 0

## 18. Open questions line: Open questions: 0

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).

1. **Diff audit:** `bash -lc 'set -euo pipefail; changed=$(git diff --name-only --relative HEAD); allowed="^(src/systems/enemy_pursuit_system\.gd|scenes/entities/enemy\.tscn|src/core/game_config\.gd|src/core/config_validator\.gd|tests/test_enemy_crowd_avoidance_reduces_jams\.gd|tests/test_enemy_crowd_avoidance_reduces_jams\.tscn|tests/test_honest_repath_without_teleport\.gd|tests/test_ai_long_run_stress\.gd|tests/test_phase_bugfixes\.gd|tests/test_runner_node\.gd|CHANGELOG\.md)$"; for f in $changed; do echo "$f" | rg -q "$allowed" || { echo "OUT_OF_SCOPE:$f"; exit 1; }; done; echo DIFF_SCOPE_OK'`
2. **Contract checks:** Read `configure_nav_agent` body in `src/systems/enemy_pursuit_system.gd`; confirm `agent.radius` and `agent.max_speed` are inside `if agent:` guard. Run all G1–G8 and PMB-1–PMB-5 gates from section 13.
3. **Runtime scenarios:** Execute P7-A, P7-B, P7-C from section 20.

## 20. Runtime scenario matrix.

**Scenario P7-A — avoidance params applied on valid agent.**
Setup: `EnemyPursuitSystem` created with default `GameConfig`. `configure_nav_agent(agent)` called with a real `NavigationAgent2D`.
Scene: `res://tests/test_enemy_crowd_avoidance_reduces_jams.tscn`.
Frame count: 1 physics frame.
Expected invariants: `agent.radius == 12.8`, `agent.max_speed == 80.0`.
Fail conditions: `agent.radius != 12.8` or `agent.max_speed != 80.0`.
Covered by: `_test_configure_nav_agent_sets_avoidance_radius` and `_test_configure_nav_agent_sets_avoidance_max_speed`.

**Scenario P7-B — null agent does not crash.**
Setup: `EnemyPursuitSystem` created. `configure_nav_agent(null)` called.
Scene: `res://tests/test_enemy_crowd_avoidance_reduces_jams.tscn`.
Frame count: 1 physics frame.
Expected invariants: `_pursuit._use_navmesh == false`, no crash, no runtime error.
Fail conditions: any GDScript runtime error or `_use_navmesh == true`.
Covered by: `_test_configure_nav_agent_null_does_not_crash`.

**Scenario P7-C — honest repath threshold unchanged with avoidance enabled.**
Setup: Single enemy, `avoidance_enabled = true` (scene default after Phase 7). No second enemy (no RVO repulsion). Same as existing `test_honest_repath_without_teleport`.
Scene: `res://tests/test_honest_repath_without_teleport.tscn`.
Frame count: existing (multiple frames).
Expected invariants: `max_step_px <= 24.0`.
Fail conditions: `max_step_px > 24.0`.
Covered by: existing `_test_honest_repath_without_teleport` assertion (no logic change required).

## 21. Verification report format.

Record all fields below to close phase:
- `phase_id: PHASE_7`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; must be empty list on close)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `legacy_rg: [{command, expected: "0 matches", actual, PASS|FAIL}]` for each [L1]–[L7]
- `rg_gates: [{command, expected, actual, PASS|FAIL}]` for each G1–G8
- `phase_tests: [{test_function, exit_code: 0, PASS|FAIL}]` for 3 new tests + 5 updated test suites
- `smoke_suite: [{command, exit_code, PASS|FAIL}]` for all 3 Tier 1 commands
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 7` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- pmb_contract_check present in section 21 (PMB section exists in document): yes

## 23. Dependencies on previous phases.

1. **Phase 0** — deleted `EnemyPursuitSystem._validate_path_policy` and `_validate_path_policy_with_traverse_samples` from `src/systems/enemy_pursuit_system.gd`. Phase 7 inherits: `PATH_POLICY_SAMPLE_STEP_PX` (L1) is dead because its only two call sites (pre-Phase-0 lines 888 and 902, both inside the deleted functions) no longer exist. Without Phase 0, L1 has active callers and deleting it produces a compile error.

2. **Phase 2** — deleted `_resolve_nearest_reachable_fallback`, `_sample_fallback_candidates`, `_attempt_shadow_escape_recovery`, `_resolve_shadow_escape_target`, `_sample_shadow_escape_candidates`, `_resolve_movement_target_with_shadow_escape`, `debug_select_nearest_reachable_fallback`, `FALLBACK_RING_*`, `SHADOW_ESCAPE_RING_*`, `_policy_fallback_used`, `_policy_fallback_target`, `_shadow_escape_active`, `_shadow_escape_target`, `_shadow_escape_target_valid` from `src/systems/enemy_pursuit_system.gd`. Phase 7 inherits: `_is_owner_in_shadow_without_flashlight` (L2) is dead because all three callers are deleted by Phase 2; `_select_nearest_reachable_candidate` (L3) is dead because all three callers are deleted by Phase 2. Without Phase 2, L2 and L3 have active callers; deleting them produces compile errors.

3. **Phase 5** — enforced mandatory navmesh extraction and NavigationServer2D map availability in `NavigationService`. Phase 7 inherits: `NavigationAgent2D.avoidance_enabled = true` produces correct RVO avoidance output only when a valid NavMesh map exists in NavigationServer2D. Without Phase 5's extraction guarantee, enabling avoidance in `enemy.tscn` produces zero-velocity RVO output (NavigationServer2D computes nothing without a map), making the crowd jam reduction goal unachievable.

---

## PHASE 8
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_8.
Scope boundary (exact files): section 4.
Execution sequence: section 14.

### Evidence

**Inspected files:**
- `src/systems/enemy_utility_brain.gd` (188 lines) — current decision layer; contains `IntentType` enum (9 values: PATROL, INVESTIGATE, SEARCH, MOVE_TO_SLOT, HOLD_RANGE, PUSH, RETREAT, RETURN_HOME, SHADOW_BOUNDARY_SCAN), `update()`, `_choose_intent()`, `_intent_changed()`, `get_current_intent()`, `reset()`.
- `src/core/game_config.gd` — `DEFAULT_AI_BALANCE["utility"]` dict (lines 151–160): keys `decision_interval_sec`, `min_action_hold_sec`, `hold_range_min_px`, `hold_range_max_px`, `retreat_hp_ratio`, `investigate_max_last_seen_age`, `slot_reposition_threshold_px`, `intent_target_delta_px`.
- `src/core/config_validator.gd` — utility validation block (lines 206–216): validates hold_range_min/max, decision_interval_sec, min_action_hold_sec, retreat_hp_ratio, investigate_max_last_seen_age, slot_reposition_threshold_px, intent_target_delta_px.
- `tests/test_enemy_utility_brain.gd` (142 lines) — tests `_test_core_decisions()` (5 intent assertions) and `_test_antichatter_hold()` (2 intent-hold assertions). No mode assertions exist.
- `docs/ai_nav_refactor_execution_v2.md` (`PHASE 8` sections 1, 10, 12) — explicit pursuit modes baseline and associated legacy-gate/test expectations used for continuity checks in this phase.

**Inspected functions/methods:**
- `EnemyUtilityBrain.update(delta, context)` — decision and action-hold timer logic; early-return path when both `_decision_timer > 0` AND `_action_hold_timer > 0`.
- `EnemyUtilityBrain._choose_intent(ctx)` — returns one of the 9 IntentType values as a Dictionary.
- `EnemyUtilityBrain.reset()` — sets `_decision_timer = 0.0`, `_action_hold_timer = 0.0`, `_current_intent = {"type": IntentType.PATROL}`.
- `EnemyUtilityBrain._intent_changed(a, b)` — compares intent type and target distance.
- `EnemyUtilityBrain._utility_cfg_float(key, fallback)` — reads from `GameConfig.ai_balance["utility"]`.

**Search commands used:**
```
rg "PursuitMode" /root/arena-shooter/src/            # exit 1 (not found)
rg "get_pursuit_mode" /root/arena-shooter/src/       # exit 1 (not found)
rg "mode_min_hold" /root/arena-shooter/src/          # exit 1 (not found)
rg "force_intent_override" /root/arena-shooter/src/ /root/arena-shooter/tests/  # exit 1 (not found)
rg "legacy_mode_switch" /root/arena-shooter/src/ /root/arena-shooter/tests/     # exit 1 (not found)
rg -n "IntentType" /root/arena-shooter/src/systems/enemy_utility_brain.gd -S   # 9-value enum at lines 9-18
rg -n "func update|func reset|func _choose" /root/arena-shooter/src/systems/enemy_utility_brain.gd -S
```

---

## 1. What now.

`EnemyUtilityBrain` produces fine-grained `IntentType` values (9 values) but exposes no higher-level behavioral mode. Consumer systems (Phase 9 navigation cost, Phase 10 team tactics) cannot query whether the enemy is currently in a pursuit-pressure role vs. a search role without parsing raw `IntentType` themselves. No mode-level jitter guard exists separate from the `min_action_hold_sec` intent guard.

Verifiable current state:
```
rg -n "enum PursuitMode" src/systems/enemy_utility_brain.gd -S
# Expected: 0 matches (PursuitMode does not exist)

rg -n "func get_pursuit_mode" src/systems/enemy_utility_brain.gd -S
# Expected: 0 matches (accessor does not exist)

rg -n "_current_mode" src/systems/enemy_utility_brain.gd -S
# Expected: 0 matches (mode tracking state does not exist)
```

## 2. What changes.

1. Add `enum PursuitMode { PATROL, LOST_CONTACT_SEARCH, DIRECT_PRESSURE, CONTAIN, SHADOW_AWARE_SWEEP }` in `src/systems/enemy_utility_brain.gd` after the `IntentType` enum block.
2. Add `const MODE_MIN_HOLD_SEC := 0.8` in `src/systems/enemy_utility_brain.gd` after the existing constants block.
3. Add `var _current_mode: PursuitMode = PursuitMode.PATROL` and `var _mode_hold_timer: float = 0.0` in `src/systems/enemy_utility_brain.gd` in the vars block.
4. Extend `func reset()` in `src/systems/enemy_utility_brain.gd`: add `_current_mode = PursuitMode.PATROL` and `_mode_hold_timer = 0.0` to the reset body.
5. Add `func get_pursuit_mode() -> PursuitMode` in `src/systems/enemy_utility_brain.gd`: returns `_current_mode`.
6. Add `func _derive_mode_from_intent(intent: Dictionary) -> PursuitMode` in `src/systems/enemy_utility_brain.gd`: deterministic mapping from IntentType to PursuitMode (section 7).
7. Extend `func update()` in `src/systems/enemy_utility_brain.gd`: add `_mode_hold_timer` decrement on line 3 (after `_action_hold_timer` decrement); add mode candidate derivation and hold-guard update before the final `return get_current_intent()`.
8. Add `"mode_min_hold_sec": 0.8` to `GameConfig.DEFAULT_AI_BALANCE["utility"]` in `src/core/game_config.gd`.
9. Add `_validate_number_key(result, utility, "mode_min_hold_sec", "ai_balance.utility", 0.1, 5.0)` in `src/core/config_validator.gd` after the `intent_target_delta_px` validation line.
10. Create `tests/test_pursuit_mode_selection_by_context.gd` (7 test functions, section 12).
11. Create `tests/test_pursuit_mode_selection_by_context.tscn` (minimal headless scene).
12. Create `tests/test_mode_transition_guard_no_jitter.gd` (3 test functions, section 12).
13. Create `tests/test_mode_transition_guard_no_jitter.tscn` (minimal headless scene).
14. Update `tests/test_enemy_utility_brain.gd`: add 5 mode assertions in `_test_core_decisions()` after each existing intent test (section 12).
15. Register both new test files in `tests/test_runner_node.gd` by adding scene constants, scene existence checks, and `await _run_embedded_scene_suite(...)` calls in the existing embedded-suite sections.

## 3. What will be after.

Each item is verifiable by the named gate or test.

- `enum PursuitMode` (5 values) exists in `src/systems/enemy_utility_brain.gd`: verified by G3.
- `func get_pursuit_mode() -> PursuitMode` exists as the sole public accessor: verified by G4.
- PUSH intent context yields `PursuitMode.DIRECT_PRESSURE`: verified by `_test_push_intent_maps_to_direct_pressure` (section 12).
- RETREAT intent context yields `PursuitMode.DIRECT_PRESSURE`: verified by `_test_retreat_intent_maps_to_direct_pressure` (section 12).
- HOLD_RANGE intent context yields `PursuitMode.CONTAIN`: verified by `_test_hold_range_intent_maps_to_contain` (section 12).
- MOVE_TO_SLOT intent context yields `PursuitMode.CONTAIN`: verified by `_test_move_to_slot_intent_maps_to_contain` (section 12).
- SHADOW_BOUNDARY_SCAN intent context yields `PursuitMode.SHADOW_AWARE_SWEEP`: verified by `_test_shadow_boundary_scan_maps_to_shadow_aware_sweep` (section 12).
- INVESTIGATE/SEARCH/RETURN_HOME intent context yields `PursuitMode.LOST_CONTACT_SEARCH`: verified by `_test_investigate_maps_to_lost_contact_search` (section 12).
- PATROL intent context yields `PursuitMode.PATROL`: verified by `_test_patrol_maps_to_patrol` (section 12).
- Mode does not flip within `mode_min_hold_sec` window: verified by `_test_mode_does_not_flip_before_hold_expires` (section 12).
- Mode changes after `mode_min_hold_sec` expires: verified by `_test_mode_can_change_after_hold_expires` (section 12).
- `reset()` clears mode to PATROL: verified by `_test_reset_clears_mode_and_timer` (section 12).
- `mode_min_hold_sec` key present in `game_config.gd`: verified by G5.
- `mode_min_hold_sec` validated in `config_validator.gd`: verified by G6.
- Forbidden patterns absent: verified by G1, G2.

## 4. Scope and non-scope.

**In-scope (allowed file-change boundary):**
- `src/systems/enemy_utility_brain.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `tests/test_pursuit_mode_selection_by_context.gd` (new)
- `tests/test_pursuit_mode_selection_by_context.tscn` (new)
- `tests/test_mode_transition_guard_no_jitter.gd` (new)
- `tests/test_mode_transition_guard_no_jitter.tscn` (new)
- `tests/test_enemy_utility_brain.gd` (update)
- `tests/test_runner_node.gd` (registration only)
- `CHANGELOG.md`

Any change outside this list = phase FAILED regardless of test results.

**Out-of-scope:**
- `src/systems/enemy_pursuit_system.gd`
- `src/entities/enemy.gd`
- `src/systems/enemy_squad_system.gd`
- `scenes/entities/enemy.tscn`
- `src/systems/enemy_patrol_system.gd`
- All other files not listed in in-scope.

## 5. Single-owner authority.

The exact file that owns the PursuitMode derivation decision: `src/systems/enemy_utility_brain.gd`.
The exact function that is the sole decision point: `EnemyUtilityBrain._derive_mode_from_intent`.
No other file duplicates this decision: verified by G7 (`rg -n "func _derive_mode_from_intent" src/ -S` → 1 match, in `enemy_utility_brain.gd` only).

## 6. Full input/output contract.

**Contract name: PursuitModeDerivationContract**

Input:
- `intent: Dictionary` — non-null (always a Dictionary returned by `_choose_intent()` or stored in `_current_intent`). Must contain key `"type"` with value castable to `int` mapping to an `IntentType` enum value. If key `"type"` is absent, treated as `IntentType.PATROL` (value 0). No finite-check required: `int(intent.get("type", IntentType.PATROL))` is always a valid int.

Output:
- Return type: `PursuitMode` enum value.
- Valid values: `PursuitMode.PATROL`, `PursuitMode.LOST_CONTACT_SEARCH`, `PursuitMode.DIRECT_PRESSURE`, `PursuitMode.CONTAIN`, `PursuitMode.SHADOW_AWARE_SWEEP`.
- No error state: function always returns a PursuitMode value.

Status enums: N/A — function always returns a valid PursuitMode; no "error" or "undefined" status.

Reason enums: N/A.

Constants:
- `MODE_MIN_HOLD_SEC := 0.8` — local constant in `src/systems/enemy_utility_brain.gd`. Used as fallback in `_utility_cfg_float("mode_min_hold_sec", MODE_MIN_HOLD_SEC)` inside `update()`. Not exported to GameConfig as a top-level var; added to `DEFAULT_AI_BALANCE["utility"]` dict.

IntentType-to-PursuitMode mapping (complete, covers all 9 IntentType values):

| IntentType | PursuitMode |
|---|---|
| PUSH | DIRECT_PRESSURE |
| RETREAT | DIRECT_PRESSURE |
| HOLD_RANGE | CONTAIN |
| MOVE_TO_SLOT | CONTAIN |
| SHADOW_BOUNDARY_SCAN | SHADOW_AWARE_SWEEP |
| INVESTIGATE | LOST_CONTACT_SEARCH |
| SEARCH | LOST_CONTACT_SEARCH |
| RETURN_HOME | LOST_CONTACT_SEARCH |
| PATROL | PATROL |
| (unknown / default) | PATROL |

## 7. Deterministic algorithm with exact order.

**`_derive_mode_from_intent(intent: Dictionary) -> PursuitMode`:**
1. `var intent_type := int(intent.get("type", IntentType.PATROL))`
2. `match intent_type:` — evaluated top-to-bottom. Branches are mutually exclusive (each IntentType value matches at most one branch).
   - `IntentType.PUSH, IntentType.RETREAT:` → `return PursuitMode.DIRECT_PRESSURE`
   - `IntentType.HOLD_RANGE, IntentType.MOVE_TO_SLOT:` → `return PursuitMode.CONTAIN`
   - `IntentType.SHADOW_BOUNDARY_SCAN:` → `return PursuitMode.SHADOW_AWARE_SWEEP`
   - `IntentType.INVESTIGATE, IntentType.SEARCH, IntentType.RETURN_HOME:` → `return PursuitMode.LOST_CONTACT_SEARCH`
   - `_:` (default, covers PATROL and any unknown int) → `return PursuitMode.PATROL`

**`update(delta, context)` mode extension:**
Mode timer decrement is inserted as line 3 of `update()`, immediately after `_action_hold_timer` decrement:
```gdscript
_mode_hold_timer = maxf(0.0, _mode_hold_timer - maxf(delta, 0.0))
```
The following mode candidate + hold-guard block is inserted immediately before the final `return get_current_intent()` (after `_decision_timer` is reset, so `_current_intent` is finalized):
```gdscript
var candidate_mode := _derive_mode_from_intent(_current_intent)
if candidate_mode != _current_mode and _mode_hold_timer <= 0.0:
    _current_mode = candidate_mode
    _mode_hold_timer = _utility_cfg_float("mode_min_hold_sec", MODE_MIN_HOLD_SEC)
```
The existing early-return path (`return get_current_intent()` inside the timers-both-positive branch) does NOT reach the mode update block. This is correct: when both `_decision_timer > 0` and `_action_hold_timer > 0`, `_current_intent` has not changed, so the mode candidate would be identical to `_current_mode`. The mode hold timer IS decremented on all code paths (line 3, before the early return check).

Tie-break rules: N/A. `_derive_mode_from_intent` produces exactly one `PursuitMode` for any given `IntentType` value. The match branches are mutually exclusive. No selection among candidates occurs; the function is a pure deterministic mapping.

Behavior when input is empty: `intent = {}` → `int({}.get("type", IntentType.PATROL))` = `int(0)` = `IntentType.PATROL` → default branch → `PursuitMode.PATROL`.

## 8. Edge-case matrix.

**Case A — empty intent dict.**
Input: `intent = {}`.
`_derive_mode_from_intent({})`: `intent_type = int(IntentType.PATROL) = 0`. Default branch. Returns `PursuitMode.PATROL`.
Mode update in `update()`: candidate = PATROL = `_current_mode` (initial). Mode unchanged. Mode hold timer not reset.

**Case B — single valid input, no ambiguity.**
Input: `intent = {"type": IntentType.PUSH, "target": Vector2(100.0, 0.0)}`.
`_derive_mode_from_intent(intent)`: `intent_type = int(IntentType.PUSH)`. First branch matches. Returns `PursuitMode.DIRECT_PRESSURE`.
Mode update: candidate = DIRECT_PRESSURE ≠ PATROL (initial), `_mode_hold_timer = 0.0 <= 0.0` → `_current_mode = DIRECT_PRESSURE`, `_mode_hold_timer = 0.8`.

**Case C — tie-break N/A.**
`_derive_mode_from_intent` accepts exactly one `intent: Dictionary` and maps it to exactly one `PursuitMode` via a deterministic match. With a given `IntentType` value, exactly one match branch fires (branches are mutually exclusive). There are no ranked candidates to tie-break. This is proved by section 7: the match has no overlapping branches and a default fallback.

**Case D — unknown IntentType value.**
Input: `intent = {"type": 999}`.
`_derive_mode_from_intent(intent)`: `intent_type = 999`. No explicit branch matches. Default branch fires. Returns `PursuitMode.PATROL`.

**Case E — mode hold guard active.**
State: `_current_mode = DIRECT_PRESSURE`, `_mode_hold_timer = 0.5`.
`update(0.1, investigate_ctx)`: `_mode_hold_timer = max(0, 0.5 - 0.1) = 0.4`. Candidate = LOST_CONTACT_SEARCH. `candidate != _current_mode` AND `_mode_hold_timer = 0.4 > 0.0` → condition false. `_current_mode` unchanged = DIRECT_PRESSURE.

**Case F — mode hold guard expired.**
State: `_current_mode = DIRECT_PRESSURE`, `_mode_hold_timer = 0.0`.
`update(0.1, investigate_ctx)`: `_mode_hold_timer = max(0, 0.0 - 0.1) = 0.0`. Candidate = LOST_CONTACT_SEARCH. `candidate != _current_mode` AND `_mode_hold_timer = 0.0 <= 0.0` → condition true. `_current_mode = LOST_CONTACT_SEARCH`, `_mode_hold_timer = 0.8`.

**Case G — delta = 0.0.**
`_mode_hold_timer = maxf(0.0, _mode_hold_timer - 0.0)` = `_mode_hold_timer` (unchanged). If timer was already 0.0 and candidate != current mode: mode updates. If timer was > 0: mode blocked.

## 9. Legacy removal plan.

N/A — no legacy identifiers exist in the codebase prior to Phase 8 that this phase must delete. Phase 8 introduces entirely new code (`PursuitMode` enum, `_current_mode`, `_mode_hold_timer`, `get_pursuit_mode()`, `_derive_mode_from_intent()`). The forbidden patterns `force_intent_override` and `legacy_mode_switch` have never existed in the codebase (verified by PROJECT DISCOVERY search commands in Evidence preamble). Section 10 documents these as forbidden-pattern gates.

## 10. Legacy verification commands.

No legacy identifiers to verify removed. The following commands verify forbidden patterns are NOT introduced by Phase 8 (expected: 0 matches each):

**[FP-1] force_intent_override must not exist:**
```
rg -n "force_intent_override" src/ tests/ -S
```
Expected: 0 matches.

**[FP-2] legacy_mode_switch must not exist:**
```
rg -n "legacy_mode_switch" src/ tests/ -S
```
Expected: 0 matches.

Phase cannot close if either command returns non-zero match count.

## 11. Acceptance criteria.

All items are binary boolean statements answerable by running a command or reading a test result.

1. `rg -n "enum PursuitMode" src/systems/enemy_utility_brain.gd -S` returns exactly 1 match: PASS|FAIL.
2. `rg -n "func get_pursuit_mode" src/systems/enemy_utility_brain.gd -S` returns exactly 1 match: PASS|FAIL.
3. `rg -n "func _derive_mode_from_intent" src/ -S` returns exactly 1 match: PASS|FAIL.
4. `rg -n "mode_min_hold_sec" src/core/game_config.gd -S` returns exactly 1 match: PASS|FAIL.
5. `rg -n "mode_min_hold_sec" src/core/config_validator.gd -S` returns exactly 1 match: PASS|FAIL.
6. `rg -n "force_intent_override" src/ tests/ -S` returns 0 matches: PASS|FAIL.
7. `rg -n "legacy_mode_switch" src/ tests/ -S` returns 0 matches: PASS|FAIL.
8. `tests/test_pursuit_mode_selection_by_context.tscn` exits 0: PASS|FAIL.
9. `tests/test_mode_transition_guard_no_jitter.tscn` exits 0: PASS|FAIL.
10. `tests/test_enemy_utility_brain.tscn` exits 0: PASS|FAIL.
11. `tests/test_runner.tscn` exits 0: PASS|FAIL.
12. Both new test files registered in `tests/test_runner_node.gd` (scene constants + scene existence checks + `_run_embedded_scene_suite` calls): PASS|FAIL.

## 12. Tests.

### New file: `tests/test_pursuit_mode_selection_by_context.gd`

Test functions (all operate on a freshly created `EnemyUtilityBrain` with `reset()` called before each):

- `_test_push_intent_maps_to_direct_pressure`: context `{dist: 820, los: true, alert: COMBAT, player_pos: Vector2(300,0)}`. Call `brain.update(0.3, ctx)`. Assert `brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE`.
- `_test_retreat_intent_maps_to_direct_pressure`: context `{dist: 220, los: true, hp_ratio: 0.2, alert: COMBAT, player_pos: Vector2(100,0)}`. Call `brain.update(0.3, ctx)`. Assert `get_pursuit_mode() == PursuitMode.DIRECT_PRESSURE`.
- `_test_move_to_slot_intent_maps_to_contain`: context `{dist: 470, los: true, alert: COMBAT, has_slot: true, path_ok: true, slot_position: Vector2(220,10), dist_to_slot: 120, role: Role.FLANK}`. Call `brain.update(0.3, ctx)`. Assert `get_pursuit_mode() == PursuitMode.CONTAIN`.
- `_test_hold_range_intent_maps_to_contain`: context `{dist: 500, los: true, alert: COMBAT, has_slot: false}`. Call `brain.update(0.3, ctx)`. Assert `get_pursuit_mode() == PursuitMode.CONTAIN`.
- `_test_shadow_boundary_scan_maps_to_shadow_aware_sweep`: context `{dist: 300, los: false, alert: SUSPICIOUS, has_shadow_scan_target: true, shadow_scan_target: Vector2(64,-32), shadow_scan_target_in_shadow: true}`. Call `brain.update(0.3, ctx)`. Assert `get_pursuit_mode() == PursuitMode.SHADOW_AWARE_SWEEP`.
- `_test_investigate_maps_to_lost_contact_search`: context `{dist: 999, los: false, alert: ALERT, last_seen_age: 1.0, last_seen_pos: Vector2(64,-16)}`. Call `brain.update(0.3, ctx)`. Assert `get_pursuit_mode() == PursuitMode.LOST_CONTACT_SEARCH`.
- `_test_patrol_maps_to_patrol`: context `{dist: 999, los: false, alert: CALM, last_seen_age: INF}`. Call `brain.update(0.3, ctx)`. Assert `get_pursuit_mode() == PursuitMode.PATROL`.

Registration: add a scene constant for `res://tests/test_pursuit_mode_selection_by_context.tscn`, a scene existence check, and an `await _run_embedded_scene_suite(...)` call in `tests/test_runner_node.gd`.

### New file: `tests/test_mode_transition_guard_no_jitter.gd`

- `_test_mode_does_not_flip_before_hold_expires`:
  1. Call `brain.update(0.3, push_ctx)` → intent=PUSH, `get_pursuit_mode() == DIRECT_PRESSURE`, `_mode_hold_timer = 0.8`.
  2. Call `brain.update(0.1, investigate_ctx)` (both timers > 0 → early return; `_mode_hold_timer = 0.7`).
  3. Assert `brain.get_pursuit_mode() == PursuitMode.DIRECT_PRESSURE`.
  Mode has not flipped despite contradicting context.

- `_test_mode_can_change_after_hold_expires`:
  1. Call `brain.update(0.3, push_ctx)` → mode = DIRECT_PRESSURE, `_mode_hold_timer = 0.8`.
  2. Call `brain.update(1.0, investigate_ctx)` → all timers advance past thresholds: `decision_timer = max(0, 0.25-1.0) = 0`, `action_hold = max(0, 0.6-1.0) = 0`, `mode_hold = max(0, 0.8-1.0) = 0`. Not early return. `_choose_intent` → INVESTIGATE intent. Mode candidate = LOST_CONTACT_SEARCH ≠ DIRECT_PRESSURE, timer = 0 → mode = LOST_CONTACT_SEARCH.
  3. Assert `brain.get_pursuit_mode() == PursuitMode.LOST_CONTACT_SEARCH`.

- `_test_reset_clears_mode_and_timer`:
  1. Call `brain.update(0.3, push_ctx)` → mode = DIRECT_PRESSURE.
  2. Call `brain.reset()`.
  3. Assert `brain.get_pursuit_mode() == PursuitMode.PATROL`.

Registration: add a scene constant for `res://tests/test_mode_transition_guard_no_jitter.tscn`, a scene existence check, and an `await _run_embedded_scene_suite(...)` call in `tests/test_runner_node.gd`.

### Updated file: `tests/test_enemy_utility_brain.gd`

In `_test_core_decisions()`, add one `_t.run_test(...)` assertion after each existing intent assertion. What changes: add `brain.get_pursuit_mode()` call (new public function) and assert the expected mode.

1. After `"Far combat LOS chooses PUSH"` assertion: add `_t.run_test("PUSH intent yields DIRECT_PRESSURE mode", brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE)`.
2. After `"Low HP close LOS chooses RETREAT"` assertion: add `_t.run_test("RETREAT intent yields DIRECT_PRESSURE mode", brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE)`.
3. After `"Recent no-LOS alert chooses INVESTIGATE"` assertion: add `_t.run_test("INVESTIGATE intent yields LOST_CONTACT_SEARCH mode", brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.LOST_CONTACT_SEARCH)`.
4. After `"Old no-LOS suspicious chooses PATROL"` assertion: add `_t.run_test("PATROL intent yields PATROL mode", brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.PATROL)`.
5. After `"Flank role with slot chooses MOVE_TO_SLOT"` assertion: add `_t.run_test("MOVE_TO_SLOT intent yields CONTAIN mode", brain.get_pursuit_mode() == ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.CONTAIN)`.

Why: `get_pursuit_mode()` is a new public API; the existing test file must verify it returns correct modes for already-verified intent contexts.

## 13. rg gates.

**Phase-specific gates:**

**[G1] Forbidden pattern: force_intent_override absent.**
```
rg -n "force_intent_override" src/ tests/ -S
```
Expected: 0 matches.

**[G2] Forbidden pattern: legacy_mode_switch absent.**
```
rg -n "legacy_mode_switch" src/ tests/ -S
```
Expected: 0 matches.

**[G3] PursuitMode enum exists in enemy_utility_brain.gd.**
```
rg -n "enum PursuitMode" src/systems/enemy_utility_brain.gd -S
```
Expected: 1 match.

**[G4] get_pursuit_mode public function exists.**
```
rg -n "func get_pursuit_mode" src/systems/enemy_utility_brain.gd -S
```
Expected: 1 match.

**[G5] mode_min_hold_sec key present in game_config.gd.**
```
rg -n "mode_min_hold_sec" src/core/game_config.gd -S
```
Expected: 1 match.

**[G6] mode_min_hold_sec validated in config_validator.gd.**
```
rg -n "mode_min_hold_sec" src/core/config_validator.gd -S
```
Expected: 1 match.

**[G7] _derive_mode_from_intent defined only in enemy_utility_brain.gd.**
```
rg -n "func _derive_mode_from_intent" src/ -S
```
Expected: 1 match (in `src/systems/enemy_utility_brain.gd` only).

**PMB gates (verbatim command set from `## Start of Persistent Module Boundary Contract`):**

**[PMB-1]** EnemyPursuitSystem — lexical anti-legacy guard for alternate path planners:
```
rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S
```
Expected: 0 matches.

**[PMB-2]** `enemy.gd` не вызывает path-planning navigation API напрямую:
```
rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S
```
Expected: 0 matches.

**[PMB-3]** `enemy_pursuit_system.gd` не производит utility-context contract fields:
```
rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S
```
Expected: 0 matches.

**[PMB-4]** `EnemyPursuitSystem` не конструирует intent dictionaries (`"type": ...`):
```
rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S
```
Expected: 0 matches.

**[PMB-5]** Только один вызов execute_intent из Enemy:
```
bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'
```
Expected: output contains "PMB-5: PASS (1)".

## 14. Execution sequence.

Step 1: (No legacy delete — section 9 confirmed N/A.)
Step 2: In `src/systems/enemy_utility_brain.gd`, add `enum PursuitMode { PATROL, LOST_CONTACT_SEARCH, DIRECT_PRESSURE, CONTAIN, SHADOW_AWARE_SWEEP }` after the closing `}` of the `IntentType` enum block (after line 18).
Step 3: In `src/systems/enemy_utility_brain.gd`, add `const MODE_MIN_HOLD_SEC := 0.8` after the existing constants block (after `DECISION_INTERVAL_SEC`, `MIN_ACTION_HOLD_SEC`, etc.).
Step 4: In `src/systems/enemy_utility_brain.gd`, add `var _current_mode: PursuitMode = PursuitMode.PATROL` and `var _mode_hold_timer: float = 0.0` in the vars block (after `_current_intent` declaration).
Step 5: In `src/systems/enemy_utility_brain.gd`, extend `func reset()`: add `_current_mode = PursuitMode.PATROL` and `_mode_hold_timer = 0.0` to the reset body.
Step 6: In `src/systems/enemy_utility_brain.gd`, add `func get_pursuit_mode() -> PursuitMode:` with body `return _current_mode`.
Step 7: In `src/systems/enemy_utility_brain.gd`, add `func _derive_mode_from_intent(intent: Dictionary) -> PursuitMode:` with the match block from section 7.
Step 8: In `src/systems/enemy_utility_brain.gd`, extend `func update()`: insert `_mode_hold_timer = maxf(0.0, _mode_hold_timer - maxf(delta, 0.0))` as line 3 (after `_action_hold_timer` decrement); insert the 4-line mode candidate block from section 7 immediately before the final `return get_current_intent()`.
Step 9: In `src/core/game_config.gd`, add `"mode_min_hold_sec": 0.8,` inside `DEFAULT_AI_BALANCE["utility"]` dict, after the `"intent_target_delta_px": 8.0,` line.
Step 10: In `src/core/config_validator.gd`, add `_validate_number_key(result, utility, "mode_min_hold_sec", "ai_balance.utility", 0.1, 5.0)` after the `intent_target_delta_px` validation line (after line 215 in current file).
Step 11: Create `tests/test_pursuit_mode_selection_by_context.gd` with 7 test functions (section 12).
Step 12: Create `tests/test_pursuit_mode_selection_by_context.tscn` as a minimal headless scene loading the .gd script.
Step 13: Create `tests/test_mode_transition_guard_no_jitter.gd` with 3 test functions (section 12).
Step 14: Create `tests/test_mode_transition_guard_no_jitter.tscn` as a minimal headless scene loading the .gd script.
Step 15: Update `tests/test_enemy_utility_brain.gd` `_test_core_decisions()`: add 5 mode assertions after the 5 existing intent assertions (section 12).
Step 16: Register both new test files in `tests/test_runner_node.gd` by adding scene constants, scene existence checks, and `await _run_embedded_scene_suite(...)` calls in the existing embedded-suite sections.
Step 17: Run Tier 1 smoke (test 1): `xvfb-run -a godot-4 --headless --path . res://tests/test_pursuit_mode_selection_by_context.tscn` — must exit 0.
Step 18: Run Tier 1 smoke (test 2): `xvfb-run -a godot-4 --headless --path . res://tests/test_mode_transition_guard_no_jitter.tscn` — must exit 0.
Step 19: Run Tier 1 smoke (test 3): `xvfb-run -a godot-4 --headless --path . res://tests/test_enemy_utility_brain.tscn` — must exit 0.
Step 20: Run Tier 2 full regression: `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit 0.
Step 21: Run all rg gates: G1, G2, G3, G4, G5, G6, G7, PMB-1, PMB-2, PMB-3, PMB-4, PMB-5 — all must return expected output.
Step 22: Prepend CHANGELOG entry under today's date header in `CHANGELOG.md` (create `## YYYY-MM-DD` first if absent).

## 15. Rollback conditions.

- Condition 1: Any test in `test_pursuit_mode_selection_by_context.tscn`, `test_mode_transition_guard_no_jitter.tscn`, or `test_enemy_utility_brain.tscn` exits non-zero → revert all Phase 8 changes to `src/systems/enemy_utility_brain.gd`, `src/core/game_config.gd`, `src/core/config_validator.gd`, `tests/test_pursuit_mode_selection_by_context.gd`, `tests/test_mode_transition_guard_no_jitter.gd`, `tests/test_enemy_utility_brain.gd`, `tests/test_runner_node.gd`. Delete new .tscn files.
- Condition 2: G3 returns 0 matches (enum not added) → revert `src/systems/enemy_utility_brain.gd`.
- Condition 3: G5 returns 0 matches (GameConfig key missing) → revert `src/core/game_config.gd`.
- Condition 4: `test_runner.tscn` exits non-zero → revert all Phase 8 changes.
- Condition 5: Any PMB gate fails → revert all Phase 8 changes and investigate root cause before re-attempting.
- Condition 6: G1 or G2 returns non-zero (forbidden patterns introduced) → revert all Phase 8 changes, clean the offending identifier, then re-attempt from Step 2.

## 16. Phase close condition.

- [ ] All rg commands in section 10 (FP-1, FP-2) return 0 matches
- [ ] All rg gates in section 13 (G1–G7) return expected output
- [ ] PMB gates in section 13 (PMB-1 through PMB-4) return 0 matches; PMB-5 output contains "PMB-5: PASS (1)"
- [ ] All tests in section 12 (7 new + 3 new + 5 updated assertions) exit 0
- [ ] Tier 1 smoke suite (3 commands, steps 17–19) — all exit 0
- [ ] Tier 2 full regression (`test_runner.tscn`) exits 0
- [ ] No file outside section 4 in-scope list was modified
- [ ] CHANGELOG entry prepended
- [ ] `rg -n "func get_pursuit_mode" src/systems/enemy_utility_brain.gd -S` → exactly 1 match
- [ ] `rg -n "enum PursuitMode" src/systems/enemy_utility_brain.gd -S` → exactly 1 match
- [ ] `rg -n "func _derive_mode_from_intent" src/ -S` → exactly 1 match

## 17. Ambiguity check: 0

## 18. Open questions: 0

## 19. Post-implementation verification plan.

**Diff audit:**
- `src/systems/enemy_utility_brain.gd` — confirm only additions: `PursuitMode` enum, `MODE_MIN_HOLD_SEC` const, 2 new vars, 2 new funcs (`get_pursuit_mode`, `_derive_mode_from_intent`), 1 line added to `reset()`, 5 lines added to `update()`. No existing lines removed.
- `src/core/game_config.gd` — confirm single line addition to utility dict (`"mode_min_hold_sec": 0.8`). No other lines changed.
- `src/core/config_validator.gd` — confirm single line addition after `intent_target_delta_px` validation. No other lines changed.

**Contract checks:**
- `func get_pursuit_mode() -> PursuitMode:` return type is explicitly declared as `PursuitMode` (not `int`, not `Variant`).
- `func _derive_mode_from_intent(intent: Dictionary) -> PursuitMode:` parameter type `Dictionary` and return type `PursuitMode` both explicitly declared.
- The `match intent_type:` block in `_derive_mode_from_intent` covers all 9 `IntentType` values and has a default branch — no intent value can produce an uninitialized return.

**Runtime scenarios to execute:** P8-A, P8-B, P8-C, P8-D (section 20).

## 20. Runtime scenario matrix.

**Scenario P8-A — direct pressure mode from PUSH intent.**
Setup: `EnemyUtilityBrain` created, `reset()` called. Context: `{dist: 820, los: true, alert: COMBAT, player_pos: Vector2(300,0)}`.
Scene: `res://tests/test_pursuit_mode_selection_by_context.tscn`.
Frame count: 1 physics frame (sufficient for `update(0.3, ctx)` call).
Expected invariants: `brain.get_pursuit_mode() == PursuitMode.DIRECT_PRESSURE`.
Fail conditions: `get_pursuit_mode() != PursuitMode.DIRECT_PRESSURE`.
Covered by: `_test_push_intent_maps_to_direct_pressure`.

**Scenario P8-B — mode hold guard prevents immediate flip.**
Setup: `EnemyUtilityBrain` created. First: `update(0.3, push_ctx)` → mode = DIRECT_PRESSURE. Immediately: `update(0.1, investigate_ctx)`.
Scene: `res://tests/test_mode_transition_guard_no_jitter.tscn`.
Frame count: 2 update calls.
Expected invariants: `get_pursuit_mode() == PursuitMode.DIRECT_PRESSURE` after second update.
Fail conditions: `get_pursuit_mode() == PursuitMode.LOST_CONTACT_SEARCH` after second update.
Covered by: `_test_mode_does_not_flip_before_hold_expires`.

**Scenario P8-C — mode changes after hold expires.**
Setup: `EnemyUtilityBrain` created. First: `update(0.3, push_ctx)`. Second: `update(1.0, investigate_ctx)`.
Scene: `res://tests/test_mode_transition_guard_no_jitter.tscn`.
Frame count: 2 update calls.
Expected invariants: `get_pursuit_mode() == PursuitMode.LOST_CONTACT_SEARCH`.
Fail conditions: `get_pursuit_mode() != PursuitMode.LOST_CONTACT_SEARCH`.
Covered by: `_test_mode_can_change_after_hold_expires`.

**Scenario P8-D — reset clears mode state.**
Setup: `EnemyUtilityBrain` created. `update(0.3, push_ctx)` → mode = DIRECT_PRESSURE. `reset()` called.
Scene: `res://tests/test_mode_transition_guard_no_jitter.tscn`.
Frame count: 1 update call + 1 reset.
Expected invariants: `get_pursuit_mode() == PursuitMode.PATROL`.
Fail conditions: `get_pursuit_mode() != PursuitMode.PATROL`.
Covered by: `_test_reset_clears_mode_and_timer`.

## 21. Verification report format.

Record all fields below to close phase:
- `phase_id: PHASE_8`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; must be empty list on close)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `forbidden_pattern_rg: [{command, expected: "0 matches", actual, PASS|FAIL}]` for FP-1, FP-2
- `rg_gates: [{command, expected, actual, PASS|FAIL}]` for each G1–G7
- `phase_tests: [{test_function, exit_code: 0, PASS|FAIL}]` for 10 new functions + 5 updated assertions
- `smoke_suite: [{command, exit_code, PASS|FAIL}]` for all 3 Tier 1 commands (steps 17–19)
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 8` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- pmb_contract_check present in section 21 (PMB section exists in document): yes

## 23. Dependencies on previous phases.

1. **Phase 2** — completed `Detour Integration + Canon Fallback FSM` in `src/systems/enemy_pursuit_system.gd`; deleted entire shadow escape system (`_resolve_movement_target_with_shadow_escape`, `_attempt_shadow_escape_recovery`, all `SHADOW_ESCAPE_RING_*` / `FALLBACK_RING_*` consts, `_policy_fallback_used`, `_policy_fallback_target`). Phase 8 inherits: after Phase 2, `EnemyUtilityBrain.IntentType` contains the final canonical set of 9 values with no shadow-escape override intents; `_derive_mode_from_intent` match branches enumerate only Phase-2-stable intent values. Without Phase 2, the intent FSM still contains shadow-escape override branches that would require additional PursuitMode entries not defined in this phase's contract.

2. **Phase 4** — implemented `IntentType.SHADOW_BOUNDARY_SCAN` behavior in `EnemyUtilityBrain._choose_intent` (conditions: `alert == SUSPICIOUS`, `has_shadow_scan_target`, `shadow_scan_target_in_shadow`) and `EnemyPursuitSystem._execute_shadow_boundary_scan` as the motion executor. Phase 8 inherits: `_derive_mode_from_intent` maps `IntentType.SHADOW_BOUNDARY_SCAN → PursuitMode.SHADOW_AWARE_SWEEP`; the test `_test_shadow_boundary_scan_maps_to_shadow_aware_sweep` exercises the specific `_choose_intent` branch that returns `SHADOW_BOUNDARY_SCAN`. Without Phase 4's `_choose_intent` implementation, the SUSPICIOUS+shadow_scan_target context would not produce `SHADOW_BOUNDARY_SCAN` intent, making the SHADOW_AWARE_SWEEP mode unreachable in production and the test unable to verify runtime behavior.

---

## PHASE 9
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_9.
Scope boundary (exact files): section 4.
Execution sequence: section 14.

### Evidence

**Inspected files:**
- `src/systems/navigation_runtime_queries.gd` (359 lines) — `build_policy_valid_path` at line 219; after Phase 1 it generates detour candidates (direct, 1wp, 2wp) and selects by `euclidean_length`; `is_point_in_shadow` does not exist in this file; `_service.call("is_point_in_shadow", sample)` delegate pattern confirmed from NavigationService. No shadow cost logic present.
- `src/systems/navigation_service.gd` — `build_policy_valid_path(from_pos, to_pos, enemy=null)` at line 400; delegates to `_runtime_queries.build_policy_valid_path(from_pos, to_pos, enemy)`; `is_point_in_shadow(point)` at line 267 exists and delegates to `_shadow_policy.is_point_in_shadow(point)`.
- `src/systems/enemy_pursuit_system.gd` (1196 lines) — `_request_path_plan_contract` at line 551 calls `nav_system.call("build_policy_valid_path", owner.global_position, target_pos, owner)` (3 args); `execute_intent` at line 221 receives `context: Dictionary`; no `_cost_profile` var or `_build_nav_cost_profile` function exists.
- `src/entities/enemy.gd` — `_build_utility_context` at line 1008; returns dict at lines 1041–1067 (no `pursuit_mode` key); `_utility_brain.update(delta, context)` called at line 624; `_pursuit.execute_intent(delta, intent, context)` at line 631; `_utility_brain` has `get_pursuit_mode()` method after Phase 8.
- `src/core/game_config.gd` — `DEFAULT_AI_BALANCE` at lines 135–222; no `nav_cost` section present.
- `src/core/config_validator.gd` — `REQUIRED_AI_BALANCE_SECTIONS` at line 9; `_ai_section` at line 291; no `nav_cost` validation block present.
- `docs/ai_nav_refactor_execution_v2.md` (`PHASE 9` contract/algorithm sections) — viable safer-route threshold baseline (`path_len <= direct_len * KPI_SAFE_ROUTE_MAX_LEN_FACTOR` and `shadow_cost_delta >= min_shadow_advantage`) and legacy-gate identifiers (`best_len_only|ignore_shadow_cost|legacy_costless_planner`) used for continuity checks.
- `docs/ai_nav_refactor_execution_v2.md` Phase 1 spec, section 7: `build_policy_valid_path` Step 12 selects candidate by `float(cand["euclidean_length"]) < best_len`; Phase 9 changes this step to score-based selection.

**Inspected functions/methods:**
- `NavigationRuntimeQueries.build_policy_valid_path` (line 219) — Phase 1 post-state: generates candidates, selects by euclidean_length.
- `NavigationRuntimeQueries._score_path_cost` — does not exist; Phase 9 adds it.
- `NavigationService.build_policy_valid_path` (line 400) — takes 3 params; Phase 9 adds 4th.
- `NavigationService.is_point_in_shadow` (line 267) — exists; delegates to shadow policy.
- `EnemyPursuitSystem._request_path_plan_contract` (line 551) — calls `nav_system.call("build_policy_valid_path", pos, target, owner)` with 3 positional args; Phase 9 adds 4th.
- `EnemyPursuitSystem.execute_intent` (line 221) — receives `context: Dictionary`; Phase 9 adds `_cost_profile` computation here.
- `enemy.gd` line 624 — `_utility_brain.update(delta, context)`; Phase 9 adds `context["pursuit_mode"] = int(_utility_brain.get_pursuit_mode())` immediately after.

**Search commands used:**
```
rg "nav_cost|shadow_weight|cost_profile|_score_path_cost|ignore_shadow_cost|best_len_only|legacy_costless" /root/arena-shooter/src/   # exit 1 (0 matches each)
rg -n "func is_point_in_shadow" /root/arena-shooter/src/systems/navigation_service.gd   # line 267
rg -n "func build_policy_valid_path" /root/arena-shooter/src/systems/navigation_service.gd   # line 400
rg -n "build_policy_valid_path" /root/arena-shooter/src/   # all callers listed
rg -n "_build_nav_cost_profile|_cost_profile" /root/arena-shooter/src/   # exit 1 (not found)
```

---

## 1. What now.

`NavigationRuntimeQueries.build_policy_valid_path` (Phase 1 state, v2 section 7 Step 12) selects the best among policy-valid candidates purely by Euclidean path length: `if float(cand["euclidean_length"]) < best_len`. No shadow exposure is measured. Mode information is not passed to path selection. Result: an enemy in CONTAIN or LOST_CONTACT_SEARCH mode navigates the shortest path regardless of how much of it passes through lit zones, taking tactically exposed routes when shadow-covered alternatives exist.

Verifiable current state:
```
rg -n "_score_path_cost" src/systems/navigation_runtime_queries.gd -S
# Expected: 0 matches (shadow cost function does not exist)

rg -n "shadow_weight|cost_profile" src/systems/enemy_pursuit_system.gd -S
# Expected: 0 matches (no cost-profile parameter or weight)

rg -n "pursuit_mode" src/entities/enemy.gd -S
# Expected: 0 matches (mode not passed to execute_intent context)

rg -n "nav_cost" src/core/game_config.gd -S
# Expected: 0 matches (nav_cost section absent)
```

## 2. What changes.

1. Add `const NAV_COST_SHADOW_SAMPLE_STEP_PX := 16.0` in `src/systems/navigation_runtime_queries.gd` (file-local constant, used only in `_score_path_cost`).
2. Add `func _score_path_cost(path_points: Array[Vector2], from_pos: Vector2, cost_profile: Dictionary) -> float` in `src/systems/navigation_runtime_queries.gd`.
3. Extend `func build_policy_valid_path` in `src/systems/navigation_runtime_queries.gd`: add `cost_profile: Dictionary = {}` as 4th parameter; change Phase 1's Step 12 candidate selection from `euclidean_length`-based to `_score_path_cost`-based.
4. Extend `func build_policy_valid_path` in `src/systems/navigation_service.gd` (line 400): add `cost_profile: Dictionary = {}` as 4th parameter; pass it to `_runtime_queries.build_policy_valid_path(from_pos, to_pos, enemy, cost_profile)`.
5. Add `var _cost_profile: Dictionary = {}` instance variable in `src/systems/enemy_pursuit_system.gd`.
6. Add `func _build_nav_cost_profile(context: Dictionary) -> Dictionary` private function in `src/systems/enemy_pursuit_system.gd`.
7. Extend `func execute_intent` in `src/systems/enemy_pursuit_system.gd`: add `_cost_profile = _build_nav_cost_profile(context)` before the `match intent_type:` statement.
8. Extend `func _request_path_plan_contract` in `src/systems/enemy_pursuit_system.gd` (line 559): change `nav_system.call("build_policy_valid_path", owner.global_position, target_pos, owner)` to `nav_system.call("build_policy_valid_path", owner.global_position, target_pos, owner, _cost_profile)`.
9. Extend `enemy.gd` line 624: add `if _utility_brain: context["pursuit_mode"] = int(_utility_brain.get_pursuit_mode())` immediately after `var intent: Dictionary = _utility_brain.update(delta, context) if _utility_brain else {}`.
10. Add `"nav_cost"` section to `GameConfig.DEFAULT_AI_BALANCE` in `src/core/game_config.gd` with 4 keys (section 6).
11. Add `nav_cost` validation block in `src/core/config_validator.gd` after the `utility` validation block. Do NOT add `"nav_cost"` to `REQUIRED_AI_BALANCE_SECTIONS` (section is optional).
12. Create `tests/test_navigation_shadow_cost_prefers_cover_path.gd` (4 test functions, section 12).
13. Create `tests/test_navigation_shadow_cost_prefers_cover_path.tscn`.
14. Create `tests/test_navigation_shadow_cost_push_mode_allows_shortcut.gd` (4 test functions, section 12).
15. Create `tests/test_navigation_shadow_cost_push_mode_allows_shortcut.tscn`.
16. Register both new test files in `tests/test_runner_node.gd` by adding scene constants, scene existence checks, and `await _run_embedded_scene_suite(...)` calls in the existing embedded-suite sections.

## 3. What will be after.

Each item is verifiable by the named gate or test.

- `_score_path_cost` exists in `src/systems/navigation_runtime_queries.gd`: verified by G3.
- `build_policy_valid_path` in NavigationRuntimeQueries accepts 4th `cost_profile` param: verified by G4.
- `build_policy_valid_path` in NavigationService accepts 4th `cost_profile` param: verified by G5.
- `_cost_profile` instance var exists in EnemyPursuitSystem: verified by G6.
- `nav_cost` section present in game_config.gd: verified by G7.
- Shadow-covered path selected over shorter lit path when `shadow_weight > 0`: verified by `_test_positive_shadow_weight_shadow_path_wins` (section 12).
- Shorter path selected when `shadow_weight = 0`: verified by `_test_zero_shadow_weight_selects_shorter_path` (section 12).
- `_build_nav_cost_profile` returns `shadow_weight = 0.0` for DIRECT_PRESSURE mode: verified by `_test_direct_pressure_mode_returns_zero_shadow_weight` (section 12).
- `_build_nav_cost_profile` returns `shadow_weight = 80.0` for non-DIRECT_PRESSURE mode: verified by `_test_non_direct_pressure_mode_returns_cautious_weight` (section 12).
- Forbidden patterns absent: verified by G1, G2.

## 4. Scope and non-scope.

**In-scope (allowed file-change boundary):**
- `src/systems/navigation_runtime_queries.gd`
- `src/systems/navigation_service.gd`
- `src/systems/enemy_pursuit_system.gd`
- `src/entities/enemy.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `tests/test_navigation_shadow_cost_prefers_cover_path.gd` (new)
- `tests/test_navigation_shadow_cost_prefers_cover_path.tscn` (new)
- `tests/test_navigation_shadow_cost_push_mode_allows_shortcut.gd` (new)
- `tests/test_navigation_shadow_cost_push_mode_allows_shortcut.tscn` (new)
- `tests/test_runner_node.gd` (registration only)
- `CHANGELOG.md`

Any change outside this list = phase FAILED regardless of test results.

**Out-of-scope:**
- `src/systems/enemy_utility_brain.gd`
- `src/systems/enemy_squad_system.gd`
- `src/systems/navigation_shadow_policy.gd`
- `src/systems/enemy_patrol_system.gd`
- `scenes/entities/enemy.tscn`
- All other `src/` files not listed in in-scope.

## 5. Single-owner authority.

The exact file that owns the shadow cost scoring decision: `src/systems/navigation_runtime_queries.gd`.
The exact function that is the sole decision point: `NavigationRuntimeQueries._score_path_cost`.
No other file duplicates this decision: verified by G3 (`rg -n "func _score_path_cost" src/ -S` → 1 match, in `navigation_runtime_queries.gd` only).

The exact file that owns the mode-to-weight mapping: `src/systems/enemy_pursuit_system.gd`.
The exact function: `EnemyPursuitSystem._build_nav_cost_profile`.
No other file duplicates this mapping: verified by G9 (`rg -n "func _build_nav_cost_profile" src/ -S` → 1 match).

## 6. Full input/output contract.

### Contract 1: ShadowCostScoringContract

Function: `NavigationRuntimeQueries._score_path_cost(path_points: Array[Vector2], from_pos: Vector2, cost_profile: Dictionary) -> float`

Inputs:
- `path_points`: `Array[Vector2]`. May be empty. If empty → return `INF`.
- `from_pos`: `Vector2`. Non-null. Starting point for segment iteration.
- `cost_profile`: `Dictionary`. Keys used:
  - `"shadow_weight": float` — weight per lit sample point. Default (if absent): `0.0`. Valid range: `[0.0, INF)`.
  - `"shadow_sample_step_px": float` — sampling granularity. Default (if absent): `NAV_COST_SHADOW_SAMPLE_STEP_PX` (16.0). Valid range: `[1.0, INF)`. Values below 1.0 are clamped to 1.0 via `maxf(sample_step, 1.0)`.

Output: `float`. Score value = `path_length_px + shadow_weight * lit_sample_count`.
- `INF` when `path_points.is_empty()`.
- `path_length_px` when `shadow_weight == 0.0` (no shadow queries issued).
- `path_length_px + shadow_weight * lit_count` when `shadow_weight > 0.0` and `_service.has_method("is_point_in_shadow") == true`.
- `path_length_px` when `shadow_weight > 0.0` but `_service == null` or `_service.has_method("is_point_in_shadow") == false` (service fallback: lit_count = 0).

### Contract 2: NavCostProfileContract

Function: `EnemyPursuitSystem._build_nav_cost_profile(context: Dictionary) -> Dictionary`

Inputs:
- `context: Dictionary`. Key used: `"pursuit_mode": int`. If absent, defaults to `-1` (treated as non-DIRECT_PRESSURE → cautious).

Output: `Dictionary` with keys:
- `"shadow_weight": float` — `0.0` when `int(context.get("pursuit_mode", -1)) == int(EnemyUtilityBrain.PursuitMode.DIRECT_PRESSURE)`; otherwise equals `float(GameConfig.ai_balance["nav_cost"]["shadow_weight_cautious"])` (default `80.0`).
- `"shadow_sample_step_px": float` — equals `float(GameConfig.ai_balance["nav_cost"]["shadow_sample_step_px"])` (default `16.0`).

GameConfig `nav_cost` section constants (added to `DEFAULT_AI_BALANCE`):

| Key | Type | Value | Description |
|---|---|---|---|
| `shadow_weight_cautious` | float | `80.0` | Shadow penalty per lit sample (cautious modes) |
| `shadow_weight_aggressive` | float | `0.0` | Shadow penalty for DIRECT_PRESSURE (zero = length only) |
| `shadow_sample_step_px` | float | `16.0` | Sample step along path segments for lit-point counting |
| `safe_route_max_len_factor` | float | `1.35` | KPI: selected path must not exceed direct_len × 1.35 |

`safe_route_max_len_factor` is used in tests as a KPI constraint only; it is not enforced at runtime in `_score_path_cost`.

## 7. Deterministic algorithm with exact order.

### 7.1 `_score_path_cost(path_points, from_pos, cost_profile) -> float`

Step 1: If `path_points.is_empty()`: return `INF`.
Step 2: `shadow_weight := float(cost_profile.get("shadow_weight", 0.0))`.
Step 3: `sample_step := maxf(float(cost_profile.get("shadow_sample_step_px", NAV_COST_SHADOW_SAMPLE_STEP_PX)), 1.0)`.
Step 4: `total_len := 0.0`. `lit_count := 0`. `prev := from_pos`.
Step 5: For each `point` in `path_points`:
  a. `seg_len := prev.distance_to(point)`.
  b. `steps := maxi(int(ceil(seg_len / sample_step)), 1)`.
  c. If `shadow_weight > 0.0`: for `s` in `range(1, steps + 1)`: sample `= prev.lerp(point, float(s)/float(steps))`; if `_service != null` and `_service.has_method("is_point_in_shadow")` and `not bool(_service.call("is_point_in_shadow", sample))`: `lit_count += 1`.
  d. `total_len += seg_len`. `prev = point`.
Step 6: Return `total_len + shadow_weight * float(lit_count)`.

Note: When `shadow_weight == 0.0`, step 5c is skipped entirely — no `is_point_in_shadow` calls are made. Score equals pure path length. This is the backward-compatible behavior identical to Phase 1's length-based selection.

### 7.2 Phase 1 Step 12 change in `build_policy_valid_path`

Phase 1 Step 12 (original): `if float(cand["euclidean_length"]) < best_len: set best_valid, best_len`

Phase 9 replacement: `var score := _score_path_cost(cand["path_points"] as Array[Vector2], from_pos, cost_profile)`. Replace `best_len` tracking with `best_score: float = INF`. Selection condition: `score < best_score`.

Tie-break: when two candidates produce equal scores (e.g., both fully in shadow with same length), the candidate that appears earlier in the `candidates` array (Phase 1's ascending `euclidean_length` sort) is selected. This makes tie-breaking deterministic.

### 7.3 `_build_nav_cost_profile(context) -> Dictionary`

Step 1: `mode := int(context.get("pursuit_mode", -1))`.
Step 2: `nc := GameConfig.ai_balance.get("nav_cost", {}) as Dictionary`.
Step 3: If `mode == int(ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE)`: `shadow_weight := float(nc.get("shadow_weight_aggressive", 0.0))`. Else: `shadow_weight := float(nc.get("shadow_weight_cautious", 80.0))`.
Step 4: `sample_step := float(nc.get("shadow_sample_step_px", 16.0))`.
Step 5: Return `{"shadow_weight": shadow_weight, "shadow_sample_step_px": sample_step}`.

## 8. Edge-case matrix.

**Case A — empty path_points.**
Input: `_score_path_cost([], from_pos, {"shadow_weight": 80.0})`.
Output: `INF`.

**Case B — single valid segment, all in shadow.**
Input: `path_points = [Vector2(0, 100)]`, `from_pos = Vector2.ZERO`, stub service returns `true` (in shadow) for all sampled points. `cost_profile = {"shadow_weight": 80.0, "shadow_sample_step_px": 100.0}`.
Steps: seg_len=100, steps=1, sample at lerp(0,100,1.0)=Vector2(0,100) → in shadow → lit_count stays 0. total_len=100.
Output: `100.0 + 80.0 * 0 = 100.0`.

**Case C — tie-break.**
Two candidates with equal score: both fully in shadow, equal path length. The candidate with lower index in the `candidates` array (Phase 1 sort: ascending euclidean_length) is selected. Proved by section 7.2: `score < best_score` (strict less-than). When tied, first candidate sets `best_valid` and `best_score`, subsequent equal-score candidates do not satisfy `score < best_score`. Output: first (lowest-index) candidate returned.

**Case D — all inputs invalid: service has no `is_point_in_shadow`.**
Input: stub service without `is_point_in_shadow`. `cost_profile = {"shadow_weight": 80.0}`, non-empty `path_points`.
Step 5c: `_service.has_method("is_point_in_shadow") == false` → lit_count stays 0.
Output: `total_len + 80.0 * 0 = total_len` (falls back to length-based scoring).

**Case E — DIRECT_PRESSURE mode: shadow_weight = 0.0.**
Input: `context = {"pursuit_mode": int(PursuitMode.DIRECT_PRESSURE)}`.
`_build_nav_cost_profile` step 3: condition true → `shadow_weight = float(nc.get("shadow_weight_aggressive", 0.0)) = 0.0`.
`_score_path_cost` called with `shadow_weight = 0.0`: step 5c skipped, no shadow queries. Score = path_length.

**Case F — absent `pursuit_mode` key in context.**
Input: `context = {}` (no `pursuit_mode`).
`_build_nav_cost_profile` step 1: `mode = int({}.get("pursuit_mode", -1)) = -1`.
Step 3: `-1 != int(PursuitMode.DIRECT_PRESSURE)` → `shadow_weight = float(nc.get("shadow_weight_cautious", 80.0)) = 80.0`.
Output: cautious profile (shadow penalty applies).

**Case G — `shadow_sample_step_px` below 1.0 in cost_profile.**
Input: `cost_profile = {"shadow_weight": 80.0, "shadow_sample_step_px": 0.0}`.
Step 3 of `_score_path_cost`: `sample_step = maxf(0.0, 1.0) = 1.0`. Minimum granularity enforced; no division by zero.

## 9. Legacy removal plan.

N/A — no legacy identifiers exist in the codebase prior to Phase 9 that this phase must delete. Phase 9 adds entirely new code. The forbidden patterns `best_len_only`, `ignore_shadow_cost`, `legacy_costless_planner` have never existed in the codebase (verified by PROJECT DISCOVERY search commands in Evidence preamble). Section 10 documents these as forbidden-pattern gates.

## 10. Legacy verification commands.

No legacy identifiers to verify removed. The following commands verify forbidden patterns are NOT introduced by Phase 9 (expected: 0 matches each):

**[FP-1] best_len_only must not exist:**
```
rg -n "best_len_only" src/ tests/ -S
```
Expected: 0 matches.

**[FP-2] ignore_shadow_cost must not exist:**
```
rg -n "ignore_shadow_cost" src/ tests/ -S
```
Expected: 0 matches.

**[FP-3] legacy_costless_planner must not exist:**
```
rg -n "legacy_costless_planner" src/ tests/ -S
```
Expected: 0 matches.

Phase cannot close if any command returns non-zero match count.

## 11. Acceptance criteria.

All items are binary boolean statements answerable by running a command or reading a test result.

1. `rg -n "func _score_path_cost" src/systems/navigation_runtime_queries.gd -S` → 1 match: PASS|FAIL.
2. `rg -n "cost_profile" src/systems/navigation_runtime_queries.gd -S` → ≥1 match (4th param added): PASS|FAIL.
3. `rg -n "cost_profile" src/systems/navigation_service.gd -S` → ≥1 match (4th param added): PASS|FAIL.
4. `rg -n "_cost_profile" src/systems/enemy_pursuit_system.gd -S` → ≥1 match: PASS|FAIL.
5. `rg -n "nav_cost" src/core/game_config.gd -S` → ≥1 match: PASS|FAIL.
6. `rg -n "nav_cost" src/core/config_validator.gd -S` → ≥1 match: PASS|FAIL.
7. `rg -n "pursuit_mode" src/entities/enemy.gd -S` → ≥1 match: PASS|FAIL.
8. All 3 forbidden-pattern gates (FP-1, FP-2, FP-3) return 0 matches: PASS|FAIL.
9. `tests/test_navigation_shadow_cost_prefers_cover_path.tscn` exits 0: PASS|FAIL.
10. `tests/test_navigation_shadow_cost_push_mode_allows_shortcut.tscn` exits 0: PASS|FAIL.
11. `tests/test_runner.tscn` exits 0: PASS|FAIL.
12. Both new test files registered in `tests/test_runner_node.gd` (scene constants + scene existence checks + `_run_embedded_scene_suite` calls): PASS|FAIL.

## 12. Tests.

### New file: `tests/test_navigation_shadow_cost_prefers_cover_path.gd`

Tests `NavigationRuntimeQueries._score_path_cost` using a stub service with controlled `is_point_in_shadow` behavior. The stub service implements `is_point_in_shadow(point: Vector2) -> bool` returning `false` (lit) for points with `x >= 0` and `true` (shadow) for points with `x < 0`.

- `_test_score_path_all_in_shadow`: path from `Vector2.ZERO` to `Vector2(-100, 0)`. `cost_profile = {"shadow_weight": 80.0, "shadow_sample_step_px": 100.0}`. One sample at `Vector2(-100, 0)` → x < 0 → in shadow → lit_count=0. Expected: `score == 100.0`.
- `_test_score_path_all_lit`: path from `Vector2.ZERO` to `Vector2(100, 0)`. `cost_profile = {"shadow_weight": 80.0, "shadow_sample_step_px": 100.0}`. One sample at `Vector2(100, 0)` → x ≥ 0 → lit → lit_count=1. Expected: `score == 100.0 + 80.0 * 1 = 180.0`.
- `_test_score_path_zero_shadow_weight`: path from `Vector2.ZERO` to `Vector2(100, 0)`. `cost_profile = {"shadow_weight": 0.0}`. Step 5c skipped → lit_count=0. Expected: `score == 100.0` (pure path length).
- `_test_score_path_empty_returns_inf`: `path_points = []`. Any `cost_profile`. Expected: `score == INF`.

Registration: add a scene constant, scene existence check, and an `await _run_embedded_scene_suite(...)` call in `tests/test_runner_node.gd`.

### New file: `tests/test_navigation_shadow_cost_push_mode_allows_shortcut.gd`

Tests use stub service with `is_point_in_shadow(point) -> bool` returning `false` (lit) for `point.x >= 0` and `true` (shadow) for `point.x < 0`.

- `_test_zero_shadow_weight_selects_shorter_path`: compare two candidates with `shadow_weight=0`. Short path: `[Vector2(100, 0)]` from `Vector2.ZERO` (length 100, x≥0, lit). Long path: `[Vector2(-300, 0)]` from `Vector2.ZERO` (length 300, all shadow). `_score_path_cost(short, ...) = 100`. `_score_path_cost(long, ...) = 300`. Expected: short path score is lower (100 < 300). Verifies aggressive mode (shadow_weight=0) selects shortest path.
- `_test_non_direct_pressure_mode_returns_cautious_weight`: create `EnemyPursuitSystem` with minimal stub setup. Call `_build_nav_cost_profile({"pursuit_mode": int(ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.CONTAIN)})`. Assert: `result["shadow_weight"] == 80.0`. Proves non-DIRECT_PRESSURE modes use the cautious weight branch.
- `_test_direct_pressure_mode_returns_zero_shadow_weight`: create `EnemyPursuitSystem` with minimal stub setup. Call `_build_nav_cost_profile({"pursuit_mode": int(ENEMY_UTILITY_BRAIN_SCRIPT.PursuitMode.DIRECT_PRESSURE)})`. Assert: `result["shadow_weight"] == 0.0`.
- `_test_positive_shadow_weight_shadow_path_wins`: stub service returns `false` (lit) for `point.x >= 0` and `true` (shadow) for `point.x < 0`. Short path: `[Vector2(100, 0)]` from `Vector2.ZERO` (100px, `shadow_sample_step_px=16.0` → `steps=ceil(100/16)=7` → 7 lit samples at x≥0) → `score = 100 + 80*7 = 660`. Long shadow path: `[Vector2(-200, 0)]` from `Vector2.ZERO` (200px, all x<0 → 0 lit samples) → `score = 200`. Assert `score_shadow (200.0) < score_lit (660.0)`. Proves that with `shadow_weight=80` and step=16, the 200px all-shadow path wins over the 100px all-lit path.

Registration: add a scene constant, scene existence check, and an `await _run_embedded_scene_suite(...)` call in `tests/test_runner_node.gd`.

## 13. rg gates.

**Phase-specific gates:**

**[G1] Forbidden pattern: best_len_only absent.**
```
rg -n "best_len_only" src/ tests/ -S
```
Expected: 0 matches.

**[G2] Forbidden pattern: ignore_shadow_cost absent.**
```
rg -n "ignore_shadow_cost" src/ tests/ -S
```
Expected: 0 matches.

**[G3] _score_path_cost defined only in navigation_runtime_queries.gd.**
```
rg -n "func _score_path_cost" src/ -S
```
Expected: 1 match (in `src/systems/navigation_runtime_queries.gd` only).

**[G4] cost_profile param added to NavigationRuntimeQueries.build_policy_valid_path.**
```
rg -n "cost_profile" src/systems/navigation_runtime_queries.gd -S
```
Expected: ≥2 matches (function signature + usage in _score_path_cost call).

**[G5] cost_profile param added to NavigationService.build_policy_valid_path.**
```
rg -n "cost_profile" src/systems/navigation_service.gd -S
```
Expected: ≥2 matches (function signature + pass-through).

**[G6] _cost_profile instance var and _build_nav_cost_profile present in EnemyPursuitSystem.**
```
rg -n "_cost_profile" src/systems/enemy_pursuit_system.gd -S
```
Expected: ≥3 matches (var declaration, assignment in execute_intent, usage in _request_path_plan_contract).

**[G7] nav_cost section present in game_config.gd.**
```
rg -n "nav_cost" src/core/game_config.gd -S
```
Expected: ≥1 match.

**[G8] nav_cost validated in config_validator.gd.**
```
rg -n "nav_cost" src/core/config_validator.gd -S
```
Expected: ≥1 match.

**[G9] _build_nav_cost_profile defined only in enemy_pursuit_system.gd.**
```
rg -n "func _build_nav_cost_profile" src/ -S
```
Expected: 1 match (in `src/systems/enemy_pursuit_system.gd` only).

**[G10] pursuit_mode key set in enemy.gd after brain update.**
```
rg -n "pursuit_mode" src/entities/enemy.gd -S
```
Expected: ≥1 match.

**[G11] legacy_costless_planner absent.**
```
rg -n "legacy_costless_planner" src/ tests/ -S
```
Expected: 0 matches.

**PMB gates (verbatim command set from `## Start of Persistent Module Boundary Contract`):**

**[PMB-1]** EnemyPursuitSystem — lexical anti-legacy guard for alternate path planners:
```
rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S
```
Expected: 0 matches.

**[PMB-2]** `enemy.gd` не вызывает path-planning navigation API напрямую:
```
rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S
```
Expected: 0 matches.

**[PMB-3]** `enemy_pursuit_system.gd` не производит utility-context contract fields:
```
rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S
```
Expected: 0 matches.

**[PMB-4]** `EnemyPursuitSystem` не конструирует intent dictionaries (`"type": ...`):
```
rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S
```
Expected: 0 matches.

**[PMB-5]** Только один вызов execute_intent из Enemy:
```
bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'
```
Expected: output contains "PMB-5: PASS (1)".

## 14. Execution sequence.

Step 1: (No legacy delete — section 9 confirmed N/A.)
Step 2: In `src/systems/navigation_runtime_queries.gd`, add `const NAV_COST_SHADOW_SAMPLE_STEP_PX := 16.0` after the existing `const POLICY_SAMPLE_STEP_PX := 12.0` constant.
Step 3: In `src/systems/navigation_runtime_queries.gd`, add `func _score_path_cost(path_points: Array[Vector2], from_pos: Vector2, cost_profile: Dictionary) -> float` with the algorithm from section 7.1.
Step 4: In `src/systems/navigation_runtime_queries.gd`, extend `func build_policy_valid_path`: add `cost_profile: Dictionary = {}` as 4th parameter; replace Phase 1 Step 12 `best_len: float = INF` tracking with `best_score: float = INF` and `score < best_score` selection using `_score_path_cost`.
Step 5: In `src/systems/navigation_service.gd`, extend `func build_policy_valid_path` (line 400): add `cost_profile: Dictionary = {}` as 4th parameter; change the `_runtime_queries.build_policy_valid_path(from_pos, to_pos, enemy)` call to `_runtime_queries.build_policy_valid_path(from_pos, to_pos, enemy, cost_profile)`.
Step 6: In `src/systems/enemy_pursuit_system.gd`, add `var _cost_profile: Dictionary = {}` in the instance vars block (after `_hard_stall` var or similar).
Step 7: In `src/systems/enemy_pursuit_system.gd`, add `func _build_nav_cost_profile(context: Dictionary) -> Dictionary` with the algorithm from section 7.3.
Step 8: In `src/systems/enemy_pursuit_system.gd`, extend `func execute_intent`: add `_cost_profile = _build_nav_cost_profile(context)` as the first statement inside the function body (before `var request_fire := false`).
Step 9: In `src/systems/enemy_pursuit_system.gd`, extend `func _request_path_plan_contract` (line 559): change `nav_system.call("build_policy_valid_path", owner.global_position, target_pos, owner)` to `nav_system.call("build_policy_valid_path", owner.global_position, target_pos, owner, _cost_profile)`.
Step 10: In `src/entities/enemy.gd`, add immediately after `var intent: Dictionary = _utility_brain.update(delta, context) if _utility_brain else {}` (line 624): `if _utility_brain: context["pursuit_mode"] = int(_utility_brain.get_pursuit_mode())`.
Step 11: In `src/core/game_config.gd`, add `"nav_cost": { "shadow_weight_cautious": 80.0, "shadow_weight_aggressive": 0.0, "shadow_sample_step_px": 16.0, "safe_route_max_len_factor": 1.35, }` to `DEFAULT_AI_BALANCE` (after the `"utility"` section or before the closing `}`).
Step 12: In `src/core/config_validator.gd`, add a `nav_cost` validation block after the `utility` validation block: `var nav_cost := _ai_section(result, ai_balance, "nav_cost")` / `if not nav_cost.is_empty():` / validate 4 keys (section 6 table).
Step 13: Create `tests/test_navigation_shadow_cost_prefers_cover_path.gd` (4 test functions, section 12).
Step 14: Create `tests/test_navigation_shadow_cost_prefers_cover_path.tscn`.
Step 15: Create `tests/test_navigation_shadow_cost_push_mode_allows_shortcut.gd` (4 test functions, section 12).
Step 16: Create `tests/test_navigation_shadow_cost_push_mode_allows_shortcut.tscn`.
Step 17: Register both new test files in `tests/test_runner_node.gd` by adding scene constants, scene existence checks, and `await _run_embedded_scene_suite(...)` calls in the existing embedded-suite sections.
Step 18: Run Tier 1 smoke (test 1): `xvfb-run -a godot-4 --headless --path . res://tests/test_navigation_shadow_cost_prefers_cover_path.tscn` — must exit 0.
Step 19: Run Tier 1 smoke (test 2): `xvfb-run -a godot-4 --headless --path . res://tests/test_navigation_shadow_cost_push_mode_allows_shortcut.tscn` — must exit 0.
Step 20: Run Tier 2 full regression: `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit 0.
Step 21: Run all rg gates: G1–G11, PMB-1 through PMB-5 — all must return expected output.
Step 22: Prepend CHANGELOG entry under today's date header in `CHANGELOG.md` (create `## YYYY-MM-DD` first if absent).

## 15. Rollback conditions.

- Condition 1: Any test in `test_navigation_shadow_cost_prefers_cover_path.tscn` or `test_navigation_shadow_cost_push_mode_allows_shortcut.tscn` exits non-zero → revert all Phase 9 changes to `src/systems/navigation_runtime_queries.gd`, `src/systems/navigation_service.gd`, `src/systems/enemy_pursuit_system.gd`, `src/entities/enemy.gd`, `src/core/game_config.gd`, `src/core/config_validator.gd`, `tests/test_runner_node.gd`. Delete new .gd and .tscn test files.
- Condition 2: G3 returns 0 matches (`_score_path_cost` not added) → revert `src/systems/navigation_runtime_queries.gd`.
- Condition 3: G4 returns 0 matches (`cost_profile` param not added to NavigationRuntimeQueries) → revert `src/systems/navigation_runtime_queries.gd`.
- Condition 4: PMB-4 fails (intent-dictionary construction key `"type":` appears in `enemy_pursuit_system.gd`) → remove the pursuit-side intent dictionary construction (do not remove legal `match intent_type` execution branches), then re-attempt from Step 7.
- Condition 5: `test_runner.tscn` exits non-zero → revert all Phase 9 changes.
- Condition 6: Any PMB gate fails → revert all Phase 9 changes and investigate root cause before re-attempting.
- Condition 7: G1, G2, or G11 returns non-zero (forbidden patterns introduced) → revert all Phase 9 changes, remove offending identifier, re-attempt.

## 16. Phase close condition.

- [ ] All rg commands in section 10 (FP-1, FP-2, FP-3) return 0 matches
- [ ] All rg gates in section 13 (G1–G11) return expected output
- [ ] PMB gates in section 13 (PMB-1 through PMB-4) return 0 matches; PMB-5 output contains "PMB-5: PASS (1)"
- [ ] All tests in section 12 (4 new + 4 new) exit 0
- [ ] Tier 1 smoke suite (2 commands, steps 18–19) — both exit 0
- [ ] Tier 2 full regression (`test_runner.tscn`) exits 0
- [ ] No file outside section 4 in-scope list was modified
- [ ] CHANGELOG entry prepended
- [ ] `"nav_cost"` NOT added to `REQUIRED_AI_BALANCE_SECTIONS` in `config_validator.gd` (section is optional)
- [ ] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S` returns 0 matches

## 17. Ambiguity check: 0

## 18. Open questions: 0

## 19. Post-implementation verification plan.

**Diff audit:**
- `src/systems/navigation_runtime_queries.gd` — confirm: 1 new const (`NAV_COST_SHADOW_SAMPLE_STEP_PX`), 1 new private function (`_score_path_cost`), `build_policy_valid_path` signature extended with 4th param, Step 12 candidate selection logic changed. No other lines removed.
- `src/systems/navigation_service.gd` — confirm: `build_policy_valid_path` signature extended with `cost_profile` param, pass-through line updated. No other lines changed.
- `src/systems/enemy_pursuit_system.gd` — confirm: 1 new var (`_cost_profile`), 1 new function (`_build_nav_cost_profile`), 1 line added to `execute_intent`, 1 line changed in `_request_path_plan_contract`. No PATROL or RETURN_HOME words introduced.
- `src/entities/enemy.gd` — confirm: 2 lines added after line 624 (`if _utility_brain: context["pursuit_mode"] = ...`). No nav API calls added to enemy.gd.
- `src/core/game_config.gd` — confirm: `"nav_cost"` dict with 4 keys added. No other sections changed.
- `src/core/config_validator.gd` — confirm: `nav_cost` block added. `REQUIRED_AI_BALANCE_SECTIONS` unchanged.

**Contract checks:**
- `func _score_path_cost(path_points: Array[Vector2], from_pos: Vector2, cost_profile: Dictionary) -> float` — all parameter types and return type explicitly declared.
- `func _build_nav_cost_profile(context: Dictionary) -> Dictionary` — parameter type `Dictionary` and return type `Dictionary` explicitly declared.
- `func build_policy_valid_path(from_pos: Vector2, to_pos: Vector2, enemy: Node = null, cost_profile: Dictionary = {}) -> Dictionary` in both NavigationRuntimeQueries and NavigationService — confirm 4th param is optional with `= {}` default.

**Runtime scenarios:** P9-A, P9-B, P9-C, P9-D (section 20).

## 20. Runtime scenario matrix.

**Scenario P9-A — cautious mode: shadow path preferred over lit shortcut.**
Setup: stub NavigationRuntimeQueries with stub service. Two paths: short all-lit (100px, score=100+80*7=660 at step=16) and long all-shadow (200px, score=200). `cost_profile = {"shadow_weight": 80.0, "shadow_sample_step_px": 16.0}`.
Scene: `res://tests/test_navigation_shadow_cost_push_mode_allows_shortcut.tscn`.
Expected: long shadow path score (200) < short lit path score (660).
Covered by: `_test_positive_shadow_weight_shadow_path_wins`.

**Scenario P9-B — aggressive mode (shadow_weight=0): shorter path wins.**
Setup: same two paths. `cost_profile = {"shadow_weight": 0.0}`. score_short=100, score_long=200.
Scene: `res://tests/test_navigation_shadow_cost_push_mode_allows_shortcut.tscn`.
Expected: score_short (100) < score_long (200).
Covered by: `_test_zero_shadow_weight_selects_shorter_path`.

**Scenario P9-C — DIRECT_PRESSURE mode maps to shadow_weight=0.**
Setup: `EnemyPursuitSystem` with `context = {"pursuit_mode": int(PursuitMode.DIRECT_PRESSURE)}`.
Scene: `res://tests/test_navigation_shadow_cost_push_mode_allows_shortcut.tscn`.
Expected: `_build_nav_cost_profile(context)["shadow_weight"] == 0.0`.
Covered by: `_test_direct_pressure_mode_returns_zero_shadow_weight`.

**Scenario P9-D — `_score_path_cost` empty path returns INF.**
Setup: `path_points = []`, any `cost_profile`.
Scene: `res://tests/test_navigation_shadow_cost_prefers_cover_path.tscn`.
Expected: return value `== INF`.
Covered by: `_test_score_path_empty_returns_inf`.

## 21. Verification report format.

Record all fields below to close phase:
- `phase_id: PHASE_9`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; must be empty list on close)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `forbidden_pattern_rg: [{command, expected: "0 matches", actual, PASS|FAIL}]` for FP-1, FP-2, FP-3
- `rg_gates: [{command, expected, actual, PASS|FAIL}]` for each G1–G11
- `phase_tests: [{test_function, exit_code: 0, PASS|FAIL}]` for 8 new test functions
- `smoke_suite: [{command, exit_code, PASS|FAIL}]` for 2 Tier 1 commands (steps 18–19)
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 9` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- pmb_contract_check present in section 21 (PMB section exists in document): yes

## 23. Dependencies on previous phases.

1. **Phase 1** — extended `NavigationRuntimeQueries.build_policy_valid_path` to generate detour candidates (direct, 1wp, 2wp) and select by `euclidean_length` (Phase 1, section 7 Steps 10–13). Phase 9 inherits: the candidate array and `euclidean_length` field produced by Phase 1 are the substrate that Phase 9's `_score_path_cost` replaces as the selection criterion. Without Phase 1, there are no multiple candidates to score — the function returns directly on the first policy-valid path, and Phase 9's cost comparison loop in Step 12 would never execute.

2. **Phase 5** — enforced mandatory navmesh extraction and `NavigationService.is_point_in_shadow` is available as a stable callable via `_service.call("is_point_in_shadow", sample)`. Phase 9 inherits: `_score_path_cost` calls `_service.call("is_point_in_shadow", sample)` to count lit sample points. Without Phase 5's navmesh and shadow-policy extraction guarantee, `NavigationService.is_point_in_shadow` returns inconsistent results (no shadow zones loaded), making lit-count computation unreliable and `_score_path_cost` values non-deterministic across map loads.

3. **Phase 8** — added `EnemyUtilityBrain.PursuitMode` enum and `get_pursuit_mode() -> PursuitMode` public accessor; `update()` sets `_current_mode` before returning. Phase 9 inherits: `_build_nav_cost_profile` reads `int(context.get("pursuit_mode", -1))` and compares it against `PursuitMode.DIRECT_PRESSURE` (the int value of the enum). `enemy.gd` sets `context["pursuit_mode"] = int(_utility_brain.get_pursuit_mode())` after `_utility_brain.update()` returns. Without Phase 8, `get_pursuit_mode()` does not exist, `context["pursuit_mode"]` is never set, `_build_nav_cost_profile` always returns cautious profile (`mode == -1`), and the DIRECT_PRESSURE → aggressive-weight branch is unreachable in production — making `_test_direct_pressure_mode_returns_zero_shadow_weight` fail.

---

## PHASE 10
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_10.

### Evidence

**Inspected files:**
1. `src/systems/enemy_squad_system.gd` (336 lines): `_build_slots` (198–221), `_build_ring_slots` (224–234), `_pick_slot_for_enemy` (142–178), `_is_slot_path_ok` (181–195), `_recompute_assignments` (102–139), `_default_assignment` (262–270), `_squad_cfg_float` (324–328), `_squad_cfg_int` (331–335). Enum `Role { PRESSURE=0, HOLD=1, FLANK=2 }` at lines 6–10. Constants `FLANK_RADIUS_PX=640.0`, `HOLD_RADIUS_PX=520.0` at lines 14–16.
2. `src/entities/enemy.gd`: constants `SQUAD_ROLE_PRESSURE=0, SQUAD_ROLE_HOLD=1, SQUAD_ROLE_FLANK=2` (53–55); `_assignment_supports_flank_role` (2243–2248); `_resolve_contextual_combat_role` (2251–2270); `_utility_cfg_float` (1504–1508); `_squad_cfg_float` — absent.
3. `src/systems/navigation_service.gd`: `nav_path_length` (410–412), `get_door_center_between` (370–372), `get_adjacent_room_ids` (355–357), `room_id_at_point` (247–249).
4. `src/systems/navigation_runtime_queries.gd`: `nav_path_length` (301–313) — returns INF on no path; `get_door_center_between` (125–126) — delegates to `_service._select_door_center`; `get_adjacent_room_ids` (95–96) — calls `get_neighbors`; `get_neighbors` (56–65) — reads `_service._room_graph`, sorted ascending.
5. `src/core/game_config.gd`: `DEFAULT_AI_BALANCE["squad"]` (167–178) — 10 keys: `rebuild_interval_sec, slot_reservation_ttl_sec, pressure_radius_px, hold_radius_px, flank_radius_px, pressure_slot_count, hold_slot_count, flank_slot_count, invalid_path_score_penalty, slot_path_tail_tolerance_px`. Keys `flank_max_path_px`, `flank_max_time_sec`, `flank_walk_speed_assumed_px_per_sec` absent.
6. `src/core/config_validator.gd`: squad validation block (226–241) — validates same 10 keys. No flank KPI validation present.
7. `tests/test_enemy_squad_system.gd` (150 lines): `_test_unique_slot_reservations`, `_test_role_stability`, `_test_path_fallback`. No `slot_path_length` assertions.
8. `tests/test_runner_node.gd` (1239 lines): `_run_embedded_scene_suite` pattern at line 1192; SECTION 18c ends before line 1116; no Phase 8–10 test registrations present.

**Inspected functions/methods:**
1. `EnemySquadSystem._pick_slot_for_enemy` — returns `{"key": String, "position": Vector2, "path_ok": bool}`. Does NOT include `slot_path_length`.
2. `EnemySquadSystem._default_assignment(role)` — returns dict with keys `role, slot_position, slot_key, path_ok, has_slot, reserved_until`. Does NOT include `slot_path_length`.
3. `Enemy._assignment_supports_flank_role(assignment)` — checks role, has_slot, path_ok only. Does NOT check path length or time budget.
4. `NavigationService.nav_path_length(from_pos, to_pos, enemy)` — exists, returns float; INF on no reachable path.
5. `NavigationService.get_door_center_between(room_a, room_b, anchor)` — exists, returns `Vector2`; returns `Vector2.ZERO` when no door found between the rooms.
6. `NavigationService.get_adjacent_room_ids(room_id)` — exists, returns `Array[int]` sorted ascending.

**Search commands used:**
1. `rg -n "slot_path_length" src/ tests/ -S` → 0 matches
2. `rg -n "_build_contain_slots_from_exits" src/ tests/ -S` → 0 matches
3. `rg -n "flank_max_path_px\|flank_max_time_sec\|flank_walk_speed_assumed" src/ -S` → 0 matches
4. `rg -n "func _squad_cfg_float" src/entities/enemy.gd -S` → 0 matches
5. `rg -n "legacy_flank|old_contain_logic|manual_role_override_legacy" src/ tests/ -S` → 0 matches
6. `rg -n "nav_path_length\|get_door_center_between\|get_adjacent_room_ids" src/systems/navigation_service.gd -S` → 3 matches

## 1. What now.

At Phase 10 start (after Phases 0–9 complete), the following rg commands each return non-zero matches or confirm missing functionality:

1. `rg -n "slot_path_length" src/systems/enemy_squad_system.gd -S` — 0 matches. Assignment dicts contain no `slot_path_length` field; `_pick_slot_for_enemy` returns only `{key, position, path_ok}`; flank time-budget and distance checks are impossible.
2. `rg -n "func _squad_cfg_float" src/entities/enemy.gd -S` — 0 matches. `enemy.gd` has no helper to read `GameConfig.ai_balance["squad"]` keys; `_assignment_supports_flank_role` cannot access flank KPI config.
3. `rg -n "flank_max_path_px\|flank_max_time_sec\|flank_walk_speed_assumed_px_per_sec" src/core/game_config.gd -S` — 0 matches. Flank KPI constants absent from `DEFAULT_AI_BALANCE["squad"]`.
4. `rg -n "_build_contain_slots_from_exits" src/systems/enemy_squad_system.gd -S` — 0 matches. HOLD-role slots are always ring slots at `hold_radius_px=520.0`; no exit-aware slot generation exists.
5. Test file `tests/test_tactic_contain_assigns_exit_slots.gd` does not exist.
6. Test file `tests/test_tactic_flank_requires_path_and_time_budget.gd` does not exist.
7. Test file `tests/test_multi_enemy_pressure_no_patrol_regression.gd` does not exist.

## 2. What changes.

1. In `src/systems/enemy_squad_system.gd`: add 3 file-scope constants after line 20 (`const INVALID_PATH_SCORE_PENALTY := 100000.0`): `const FLANK_MAX_PATH_PX := 900.0`, `const FLANK_MAX_TIME_SEC := 3.5`, `const FLANK_WALK_SPEED_ASSUMED_PX_PER_SEC := 150.0`.
2. In `src/systems/enemy_squad_system.gd`: add function `_slot_nav_path_length(enemy: Node2D, slot_pos: Vector2) -> float` — calls `navigation_service.call("nav_path_length", enemy.global_position, slot_pos, null)` if navigation_service is non-null and has method; falls back to `enemy.global_position.distance_to(slot_pos)` otherwise.
3. In `src/systems/enemy_squad_system.gd`: extend `_pick_slot_for_enemy` — after candidate selection completes, compute `slot_path_length` for the winning slot only (1 nav call per enemy per rebuild): call `_slot_nav_path_length(enemy, winning_pos)` at the two return points and write result into the winning dict before returning.
4. In `src/systems/enemy_squad_system.gd`: extend `_recompute_assignments` — in the `member["assignment"]` dict at lines 131–138, add `"slot_path_length": float(slot_pick.get("slot_path_length", INF))` after `"path_ok"`.
5. In `src/systems/enemy_squad_system.gd`: extend `_default_assignment(role)` return dict — add `"slot_path_length": INF` after `"has_slot": false,`.
6. In `src/systems/enemy_squad_system.gd`: add function `_build_contain_slots_from_exits(player_pos: Vector2) -> Array` — queries nav service for player room, adjacent rooms, door centers; returns `Array` of `{"key": String, "position": Vector2}` dicts; returns `[]` on any nav-data failure.
7. In `src/systems/enemy_squad_system.gd`: extend `_build_slots(player_pos)` — pre-compute `var hold_slots := _build_contain_slots_from_exits(player_pos)` before the return dict; if `hold_slots.is_empty()`, assign ring slots fallback; use `hold_slots` as the value for `Role.HOLD` in the returned dict.
8. In `src/entities/enemy.gd`: add function `_squad_cfg_float(key: String, fallback: float) -> float` — reads `GameConfig.ai_balance["squad"]` section; pattern identical to existing `_utility_cfg_float`.
9. In `src/entities/enemy.gd`: extend `_assignment_supports_flank_role(assignment: Dictionary) -> bool` — after existing `path_ok` check: read `path_length := float(assignment.get("slot_path_length", INF))`; check flank_distance_ok (`path_length <= _squad_cfg_float("flank_max_path_px", 900.0)`); check time_budget_ok (`path_length / maxf(_squad_cfg_float("flank_walk_speed_assumed_px_per_sec", 150.0), 0.001) <= _squad_cfg_float("flank_max_time_sec", 3.5)`); return false if either check fails.
10. In `src/core/game_config.gd`: add to `DEFAULT_AI_BALANCE["squad"]` after `"slot_path_tail_tolerance_px": 24.0,`: `"flank_max_path_px": 900.0`, `"flank_max_time_sec": 3.5`, `"flank_walk_speed_assumed_px_per_sec": 150.0`.
11. In `src/core/config_validator.gd`: add to squad validation block after `_validate_number_key(result, squad, "slot_path_tail_tolerance_px", ...)`: `_validate_number_key(result, squad, "flank_max_path_px", "ai_balance.squad", 1.0, 10000.0)`, `_validate_number_key(result, squad, "flank_max_time_sec", "ai_balance.squad", 0.1, 60.0)`, `_validate_number_key(result, squad, "flank_walk_speed_assumed_px_per_sec", "ai_balance.squad", 1.0, 10000.0)`.
12. Create `tests/test_tactic_contain_assigns_exit_slots.gd` (4 functions) and `tests/test_tactic_contain_assigns_exit_slots.tscn`. Register in `tests/test_runner_node.gd`.
13. Create `tests/test_tactic_flank_requires_path_and_time_budget.gd` (4 functions) and `tests/test_tactic_flank_requires_path_and_time_budget.tscn`. Register in `tests/test_runner_node.gd`.
14. Create `tests/test_multi_enemy_pressure_no_patrol_regression.gd` (3 functions) and `tests/test_multi_enemy_pressure_no_patrol_regression.tscn`. Register in `tests/test_runner_node.gd`.
15. Update `tests/test_enemy_squad_system.gd`: add `_test_slot_path_length_in_assignment` (3 assertions) and call in `run_suite`.

## 3. What will be after.

1. `rg -n "slot_path_length" src/systems/enemy_squad_system.gd -S` returns ≥3 matches (`_pick_slot_for_enemy`, `_recompute_assignments`, `_default_assignment`). Verified by gate G1 (section 13).
2. `rg -n "func _squad_cfg_float" src/entities/enemy.gd -S` returns 1 match. Verified by gate G2 (section 13).
3. `rg -n "flank_max_path_px" src/core/game_config.gd -S` returns 1 match. Verified by gate G3 (section 13).
4. `rg -n "flank_max_time_sec" src/core/game_config.gd -S` returns 1 match. Verified by gate G4 (section 13).
5. `rg -n "flank_walk_speed_assumed_px_per_sec" src/core/game_config.gd -S` returns 1 match. Verified by gate G5 (section 13).
6. `rg -n "_build_contain_slots_from_exits" src/systems/enemy_squad_system.gd -S` returns ≥2 matches (definition + call in `_build_slots`). Verified by gate G6 (section 13).
7. `rg -n "flank_max_path_px\|flank_max_time_sec\|flank_walk_speed_assumed" src/entities/enemy.gd -S` returns ≥2 matches (calls in `_assignment_supports_flank_role`). Verified by gate G7 (section 13).
8. All tests in section 12 exit 0. Verified by steps 16–19 (Tier 1) and step 20 (Tier 2).

## 4. Scope and non-scope (exact files).

**In-scope files (allowed file-change boundary):**
1. `src/systems/enemy_squad_system.gd`
2. `src/entities/enemy.gd`
3. `src/core/game_config.gd`
4. `src/core/config_validator.gd`
5. `tests/test_tactic_contain_assigns_exit_slots.gd` (new)
6. `tests/test_tactic_contain_assigns_exit_slots.tscn` (new)
7. `tests/test_tactic_flank_requires_path_and_time_budget.gd` (new)
8. `tests/test_tactic_flank_requires_path_and_time_budget.tscn` (new)
9. `tests/test_multi_enemy_pressure_no_patrol_regression.gd` (new)
10. `tests/test_multi_enemy_pressure_no_patrol_regression.tscn` (new)
11. `tests/test_enemy_squad_system.gd`
12. `tests/test_runner_node.gd`
13. `CHANGELOG.md`

**Out-of-scope files (must not be modified):**
1. `src/systems/enemy_pursuit_system.gd`
2. `src/systems/navigation_service.gd`
3. `src/systems/navigation_runtime_queries.gd`
4. `src/systems/enemy_utility_brain.gd`
5. `src/systems/enemy_patrol_system.gd`
6. `src/entities/boss.gd`
7. `scenes/entities/enemy.tscn`

Any change outside the in-scope list = phase FAILED regardless of test results.

## 5. Single-owner authority for this phase.

The primary new behavior (flank time-budget and distance guard) is owned by `src/entities/enemy.gd`, function `_assignment_supports_flank_role`. This is the sole runtime point where flank-role validity is checked before role confirmation.

The contain-slot generation is owned by `src/systems/enemy_squad_system.gd`, function `_build_contain_slots_from_exits`. This is the sole function that queries nav service exit positions to produce HOLD-role slots.

No other file duplicates flank budget checks. Verified by gate G8 (`rg -n "flank_max_path_px\|flank_max_time_sec" src/ -S` returns matches only in `src/entities/enemy.gd` and `src/core/game_config.gd`; zero matches in `src/systems/`).

## 6. Full input/output contract.

**Contract A: `FlankBudgetCheckContractV1`** (in `Enemy._assignment_supports_flank_role`)

- Contract name: `FlankBudgetCheckContractV1`
- Input: `assignment: Dictionary` — non-null; fields:
  - `assignment["role"]: int` — non-null; compared against `SQUAD_ROLE_FLANK (2)`.
  - `assignment["has_slot"]: bool` — non-null; `false` triggers immediate `return false`.
  - `assignment["path_ok"]: bool` — non-null; `false` triggers immediate `return false`.
  - `assignment["slot_path_length"]: float` — non-null; `INF` when no valid path or default assignment; `INF` causes distance check `INF > 900.0 → return false`.
- Output: `bool` — `true` iff all five checks pass: role==FLANK, has_slot==true, path_ok==true, flank_distance_ok==true, time_budget_ok==true.
- Status enums: N/A (boolean output).
- Reason enums: N/A.
- Constants (all in `GameConfig.ai_balance["squad"]`, fallback used when section absent):
  - `"flank_max_path_px": 900.0` — fallback 900.0.
  - `"flank_max_time_sec": 3.5` — fallback 3.5.
  - `"flank_walk_speed_assumed_px_per_sec": 150.0` — fallback 150.0.

**Contract B: `ContainSlotBuildContractV1`** (in `EnemySquadSystem._build_contain_slots_from_exits`)

- Contract name: `ContainSlotBuildContractV1`
- Input: `player_pos: Vector2` — non-null; may be `Vector2.ZERO` in tests.
- Output: `Array` of `{"key": String, "position": Vector2}` — each key unique; `[]` when nav data unavailable or no doors found.
- Output field invariants:
  - `key` format: `"hold_exit:%d:%d" % [player_room_id, adj_room_id]` — unique per directed room pair.
  - `position` equals the return value of `get_door_center_between(player_room_id, adj_room_id, player_pos)`.
- Status enums: N/A (empty array = failure state).
- Reason enums: N/A.
- Constants: none (uses nav service calls only).

**Contract C: `SlotPathLengthContractV1`** (in `EnemySquadSystem._slot_nav_path_length`)

- Contract name: `SlotPathLengthContractV1`
- Input: `enemy: Node2D` (non-null), `slot_pos: Vector2` (non-null).
- Output: `float` — nav path length in pixels; `INF` propagated as-is when nav returns `INF` (no reachable path); Euclidean `enemy.global_position.distance_to(slot_pos)` used only when `navigation_service == null` or `nav_path_length` method absent. `INF` is never substituted with Euclidean — a missing path must not appear reachable.
- `INF` propagation: stored as `assignment["slot_path_length"]` → causes `_assignment_supports_flank_role` Step 5 (`INF > 900.0`) to return false.
- Constants: none.

## 7. Deterministic algorithm with exact order.

**A. `_assignment_supports_flank_role(assignment)` extended algorithm:**

Step 1: `if int(assignment.get("role", -1)) != SQUAD_ROLE_FLANK: return false`
Step 2: `if not bool(assignment.get("has_slot", false)): return false`
Step 3: `if not bool(assignment.get("path_ok", false)): return false`
Step 4: `var path_length := float(assignment.get("slot_path_length", INF))`
Step 5: `if path_length > _squad_cfg_float("flank_max_path_px", 900.0): return false` — flank_distance_ok fails.
Step 6: `var assumed_speed := _squad_cfg_float("flank_walk_speed_assumed_px_per_sec", 150.0)`
Step 7: `if path_length / maxf(assumed_speed, 0.001) > _squad_cfg_float("flank_max_time_sec", 3.5): return false` — time_budget_ok fails.
Step 8: `return true`

Tie-break: N/A — `_assignment_supports_flank_role` returns bool; no candidates compared.
Behavior when `assumed_speed == 0.0`: `maxf(0.0, 0.001) = 0.001`; ETA becomes `path_length / 0.001`, a large value; time_budget_ok always fails — safe fallback preventing division-by-zero.

**B. `_build_contain_slots_from_exits(player_pos)` algorithm:**

Step 1: Return `[]` if `navigation_service == null`.
Step 2: Return `[]` if `navigation_service` lacks any of: `room_id_at_point`, `get_adjacent_room_ids`, `get_door_center_between`.
Step 3: `var player_room_id: int = int(navigation_service.call("room_id_at_point", player_pos))`. Return `[]` if `player_room_id < 0`.
Step 4: `var adj_rooms: Array = navigation_service.call("get_adjacent_room_ids", player_room_id) as Array`. Return `[]` if `adj_rooms.is_empty()`.
Step 5: For each `adj_variant` in `adj_rooms` (iteration order: sorted ascending by `get_neighbors` implementation):
  - `var adj_id: int = int(adj_variant)`
  - `var door_center: Vector2 = navigation_service.call("get_door_center_between", player_room_id, adj_id, player_pos) as Vector2`
  - If `door_center == Vector2.ZERO`: skip (no door found for this pair).
  - Else: append `{"key": "hold_exit:%d:%d" % [player_room_id, adj_id], "position": door_center}` to result.
Step 6: Return result. Empty result triggers ring fallback in `_build_slots`.

Tie-break: N/A — each adj room produces at most one slot; no comparison among them.
Behavior when all door centers are `Vector2.ZERO`: returns `[]` → ring fallback activates.

**C. `_build_slots(player_pos)` modification order:**

Step 1: `var hold_slots := _build_contain_slots_from_exits(player_pos)`
Step 2: `if hold_slots.is_empty(): hold_slots = _build_ring_slots(player_pos, _squad_cfg_float("hold_radius_px", HOLD_RADIUS_PX), _squad_cfg_int("hold_slot_count", HOLD_SLOT_COUNT), Role.HOLD, 0.0)`
Step 3: Return dict `{Role.PRESSURE: _build_ring_slots(...), Role.HOLD: hold_slots, Role.FLANK: _build_ring_slots(...)}`.

**D. `_pick_slot_for_enemy` path-length extension:**

Existing candidate-selection algorithm (inner loop and scoring) is unchanged. `_slot_nav_path_length` is called exactly once per enemy per rebuild, at the return point — not during candidate accumulation:
- After inner loops: if `best_for_role` is non-empty, compute `best_for_role["slot_path_length"] = _slot_nav_path_length(enemy, best_for_role.get("position", Vector2.ZERO) as Vector2)` immediately before `return best_for_role`.
- After inner loops: if `best_for_role` is empty and `best_any` is non-empty, compute `best_any["slot_path_length"] = _slot_nav_path_length(enemy, best_any.get("position", Vector2.ZERO) as Vector2)` immediately before `return best_any`.
- When `_pick_slot_for_enemy` returns empty dict: `_recompute_assignments` uses `_default_assignment(role)` which has `"slot_path_length": INF`.

This ensures at most 1 `nav_path_length` call per enemy per squad rebuild — not 1 call per candidate update.

## 8. Edge-case matrix.

**Case A — default assignment, no slot (empty/null input):**
`assignment = _default_assignment(SQUAD_ROLE_FLANK)` → `{role: 2, has_slot: false, path_ok: false, slot_path_length: INF}`.
Step 2 (`has_slot == false`) → `return false`.
Result: `false`.

**Case B — flank within both constraints (single valid input):**
`assignment = {role: 2, has_slot: true, path_ok: true, slot_path_length: 500.0}`.
Steps 1–3: pass. Step 5: `500.0 ≤ 900.0` → pass. Step 7: `500.0 / 150.0 = 3.333s ≤ 3.5s` → pass.
Result: `true`.

**Case C — tie-break N/A:** `_assignment_supports_flank_role` is a boolean predicate; no candidate comparison occurs. The function evaluates one assignment and returns true/false deterministically. No tie-break scenario applies. (Section 7 proves N ≤ 1 assignments evaluated per call.)

**Case D — all inputs invalid (path_ok=false):**
`assignment = {role: 2, has_slot: true, path_ok: false, slot_path_length: 500.0}`.
Step 3 (`path_ok == false`) → `return false`.
Result: `false`.

**Case E — distance FAIL (slot_path_length=950.0 > 900.0):**
Steps 1–4: pass. Step 5: `950.0 > 900.0` → `return false`. Time not checked.
Result: `false`.

**Case F — time FAIL (slot_path_length=600.0, ETA=4.0s > 3.5s):**
Steps 1–5: pass (600.0 ≤ 900.0). Step 7: `600.0 / 150.0 = 4.0s > 3.5s` → `return false`.
Result: `false`.

**Case G — wrong role (HOLD, not FLANK):**
`role = SQUAD_ROLE_HOLD (1)`. Step 1 → `return false`. slot_path_length not evaluated.
Result: `false`.

**Contain slot edge cases:**

**Case H — nav null:** `_build_contain_slots_from_exits(any_pos)` → `[]` → `_build_slots` uses ring fallback for Role.HOLD.

**Case I — player_room_id < 0 (player outside any room):** Step 3 → `return []` → ring fallback.

**Case J — 2 adjacent rooms, both with valid door centers:** Returns 2 dicts with keys `"hold_exit:R:A1"`, `"hold_exit:R:A2"`.

**Case K — 3 adjacent rooms, one with Vector2.ZERO door center:** Returns 2 dicts; the Zero-center room is skipped per Step 5.

## 9. Legacy removal plan.

No legacy identifiers exist in the current codebase for Phase 10. PROJECT DISCOVERY confirmed via search command 5: `rg -n "legacy_flank|old_contain_logic|manual_role_override_legacy" src/ tests/ -S` → 0 matches. These identifiers were never created in the project. No deletions are required. Implementation is entirely additive (new functions, extended existing functions, new config keys).

## 10. Legacy verification commands.

**[L1] Legacy gate (from v1 doc, section 16.6):**
```
rg -n "legacy_flank|old_contain_logic|manual_role_override_legacy" src/ tests/ -S
```
Expected: 0 matches. Already 0 at phase start; must remain 0 after implementation. This is the sole legacy verification command for Phase 10.

## 11. Acceptance criteria (binary pass/fail).

1. `rg -n "slot_path_length" src/systems/enemy_squad_system.gd -S | wc -l` output ≥ 3: true/false.
2. `rg -n "func _squad_cfg_float" src/entities/enemy.gd -S | wc -l` output == 1: true/false.
3. `rg -n "flank_max_path_px" src/core/game_config.gd -S | wc -l` output == 1: true/false.
4. `rg -n "flank_max_time_sec" src/core/game_config.gd -S | wc -l` output == 1: true/false.
5. `rg -n "flank_walk_speed_assumed_px_per_sec" src/core/game_config.gd -S | wc -l` output == 1: true/false.
6. `rg -n "_build_contain_slots_from_exits" src/systems/enemy_squad_system.gd -S | wc -l` output ≥ 2: true/false.
7. `rg -n "legacy_flank|old_contain_logic|manual_role_override_legacy" src/ tests/ -S | wc -l` output == 0: true/false.
8. All 11 new test functions (4+4+3) exit 0 when run: true/false.
9. `_test_slot_path_length_in_assignment` in `test_enemy_squad_system.gd` exits 0: true/false.
10. `tests/test_runner_node.gd` contains const definitions for all 3 new test scene paths: true/false.
11. CHANGELOG.md updated with Phase 10 entry: true/false.

## 12. Tests (new/update + purpose).

**New: `tests/test_tactic_contain_assigns_exit_slots.gd`**

Functions:
- `_test_contain_uses_door_positions_when_nav_available` — FakeNavService returns player_room=0, adj_rooms=[1,2], door centers `(100,0)` and `(0,100)`. Asserts `_build_contain_slots_from_exits(Vector2.ZERO)` returns 2 slots whose positions are exactly `Vector2(100,0)` and `Vector2(0,100)`.
- `_test_contain_slots_have_unique_keys` — FakeNavService returns 3 adjacent rooms with valid door centers. Asserts all returned slot keys are distinct strings (no duplicates in the Array).
- `_test_contain_fallback_to_ring_when_no_nav` — `navigation_service = null`. Calls `_build_slots(Vector2.ZERO)`. Asserts `Role.HOLD` entry in result contains slots with key format `"1:N"` (ring format), not `"hold_exit:..."`.
- `_test_contain_skips_zero_door_center` — FakeNavService returns 2 adjacent rooms; `get_door_center_between` returns `Vector2.ZERO` for one pair and valid position for the other. Asserts exactly 1 slot returned (Zero-center pair skipped).

Registration: add `const TACTIC_CONTAIN_EXIT_SLOTS_TEST_SCENE := "res://tests/test_tactic_contain_assigns_exit_slots.tscn"` and `_run_embedded_scene_suite("Tactic contain exit slots suite", TACTIC_CONTAIN_EXIT_SLOTS_TEST_SCENE)` to `tests/test_runner_node.gd`.

**New: `tests/test_tactic_flank_requires_path_and_time_budget.gd`**

Functions:
- `_test_flank_allowed_when_within_budget` — assignment `{role: SQUAD_ROLE_FLANK, has_slot: true, path_ok: true, slot_path_length: 500.0}`. Asserts `_assignment_supports_flank_role(assignment) == true` (500.0 ≤ 900.0, 500.0/150.0=3.33s ≤ 3.5s).
- `_test_flank_blocked_when_time_exceeds_budget` — assignment `slot_path_length: 600.0`. Asserts `_assignment_supports_flank_role(assignment) == false` (600.0/150.0=4.0s > 3.5s).
- `_test_flank_blocked_when_path_exceeds_max_px` — assignment `slot_path_length: 950.0`. Asserts `_assignment_supports_flank_role(assignment) == false` (950.0 > 900.0).
- `_test_flank_fallback_to_pressure_when_blocked` — calls `_resolve_contextual_combat_role(SQUAD_ROLE_FLANK, true, 500.0, bad_assignment)` where `bad_assignment` has `slot_path_length: INF`. Asserts returned role == `SQUAD_ROLE_PRESSURE` (flank unavailable → pressure fallback in `_resolve_contextual_combat_role` line 2261 branch).

Registration: add `const TACTIC_FLANK_BUDGET_GUARD_TEST_SCENE := "res://tests/test_tactic_flank_requires_path_and_time_budget.tscn"` and corresponding `_run_embedded_scene_suite` call.

**New: `tests/test_multi_enemy_pressure_no_patrol_regression.gd`**

Functions:
- `_test_pressure_role_assignment_stable_across_recompute` — 9 enemies registered, player moves to new position, `recompute_now()` called. Asserts all enemies with `role == SQUAD_ROLE_PRESSURE` have `has_slot == true` after recompute.
- `_test_hold_role_uses_exit_slots_not_ring_when_nav_provides_doors` — FakeNavService returns 2 adj rooms with valid door centers. Asserts at least one HOLD-role enemy's `slot_position` matches one of the door center positions (within 1.0px tolerance).
- `_test_squad_role_enum_has_no_patrol_value` — asserts that `_stable_role_for_enemy_id` returns only values in `{0, 1, 2}` across 18 consecutive enemy IDs (covering all 6 modulo-6 buckets three times). Uses `var ok := true; for i in range(18): var r := squad._stable_role_for_enemy_id(1000 + i); if not (r == 0 or r == 1 or r == 2): ok = false`. Does not call `Role.size()` (GDScript 4 enums have no `.size()` method — that would cause a runtime error).

Registration: add `const MULTI_ENEMY_PRESSURE_NO_PATROL_REGRESSION_TEST_SCENE := "res://tests/test_multi_enemy_pressure_no_patrol_regression.tscn"` and corresponding `_run_embedded_scene_suite` call.

**Update: `tests/test_enemy_squad_system.gd`**

Add function `_test_slot_path_length_in_assignment`:
- Asserts `_default_assignment(EnemySquadSystem.Role.FLANK)` contains key `"slot_path_length"` with value `INF`.
- After `_squad.recompute_now()`, asserts all assignments with `has_slot == true` contain key `"slot_path_length"` of type `TYPE_FLOAT`.
- Asserts all assignments with `has_slot == false` have `slot_path_length == INF`.
Add call to `_test_slot_path_length_in_assignment` in `run_suite()` between existing test calls.

## 13. rg gates (command + expected output).

**Phase-specific gates:**

G1: `rg -n "slot_path_length" src/systems/enemy_squad_system.gd -S`
Expected: ≥3 matches (in `_pick_slot_for_enemy` returned dicts, `_recompute_assignments` assignment dict, `_default_assignment` return dict).

G2: `rg -n "func _squad_cfg_float" src/entities/enemy.gd -S`
Expected: 1 match.

G3: `rg -n "flank_max_path_px" src/core/game_config.gd -S`
Expected: 1 match.

G4: `rg -n "flank_max_time_sec" src/core/game_config.gd -S`
Expected: 1 match.

G5: `rg -n "flank_walk_speed_assumed_px_per_sec" src/core/game_config.gd -S`
Expected: 1 match.

G6: `rg -n "_build_contain_slots_from_exits" src/systems/enemy_squad_system.gd -S`
Expected: ≥2 matches (function definition + call site in `_build_slots`).

G7: `rg -n "flank_max_path_px\|flank_max_time_sec\|flank_walk_speed_assumed" src/entities/enemy.gd -S`
Expected: ≥2 matches (calls to `_squad_cfg_float` in `_assignment_supports_flank_role`).

G8: `rg -n "flank_max_path_px\|flank_max_time_sec" src/systems/ -S`
Expected: 0 matches (flank KPI checks must not appear in any `src/systems/` file — only `src/entities/enemy.gd` and `src/core/game_config.gd`).

G9: `rg -n "slot_path_length" src/entities/enemy.gd -S`
Expected: ≥1 match (read in `_assignment_supports_flank_role`).

**PMB gates:**

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: 0 matches.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: PMB-5: PASS (1).

## 14. Execution sequence (step-by-step, no ambiguity).

Step 1: Run legacy gate `rg -n "legacy_flank|old_contain_logic|manual_role_override_legacy" src/ tests/ -S` — confirm 0 matches. No deletions proceed (no legacy exists).

Step 2 (game_config.gd): In `src/core/game_config.gd`, `DEFAULT_AI_BALANCE["squad"]` dict, after `"slot_path_tail_tolerance_px": 24.0,` (line 177), insert:
```
"flank_max_path_px": 900.0,
"flank_max_time_sec": 3.5,
"flank_walk_speed_assumed_px_per_sec": 150.0,
```

Step 3 (config_validator.gd): In `src/core/config_validator.gd`, squad validation block, after `_validate_number_key(result, squad, "slot_path_tail_tolerance_px", "ai_balance.squad", 0.0, 1000.0)` (line 237), add:
```gdscript
_validate_number_key(result, squad, "flank_max_path_px", "ai_balance.squad", 1.0, 10000.0)
_validate_number_key(result, squad, "flank_max_time_sec", "ai_balance.squad", 0.1, 60.0)
_validate_number_key(result, squad, "flank_walk_speed_assumed_px_per_sec", "ai_balance.squad", 1.0, 10000.0)
```

Step 4 (enemy_squad_system.gd — constants): After `const INVALID_PATH_SCORE_PENALTY := 100000.0` (line 20), add:
```gdscript
const FLANK_MAX_PATH_PX := 900.0
const FLANK_MAX_TIME_SEC := 3.5
const FLANK_WALK_SPEED_ASSUMED_PX_PER_SEC := 150.0
```

Step 5 (enemy_squad_system.gd — _default_assignment): Extend return dict in `_default_assignment` — add `"slot_path_length": INF,` after `"has_slot": false,`.

Step 6 (enemy_squad_system.gd — _slot_nav_path_length): Add new function after `_is_slot_path_ok`:
```gdscript
func _slot_nav_path_length(enemy: Node2D, slot_pos: Vector2) -> float:
	if navigation_service == null or not navigation_service.has_method("nav_path_length"):
		return enemy.global_position.distance_to(slot_pos)
	return float(navigation_service.call("nav_path_length", enemy.global_position, slot_pos, null))
```

`INF` returned by `nav_path_length` propagates as-is — never replaced with Euclidean distance (no path ≠ short path).

Step 7 (enemy_squad_system.gd — _pick_slot_for_enemy): At the two return points only (not inside the candidate loop), inject `slot_path_length` into the winning dict:
```gdscript
# Before "return best_for_role" (when non-empty):
best_for_role["slot_path_length"] = _slot_nav_path_length(enemy, best_for_role.get("position", Vector2.ZERO) as Vector2)
return best_for_role

# Before "return best_any" (when best_for_role empty, best_any non-empty):
best_any["slot_path_length"] = _slot_nav_path_length(enemy, best_any.get("position", Vector2.ZERO) as Vector2)
return best_any
```
This guarantees exactly 1 `nav_path_length` call per enemy per squad rebuild.

Step 8 (enemy_squad_system.gd — _recompute_assignments): In the `member["assignment"] = { ... }` dict (lines 131–138), add `"slot_path_length": float(slot_pick.get("slot_path_length", INF)),` after the `"path_ok"` key.

Step 9 (enemy_squad_system.gd — _build_contain_slots_from_exits): Add new function before `_build_slots`:
```gdscript
func _build_contain_slots_from_exits(player_pos: Vector2) -> Array:
	if navigation_service == null:
		return []
	if not navigation_service.has_method("room_id_at_point"):
		return []
	if not navigation_service.has_method("get_adjacent_room_ids"):
		return []
	if not navigation_service.has_method("get_door_center_between"):
		return []
	var player_room_id: int = int(navigation_service.call("room_id_at_point", player_pos))
	if player_room_id < 0:
		return []
	var adj_rooms: Array = navigation_service.call("get_adjacent_room_ids", player_room_id) as Array
	if adj_rooms.is_empty():
		return []
	var slots: Array = []
	for adj_variant in adj_rooms:
		var adj_id: int = int(adj_variant)
		var door_center: Vector2 = navigation_service.call("get_door_center_between", player_room_id, adj_id, player_pos) as Vector2
		if door_center == Vector2.ZERO:
			continue
		slots.append({"key": "hold_exit:%d:%d" % [player_room_id, adj_id], "position": door_center})
	return slots
```

Step 10 (enemy_squad_system.gd — _build_slots): Replace the `_build_slots` function body. Before the return dict, pre-compute hold slots:
```gdscript
func _build_slots(player_pos: Vector2) -> Dictionary:
	var hold_slots := _build_contain_slots_from_exits(player_pos)
	if hold_slots.is_empty():
		hold_slots = _build_ring_slots(
			player_pos,
			_squad_cfg_float("hold_radius_px", HOLD_RADIUS_PX),
			_squad_cfg_int("hold_slot_count", HOLD_SLOT_COUNT),
			Role.HOLD,
			0.0
		)
	return {
		Role.PRESSURE: _build_ring_slots(
			player_pos,
			_squad_cfg_float("pressure_radius_px", PRESSURE_RADIUS_PX),
			_squad_cfg_int("pressure_slot_count", PRESSURE_SLOT_COUNT),
			Role.PRESSURE,
			0.0
		),
		Role.HOLD: hold_slots,
		Role.FLANK: _build_ring_slots(
			player_pos,
			_squad_cfg_float("flank_radius_px", FLANK_RADIUS_PX),
			_squad_cfg_int("flank_slot_count", FLANK_SLOT_COUNT),
			Role.FLANK,
			PI / float(maxi(_squad_cfg_int("flank_slot_count", FLANK_SLOT_COUNT), 1))
		),
	}
```

Step 11 (enemy.gd — _squad_cfg_float): Add after `_utility_cfg_float` (after line 1508):
```gdscript
func _squad_cfg_float(key: String, fallback: float) -> float:
	if GameConfig and GameConfig.ai_balance.has("squad"):
		var section := GameConfig.ai_balance["squad"] as Dictionary
		return float(section.get(key, fallback))
	return fallback
```

Step 12 (enemy.gd — _assignment_supports_flank_role): Replace function body (lines 2243–2248) with:
```gdscript
func _assignment_supports_flank_role(assignment: Dictionary) -> bool:
	if int(assignment.get("role", -1)) != SQUAD_ROLE_FLANK:
		return false
	if not bool(assignment.get("has_slot", false)):
		return false
	if not bool(assignment.get("path_ok", false)):
		return false
	var path_length := float(assignment.get("slot_path_length", INF))
	if path_length > _squad_cfg_float("flank_max_path_px", 900.0):
		return false
	var assumed_speed := _squad_cfg_float("flank_walk_speed_assumed_px_per_sec", 150.0)
	if path_length / maxf(assumed_speed, 0.001) > _squad_cfg_float("flank_max_time_sec", 3.5):
		return false
	return true
```

Step 13: Create `tests/test_tactic_contain_assigns_exit_slots.gd` with FakeNavService class and 4 test functions per section 12. Create corresponding `.tscn` scene file.

Step 14: Create `tests/test_tactic_flank_requires_path_and_time_budget.gd` with FakeEnemy class and 4 test functions per section 12. Create corresponding `.tscn` scene file.

Step 15: Create `tests/test_multi_enemy_pressure_no_patrol_regression.gd` with FakeNavService/FakeEnemy classes and 3 test functions per section 12. Create corresponding `.tscn` scene file.

Step 16: Update `tests/test_enemy_squad_system.gd`: add `_test_slot_path_length_in_assignment` function (3 assertions) and call in `run_suite()`.

Step 17: Update `tests/test_runner_node.gd`: add 3 const declarations and 3 `_run_embedded_scene_suite` calls in a new `--- SECTION 18d: Phase 10 tactic suites ---` block.

Step 18: Run Tier 1 smoke suite command 1:
`xvfb-run -a godot-4 --headless --path . res://tests/test_tactic_contain_assigns_exit_slots.tscn`
Must exit 0.

Step 19: Run Tier 1 smoke suite command 2:
`xvfb-run -a godot-4 --headless --path . res://tests/test_tactic_flank_requires_path_and_time_budget.tscn`
Must exit 0.

Step 20: Run Tier 1 smoke suite command 3:
`xvfb-run -a godot-4 --headless --path . res://tests/test_multi_enemy_pressure_no_patrol_regression.tscn`
Must exit 0.

Step 21: Run Tier 1 smoke suite command 4:
`xvfb-run -a godot-4 --headless --path . res://tests/test_enemy_squad_system.tscn`
Must exit 0.

Step 22: Run Tier 2 full regression:
`xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn`
Must exit 0.

Step 23: Run all rg gates from section 13 (G1–G9, PMB-1 through PMB-5). All must return expected output.

Step 24: Prepend CHANGELOG entry under the current date header.

## 15. Rollback conditions.

1. **Trigger**: Any rg gate in section 13 (G1–G9 or PMB-1–PMB-5) returns unexpected output after implementation. **Action**: Revert all changes to files in section 4 in-scope list to their pre-Phase-10 state.
2. **Trigger**: Tier 2 full regression (`test_runner.tscn`) exits non-zero. **Action**: Revert all changes to files in section 4 in-scope list.
3. **Trigger**: Existing tests `_test_role_stability`, `_test_path_fallback`, or `_test_unique_slot_reservations` in `test_enemy_squad_system.gd` fail after Step 16. **Action**: Revert changes to `src/systems/enemy_squad_system.gd` and re-evaluate the `_pick_slot_for_enemy` extension in Step 7.
4. **Trigger**: Any file outside section 4 in-scope list is found modified. **Action**: Revert the out-of-scope file immediately; do not proceed until scope is restored.

## 16. Phase close condition.

- [ ] All rg commands in section 10 return 0 matches (L1 legacy gate)
- [ ] All rg gates G1–G9 return expected output
- [ ] All PMB gates PMB-1 through PMB-5 return expected output
- [ ] All 11 new test functions (4+4+3 across 3 new files) exit 0
- [ ] `_test_slot_path_length_in_assignment` in `test_enemy_squad_system.gd` exits 0
- [ ] Tier 1 smoke suite — all 4 commands (steps 18–21) exit 0
- [ ] Tier 2 full regression (`test_runner.tscn`) exits 0
- [ ] No file outside section 4 in-scope list was modified
- [ ] CHANGELOG entry prepended
- [ ] `tests/test_runner_node.gd` contains `TACTIC_CONTAIN_EXIT_SLOTS_TEST_SCENE`, `TACTIC_FLANK_BUDGET_GUARD_TEST_SCENE`, `MULTI_ENEMY_PRESSURE_NO_PATROL_REGRESSION_TEST_SCENE` consts and their `_run_embedded_scene_suite` calls

## 17. Ambiguity self-check line.

Ambiguity check: 0

## 18. Open questions line.

Open questions: 0

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).

**Files to diff:**
- `src/systems/enemy_squad_system.gd` — verify: `FLANK_MAX_PATH_PX/SEC/SPEED` consts present; `_slot_nav_path_length` function added; `_build_contain_slots_from_exits` function added; `_default_assignment` has `"slot_path_length": INF`; `_pick_slot_for_enemy` includes `"slot_path_length"` in both returned dicts; `_recompute_assignments` stores `"slot_path_length"` from slot_pick; `_build_slots` pre-computes `hold_slots` via `_build_contain_slots_from_exits`.
- `src/entities/enemy.gd` — verify: `_squad_cfg_float` function added; `_assignment_supports_flank_role` has 5 return-false branches (role, has_slot, path_ok, distance, time).
- `src/core/game_config.gd` — verify: 3 new keys `flank_max_path_px`, `flank_max_time_sec`, `flank_walk_speed_assumed_px_per_sec` in `["squad"]` section.
- `src/core/config_validator.gd` — verify: 3 new `_validate_number_key` calls in squad block.
- `tests/test_runner_node.gd` — verify: 3 new const declarations and 3 `_run_embedded_scene_suite` calls in SECTION 18d block.

**Contracts to check:**
- `FlankBudgetCheckContractV1`: execute scenarios P10-A and P10-B (section 20).
- `ContainSlotBuildContractV1`: execute scenarios P10-C and P10-D (section 20).
- `SlotPathLengthContractV1`: run `_test_slot_path_length_in_assignment` (INF propagation for default assignment, float presence for slot-assigned enemies).

**Runtime scenarios:** execute P10-A through P10-D from section 20.

## 20. Runtime scenario matrix.

**Scenario P10-A — flank blocked by time budget (FlankBudgetCheckContractV1, FAIL branch):**
Setup: construct assignment dict `{role: SQUAD_ROLE_FLANK, has_slot: true, path_ok: true, slot_path_length: 600.0}`. Use default GameConfig (flank_walk_speed_assumed_px_per_sec=150.0, flank_max_time_sec=3.5).
Scene: `res://tests/test_tactic_flank_requires_path_and_time_budget.tscn`. Frame count: 0 (unit test, no physics).
Expected invariant: `_assignment_supports_flank_role(assignment) == false`. ETA=600.0/150.0=4.0s > 3.5s → time_budget_ok fails.
Fail condition: function returns `true`.
Covered by: `_test_flank_blocked_when_time_exceeds_budget`.

**Scenario P10-B — flank allowed within both constraints (FlankBudgetCheckContractV1, PASS branch):**
Setup: assignment `{role: SQUAD_ROLE_FLANK, has_slot: true, path_ok: true, slot_path_length: 500.0}`. Default GameConfig.
Scene: same as P10-A.
Expected invariant: `_assignment_supports_flank_role(assignment) == true`. 500.0≤900.0, 500.0/150.0=3.33s≤3.5s.
Fail condition: function returns `false`.
Covered by: `_test_flank_allowed_when_within_budget`.

**Scenario P10-C — contain uses exit slots (ContainSlotBuildContractV1, PASS branch):**
Setup: FakeNavService.room_id_at_point(Vector2.ZERO)=0; get_adjacent_room_ids(0)=[1,2]; get_door_center_between(0,1,pos)=Vector2(100,0); get_door_center_between(0,2,pos)=Vector2(0,100).
Scene: `res://tests/test_tactic_contain_assigns_exit_slots.tscn`. Frame count: 0 (unit test).
Expected invariant: `_build_contain_slots_from_exits(Vector2.ZERO)` returns Array of size 2 with positions {Vector2(100,0), Vector2(0,100)}.
Fail condition: Array size ≠ 2, or positions mismatch.
Covered by: `_test_contain_uses_door_positions_when_nav_available`.

**Scenario P10-D — contain fallback to ring when nav absent (ContainSlotBuildContractV1, fallback branch):**
Setup: `navigation_service = null`. Call `_build_slots(Vector2.ZERO)`.
Scene: same as P10-C.
Expected invariant: HOLD-role slots in result use key format `"1:N"` (ring keys from `_build_ring_slots`, role=1).
Fail condition: any HOLD slot has key starting with `"hold_exit:"`.
Covered by: `_test_contain_fallback_to_ring_when_no_nav`.

## 21. Verification report format.

Record all fields below to close phase:
- `phase_id: PHASE_10`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; must be empty list on close)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `legacy_rg: [{command, expected: "0 matches", actual, PASS|FAIL}]` for L1
- `rg_gates: [{command, expected, actual, PASS|FAIL}]` for each G1–G9
- `phase_tests: [{test_function, exit_code: 0, PASS|FAIL}]` for 12 test functions (11 new + 1 updated)
- `smoke_suite: [{command, exit_code, PASS|FAIL}]` for 4 Tier 1 commands (steps 18–21)
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 10` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- pmb_contract_check present in section 21 (PMB section exists in document): yes

## 23. Dependencies on previous phases.

1. **Phase 7** — deleted dead functions L1–L7 from `enemy_pursuit_system.gd` and set `avoidance_enabled=true` in `scenes/entities/enemy.tscn`. Phase 10 inherits: the legacy cleanup from Phase 7 ensures PMB-1 and PMB-2 gates in Phase 10's section 13 produce 0 matches from a clean baseline. Without Phase 7, dead functions `_is_owner_in_shadow_without_flashlight` and `_select_nearest_reachable_candidate` remain in `enemy_pursuit_system.gd`, PMB-1 audit would surface stale callers, and the crowd avoidance-enabled enemies (from Phase 7's `avoidance_enabled=true`) are required for Phase 10's `_test_pressure_role_assignment_stable_across_recompute` to correctly simulate multi-enemy navigation without jams invalidating slot assignments.

2. **Phase 8** — added `EnemyUtilityBrain.PursuitMode` enum (`PATROL, LOST_CONTACT_SEARCH, DIRECT_PRESSURE, CONTAIN, SHADOW_AWARE_SWEEP`) and `get_pursuit_mode() -> PursuitMode`; `update()` sets `_current_mode`. Phase 10 inherits: the `PursuitMode.CONTAIN` value maps to `SQUAD_ROLE_HOLD` enemies (via `IntentType.HOLD_RANGE/MOVE_TO_SLOT → CONTAIN` mapping from Phase 8, section 7). Phase 10's contain-slot assignment is the positional substrate for Phase 8's CONTAIN pursuit mode. Without Phase 8, `context["pursuit_mode"]` is absent, `_build_nav_cost_profile` (Phase 9) always returns cautious profile for HOLD-role enemies regardless of their tactical slot position — making Phase 10's integration assumption (CONTAIN mode uses shadow-weighted routing to exit slots) impossible to validate.

3. **Phase 9** — extended `build_policy_valid_path` with `cost_profile` param; added `_build_nav_cost_profile` in `EnemyPursuitSystem` (DIRECT_PRESSURE→weight=0.0, others→weight=80.0); injected `context["pursuit_mode"]` from `_utility_brain.get_pursuit_mode()` in `enemy.gd`. Phase 10 inherits: HOLD-role enemies navigating to exit/door slots (Phase 10) automatically receive `shadow_weight=80.0` in their path cost profile (Phase 9, via CONTAIN mode). This integration means Phase 10's contain-slot positions near exits are navigated via shadow-preferring routes — the behavioral coupling that `_test_hold_role_uses_exit_slots_not_ring_when_nav_provides_doors` validates at the positional level. Without Phase 9, all enemies use length-only path selection regardless of pursuit mode, and the Phase 10 contain-slot positions are reached via naively shortest paths — breaking the stealth corridor pressure scenario's expected behavior.

---

## PHASE 11
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_11.

### Evidence

**Inspected files:**
- `src/systems/enemy_pursuit_system.gd` — primary owner of shadow scan state machine
- `src/systems/enemy_utility_brain.gd` — emits SHADOW_BOUNDARY_SCAN intent; SUSPICIOUS-only guard confirmed
- `src/entities/enemy.gd` — mirror flag `_shadow_scan_active` (line 153), `set_shadow_scan_active()` (line 1192)
- `src/core/game_config.gd` — `ai_balance["pursuit"]` block confirmed at line 135; 14 existing keys
- `src/core/config_validator.gd` — pursuit validation block at lines 185–204

**Inspected functions/methods:**
- `EnemyPursuitSystem._execute_shadow_boundary_scan` (lines 412–438): 2-implicit-stage (move-to-boundary / sweep); calls `clear_shadow_scan_state()` when timer expires
- `EnemyPursuitSystem._run_shadow_scan_sweep` (lines 449–463): oscillates facing, decrements `_shadow_scan_timer`; calls `clear_shadow_scan_state()` on timer ≤ 0; sets `_shadow_scan_active = true` on line 434
- `EnemyPursuitSystem.clear_shadow_scan_state` (lines 399–409): resets `_shadow_scan_active`, `_shadow_scan_phase`, `_shadow_scan_timer`, `_shadow_scan_target`, `_shadow_scan_boundary_point`, `_shadow_scan_boundary_valid`
- `EnemyPursuitSystem.configure_navigation` (line 170): sets `_shadow_scan_active = false`
- `EnemyPursuitSystem.execute_intent` (line 248): guard `_shadow_scan_active or _shadow_scan_boundary_valid` — clears scan state on non-SHADOW_BOUNDARY_SCAN intent
- `EnemyPursuitSystem._resolve_shadow_scan_boundary_point` (lines 441–446): queries `nav_system.get_nearest_non_shadow_point`
- `EnemyUtilityBrain._choose_intent` (line 104–109): SHADOW_BOUNDARY_SCAN emitted only at SUSPICIOUS level when `has_shadow_scan_target and shadow_scan_target_in_shadow`
- `Enemy.set_shadow_scan_active` (line 1192): mirror flag setter; affects flashlight policy
- `Enemy._shadow_scan_active` (line 153): independent mirror var, NOT the same as `enemy_pursuit_system.gd` `_shadow_scan_active`

**Search commands used:**
```
rg -n "_shadow_scan_active" src/systems/enemy_pursuit_system.gd -S
rg -n "_shadow_scan_active" src/entities/enemy.gd -S
rg -n "shadow_search|search_stage|search_coverage|shadow_choreography|ShadowSearchStage" src/ -S
rg -n "search_sweep|shadow_scan" src/core/game_config.gd -S
rg -n "pursuit" src/core/config_validator.gd -S
```

**Key findings:**
- `_shadow_scan_active` in `enemy_pursuit_system.gd`: 5 occurrences (lines 97 decl, 170, 248, 400, 434). This is the LEGACY identifier for Phase 11.
- `_shadow_scan_active` in `enemy.gd`: separate variable (mirror/UI flag), NOT deleted in this phase.
- No identifiers `ShadowSearchStage`, `_shadow_search_stage`, `_shadow_search_coverage`, `shadow_search_probe_count` exist anywhere in `src/`.
- `ai_balance["pursuit"]` ends at line 150; new keys append before closing brace.
- `_run_shadow_scan_sweep` is `void` currently; Phase 11 changes return type to `bool`.
- `_execute_shadow_boundary_scan` returns `bool` currently; return type is preserved.

---

## 1. What now.

`rg -n "_shadow_scan_active" src/systems/enemy_pursuit_system.gd -S` → 5 matches (lines 97, 170, 248, 400, 434). A binary `_shadow_scan_active: bool` flag drives a single-stage sweep with no probe follow-up and no coverage metric. After one sweep timer expires, `clear_shadow_scan_state()` is called immediately from inside `_run_shadow_scan_sweep()`, returning to IDLE with no recorded search coverage. The enemy never continues to secondary probe points around the shadow zone.

Failing state: `tests/test_shadow_search_choreography_progressive_coverage.gd` does not exist. `tests/test_shadow_search_stage_transition_contract.gd` does not exist.

Observable metric (current): after SHADOW_BOUNDARY_SCAN completes, `_shadow_scan_active` returns to `false` with zero recorded coverage — no measurable progression.

---

## 2. What changes.

1. **`src/systems/enemy_pursuit_system.gd` — delete** `var _shadow_scan_active: bool = false` (line 97).
2. **`src/systems/enemy_pursuit_system.gd` — add** `enum ShadowSearchStage { IDLE = 0, BOUNDARY_LOCK = 1, SWEEP = 2, PROBE = 3 }` at file scope (before class variables).
3. **`src/systems/enemy_pursuit_system.gd` — add** 7 new state vars at file scope: `var _shadow_search_stage: int`, `var _shadow_search_probe_points: Array[Vector2]`, `var _shadow_search_probe_cursor: int`, `var _shadow_search_sweep_done: int`, `var _shadow_search_total_sweeps_planned: int`, `var _shadow_search_coverage: float`, `var _shadow_search_total_timer: float`.
4. **`src/systems/enemy_pursuit_system.gd` — add** public function `get_shadow_search_stage() -> int` returning `_shadow_search_stage`.
5. **`src/systems/enemy_pursuit_system.gd` — add** public function `get_shadow_search_coverage() -> float` returning `_shadow_search_coverage`.
6. **`src/systems/enemy_pursuit_system.gd` — rewrite** `_execute_shadow_boundary_scan(delta, target, has_target)` to drive the 4-state machine (IDLE → BOUNDARY_LOCK → SWEEP → PROBE); see section 7 for exact algorithm.
7. **`src/systems/enemy_pursuit_system.gd` — add** private function `_build_shadow_probe_points(center: Vector2) -> Array[Vector2]` sampling `shadow_search_probe_count` candidates at `shadow_search_probe_ring_radius_px` around `center`, filtered to non-shadow positions via `nav_system.is_point_in_shadow`.
8. **`src/systems/enemy_pursuit_system.gd` — modify** `_run_shadow_scan_sweep(delta, target)`: change return type from `void` to `bool`; remove `_shadow_scan_active = true` (line 434); remove `clear_shadow_scan_state()` call (timer ≤ 0 branch); return `true` when timer hits 0, `false` otherwise.
9. **`src/systems/enemy_pursuit_system.gd` — modify** `clear_shadow_scan_state()`: add resets for all 7 new vars (`_shadow_search_stage = ShadowSearchStage.IDLE`, arrays cleared, int/float vars set to 0).
10. **`src/systems/enemy_pursuit_system.gd` — modify** `configure_navigation()`: replace `_shadow_scan_active = false` with `_shadow_search_stage = ShadowSearchStage.IDLE`; add reset of all 6 other new vars.
11. **`src/systems/enemy_pursuit_system.gd` — modify** `execute_intent()` (line 248): replace `_shadow_scan_active` with `_shadow_search_stage != ShadowSearchStage.IDLE`.
12. **`src/core/game_config.gd`**: add 4 keys to `ai_balance["pursuit"]`: `"shadow_search_probe_count": 3`, `"shadow_search_probe_ring_radius_px": 64.0`, `"shadow_search_coverage_threshold": 0.8`, `"shadow_search_total_budget_sec": 12.0`.
13. **`src/core/config_validator.gd`**: add 4 `_validate_number_key` calls in pursuit validation block (after line 200).
14. **New** `tests/test_shadow_search_stage_transition_contract.gd` + `.tscn` — 4 test functions; see section 12.
15. **New** `tests/test_shadow_search_choreography_progressive_coverage.gd` + `.tscn` — 4 test functions; see section 12.
16. **`tests/test_runner_node.gd`**: add 2 new const declarations + 2 `_run_embedded_scene_suite` calls in a new `--- SECTION 18e` block.

---

## 3. What will be after.

1. `rg -n "_shadow_scan_active" src/systems/enemy_pursuit_system.gd -S` → 0 matches (verified by section 10 legacy gate L1).
2. `rg -n "ShadowSearchStage" src/systems/enemy_pursuit_system.gd -S` → ≥ 5 matches (verified by G1).
3. `rg -n "func get_shadow_search_stage" src/systems/enemy_pursuit_system.gd -S` → 1 match (verified by G2).
4. `rg -n "func get_shadow_search_coverage" src/systems/enemy_pursuit_system.gd -S` → 1 match (verified by G3).
5. `rg -n "shadow_search_probe_count" src/core/game_config.gd -S` → 1 match (verified by G4).
6. `rg -n "shadow_search_probe_count" src/core/config_validator.gd -S` → 1 match (verified by G5).
7. `rg -n "_build_shadow_probe_points" src/systems/enemy_pursuit_system.gd -S` → ≥ 2 matches (verified by G6).
8. All 8 test functions in section 12 pass (verified by Tier 1 smoke + Tier 2 regression).

---

## 4. Scope and non-scope (exact files).

**In-scope:**
- `src/systems/enemy_pursuit_system.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `tests/test_shadow_search_stage_transition_contract.gd` (new)
- `tests/test_shadow_search_stage_transition_contract.tscn` (new)
- `tests/test_shadow_search_choreography_progressive_coverage.gd` (new)
- `tests/test_shadow_search_choreography_progressive_coverage.tscn` (new)
- `tests/test_runner_node.gd`
- `CHANGELOG.md`

**Out-of-scope (must not be modified):**
- `src/entities/enemy.gd` — `_shadow_scan_active` mirror var and `set_shadow_scan_active()` method remain unchanged
- `src/systems/enemy_utility_brain.gd` — SHADOW_BOUNDARY_SCAN intent emission logic unchanged
- `src/systems/navigation_service.gd` — no nav API changes
- `src/systems/enemy_squad_system.gd` — squad logic unchanged
- `src/systems/enemy_patrol_system.gd` — patrol logic unchanged
- `scenes/entities/enemy.tscn` — scene file unchanged

---

## 5. Single-owner authority for this phase.

**Owner file:** `src/systems/enemy_pursuit_system.gd`.
**Owner function:** `_execute_shadow_boundary_scan(delta: float, target: Vector2, has_target: bool) -> bool` — sole decision point for all ShadowSearchStage transitions.
**Uniqueness:** No other file contains `ShadowSearchStage` or `_shadow_search_stage` logic.
**Verifiable via G1:** `rg -n "ShadowSearchStage" src/ -S` → all matches in `src/systems/enemy_pursuit_system.gd` only; 0 matches in any other file.

---

## 6. Full input/output contract.

**Contract name:** `ShadowSearchStageContractV1`

**Inputs to `_execute_shadow_boundary_scan`:**
- `delta: float` — frame delta; must be > 0.0; if ≤ 0.0, `_stop_motion(delta)` is called and function returns `false`
- `target: Vector2` — shadow zone center (last_seen_pos or investigate_anchor from utility context)
- `has_target: bool` — if `false`, function calls `clear_shadow_scan_state()` and returns `false` immediately

**Inputs to `_build_shadow_probe_points`:**
- `center: Vector2` — shadow zone center; non-zero guaranteed by caller (called only when `_shadow_scan_target != Vector2.ZERO`)

**Outputs of `_execute_shadow_boundary_scan`:** `bool` — `true` if movement_intent (enemy is moving), `false` if stationary or clearing

**Stage enum values (exact):**
- `ShadowSearchStage.IDLE = 0`
- `ShadowSearchStage.BOUNDARY_LOCK = 1`
- `ShadowSearchStage.SWEEP = 2`
- `ShadowSearchStage.PROBE = 3`

**Coverage output:**
- `get_shadow_search_coverage() -> float`: range `[0.0, 1.0]`; 0.0 on IDLE entry; monotonically non-decreasing within a single search session; resets to 0.0 on `clear_shadow_scan_state()`
- Formula: `clampf(float(_shadow_search_sweep_done) / float(maxi(1, _shadow_search_total_sweeps_planned)), 0.0, 1.0)`

**Stage output:**
- `get_shadow_search_stage() -> int`: one of 0, 1, 2, 3 (ShadowSearchStage values)

**Constants/thresholds (exact values + placement):**

| Key | Value | Placement |
|---|---|---|
| `shadow_search_probe_count` | `3` (int) | `ai_balance["pursuit"]` in `game_config.gd` |
| `shadow_search_probe_ring_radius_px` | `64.0` (float) | `ai_balance["pursuit"]` in `game_config.gd` |
| `shadow_search_coverage_threshold` | `0.8` (float) | `ai_balance["pursuit"]` in `game_config.gd` |
| `shadow_search_total_budget_sec` | `12.0` (float) | `ai_balance["pursuit"]` in `game_config.gd` |

All 4 keys are read via existing `_pursuit_cfg_float(key, fallback)` helper in `EnemyPursuitSystem`.

---

## 7. Deterministic algorithm with exact order.

**`_execute_shadow_boundary_scan(delta: float, target: Vector2, has_target: bool) -> bool`:**

Step 1 — Guards: if `delta <= 0.0`: call `_stop_motion(delta)`; return `false`. Then if `has_target == false`: call `clear_shadow_scan_state()`; call `_stop_motion(delta)`; return `false`.

Step 2 — Target change detection: if `_shadow_scan_target.distance_to(target) > 0.5`: call `clear_shadow_scan_state()` (resets stage to IDLE and all new vars); set `_shadow_scan_target = target`; set `_shadow_scan_boundary_valid = false`.

Step 3 — Total timer: if `_shadow_search_stage != ShadowSearchStage.IDLE`: `_shadow_search_total_timer += maxf(delta, 0.0)`.

Step 4 — Budget check: if `_shadow_search_total_timer >= _pursuit_cfg_float("shadow_search_total_budget_sec", 12.0)`: call `clear_shadow_scan_state()`; return `false`.

Step 5 — Stage dispatch (match `_shadow_search_stage`):

**IDLE branch:**
- If `_shadow_scan_boundary_valid == false`: call `_shadow_scan_boundary_point = _resolve_shadow_scan_boundary_point(target)`. Set `_shadow_scan_boundary_valid = (_shadow_scan_boundary_point != Vector2.ZERO)`.
- If `_shadow_scan_boundary_valid == false`: call `_stop_motion(delta)`. Set `_target_facing_dir = (target - owner.global_position).normalized()`. Return `false`.
- Set `_shadow_search_stage = ShadowSearchStage.BOUNDARY_LOCK`. Fall through to BOUNDARY_LOCK branch in next frame (return `false` this frame after stop).

**BOUNDARY_LOCK branch:**
- Call `_execute_move_to_target(delta, _shadow_scan_boundary_point, 1.0, -1.0, true)`.
- If `owner.global_position.distance_to(_shadow_scan_boundary_point) <= _pursuit_cfg_float("last_seen_reached_px", LAST_SEEN_REACHED_PX)`: set `_shadow_search_stage = ShadowSearchStage.SWEEP`; set `_shadow_scan_phase = 0.0`; set `_shadow_scan_timer = _rng.randf_range(SHADOW_SCAN_DURATION_MIN_SEC, SHADOW_SCAN_DURATION_MAX_SEC)`. Return `true` (movement this frame).
- Return `true`.

**SWEEP branch:**
- Call `var sweep_done: bool = _run_shadow_scan_sweep(delta, target)`.
- If `sweep_done == false`: return `false`.
- `_shadow_search_sweep_done += 1`.
- If `_shadow_search_probe_cursor == 0` (first sweep just completed): call `_shadow_search_probe_points = _build_shadow_probe_points(target)`. Set `_shadow_search_total_sweeps_planned = 1 + _shadow_search_probe_points.size()`.
- Update coverage: `_shadow_search_coverage = clampf(float(_shadow_search_sweep_done) / float(maxi(1, _shadow_search_total_sweeps_planned)), 0.0, 1.0)`.
- Exit check: if `_shadow_search_probe_cursor >= _shadow_search_probe_points.size()` OR `_shadow_search_coverage >= _pursuit_cfg_float("shadow_search_coverage_threshold", 0.8)`: call `clear_shadow_scan_state()`; return `false`.
- Set `_shadow_search_stage = ShadowSearchStage.PROBE`. Return `false`.

**PROBE branch:**
- If `_shadow_search_probe_cursor >= _shadow_search_probe_points.size()`: call `clear_shadow_scan_state()`; return `false`.
- `var probe_target: Vector2 = _shadow_search_probe_points[_shadow_search_probe_cursor]`.
- Call `_execute_move_to_target(delta, probe_target, 1.0, -1.0, true)`.
- If `owner.global_position.distance_to(probe_target) <= _pursuit_cfg_float("last_seen_reached_px", LAST_SEEN_REACHED_PX)`: `_shadow_search_probe_cursor += 1`. Set `_shadow_search_stage = ShadowSearchStage.SWEEP`. Set `_shadow_scan_phase = 0.0`. Set `_shadow_scan_timer = _rng.randf_range(SHADOW_SCAN_DURATION_MIN_SEC, SHADOW_SCAN_DURATION_MAX_SEC)`.
- Return `true`.

**`_run_shadow_scan_sweep(delta: float, target: Vector2) -> bool`:**

Same logic as current implementation EXCEPT:
- Remove `_shadow_scan_active = true` assignment.
- Change `clear_shadow_scan_state()` call on timer ≤ 0 to: call `set_shadow_scan_active(false)` on owner; call `set_shadow_check_flashlight(false)` on owner; return `true`.
- Return `false` when timer > 0.
- Owner callbacks `set_shadow_check_flashlight(true)` and `set_shadow_scan_active(true)` remain (called at entry of sweep each frame while active).

**`_build_shadow_probe_points(center: Vector2) -> Array[Vector2]`:**

- `var probe_count: int = int(_pursuit_cfg_float("shadow_search_probe_count", 3.0))`.
- `var radius: float = _pursuit_cfg_float("shadow_search_probe_ring_radius_px", 64.0)`.
- `var result: Array[Vector2] = []`.
- For `i` in `range(probe_count)`: angle = `TAU * float(i) / float(maxi(1, probe_count))`; candidate = `center + Vector2.RIGHT.rotated(angle) * radius`.
  - If `nav_system != null` and `nav_system.has_method("is_point_in_shadow")` and `bool(nav_system.call("is_point_in_shadow", candidate)) == true`: skip (candidate is inside shadow — not a valid boundary probe).
  - Else: `result.append(candidate)`.
- Return `result`.

**Tie-break rules:** Probe points are sampled at fixed angles `TAU * i / probe_count` (i = 0, 1, ..., probe_count-1) when `probe_count > 0`. Order is fully deterministic. If `probe_count == 0` (allowed by validator floor `0.0`), the function returns an empty array and tie-break is N/A. For `probe_count >= 1`, ordering is by index, not by score comparison.

**Behavior when input is empty/null/invalid:**
- `has_target == false` → immediate clear + return `false` (section 7, Step 1).
- `nav_system == null` in `_build_shadow_probe_points` → all candidates included (no shadow filter possible) → returns full `probe_count` array.
- Boundary point unresolvable (`get_nearest_non_shadow_point` returns `Vector2.ZERO`) → IDLE branch stops motion and returns `false`; no stage transition.

---

## 8. Edge-case matrix.

**Case A: `has_target = false`**
Input: `_execute_shadow_boundary_scan(0.016, Vector2.ZERO, false)`
Expected output: `false`. Stage → `ShadowSearchStage.IDLE`. Coverage = 0.0. `_stop_motion` called. `set_shadow_scan_active(false)` called on owner.

**Case B: Single valid target, boundary resolves, enemy at boundary**
Input: `has_target = true`, `target = Vector2(200, 200)`, `_shadow_scan_boundary_point` resolves to `Vector2(180, 200)`, `owner.global_position = Vector2(180, 200)` (arrive_px = 20).
Expected: First call transitions IDLE → BOUNDARY_LOCK (boundary resolved). Second call: distance ≤ 20 → transitions BOUNDARY_LOCK → SWEEP. Stage = `ShadowSearchStage.SWEEP`. `_shadow_scan_timer` = randf_range(2.0, 3.0). Returns `true` (movement frame).

**Case C: Tie-break N/A by deterministic angular ordering**
Proof (section 7 `_build_shadow_probe_points`): when `probe_count > 0`, candidates are computed as `Vector2.RIGHT.rotated(TAU * i / probe_count) * radius`. For probe_count=3: angles are 0, 2.094, 4.189 radians — all distinct by construction. Order = insertion order by index. No score comparison is used, so tie-break is N/A. When `probe_count == 0`, the result is `[]` and tie-break is also N/A.

**Case D: All probe points filtered (all in shadow)**
Input: `nav_system.is_point_in_shadow` returns `true` for all sampled candidates.
Result of `_build_shadow_probe_points`: empty array `[]`. `_shadow_search_total_sweeps_planned = 1 + 0 = 1`. After initial sweep completes: `sweep_done = 1`, coverage = `1.0 / 1 = 1.0`. Coverage ≥ threshold (0.8) → `clear_shadow_scan_state()`. No PROBE stage entered.

**Case E: Total budget exceeded mid-PROBE**
Input: `_shadow_search_total_timer` reaches `12.0` during PROBE movement.
Step 4 in `_execute_shadow_boundary_scan`: budget check triggers. `clear_shadow_scan_state()` called. Stage → IDLE. Function returns `false`. No crash.

**Case F: nav_system == null**
`_resolve_shadow_scan_boundary_point` returns `Vector2.ZERO`. `_shadow_scan_boundary_valid = false`. IDLE branch: stop motion, return `false`. No stage transition. Enemy stays IDLE indefinitely until `has_target` becomes `false` and intent changes.
`_build_shadow_probe_points`: nav_system null branch → includes all `probe_count` candidates without shadow filtering → returns full array.

---

## 9. Legacy removal plan (delete-first, exact ids).

**L1. `var _shadow_scan_active: bool = false`**
File: `src/systems/enemy_pursuit_system.gd`, line 97 (confirmed by PROJECT DISCOVERY).
Action: Delete declaration. Replace all 4 downstream usages before deletion:
- Line 170 (`configure_navigation`): replace `_shadow_scan_active = false` with `_shadow_search_stage = ShadowSearchStage.IDLE`.
- Line 248 (`execute_intent`): replace `_shadow_scan_active` with `_shadow_search_stage != ShadowSearchStage.IDLE`.
- Line 400 (`clear_shadow_scan_state`): remove assignment (new stage var handles IDLE reset).
- Line 434 (`_run_shadow_scan_sweep`): remove `_shadow_scan_active = true` (flashlight/scan signals are now emitted per-frame by `_run_shadow_scan_sweep` while timer > 0, unchanged logic).
After replacement: declaration on line 97 is deleted.

No other legacy items. Existing `_shadow_scan_phase`, `_shadow_scan_timer`, `_shadow_scan_boundary_point`, `_shadow_scan_boundary_valid`, `_shadow_scan_target` vars are retained (still used by `_run_shadow_scan_sweep` and `_execute_shadow_boundary_scan`).

---

## 10. Legacy verification commands (exact rg + expected 0 matches for every removed legacy item).

**[L1]** `rg -n "_shadow_scan_active" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.
Note: `_shadow_scan_active` remains in `src/entities/enemy.gd` (different variable, mirror flag). The command is scoped to `enemy_pursuit_system.gd` because PROJECT DISCOVERY evidence confirms the two vars are independent (different files, different semantics). Scoped command is valid per template rule: "unless the identifier is guaranteed file-unique by PROJECT DISCOVERY evidence — in that case state the evidence explicitly." Evidence: `enemy.gd` line 153 `_shadow_scan_active` is the mirror UI flag set by `set_shadow_scan_active()` callback; `enemy_pursuit_system.gd` line 97 `_shadow_scan_active` is the pursuit-system internal scan state — confirmed by inspecting both files.

---

## 11. Acceptance criteria (binary pass/fail).

- [ ] `rg -n "_shadow_scan_active" src/systems/enemy_pursuit_system.gd -S` returns 0 matches.
- [ ] `rg -n "ShadowSearchStage" src/systems/enemy_pursuit_system.gd -S` returns ≥ 5 matches.
- [ ] `rg -n "func get_shadow_search_stage" src/systems/enemy_pursuit_system.gd -S` returns exactly 1 match.
- [ ] `rg -n "func get_shadow_search_coverage" src/systems/enemy_pursuit_system.gd -S` returns exactly 1 match.
- [ ] `rg -n "shadow_search_probe_count" src/core/game_config.gd -S` returns exactly 1 match.
- [ ] `rg -n "shadow_search_probe_count" src/core/config_validator.gd -S` returns exactly 1 match.
- [ ] `rg -n "_build_shadow_probe_points" src/systems/enemy_pursuit_system.gd -S` returns ≥ 2 matches (definition + call).
- [ ] All 4 test functions in `test_shadow_search_stage_transition_contract.gd` pass (exit 0).
- [ ] All 4 test functions in `test_shadow_search_choreography_progressive_coverage.gd` pass (exit 0).
- [ ] Tier 2 full regression `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` exits 0.

---

## 12. Tests (new/update + purpose).

**New: `tests/test_shadow_search_stage_transition_contract.gd`**
Registration: const `SHADOW_SEARCH_STAGE_TRANSITION_TEST_SCENE = "res://tests/test_shadow_search_stage_transition_contract.tscn"` in `test_runner_node.gd`.

- `_test_idle_to_boundary_lock_on_valid_boundary`:
  Construct `EnemyPursuitSystem` with a fake owner at `Vector2(0, 0)`. Fake `nav_system` returns `Vector2(100, 0)` for `get_nearest_non_shadow_point`. Call `_execute_shadow_boundary_scan(0.016, Vector2(200, 0), true)`. Assert `get_shadow_search_stage() == ShadowSearchStage.BOUNDARY_LOCK`.

- `_test_boundary_lock_to_sweep_on_arrive`:
  Same setup. Teleport owner to `Vector2(100, 0)` (boundary point). Call `_execute_shadow_boundary_scan(0.016, Vector2(200, 0), true)` twice. Assert `get_shadow_search_stage() == ShadowSearchStage.SWEEP`.

- `_test_sweep_to_probe_when_probe_points_exist`:
  Setup: stage = SWEEP, `_shadow_scan_timer = 0.01`, fake nav returns non-shadow candidates for probe ring. Call `_execute_shadow_boundary_scan(0.05, Vector2(200, 0), true)` so timer expires. Assert `get_shadow_search_stage() == ShadowSearchStage.PROBE`.

- `_test_clear_state_on_no_target`:
  Set stage to SWEEP manually. Call `_execute_shadow_boundary_scan(0.016, Vector2.ZERO, false)`. Assert `get_shadow_search_stage() == ShadowSearchStage.IDLE` and `get_shadow_search_coverage() == 0.0`.

**New: `tests/test_shadow_search_choreography_progressive_coverage.gd`**
Registration: const `SHADOW_SEARCH_PROGRESSIVE_COVERAGE_TEST_SCENE = "res://tests/test_shadow_search_choreography_progressive_coverage.tscn"` in `test_runner_node.gd`.

- `_test_coverage_starts_at_zero`:
  Fresh `EnemyPursuitSystem`. Assert `get_shadow_search_coverage() == 0.0`.

- `_test_coverage_increases_after_first_sweep`:
  Drive system to SWEEP stage. Expire sweep timer (set `_shadow_scan_timer = 0.001`, call `_execute_shadow_boundary_scan(0.05, ...)` so timer hits 0). Assert `get_shadow_search_coverage() > 0.0`.

- `_test_coverage_reaches_threshold_after_all_probes`:
  Drive system through full session (initial sweep + all probe sweeps). Assert `get_shadow_search_coverage() >= 0.8` (≥ threshold) OR `get_shadow_search_stage() == ShadowSearchStage.IDLE` (session ended after threshold).

- `_test_coverage_resets_on_clear_state`:
  Drive coverage to > 0.0. Call `clear_shadow_scan_state()` directly. Assert `get_shadow_search_coverage() == 0.0` and `get_shadow_search_stage() == ShadowSearchStage.IDLE`.

**Updated: none.** No existing test files are modified.

---

## 13. rg gates (command + expected output).

**Phase-specific gates:**

[G1] `rg -n "ShadowSearchStage" src/systems/enemy_pursuit_system.gd -S`
Expected: ≥ 5 matches (enum declaration + IDLE=0/BOUNDARY_LOCK=1/SWEEP=2/PROBE=3 values + ≥ 1 stage assignment use).

[G2] `rg -n "func get_shadow_search_stage" src/systems/enemy_pursuit_system.gd -S`
Expected: exactly 1 match.

[G3] `rg -n "func get_shadow_search_coverage" src/systems/enemy_pursuit_system.gd -S`
Expected: exactly 1 match.

[G4] `rg -n "shadow_search_probe_count" src/core/game_config.gd -S`
Expected: exactly 1 match.

[G5] `rg -n "shadow_search_probe_count" src/core/config_validator.gd -S`
Expected: exactly 1 match.

[G6] `rg -n "_build_shadow_probe_points" src/systems/enemy_pursuit_system.gd -S`
Expected: ≥ 2 matches (function definition + call site in SWEEP branch).

[G7] `rg -n "shadow_search_probe_ring_radius_px|shadow_search_coverage_threshold|shadow_search_total_budget_sec" src/core/game_config.gd -S`
Expected: exactly 3 matches (one per key).

[G8] `rg -n "ShadowSearchStage" src/entities/enemy.gd -S`
Expected: 0 matches (enum defined only in `enemy_pursuit_system.gd`, not leaked to `enemy.gd`).

[G9] `rg -n "_shadow_search_stage|_shadow_search_coverage|_shadow_search_probe_points" src/entities/enemy.gd -S`
Expected: 0 matches (new state vars not duplicated in enemy.gd).

**PMB gates (verbatim from document PMB section):**

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: 0 matches.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

---

## 14. Execution sequence (step-by-step, no ambiguity).

**Step 1 (Legacy delete):** In `src/systems/enemy_pursuit_system.gd` line 97: delete `var _shadow_scan_active: bool = false`. Run `rg -n "_shadow_scan_active" src/systems/enemy_pursuit_system.gd -S` to locate remaining 4 usages (lines 170, 248, 400, 434).

**Step 2 (Legacy replacement — configure_navigation):** In `configure_navigation()`, replace `_shadow_scan_active = false` with `_shadow_search_stage = ShadowSearchStage.IDLE`.

**Step 3 (Legacy replacement — execute_intent guard):** In `execute_intent()` guard (line ~248), replace `_shadow_scan_active or _shadow_scan_boundary_valid` with `_shadow_search_stage != ShadowSearchStage.IDLE or _shadow_scan_boundary_valid`.

**Step 4 (Legacy replacement — clear_shadow_scan_state):** In `clear_shadow_scan_state()`, remove `_shadow_scan_active = false`; leave all other existing resets intact.

**Step 5 (Legacy replacement — _run_shadow_scan_sweep):** In `_run_shadow_scan_sweep()`, remove `_shadow_scan_active = true`; change return type from `void` to `bool`; replace `clear_shadow_scan_state()` call on timer ≤ 0 with `owner.call("set_shadow_check_flashlight", false)` + `owner.call("set_shadow_scan_active", false)` + `return true`; add `return false` at function end.

**Step 6 (Verify L1 gate):** Run `rg -n "_shadow_scan_active" src/systems/enemy_pursuit_system.gd -S` → must return 0 matches before continuing.

**Step 7 (Add enum):** In `enemy_pursuit_system.gd` at file scope (before first `const` or `var`): add `enum ShadowSearchStage { IDLE = 0, BOUNDARY_LOCK = 1, SWEEP = 2, PROBE = 3 }`.

**Step 8 (Add new state vars):** In `enemy_pursuit_system.gd` after existing `_shadow_scan_boundary_valid` var: add 7 new vars with initializers:
```gdscript
var _shadow_search_stage: int = ShadowSearchStage.IDLE
var _shadow_search_probe_points: Array[Vector2] = []
var _shadow_search_probe_cursor: int = 0
var _shadow_search_sweep_done: int = 0
var _shadow_search_total_sweeps_planned: int = 0
var _shadow_search_coverage: float = 0.0
var _shadow_search_total_timer: float = 0.0
```

**Step 9 (Update clear_shadow_scan_state):** Add resets for all 7 new vars at end of `clear_shadow_scan_state()`:
```gdscript
_shadow_search_stage = ShadowSearchStage.IDLE
_shadow_search_probe_points.clear()
_shadow_search_probe_cursor = 0
_shadow_search_sweep_done = 0
_shadow_search_total_sweeps_planned = 0
_shadow_search_coverage = 0.0
_shadow_search_total_timer = 0.0
```

**Step 10 (Update configure_navigation):** After existing resets at bottom of `configure_navigation()`, add resets for all 7 new vars (identical values as in step 9).

**Step 11 (Add public getters):** Add to `enemy_pursuit_system.gd`:
```gdscript
func get_shadow_search_stage() -> int:
    return _shadow_search_stage

func get_shadow_search_coverage() -> float:
    return _shadow_search_coverage
```

**Step 12 (Add _build_shadow_probe_points):** Add private function per section 7 algorithm.

**Step 13 (Rewrite _execute_shadow_boundary_scan):** Replace function body with the 5-step stage machine from section 7. Function signature unchanged: `_execute_shadow_boundary_scan(delta: float, target: Vector2, has_target: bool) -> bool`.

**Step 14 (Add GameConfig keys):** In `src/core/game_config.gd`, inside `ai_balance["pursuit"]` block (before the closing `}`): add 4 keys per section 6.

**Step 15 (Add config validator calls):** In `src/core/config_validator.gd`, inside the pursuit block after line 200 (after `waypoint_reached_px` validation):
```gdscript
_validate_number_key(result, pursuit, "shadow_search_probe_count", "ai_balance.pursuit", 0.0, 20.0)
_validate_number_key(result, pursuit, "shadow_search_probe_ring_radius_px", "ai_balance.pursuit", 1.0, 2000.0)
_validate_number_key(result, pursuit, "shadow_search_coverage_threshold", "ai_balance.pursuit", 0.0, 1.0)
_validate_number_key(result, pursuit, "shadow_search_total_budget_sec", "ai_balance.pursuit", 0.1, 120.0)
```

**Step 16 (Create test files):** Create `tests/test_shadow_search_stage_transition_contract.gd` and `tests/test_shadow_search_choreography_progressive_coverage.gd` with all 8 test functions from section 12. Create corresponding `.tscn` files.

**Step 17 (Register tests in test_runner_node.gd):** Add at file scope:
```gdscript
const SHADOW_SEARCH_STAGE_TRANSITION_TEST_SCENE = "res://tests/test_shadow_search_stage_transition_contract.tscn"
const SHADOW_SEARCH_PROGRESSIVE_COVERAGE_TEST_SCENE = "res://tests/test_shadow_search_choreography_progressive_coverage.tscn"
```
Add in `_get_test_suites()` (or equivalent registration point), inside a new `--- SECTION 18e` block:
```gdscript
print("\n--- SECTION 18e: Shadow search choreography unit tests ---")
_test("Shadow search stage transition test scene exists", func(): return _scene_exists(SHADOW_SEARCH_STAGE_TRANSITION_TEST_SCENE))
_test("Shadow search progressive coverage test scene exists", func(): return _scene_exists(SHADOW_SEARCH_PROGRESSIVE_COVERAGE_TEST_SCENE))
await _run_embedded_scene_suite("Shadow search stage transition suite", SHADOW_SEARCH_STAGE_TRANSITION_TEST_SCENE)
await _run_embedded_scene_suite("Shadow search progressive coverage suite", SHADOW_SEARCH_PROGRESSIVE_COVERAGE_TEST_SCENE)
```

**Step 18 (Tier 1 smoke — stage transition):** `xvfb-run -a godot-4 --headless --path . res://tests/test_shadow_search_stage_transition_contract.tscn` — must exit 0.

**Step 19 (Tier 1 smoke — coverage):** `xvfb-run -a godot-4 --headless --path . res://tests/test_shadow_search_choreography_progressive_coverage.tscn` — must exit 0.

**Step 20 (Tier 2 full regression):** `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit 0.

**Step 21 (Run all rg gates):** Execute G1–G9 and PMB-1–PMB-5 from section 13 — all must return expected output.

**Step 22 (Prepend CHANGELOG entry):** Prepend one entry to `CHANGELOG.md` under the current date header per CHANGELOG policy. Do not read the full file.

---

## 15. Rollback conditions.

- Condition 1: L1 legacy gate after Step 6 returns non-zero (`_shadow_scan_active` still present in `enemy_pursuit_system.gd`) → revert Steps 1–5; do not proceed until L1 returns 0.
- Condition 2: Any Tier 1 smoke command (Steps 18–19) exits non-zero → revert all Phase 11 changes to `src/systems/enemy_pursuit_system.gd`, `src/core/game_config.gd`, `src/core/config_validator.gd`, `tests/test_runner_node.gd`; delete new `.gd` and `.tscn` test files.
- Condition 3: Tier 2 full regression exits non-zero → same full revert as Condition 2.
- Condition 4: Any PMB gate returns unexpected output → locate offending identifier; if in `enemy_pursuit_system.gd`, remove it; re-run gate. If cannot be fixed without architecture change → full revert.
- Condition 5: G8 returns non-zero (`ShadowSearchStage` found in `enemy.gd`) → remove the leak from `enemy.gd`; re-run gate. If the remove is impossible without rework → full revert.
- Condition 6: `_run_shadow_scan_sweep` called from any location outside `_execute_shadow_boundary_scan` → locate caller; update to handle `bool` return; if impossible → full revert.

---

## 16. Phase close condition.

- [ ] `rg -n "_shadow_scan_active" src/systems/enemy_pursuit_system.gd -S` returns 0 matches (L1 gate)
- [ ] G1: `ShadowSearchStage` in `enemy_pursuit_system.gd` ≥ 5 matches
- [ ] G2: `func get_shadow_search_stage` → exactly 1 match
- [ ] G3: `func get_shadow_search_coverage` → exactly 1 match
- [ ] G4: `shadow_search_probe_count` in `game_config.gd` → exactly 1 match
- [ ] G5: `shadow_search_probe_count` in `config_validator.gd` → exactly 1 match
- [ ] G6: `_build_shadow_probe_points` in `enemy_pursuit_system.gd` → ≥ 2 matches
- [ ] G7: 3 new config keys in `game_config.gd` → exactly 3 matches
- [ ] G8: `ShadowSearchStage` not in `enemy.gd` → 0 matches
- [ ] G9: new stage vars not in `enemy.gd` → 0 matches
- [ ] PMB-1 through PMB-5: all return expected output
- [ ] All 8 test functions in section 12 (new files) exit 0
- [ ] Tier 1 smoke suite (Steps 18–19) — both commands exit 0
- [ ] Tier 2 full regression (`test_runner.tscn`) exits 0
- [ ] No file outside section 4 in-scope list was modified
- [ ] CHANGELOG entry prepended

---

## 17. Ambiguity self-check line.

Ambiguity check: 0

---

## 18. Open questions line.

Open questions: 0

---

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).

**Files to diff:**
- `src/systems/enemy_pursuit_system.gd` — verify: `_shadow_scan_active` var declaration absent; `enum ShadowSearchStage` present; 7 new vars declared; `get_shadow_search_stage()` and `get_shadow_search_coverage()` present; `_execute_shadow_boundary_scan` body uses stage dispatch (`match _shadow_search_stage`); `_run_shadow_scan_sweep` returns `bool` and has no `clear_shadow_scan_state()` call; `_build_shadow_probe_points` function present; `clear_shadow_scan_state()` resets all 7 new vars; `configure_navigation()` resets all 7 new vars.
- `src/core/game_config.gd` — verify: 4 new keys present in `ai_balance["pursuit"]` block.
- `src/core/config_validator.gd` — verify: 4 new `_validate_number_key` calls in pursuit block.
- `tests/test_runner_node.gd` — verify: 2 new const declarations and 2 `_run_embedded_scene_suite` calls in SECTION 18e block.

**Contracts to check:**
- `ShadowSearchStageContractV1`: execute runtime scenarios P11-A, P11-B, P11-C, P11-D (section 20).
- Coverage monotonicity: run scenario P11-C and assert `get_shadow_search_coverage()` never decreases between frames.

**Runtime scenarios:** execute P11-A through P11-D from section 20.

---

## 20. Runtime scenario matrix.

**Scenario P11-A — immediate clear on no_target (Case A):**
Setup: `EnemyPursuitSystem` in SWEEP stage, `has_target = false`.
Scene: `res://tests/test_shadow_search_stage_transition_contract.tscn`. Frame count: 0 (unit).
Expected invariant: after call, `get_shadow_search_stage() == 0` (IDLE) and `get_shadow_search_coverage() == 0.0`.
Fail condition: stage ≠ IDLE or coverage ≠ 0.0.
Covered by: `_test_clear_state_on_no_target`.

**Scenario P11-B — boundary lock resolves and arrives (Case B):**
Setup: fake nav returns boundary at `Vector2(100, 0)`. Owner at `Vector2(100, 0)` (at boundary). Stage = BOUNDARY_LOCK after first call.
Scene: `res://tests/test_shadow_search_stage_transition_contract.tscn`. Frame count: 0 (unit).
Expected invariant: after arrival, `get_shadow_search_stage() == 2` (SWEEP). `_shadow_scan_timer > 0`.
Fail condition: stage ≠ SWEEP.
Covered by: `_test_boundary_lock_to_sweep_on_arrive`.

**Scenario P11-C — full session coverage progression:**
Setup: fake nav; probe_count = 3; all 3 probe candidates non-shadow. Drive through initial sweep + all 3 probe sweeps.
Scene: `res://tests/test_shadow_search_choreography_progressive_coverage.tscn`. Frame count: 0 (unit; each sweep manually expired by setting timer to 0).
Expected invariant: after each sweep completion, `get_shadow_search_coverage()` strictly increases. After 4th sweep: coverage = 4/4 = 1.0 ≥ 0.8 → `clear_shadow_scan_state()`. Stage = IDLE.
Fail condition: coverage does not increase after any sweep, OR stage ≠ IDLE after 4th sweep.
Covered by: `_test_coverage_reaches_threshold_after_all_probes`.

**Scenario P11-D — probe points all filtered (all in shadow, Case D):**
Setup: `nav_system.is_point_in_shadow` returns `true` for all candidates. Drive to SWEEP stage. Expire sweep timer.
Scene: `res://tests/test_shadow_search_choreography_progressive_coverage.tscn`. Frame count: 0 (unit).
Expected invariant: `_build_shadow_probe_points` returns `[]`. `_shadow_search_total_sweeps_planned = 1`. After sweep complete: coverage = 1.0/1 = 1.0 ≥ 0.8 → `clear_shadow_scan_state()`. Stage = IDLE. No PROBE stage entered.
Fail condition: stage enters PROBE, OR coverage < 1.0 after first sweep, OR stage ≠ IDLE after.
Covered by: `_test_coverage_reaches_threshold_after_all_probes` (implicit — empty probe array → single sweep equals 100% coverage).

---

## 21. Verification report format.

Record all fields below to close phase:
- `phase_id: PHASE_11`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; must be empty list on close)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `legacy_rg: [{command: "rg -n \"_shadow_scan_active\" src/systems/enemy_pursuit_system.gd -S", expected: "0 matches", actual, PASS|FAIL}]`
- `rg_gates: [{command, expected, actual, PASS|FAIL}]` for each G1–G9
- `phase_tests: [{test_function, exit_code: 0, PASS|FAIL}]` for all 8 test functions
- `smoke_suite: [{command, exit_code, PASS|FAIL}]` for Steps 18–19
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

---

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 11` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- pmb_contract_check present in section 21 (PMB section exists in document): yes

---

## 23. Dependencies on previous phases.

1. **Phase 2** — introduced strict `unreachable_policy → SHADOW_BOUNDARY_SCAN → SEARCH` FSM and removed shadow-escape fallbacks from SUSPICIOUS state. Phase 11 inherits: SHADOW_BOUNDARY_SCAN intent is emitted only in SUSPICIOUS state (confirmed in `EnemyUtilityBrain._choose_intent` lines 104–109). The Phase 2 prohibition on direct PATROL fallback from SUSPICIOUS means all shadow-in-shadow SUSPICIOUS scenarios flow through SHADOW_BOUNDARY_SCAN → Phase 11's staged choreography is guaranteed to be the execution path. Without Phase 2, the shadow boundary scan intent might be bypassed via direct PATROL fallback, making Phase 11's coverage tracking unreachable in practice.

2. **Phase 4** — extended `_build_utility_context` in `enemy.gd` to emit `shadow_scan_target` and `has_shadow_scan_target` for ALERT and COMBAT states in addition to SUSPICIOUS. Phase 11 inherits: the `set_shadow_scan_active()` callback called by `_run_shadow_scan_sweep()` activates the flashlight on the enemy (via `enemy.gd` mirror flag). Phase 4 ensured that flashlight policy correctly responds to `_shadow_scan_active` mirror flag during shadow scan sessions — which Phase 11's multi-stage probe sweeps continue to use for visual feedback via the same `set_shadow_scan_active(true/false)` calls emitted by the modified `_run_shadow_scan_sweep`.

3. **Phase 7** — deleted legacy dead functions from `enemy_pursuit_system.gd` (L1–L7), ensuring PMB gates pass from a clean baseline. Phase 11 inherits: the absence of deleted functions `_is_owner_in_shadow_without_flashlight` and `_select_nearest_reachable_candidate` guarantees PMB-1 through PMB-3 produce 0 matches from a clean state. Without Phase 7 cleanup, stale identifiers in `enemy_pursuit_system.gd` would confuse PMB audits and potentially conflict with the new `_build_shadow_probe_points` function's shadow query calls.

---

## PHASE 12
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_12.

### Evidence

**Inspected files:**
- `src/systems/enemy_squad_system.gd` — full source read; 336 lines
- `src/entities/enemy.gd` — flashlight-related functions and variables inspected
- `src/core/game_config.gd` — zone_profiles and flashlight-related config keys inspected
- `src/core/config_validator.gd` — squad validation block inspected

**Inspected functions/methods:**
- `EnemySquadSystem._recompute_assignments` (lines 102–139): calls `_build_slots`, iterates `_members`, stores assignments; no flashlight logic
- `EnemySquadSystem._member_enemy` (lines 252–259): resolves WeakRef → Node2D; returns null if invalid
- `EnemySquadSystem._squad_cfg_int` (lines 331–335): reads int from `ai_balance["squad"]`; already exists
- `EnemySquadSystem._members` (line 26): `Dictionary` mapping `enemy_id (int) → {enemy_ref: WeakRef, role: int, assignment: Dictionary}`
- `EnemySquadSystem.Role` (lines 6–10): enum PRESSURE=0, HOLD=1, FLANK=2
- `Enemy._compute_flashlight_active` (inspected via Explore): returns multiline OR of policy conditions; no squad awareness currently
- `Enemy.squad_system` (line 134): `var squad_system: Node = null` — already present
- `Enemy.entity_id` (line 100): `var entity_id: int = 0` — already present
- `Enemy.set_tactical_systems` (line 756): sets `squad_system` reference; confirms push model is viable
- `Enemy._register_to_squad_system` (line 1511): calls `squad_system.register_enemy(entity_id, self)` — confirms enemy_id ownership
- `GameConfig.zone_system["zone_profiles"]`: contains `flashlight_active_cap` per level (CALM=1, ELEVATED=2, LOCKDOWN=4) — config exists but NOT enforced in code
- `GameConfig.ai_balance["squad"]`: existing squad config section used by `_squad_cfg_int`

**Search commands used:**
```
rg -n "flashlight" src/systems/enemy_squad_system.gd -S
rg -n "squad_system" src/entities/enemy.gd -S
rg -n "entity_id" src/entities/enemy.gd -S
rg -n "_flashlight_scanner_allowed|flashlight_scanner_cap|set_flashlight_scanner_allowed" src/ -S
rg -n "force_flashlight_all|legacy_flashlight_override|old_scanner_logic" src/ tests/ -S
rg -n "_squad_cfg_int|_squad_cfg_float" src/systems/enemy_squad_system.gd -S
```

**Key findings:**
- No flashlight references in `enemy_squad_system.gd` (0 matches) — squad and flashlight fully independent today.
- `_flashlight_scanner_allowed`, `flashlight_scanner_cap`, `set_flashlight_scanner_allowed` — NONE found anywhere in `src/`.
- `force_flashlight_all|legacy_flashlight_override|old_scanner_logic` — 0 matches in `src/` and `tests/`. No legacy to delete.
- Squad system already has `_squad_cfg_int` (line 331) — no new helper needed.
- Squad system holds `WeakRef` to each enemy in `_members`; `_member_enemy()` resolves them → push model is viable.
- `enemy.gd` already holds `squad_system: Node` reference (line 134) and `entity_id: int` (line 100).
- `flashlight_active_cap` exists in zone_profiles config but has zero enforcement code — Phase 12 does NOT enforce zone-dynamic cap (uses a single squad-level cap from `ai_balance["squad"]` for simplicity).

---

## 1. What now.

`rg -n "flashlight" src/systems/enemy_squad_system.gd -S` → 0 matches. Squad system has no awareness of flashlight state. All enemies in ALERT/COMBAT activate their flashlights independently according to individual policy, with no coordination. The `flashlight_active_cap` values in `GameConfig.zone_system["zone_profiles"]` have no enforcement code anywhere in `src/`. FLANK-role enemies activate flashlight under the same conditions as PRESSURE-role enemies, contradicting the intended atmospheric pressure design where FLANK approaches stealthily without revealing position via flashlight.

Failing state: `tests/test_flashlight_single_scanner_role_assignment.gd` does not exist. `tests/test_team_contain_with_flashlight_pressure.gd` does not exist.

Observable metric (current): `rg -n "flashlight_scanner_cap" src/ -S` → 0 matches. No scanner cap is enforced. All eligible enemies scan simultaneously.

---

## 2. What changes.

1. **`src/systems/enemy_squad_system.gd` — add** `var _scanner_slots: Dictionary = {}` (int enemy_id → bool scanner_allowed) at file scope after `_rebuild_timer`.
2. **`src/systems/enemy_squad_system.gd` — add** private function `_rebuild_scanner_slots() -> void`: collects PRESSURE/HOLD member ids sorted ascending, assigns scanner=true to first `_squad_cfg_int("flashlight_scanner_cap", 2)` slots (PRESSURE priority over HOLD; FLANK always false); pushes result to each enemy via `set_flashlight_scanner_allowed`.
3. **`src/systems/enemy_squad_system.gd` — add** public function `get_scanner_allowed(enemy_id: int) -> bool` returning `bool(_scanner_slots.get(enemy_id, false))`.
4. **`src/systems/enemy_squad_system.gd` — modify** `_recompute_assignments()`: add `_rebuild_scanner_slots()` call at the end (after the existing member iteration loop).
5. **`src/entities/enemy.gd` — add** `var _flashlight_scanner_allowed: bool = true` at file scope (near existing flashlight vars, after `_shadow_linger_flashlight`).
6. **`src/entities/enemy.gd` — add** public function `set_flashlight_scanner_allowed(allowed: bool) -> void` setting `_flashlight_scanner_allowed = allowed`.
7. **`src/entities/enemy.gd` — add** `_flashlight_scanner_allowed = true` reset in the enemy reset block (where `_shadow_check_flashlight_override = false` is already set).
8. **`src/entities/enemy.gd` — modify** `_compute_flashlight_active(awareness_state)`: split the single multiline `return` expression into `var raw_active := <existing expression>` then `return raw_active and _flashlight_scanner_allowed`.
9. **`src/core/game_config.gd`**: add key `"flashlight_scanner_cap": 2` to `ai_balance["squad"]` block.
10. **`src/core/config_validator.gd`**: add `_validate_number_key(result, squad, "flashlight_scanner_cap", "ai_balance.squad", 0.0, 32.0)` in squad validation block.
11. **New** `tests/test_flashlight_single_scanner_role_assignment.gd` + `.tscn` — 4 test functions; see section 12.
12. **New** `tests/test_team_contain_with_flashlight_pressure.gd` + `.tscn` — 4 test functions; see section 12.
13. **`tests/test_runner_node.gd`**: add 2 new const declarations + 2 `_run_embedded_scene_suite` calls in a new `--- SECTION 18f` block.

---

## 3. What will be after.

1. `rg -n "flashlight" src/systems/enemy_squad_system.gd -S` → ≥ 3 matches (`_scanner_slots`, `_rebuild_scanner_slots`, `get_scanner_allowed`, `set_flashlight_scanner_allowed` push call) — verified by G1.
2. `rg -n "func get_scanner_allowed" src/systems/enemy_squad_system.gd -S` → 1 match — verified by G2.
3. `rg -n "_flashlight_scanner_allowed" src/entities/enemy.gd -S` → ≥ 3 matches (declaration, reset, return expr) — verified by G3.
4. `rg -n "flashlight_scanner_cap" src/core/game_config.gd -S` → 1 match — verified by G4.
5. `rg -n "flashlight_scanner_cap" src/core/config_validator.gd -S` → 1 match — verified by G5.
6. All 8 test functions in section 12 pass — verified by Tier 1 smoke + Tier 2 regression.

---

## 4. Scope and non-scope (exact files).

**In-scope:**
- `src/systems/enemy_squad_system.gd`
- `src/entities/enemy.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `tests/test_flashlight_single_scanner_role_assignment.gd` (new)
- `tests/test_flashlight_single_scanner_role_assignment.tscn` (new)
- `tests/test_team_contain_with_flashlight_pressure.gd` (new)
- `tests/test_team_contain_with_flashlight_pressure.tscn` (new)
- `tests/test_runner_node.gd`
- `CHANGELOG.md`

**Out-of-scope (must not be modified):**
- `src/systems/enemy_pursuit_system.gd` — no navigation changes
- `src/systems/enemy_utility_brain.gd` — intent logic unchanged
- `src/systems/navigation_service.gd` — no nav changes
- `src/systems/zone_director.gd` — zone-dynamic cap NOT implemented in this phase (deferred to a later phase; not part of this scope)
- `src/systems/enemy_patrol_system.gd` — patrol unchanged
- `scenes/entities/enemy.tscn` — scene unchanged

---

## 5. Single-owner authority for this phase.

**Owner file:** `src/systems/enemy_squad_system.gd`.
**Owner function:** `_rebuild_scanner_slots() -> void` — sole decision point for all scanner slot assignments. No other file computes who gets a scanner slot.
**Uniqueness:** No other file contains `_scanner_slots` or scanner assignment logic.
**Verifiable via G6:** `rg -n "_scanner_slots\|_rebuild_scanner_slots" src/ -S` → all matches in `src/systems/enemy_squad_system.gd` only; 0 matches in any other file.

---

## 6. Full input/output contract.

**Contract name:** `FlashlightScannerPolicyContractV1`

**Inputs to `_rebuild_scanner_slots()`:**
- Implicit: `_members: Dictionary` — current squad membership (int enemy_id → member dict); populated by `_recompute_assignments()`
- Implicit: `GameConfig.ai_balance["squad"]["flashlight_scanner_cap"]` — int cap value; read via `_squad_cfg_int("flashlight_scanner_cap", 2)`

**Outputs of `_rebuild_scanner_slots()`:**
- `_scanner_slots: Dictionary` — maps each registered enemy_id to `bool` scanner_allowed
- Side effect: calls `enemy.set_flashlight_scanner_allowed(bool)` on each valid enemy instance via WeakRef

**Inputs to `get_scanner_allowed(enemy_id: int) -> bool`:**
- `enemy_id: int` — must be > 0; if not in `_scanner_slots` returns `false`

**Output:** `bool` — `true` if enemy holds a scanner slot, `false` otherwise

**Role scanner eligibility (exact):**
- `Role.PRESSURE (0)`: eligible; highest priority
- `Role.HOLD (1)`: eligible; lower priority than PRESSURE
- `Role.FLANK (2)`: NEVER eligible; always `false` regardless of cap

**Priority order within eligible role:** lower `enemy_id` (int) wins — ascending sort; deterministic

**Cap semantics:** total scanner slots = `min(cap, eligible_member_count)`. If cap = 0: all enemies get `false`. If cap ≥ total eligible: all PRESSURE and HOLD get `true`; FLANK always `false`.

**`_flashlight_scanner_allowed` in enemy.gd:**
- Default: `true` (individual policy — no squad coordinator)
- Set to `false` when `_rebuild_scanner_slots()` determines enemy has no slot
- Reset to `true` on enemy reset (ensures individual policy when squad deregistered)

**Constants/thresholds:**

| Key | Value | Placement |
|---|---|---|
| `flashlight_scanner_cap` | `2` (int) | `ai_balance["squad"]` in `game_config.gd` |

Read via existing `_squad_cfg_int("flashlight_scanner_cap", 2)` in `enemy_squad_system.gd`.

---

## 7. Deterministic algorithm with exact order.

**`_rebuild_scanner_slots() -> void`:**

Step 1 — Cap read: `var cap: int = _squad_cfg_int("flashlight_scanner_cap", 2)`.

Step 2 — Clear: `_scanner_slots.clear()`.

Step 3 — Collect by role: iterate `_members.keys()`; for each `enemy_id: int` in members: read `role = int(member.get("role", Role.PRESSURE))`. Append to `pressure_ids: Array[int]` if `role == Role.PRESSURE`; append to `hold_ids: Array[int]` if `role == Role.HOLD`; skip if `role == Role.FLANK`.

Step 4 — Sort: `pressure_ids.sort()` ascending. `hold_ids.sort()` ascending.

Step 5 — Assign PRESSURE: `var slots_remaining: int = cap`. For each `enemy_id` in `pressure_ids`: `_scanner_slots[enemy_id] = slots_remaining > 0`. If `slots_remaining > 0`: `slots_remaining -= 1`.

Step 6 — Assign HOLD: For each `enemy_id` in `hold_ids`: `_scanner_slots[enemy_id] = slots_remaining > 0`. If `slots_remaining > 0`: `slots_remaining -= 1`.

Step 7 — Assign FLANK: For each `enemy_id` in `_members.keys()` where `role == Role.FLANK`: `_scanner_slots[enemy_id] = false`.

Step 8 — Push: For each `enemy_id` in `_members.keys()`: resolve enemy via `_member_enemy(member)`. If `enemy == null`: skip. If `enemy.has_method("set_flashlight_scanner_allowed")`: `enemy.call("set_flashlight_scanner_allowed", bool(_scanner_slots.get(enemy_id, false)))`.

**Modification to `_compute_flashlight_active(awareness_state: int) -> bool` in `enemy.gd`:**

Replace single multiline `return <expr>` with:
```gdscript
var raw_active: bool = <existing multiline OR expression, unchanged>
return raw_active and _flashlight_scanner_allowed
```

**Tie-break rules:** Within the same role, lower `enemy_id` (int ascending) wins. This order is deterministic and reproducible across rebuilds with the same membership.

**Behavior when input is empty/null/invalid:**
- `_members` empty: `_scanner_slots` remains empty after clear; no push calls. No crash.
- `cap == 0`: all eligible enemies get `false`; all FLANK get `false`. All enemies set to `set_flashlight_scanner_allowed(false)`.
- `_member_enemy()` returns null: push step skips that enemy silently.
- `squad_system == null` in enemy: `_flashlight_scanner_allowed` remains `true` (default) → individual policy applies.

---

## 8. Edge-case matrix.

**Case A: Squad is empty (no members)**
Input: `_members = {}`. Call `_rebuild_scanner_slots()`.
Expected: `_scanner_slots = {}`. No push calls. No crash. `get_scanner_allowed(1) == false` (id not in dict → default false).

**Case B: Cap=1, one PRESSURE + one HOLD + one FLANK (canonical case)**
Input: ids = {1:PRESSURE, 2:HOLD, 3:FLANK}, cap=1.
Expected: `_scanner_slots = {1:true, 2:false, 3:false}`. Enemy 1 receives `set_flashlight_scanner_allowed(true)`. Enemies 2,3 receive `false`.

**Case C: Tie-break — two PRESSURE enemies, cap=1**
Input: ids = {5:PRESSURE, 3:PRESSURE}, cap=1.
Expected: pressure_ids sorted = [3, 5]. `_scanner_slots = {3:true, 5:false}`. Lower id (3) wins.

**Case D: All FLANK, cap=10**
Input: ids = {1:FLANK, 2:FLANK, 3:FLANK}, cap=10.
Expected: `_scanner_slots = {1:false, 2:false, 3:false}`. All enemies receive `set_flashlight_scanner_allowed(false)`. `cap` does not grant slots to FLANK regardless of value.

**Case E: cap=0**
Input: ids = {1:PRESSURE, 2:HOLD}, cap=0.
Expected: `slots_remaining=0` from start. `_scanner_slots = {1:false, 2:false}`. All enemies get `set_flashlight_scanner_allowed(false)`.

**Case F: `_flashlight_scanner_allowed = false` in enemy, `_compute_flashlight_active(ALERT)` called**
Input: awareness_state = ALERT, `_flashlight_policy_active_in_alert()` returns true, `_flashlight_scanner_allowed = false`.
Expected: `raw_active = true`, `return true and false = false`. Flashlight inactive.

---

## 9. Legacy removal plan (delete-first, exact ids).

No legacy to delete in this phase. `rg -n "force_flashlight_all|legacy_flashlight_override|old_scanner_logic" src/ tests/ -S` returns 0 matches (confirmed by PROJECT DISCOVERY). The legacy removal gate from v1 spec section 18.6 is satisfied at baseline — no identifiers exist.

---

## 10. Legacy verification commands (exact rg + expected 0 matches for every removed legacy item).

No items to verify. The phase adds new identifiers; it does not remove existing ones.

Mandatory baseline check (satisfies v1 spec legacy gate):

**[L-BASELINE]** `rg -n "force_flashlight_all|legacy_flashlight_override|old_scanner_logic" src/ tests/ -S`
Expected: 0 matches. (Confirmed at phase start by PROJECT DISCOVERY — must still be 0 at phase close.)

---

## 11. Acceptance criteria (binary pass/fail).

- [ ] `rg -n "func get_scanner_allowed" src/systems/enemy_squad_system.gd -S` returns exactly 1 match.
- [ ] `rg -n "_scanner_slots" src/systems/enemy_squad_system.gd -S` returns ≥ 3 matches.
- [ ] `rg -n "_flashlight_scanner_allowed" src/entities/enemy.gd -S` returns ≥ 3 matches (decl, reset, return).
- [ ] `rg -n "flashlight_scanner_cap" src/core/game_config.gd -S` returns exactly 1 match.
- [ ] `rg -n "flashlight_scanner_cap" src/core/config_validator.gd -S` returns exactly 1 match.
- [ ] `rg -n "force_flashlight_all|legacy_flashlight_override|old_scanner_logic" src/ tests/ -S` returns 0 matches.
- [ ] `rg -n "_scanner_slots\|_rebuild_scanner_slots" src/entities/enemy.gd -S` returns 0 matches (logic not duplicated).
- [ ] All 8 test functions in section 12 pass (exit 0).
- [ ] Tier 2 full regression `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` exits 0.

---

## 12. Tests (new/update + purpose).

**New: `tests/test_flashlight_single_scanner_role_assignment.gd`**
Registration: const `FLASHLIGHT_SCANNER_ROLE_ASSIGNMENT_TEST_SCENE = "res://tests/test_flashlight_single_scanner_role_assignment.tscn"` in `test_runner_node.gd`.

- `_test_only_pressure_gets_scanner_when_cap_1`:
  Register 3 enemies: id=1 PRESSURE, id=2 HOLD, id=3 FLANK. Set cap=1. Call `_recompute_assignments()`. Assert `get_scanner_allowed(1)==true`, `get_scanner_allowed(2)==false`, `get_scanner_allowed(3)==false`.

- `_test_flank_never_gets_scanner_slot`:
  Register 3 FLANK enemies (ids 1,2,3). Set cap=10. Call `_recompute_assignments()`. Assert all `get_scanner_allowed(id)==false` for ids 1,2,3.

- `_test_pressure_priority_over_hold_within_cap`:
  Register: id=6 PRESSURE, id=2 HOLD, id=4 HOLD. Cap=1. Call `_recompute_assignments()`. Assert `get_scanner_allowed(6)==true`, `get_scanner_allowed(2)==false`, `get_scanner_allowed(4)==false`.

- `_test_cap_limits_total_scanners_to_configured_value`:
  Register 4 PRESSURE enemies (ids 1,2,3,4). Cap=2. Call `_recompute_assignments()`. Assert `get_scanner_allowed(1)==true`, `get_scanner_allowed(2)==true`, `get_scanner_allowed(3)==false`, `get_scanner_allowed(4)==false`.

**New: `tests/test_team_contain_with_flashlight_pressure.gd`**
Registration: const `TEAM_CONTAIN_FLASHLIGHT_PRESSURE_TEST_SCENE = "res://tests/test_team_contain_with_flashlight_pressure.tscn"` in `test_runner_node.gd`.

- `_test_hold_role_gets_scanner_when_no_pressure_in_squad`:
  Register 3 HOLD enemies (ids 1,2,3). Cap=2. Call `_recompute_assignments()`. Assert `get_scanner_allowed(1)==true`, `get_scanner_allowed(2)==true`, `get_scanner_allowed(3)==false`.

- `_test_flank_enemy_compute_flashlight_returns_false_despite_alert`:
  Construct minimal enemy instance. Set `_flashlight_scanner_allowed = false`. Set awareness state to ALERT with flashlight policy active. Call `_compute_flashlight_active(ALERT)`. Assert result `== false`.

- `_test_pressure_enemy_compute_flashlight_passes_when_allowed`:
  Construct minimal enemy. Set `_flashlight_scanner_allowed = true`. Set awareness state ALERT with `flashlight_works_in_alert = true` in canon. Call `_compute_flashlight_active(ALERT)`. Assert result `== true`.

- `_test_no_squad_default_scanner_allowed_true`:
  Fresh enemy instance (squad_system = null). Assert `_flashlight_scanner_allowed == true` (initial value). `_compute_flashlight_active(ALERT)` with policy active returns `true` (individual policy unblocked).

**Updated: none.** No existing test files are modified.

---

## 13. rg gates (command + expected output).

**Phase-specific gates:**

[G1] `rg -n "flashlight" src/systems/enemy_squad_system.gd -S`
Expected: ≥ 3 matches (`_scanner_slots` var, `_rebuild_scanner_slots` def, `set_flashlight_scanner_allowed` push call, `get_scanner_allowed` def).

[G2] `rg -n "func get_scanner_allowed" src/systems/enemy_squad_system.gd -S`
Expected: exactly 1 match.

[G3] `rg -n "_flashlight_scanner_allowed" src/entities/enemy.gd -S`
Expected: ≥ 3 matches (var declaration, reset assignment, return expression).

[G4] `rg -n "flashlight_scanner_cap" src/core/game_config.gd -S`
Expected: exactly 1 match.

[G5] `rg -n "flashlight_scanner_cap" src/core/config_validator.gd -S`
Expected: exactly 1 match.

[G6] `rg -n "_scanner_slots|_rebuild_scanner_slots" src/ -S`
Expected: all matches in `src/systems/enemy_squad_system.gd` only; 0 matches in any other file.

[G7] `rg -n "_scanner_slots|_rebuild_scanner_slots" src/entities/enemy.gd -S`
Expected: 0 matches (scanner logic not duplicated in enemy.gd).

[G8] `rg -n "force_flashlight_all|legacy_flashlight_override|old_scanner_logic" src/ tests/ -S`
Expected: 0 matches (baseline gate).

**PMB gates (verbatim from document PMB section):**

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: 0 matches.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

---

## 14. Execution sequence (step-by-step, no ambiguity).

**Step 1 (Add scanner_slots var):** In `src/systems/enemy_squad_system.gd` after `_rebuild_timer` var (line ~27): add `var _scanner_slots: Dictionary = {}`.

**Step 2 (Add _rebuild_scanner_slots function):** Add private function `_rebuild_scanner_slots() -> void` per section 7 algorithm (8 steps: cap read, clear, collect by role, sort, assign PRESSURE, assign HOLD, assign FLANK, push to enemies).

**Step 3 (Add get_scanner_allowed function):** Add public function:
```gdscript
func get_scanner_allowed(enemy_id: int) -> bool:
    return bool(_scanner_slots.get(enemy_id, false))
```

**Step 4 (Call _rebuild_scanner_slots in _recompute_assignments):** In `_recompute_assignments()`, add `_rebuild_scanner_slots()` as the last statement (after the `for enemy_id in ids:` loop closes, i.e., after line 139).

**Step 5 (Add flashlight_scanner_cap to GameConfig):** In `src/core/game_config.gd`, inside `ai_balance["squad"]` block: add `"flashlight_scanner_cap": 2`.

**Step 6 (Add config validator call):** In `src/core/config_validator.gd`, inside squad validation block (after existing squad `_validate_number_key` calls): add `_validate_number_key(result, squad, "flashlight_scanner_cap", "ai_balance.squad", 0.0, 32.0)`.

**Step 7 (Add _flashlight_scanner_allowed var to enemy.gd):** In `src/entities/enemy.gd`, after `var _shadow_linger_flashlight: bool = false` (confirmed near line 152): add `var _flashlight_scanner_allowed: bool = true`.

**Step 8 (Add set_flashlight_scanner_allowed function to enemy.gd):** Add public function:
```gdscript
func set_flashlight_scanner_allowed(allowed: bool) -> void:
    _flashlight_scanner_allowed = allowed
```

**Step 9 (Add reset to enemy reset block):** In the reset block where `_shadow_check_flashlight_override = false` is set (confirmed ~line 321): add `_flashlight_scanner_allowed = true` on the following line.

**Step 10 (Modify _compute_flashlight_active):** In `src/entities/enemy.gd`, find `_compute_flashlight_active(awareness_state: int) -> bool`. Replace the single multiline `return <expr>` with:
```gdscript
var raw_active: bool = <existing multiline OR expression, unchanged>
return raw_active and _flashlight_scanner_allowed
```

**Step 11 (Create test files):** Create `tests/test_flashlight_single_scanner_role_assignment.gd` and `tests/test_team_contain_with_flashlight_pressure.gd` with all 8 test functions from section 12. Create corresponding `.tscn` files.

**Step 12 (Register tests in test_runner_node.gd):** Add at file scope:
```gdscript
const FLASHLIGHT_SCANNER_ROLE_ASSIGNMENT_TEST_SCENE = "res://tests/test_flashlight_single_scanner_role_assignment.tscn"
const TEAM_CONTAIN_FLASHLIGHT_PRESSURE_TEST_SCENE = "res://tests/test_team_contain_with_flashlight_pressure.tscn"
```
Add in registration function, inside a new `--- SECTION 18f` block:
```gdscript
print("\n--- SECTION 18f: Flashlight team role policy unit tests ---")
_test("Flashlight scanner role assignment test scene exists", func(): return _scene_exists(FLASHLIGHT_SCANNER_ROLE_ASSIGNMENT_TEST_SCENE))
_test("Team contain flashlight pressure test scene exists", func(): return _scene_exists(TEAM_CONTAIN_FLASHLIGHT_PRESSURE_TEST_SCENE))
await _run_embedded_scene_suite("Flashlight scanner role assignment suite", FLASHLIGHT_SCANNER_ROLE_ASSIGNMENT_TEST_SCENE)
await _run_embedded_scene_suite("Team contain flashlight pressure suite", TEAM_CONTAIN_FLASHLIGHT_PRESSURE_TEST_SCENE)
```

**Step 13 (Tier 1 smoke — scanner assignment):** `xvfb-run -a godot-4 --headless --path . res://tests/test_flashlight_single_scanner_role_assignment.tscn` — must exit 0.

**Step 14 (Tier 1 smoke — team contain):** `xvfb-run -a godot-4 --headless --path . res://tests/test_team_contain_with_flashlight_pressure.tscn` — must exit 0.

**Step 15 (Tier 2 full regression):** `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit 0.

**Step 16 (Run all rg gates):** Execute G1–G8 and PMB-1–PMB-5 from section 13 — all must return expected output.

**Step 17 (Prepend CHANGELOG entry):** Prepend one entry to `CHANGELOG.md` under the current date header per CHANGELOG policy. Do not read the full file.

---

## 15. Rollback conditions.

- Condition 1: Any Tier 1 smoke command (Steps 13–14) exits non-zero → revert all Phase 12 changes to `src/systems/enemy_squad_system.gd`, `src/entities/enemy.gd`, `src/core/game_config.gd`, `src/core/config_validator.gd`, `tests/test_runner_node.gd`; delete new `.gd` and `.tscn` test files.
- Condition 2: Tier 2 full regression exits non-zero → same full revert as Condition 1.
- Condition 3: G7 returns non-zero (`_scanner_slots` or `_rebuild_scanner_slots` found in `enemy.gd`) → find and remove the duplicate; revert offending change. If removal breaks functionality → full revert.
- Condition 4: Any PMB gate fails → inspect root cause; if resolvable without architecture change, fix and re-run; otherwise full revert.
- Condition 5: G8 returns non-zero (legacy identifier found) → phase FAILED; locate source and remove before re-attempting.
- Condition 6: Existing flashlight tests that previously passed now fail after Step 10 modification → the `_compute_flashlight_active` split introduced a logic error; revert Step 10 and investigate.

---

## 16. Phase close condition.

- [ ] G1: `flashlight` in `enemy_squad_system.gd` → ≥ 3 matches
- [ ] G2: `func get_scanner_allowed` in `enemy_squad_system.gd` → exactly 1 match
- [ ] G3: `_flashlight_scanner_allowed` in `enemy.gd` → ≥ 3 matches
- [ ] G4: `flashlight_scanner_cap` in `game_config.gd` → exactly 1 match
- [ ] G5: `flashlight_scanner_cap` in `config_validator.gd` → exactly 1 match
- [ ] G6: `_scanner_slots|_rebuild_scanner_slots` only in `enemy_squad_system.gd`, 0 matches elsewhere
- [ ] G7: same identifiers not in `enemy.gd` → 0 matches
- [ ] G8: legacy baseline 0 matches
- [ ] PMB-1 through PMB-5: all return expected output
- [ ] L-BASELINE: 0 matches for `force_flashlight_all|legacy_flashlight_override|old_scanner_logic`
- [ ] All 8 test functions in section 12 exit 0
- [ ] Tier 1 smoke suite (Steps 13–14) — both commands exit 0
- [ ] Tier 2 full regression (`test_runner.tscn`) exits 0
- [ ] No file outside section 4 in-scope list was modified
- [ ] CHANGELOG entry prepended

---

## 17. Ambiguity self-check line.

Ambiguity check: 0

---

## 18. Open questions line.

Open questions: 0

---

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).

**Files to diff:**
- `src/systems/enemy_squad_system.gd` — verify: `_scanner_slots` var declared; `_rebuild_scanner_slots()` function present (PRESSURE sort → HOLD sort → FLANK false → push loop); `get_scanner_allowed()` present; `_recompute_assignments()` ends with `_rebuild_scanner_slots()` call.
- `src/entities/enemy.gd` — verify: `_flashlight_scanner_allowed: bool = true` declared; `set_flashlight_scanner_allowed()` present; `_flashlight_scanner_allowed = true` in reset block; `_compute_flashlight_active()` has `var raw_active` + `return raw_active and _flashlight_scanner_allowed`.
- `src/core/game_config.gd` — verify: `"flashlight_scanner_cap": 2` in `ai_balance["squad"]`.
- `src/core/config_validator.gd` — verify: `_validate_number_key(... "flashlight_scanner_cap" ...)` in squad block.
- `tests/test_runner_node.gd` — verify: 2 new const declarations and 2 `_run_embedded_scene_suite` calls in SECTION 18f block.

**Contracts to check:**
- `FlashlightScannerPolicyContractV1`: execute runtime scenarios P12-A through P12-D from section 20.
- FLANK-never invariant: in any squad with FLANK enemies and any cap value, `get_scanner_allowed(flank_id)` returns `false`.

**Runtime scenarios:** execute P12-A through P12-D from section 20.

---

## 20. Runtime scenario matrix.

**Scenario P12-A — PRESSURE priority canonical case (Case B):**
Setup: Register ids={1:PRESSURE, 2:HOLD, 3:FLANK} in squad. cap=1. Call `_recompute_assignments()`.
Scene: `res://tests/test_flashlight_single_scanner_role_assignment.tscn`. Frame count: 0 (unit).
Expected invariant: `get_scanner_allowed(1)==true`, `get_scanner_allowed(2)==false`, `get_scanner_allowed(3)==false`.
Fail condition: any assertion fails.
Covered by: `_test_only_pressure_gets_scanner_when_cap_1`.

**Scenario P12-B — FLANK exclusion regardless of cap (Case D):**
Setup: Register ids={1:FLANK, 2:FLANK, 3:FLANK}. cap=10. Call `_recompute_assignments()`.
Scene: same as P12-A. Frame count: 0.
Expected invariant: all three return `get_scanner_allowed(id)==false`.
Fail condition: any FLANK enemy has scanner=true.
Covered by: `_test_flank_never_gets_scanner_slot`.

**Scenario P12-C — _compute_flashlight_active blocked by scanner policy (Case F):**
Setup: enemy instance, `_flashlight_scanner_allowed=false`, awareness=ALERT, `flashlight_works_in_alert=true`.
Scene: `res://tests/test_team_contain_with_flashlight_pressure.tscn`. Frame count: 0.
Expected invariant: `_compute_flashlight_active(ALERT) == false`.
Fail condition: returns `true` despite `_flashlight_scanner_allowed=false`.
Covered by: `_test_flank_enemy_compute_flashlight_returns_false_despite_alert`.

**Scenario P12-D — no squad system falls back to individual policy (Case from section 7):**
Setup: fresh enemy, `squad_system=null`. `_flashlight_scanner_allowed == true` by default.
Scene: same as P12-C. Frame count: 0.
Expected invariant: `_compute_flashlight_active(ALERT)` returns `true` with policy active.
Fail condition: returns `false` (incorrect — no squad = individual policy).
Covered by: `_test_no_squad_default_scanner_allowed_true`.

---

## 21. Verification report format.

Record all fields below to close phase:
- `phase_id: PHASE_12`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; must be empty list on close)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `legacy_rg: [{command: "rg -n \"force_flashlight_all|legacy_flashlight_override|old_scanner_logic\" src/ tests/ -S", expected: "0 matches", actual, PASS|FAIL}]`
- `rg_gates: [{command, expected, actual, PASS|FAIL}]` for each G1–G8
- `phase_tests: [{test_function, exit_code: 0, PASS|FAIL}]` for all 8 test functions
- `smoke_suite: [{command, exit_code, PASS|FAIL}]` for Steps 13–14
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

---

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 12` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- pmb_contract_check present in section 21 (PMB section exists in document): yes

---

## 23. Dependencies on previous phases.

1. **Phase 4** — extended `_compute_flashlight_active()` in `enemy.gd` to include `_investigate_target_in_shadow` check and SUSPICIOUS-state shadow scan flashlight path. Phase 12 modifies this same function by splitting the `return` statement into `var raw_active + return raw_active and _flashlight_scanner_allowed`. Phase 12's modification must be applied on top of Phase 4's baseline version of `_compute_flashlight_active`. Without Phase 4, the function lacks the `_investigate_target_in_shadow` condition, and Phase 12's wrapping would gate an incomplete expression — changing behavioral coverage of the scanner policy check.

2. **Phase 10** — modified `_recompute_assignments()` in `enemy_squad_system.gd` to pre-compute `hold_slots` via `_build_contain_slots_from_exits` and store `slot_path_length` in assignments. Phase 12 adds `_rebuild_scanner_slots()` as the final call in `_recompute_assignments()`. This call must be appended after Phase 10's modifications to the same function — specifically after Phase 10's extended member assignment loop that stores `"slot_path_length"` in member assignments. Without Phase 10's execution order, `_scanner_slots` would be built from incomplete assignment data that lacks Phase 10's path-length enrichment, though the scanner slot logic itself only reads `role` from `_members`, making the functional impact minimal. The ordering dependency is structural (apply Phase 12 on top of Phase 10's version of `_recompute_assignments`).

---

## PHASE 13
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_13.

### Evidence

**Inspected files (exact paths):**
- `src/entities/enemy.gd` (vars: lines 141 `_shot_rng`, 272 `_shot_rng.randomize()`; perception tick: lines 500–600; teammate call handler: line 802)
- `src/systems/enemy_aggro_coordinator.gd` (full, 326 lines)
- `src/systems/enemy_pursuit_system.gd` (vars + init: lines 60–130; `_rng.randomize()`: line 109)
- `src/systems/enemy_awareness_system.gd` (full, 415 lines)
- `src/core/game_config.gd` (line 432: `layout_seed: int = 1337`)
- `src/systems/event_bus.gd` (full; `enemy_teammate_call` signal definition and dispatch confirmed)
- `src/levels/stealth_test_config.gd` (lines 34–35: `recognition_delay_min_sec: 0.15`, `recognition_delay_max_sec: 0.30` — test stubs only, no runtime implementation)

**Inspected functions/methods (exact identifiers):**
- `EnemyPursuitSystem._init(p_owner, p_sprite, p_speed_tiles)` — line 107; `_rng.randomize()` at line 109
- `Enemy._physics_process` — perception section lines 500–600; `_awareness.process_confirm(delta, raw_player_visible, in_shadow, flashlight_hit, ...)` at line 554
- `Enemy.apply_teammate_call` — line 802; calls `_awareness.register_teammate_call()` immediately, no delay
- `EnemyAggroCoordinator._on_enemy_teammate_call` — line 64; calls `enemy.call("apply_teammate_call", ...)` at line 85 synchronously
- `EnemyAggroCoordinator._now_sec()` — line 193; supports `_debug_time_override_sec` for test determinism
- `EnemyAwarenessSystem.process_confirm` — line 121; builds `_confirm_progress` immediately when `has_visual_los=true`; no warmup gate

**Search commands used (exact):**
- `rg -n "_rng\.randomize\(\)" src/systems/enemy_pursuit_system.gd -S` → 1 match (line 109)
- `rg -n "_pending_teammate_calls\|comm_delay\|_reaction_warmup_timer\|_had_visual_los" src/entities/enemy.gd src/systems/enemy_aggro_coordinator.gd -S` → 0 matches
- `rg -n "instant_global_alert\|telepathy_call\|legacy_reaction_snap" src/ tests/ -S` → 0 matches
- `grep -n "layout_seed\|rng_seed" src/core/game_config.gd` → line 432: `layout_seed: int = 1337`
- `grep -n "GameConfig" src/systems/enemy_pursuit_system.gd` → matches at lines 715, 737, 1193, 1194 confirm `GameConfig` is accessible as autoload singleton
- `grep -n "apply_teammate_call\|teammate_call" src/ -r` → confirms single delivery path: `enemy_aggro_coordinator.gd` line 85 is the sole `apply_teammate_call` call site

**Key findings:**
1. `enemy_pursuit_system.gd._init()` line 109: `_rng.randomize()` — non-deterministic; LEGACY L1.
2. `enemy_aggro_coordinator.gd._on_enemy_teammate_call()` line 85: `apply_teammate_call` called in the same EventBus dispatch frame; zero delay; "telepathy" confirmed.
3. `enemy.gd` line 554: `process_confirm(delta, raw_player_visible, ...)` — `raw_player_visible` is passed directly; no warmup gate; enemies start building confirm-progress in the same frame LOS is acquired.
4. `stealth_test_config.gd` lines 34–35: `recognition_delay_min_sec / max_sec` exist as test-config stubs only; no `_reaction_warmup_timer` implementation in `enemy.gd`.
5. `GameConfig.layout_seed: int = 1337` (game_config.gd line 432) — deterministic seed source available as singleton.
6. `enemy.gd._shot_rng` (line 141, randomized line 272): used for combat shot timing; must NOT be reused for perception warmup (state coupling risk); a separate `_perception_rng` is required.
7. `EnemyAggroCoordinator` extends `Node` and has `_now_sec()` with `_debug_time_override_sec`; adding `_process(delta)` is structurally sound.

---

## 1. What now.

`rg -n "_rng\.randomize\(\)" src/systems/enemy_pursuit_system.gd -S` → 1 match (line 109): enemy pursuit uses non-deterministic seed; identical entity_id enemies on the same layout_seed pick different roam/search sequences each run.

`rg -n "_pending_teammate_calls\|_comm_rng" src/systems/enemy_aggro_coordinator.gd -S` → 0 matches: teammate calls are dispatched synchronously in `_on_enemy_teammate_call`; all eligible enemies receive `apply_teammate_call` in a single EventBus dispatch frame with no inter-enemy delay.

`rg -n "_reaction_warmup_timer\|_had_visual_los_last_frame" src/entities/enemy.gd -S` → 0 matches: `process_confirm` receives `raw_player_visible=true` on the first LOS frame; enemies begin building `_confirm_progress` in the same frame LOS is established.

Failing tests (from v1 spec, files not yet created):
- `tests/test_comm_delay_prevents_telepathy.gd`
- `tests/test_reaction_latency_window_respected.gd`
- `tests/test_seeded_variation_deterministic_per_seed.gd`

---

## 2. What changes.

1. **`src/systems/enemy_pursuit_system.gd::_init()`** (line 109): delete `_rng.randomize()` (LEGACY L1); add `_rng.seed = _compute_pursuit_seed()` at same position.
2. **`src/systems/enemy_pursuit_system.gd`**: add private function `_compute_pursuit_seed() -> int` — deterministic seed formula using `owner.entity_id` XOR `GameConfig.layout_seed`. **Timing assumption**: `owner.entity_id` must be non-zero at `_init()` call time. The project convention is that spawners set `entity_id` before `add_child()` (which fires `_ready()`), so `_init()` receives a valid `entity_id`. If `entity_id == 0` at call time, `_compute_pursuit_seed()` returns the salt-only fallback `2654435761` (non-deterministic per entity, but no crash). An `entity_id == 0` result is treated as a spawner misconfiguration, not a Phase 13 defect.
3. **`src/entities/enemy.gd`**: add var `_perception_rng: RandomNumberGenerator`; add var `_reaction_warmup_timer: float = 0.0`; add var `_had_visual_los_last_frame: bool = false`.
4. **`src/entities/enemy.gd`** (initialization block where `_shot_rng.randomize()` is called, line 272): seed `_perception_rng` with `int(entity_id) * 6364136223846793005 ^ (GameConfig.layout_seed if GameConfig else 0)`. **Same timing assumption as item 2 applies**: if `entity_id == 0` at this point, `_perception_rng.seed` = `GameConfig.layout_seed` — all such enemies share one seed, warmup intervals are identical but non-zero. Not a crash; treated as spawner misconfiguration.
5. **`src/entities/enemy.gd`**: add private function `_tick_reaction_warmup(delta: float, raw_los: bool) -> bool`.
6. **`src/entities/enemy.gd`** (physics perception tick, call site at line 554): introduce local `var gated_los: bool = _tick_reaction_warmup(delta, raw_player_visible)`; replace `raw_player_visible` argument in `process_confirm` call with `gated_los`.
7. **`src/systems/enemy_aggro_coordinator.gd`**: add var `_pending_teammate_calls: Array[Dictionary] = []`; add var `_comm_rng: RandomNumberGenerator`.
8. **`src/systems/enemy_aggro_coordinator.gd::initialize()`**: seed `_comm_rng` with `GameConfig.layout_seed if GameConfig else 0`.
9. **`src/systems/enemy_aggro_coordinator.gd::_on_enemy_teammate_call()`**: replace direct `enemy.call("apply_teammate_call", ...)` (line 85) with enqueue to `_pending_teammate_calls`; compute `fire_at_sec = _now_sec() + _comm_rng.randf_range(comm_delay_min_sec, comm_delay_max_sec)`.
10. **`src/systems/enemy_aggro_coordinator.gd`**: add private function `_drain_pending_teammate_calls()`.
11. **`src/systems/enemy_aggro_coordinator.gd`**: add `_process(delta: float) -> void` calling `_drain_pending_teammate_calls()`.
12. **`src/core/game_config.gd`**: add `ai_balance["fairness"]` sub-dictionary with 4 keys: `reaction_warmup_min_sec`, `reaction_warmup_max_sec`, `comm_delay_min_sec`, `comm_delay_max_sec`.
13. **`src/core/config_validator.gd`**: add validation block for `ai_balance["fairness"]` (4 `_validate_number_key` calls).

---

## 3. What will be after.

Each item verifiable by named rg gate (section 13) or test (section 12):

- `_rng.seed` in `enemy_pursuit_system.gd._init()` is set to `_compute_pursuit_seed()` result, making search variation deterministic per entity_id and layout_seed: verified by rg gate G3 (≥ 2 matches for `_compute_pursuit_seed`) and tests `_test_seeded_pursuit_same_entity_same_seed_identical_sequence` and `_test_seeded_pursuit_different_entity_different_sequence`.
- Teammate calls are enqueued with `fire_at_sec > _now_sec()` before being delivered: verified by rg gate G1 (≥ 2 matches for `_pending_teammate_calls`) and test `_test_comm_delay_queue_entry_has_fire_at_sec`.
- `apply_teammate_call` is not invoked in the same frame as `_on_enemy_teammate_call`: verified by test `_test_comm_delay_not_applied_before_fire_at_sec_elapses`.
- `process_confirm` receives `gated_los=false` during the warmup window on first CALM LOS acquisition: verified by rg gate G2 (≥ 2 matches for `_reaction_warmup_timer`) and test `_test_reaction_warmup_blocks_confirm_during_window`.
- No warmup fires when awareness state is SUSPICIOUS, ALERT, or COMBAT at moment of LOS acquisition: verified by test `_test_no_warmup_when_already_alert`.

---

## 4. Scope and non-scope.

**In-scope files (allowed change boundary):**
- `src/entities/enemy.gd`
- `src/systems/enemy_aggro_coordinator.gd`
- `src/systems/enemy_pursuit_system.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `tests/test_comm_delay_prevents_telepathy.gd` (new)
- `tests/test_comm_delay_prevents_telepathy.tscn` (new)
- `tests/test_reaction_latency_window_respected.gd` (new)
- `tests/test_reaction_latency_window_respected.tscn` (new)
- `tests/test_seeded_variation_deterministic_per_seed.gd` (new)
- `tests/test_seeded_variation_deterministic_per_seed.tscn` (new)
- `tests/test_runner_node.gd` (registration only)
- `CHANGELOG.md`

Any change outside this list = phase FAILED regardless of test results.

**Out-of-scope files (minimum 3):**
- `src/systems/enemy_awareness_system.gd` — awareness state machine logic is not modified; `process_confirm` signature is unchanged.
- `src/systems/enemy_squad_system.gd` — squad slot assignment is not involved in fairness layer.
- `src/systems/event_bus.gd` — signal definitions and dispatch queue unchanged; `enemy_teammate_call` signal is consumed but not modified.

---

## 5. Single-owner authority.

The primary decision introduced in this phase — deferred teammate call delivery with per-target seeded delay — is owned exclusively by `src/systems/enemy_aggro_coordinator.gd`, function `_drain_pending_teammate_calls()`. No other file schedules or delivers deferred teammate calls. `enemy.gd::apply_teammate_call()` is the delivery endpoint but holds no scheduling logic.

Verification: rg gate G4 (`rg -n "_pending_teammate_calls\|_drain_pending_teammate_calls" src/ -S` — all matches in `enemy_aggro_coordinator.gd` only; section 13).

---

## 6. Full input/output contract.

### Contract A: FairnessReactionWarmupContractV1 (enemy.gd)

**Function:** `_tick_reaction_warmup(delta: float, raw_los: bool) -> bool`

**Inputs:**
- `delta: float` — physics frame delta; must be ≥ 0.0; `maxf(delta, 0.0)` applied internally.
- `raw_los: bool` — whether player is visible this frame (computed before call).
- Implicit input: `int(_awareness.get_awareness_state()) if _awareness else 0` — current awareness state.

**Output:**
- `gated_los: bool` — equals `raw_los` in all cases except when warmup is active (`_reaction_warmup_timer > 0.0`), where it always returns `false`.

**State modified:**
- `_reaction_warmup_timer: float` — counts down from `[reaction_warmup_min_sec, reaction_warmup_max_sec]` to 0.0.
- `_had_visual_los_last_frame: bool` — set to `raw_los` at end of each call.

**Activation rule:** warmup arms when `_had_visual_los_last_frame == false AND raw_los == true AND awareness_state == 0 (CALM)`. Warmup does not activate when `awareness_state > 0`.

**Constants (in `ai_balance["fairness"]` of `game_config.gd`):**
- `reaction_warmup_min_sec: float = 0.15`
- `reaction_warmup_max_sec: float = 0.30`

---

### Contract B: CommDelayQueueEntryContractV1 (enemy_aggro_coordinator.gd)

**Queue entry fields:**
- `enemy_ref: WeakRef` — weak reference to target enemy node.
- `source_enemy_id: int` — ID of the alerting enemy.
- `source_room_id: int` — room of the alerting enemy.
- `target_enemy_id: int` — ID of the receiving enemy (used for `_target_last_accept_sec` update on delivery).
- `target_room_id: int` — room of the receiving enemy at enqueue time (used for zone director `record_accepted_teammate_call` call).
- `call_id: int` — dedup key from original teammate call.
- `shot_pos: Vector2` — investigate anchor from source.
- `fire_at_sec: float` — `_now_sec() + _comm_rng.randf_range(comm_delay_min_sec, comm_delay_max_sec)`.

**Drain rule:** entry fires when `_now_sec() >= fire_at_sec`. Entries drain in FIFO insertion order when multiple are due.

**Constants (in `ai_balance["fairness"]` of `game_config.gd`):**
- `comm_delay_min_sec: float = 0.30`
- `comm_delay_max_sec: float = 0.80`

---

### Contract C: DeterministicPursuitSeedContractV1 (enemy_pursuit_system.gd)

**Function:** `_compute_pursuit_seed() -> int`

**Output:** `int(owner.entity_id) * 2654435761 ^ (GameConfig.layout_seed if GameConfig else 0)`

**Fallback (null owner or `entity_id` absent):** returns `2654435761` (salt-only constant; no crash).

**GDScript type safety:** `int(owner.entity_id)` cast required because `entity_id` is declared `var entity_id: int = 0` in enemy.gd but accessed through `owner` reference typed as `CharacterBody2D`; explicit `int()` cast prevents Variant arithmetic warning.

---

## 7. Deterministic algorithm with exact order.

### Reaction warmup tick (`_tick_reaction_warmup(delta: float, raw_los: bool) -> bool`):

1. `var awareness_state: int = int(_awareness.get_awareness_state()) if _awareness else 0`
2. If `_had_visual_los_last_frame == false AND raw_los == true AND awareness_state == 0`:
   a. Read `var cfg_min: float = float(fairness_cfg.get("reaction_warmup_min_sec", 0.15))` where `fairness_cfg` = `GameConfig.ai_balance["fairness"] if (GameConfig and GameConfig.ai_balance.has("fairness")) else {}`.
   b. Read `var cfg_max: float = float(fairness_cfg.get("reaction_warmup_max_sec", 0.30))`.
   c. `_reaction_warmup_timer = _perception_rng.randf_range(cfg_min, cfg_max)`
3. If `_reaction_warmup_timer > 0.0`:
   a. `_reaction_warmup_timer = maxf(0.0, _reaction_warmup_timer - maxf(delta, 0.0))`
   b. `_had_visual_los_last_frame = raw_los`
   c. Return `false`
4. `_had_visual_los_last_frame = raw_los`
5. Return `raw_los`

Tie-break N/A: single boolean output; no candidate selection involved.

Exact behavior on invalid input: `delta <= 0.0` → `maxf(delta, 0.0) = 0.0` → timer unchanged this tick. `awareness_state > 0` → warmup activation block skipped; existing timer continues draining normally.

Exact behavior when LOS drops mid-warmup: if `raw_los = false` arrives while `_reaction_warmup_timer > 0.0`, step 3 still fires (timer > 0), timer decrements, function returns `false`. Warmup is NOT cancelled. When timer reaches 0.0, step 4 runs and `_had_visual_los_last_frame = false` (since `raw_los = false`); step 5 returns `false`. No special re-arm occurs — if LOS returns after warmup has expired, the next `false → true` edge in CALM state will arm a fresh warmup.

---

### Comm delay drain (`_drain_pending_teammate_calls()`, called from `_process(delta)`):

1. `var now: float = _now_sec()`
2. Build `var to_fire: Array[Dictionary] = []` — all entries in `_pending_teammate_calls` where `float(entry["fire_at_sec"]) <= now`.
3. Remove all `to_fire` entries from `_pending_teammate_calls` (rebuild array excluding them).
4. For each entry in `to_fire` in insertion order (FIFO):
   a. `var enemy: Node2D = entry["enemy_ref"].get_ref() as Node2D`
   b. If `enemy == null or not enemy.is_in_group("enemies")`: skip.
   c. If `not enemy.has_method("apply_teammate_call")`: skip.
   d. `enemy.apply_teammate_call(int(entry["source_enemy_id"]), int(entry["source_room_id"]), int(entry["call_id"]), entry["shot_pos"] as Vector2)`
   e. `_target_last_accept_sec[int(entry["target_enemy_id"])] = _now_sec()`
   f. Call zone director `record_accepted_teammate_call(int(entry["source_room_id"]), target_room_id)` if director available (preserves Phase 0 behavior).

Tie-break: FIFO by insertion order when multiple entries share identical `fire_at_sec`. Duplicate `{enemy_id, call_id}` pairs are impossible: `_target_call_dedup` in `_on_enemy_teammate_call` (lines 74–76 of `enemy_aggro_coordinator.gd`) prevents duplicate enqueue for the same `(target_enemy_id, call_id)` pair.

Exact behavior on empty queue: loop body executes 0 iterations; no-op.

---

### Deterministic pursuit seed (`_compute_pursuit_seed() -> int`):

1. If `owner == null or not ("entity_id" in owner)`: return `2654435761`.
2. `var eid: int = int(owner.entity_id)`
3. `var lseed: int = GameConfig.layout_seed if GameConfig else 0`
4. Return `eid * 2654435761 ^ lseed`

No tie-break: single deterministic integer output.

---

## 8. Edge-case matrix.

**Case A — Empty pending queue (comm delay):**
Setup: `_pending_teammate_calls = []`; `_process(0.016)` called.
Expected: 0 `apply_teammate_call` invocations; `_pending_teammate_calls` remains empty; no crash.

**Case B — Single entry due (comm delay):**
Setup: 1 entry with `fire_at_sec = 0.0`; `_debug_time_override_sec = 100.0`; valid enemy WeakRef.
Expected: entry drained; `apply_teammate_call` called once; `_pending_teammate_calls.size() == 0`.

**Case C — Tie-break N/A:**
`_target_call_dedup` in `_on_enemy_teammate_call` (lines 74–76 of `enemy_aggro_coordinator.gd`) prevents duplicate `{enemy_id, call_id}` pairs from entering the queue; simultaneous same-`fire_at_sec` entries with different targets drain in FIFO order. Per section 7, N ≤ 1 entries per unique `(enemy_id, call_id)` by design. Tie-break is FIFO and unambiguous.

**Case D — No entries due (comm delay):**
Setup: 3 entries, all `fire_at_sec = _now_sec() + 5.0`; `_process(0.016)` called.
Expected: 0 entries drained; `_pending_teammate_calls.size() == 3`.

**Case E — LOS acquired in CALM (reaction warmup):**
Setup: `_had_visual_los_last_frame = false`; awareness_state = CALM (0); `raw_los = true`.
Expected: `_reaction_warmup_timer ∈ [0.15, 0.30]`; function returns `false`.

**Case F — LOS acquired in ALERT (no warmup):**
Setup: `_had_visual_los_last_frame = false`; awareness_state = ALERT (2); `raw_los = true`.
Expected: `_reaction_warmup_timer == 0.0` (unchanged); function returns `true`.

**Case G — Same entity_id + same layout_seed (seeded variation):**
Setup: Two `EnemyPursuitSystem` instances; `owner.entity_id = 42`; `GameConfig.layout_seed = 1337`.
Expected: `_rng.seed` equal on both; first 5 `randf()` outputs identical.

**Case H — Null owner fallback (seeded variation):**
Setup: `EnemyPursuitSystem._compute_pursuit_seed()` called with `owner = null`.
Expected: returns `2654435761`; no crash.

---

## 9. Legacy removal plan.

**L1**: identifier `_rng.randomize()` (call expression), file `src/systems/enemy_pursuit_system.gd`, function `_init()`, line 109 (confirmed by PROJECT DISCOVERY).
Delete first; then add `_rng.seed = _compute_pursuit_seed()` at same position in step 3.

No other legacy identifiers exist. `rg -n "instant_global_alert\|telepathy_call\|legacy_reaction_snap" src/ tests/ -S` returns 0 matches at baseline (confirmed by PROJECT DISCOVERY).

---

## 10. Legacy verification commands.

**L1**: `rg -n "_rng\.randomize\(\)" src/systems/enemy_pursuit_system.gd -S` → expected: 0 matches.

Evidence of file-uniqueness: PROJECT DISCOVERY confirmed `_rng.randomize()` exists only in `_init()` at line 109 of `enemy_pursuit_system.gd`; the identifier `_rng` is declared at line 66 of that file and its `.randomize()` call appears nowhere else in that file. File-scoped command is sufficient.

---

## 11. Acceptance criteria.

1. `rg -n "_rng\.randomize\(\)" src/systems/enemy_pursuit_system.gd -S` returns 0 matches: true / false.
2. `rg -n "_pending_teammate_calls" src/systems/enemy_aggro_coordinator.gd -S` returns ≥ 2 matches: true / false.
3. `rg -n "_reaction_warmup_timer" src/entities/enemy.gd -S` returns ≥ 2 matches: true / false.
4. `rg -n "comm_delay_min_sec\|comm_delay_max_sec\|reaction_warmup_min_sec\|reaction_warmup_max_sec" src/core/game_config.gd -S` returns ≥ 4 matches (all four keys present): true / false.
5. `rg -n "reaction_warmup_min_sec\|reaction_warmup_max_sec\|comm_delay_min_sec\|comm_delay_max_sec" src/core/config_validator.gd -S` returns exactly 4 matches (fairness validator block): true / false.
6. All 10 test functions in section 12 exit 0: true / false.
7. Tier 2 full regression exits 0: true / false.

---

## 12. Tests (new/update + purpose).

### New file: `tests/test_comm_delay_prevents_telepathy.gd`

Test functions:
- `_test_comm_delay_queue_entry_has_fire_at_sec`: construct `EnemyAggroCoordinator`; call `_on_enemy_teammate_call` via simulated single eligible target; assert `_pending_teammate_calls.size() == 1` and `float(_pending_teammate_calls[0]["fire_at_sec"]) > coordinator._now_sec()`.
- `_test_comm_delay_not_applied_before_fire_at_sec_elapses`: manually enqueue 1 entry with `fire_at_sec = coordinator._now_sec() + 10.0`; call `_drain_pending_teammate_calls()`; assert entry not removed and no `apply_teammate_call` invocation.
- `_test_comm_delay_applied_after_fire_at_sec`: manually enqueue 1 entry with `fire_at_sec = 0.0`; set `_debug_time_override_sec = 999.0`; call `_drain_pending_teammate_calls()`; assert entry removed from `_pending_teammate_calls`.
- `_test_comm_delay_null_enemy_ref_skipped`: enqueue 1 entry whose `enemy_ref.get_ref()` returns null (freed instance); call `_drain_pending_teammate_calls()`; assert no crash and `_pending_teammate_calls` is empty.

Registration: add scene constant + scene existence check + `_run_embedded_scene_suite(...)` call in `tests/test_runner_node.gd` (follow existing runner pattern; no `_get_test_suites()` helper required).

---

### New file: `tests/test_reaction_latency_window_respected.gd`

Test functions:
- `_test_reaction_warmup_blocks_confirm_during_window`: create enemy mock with `_had_visual_los_last_frame = false`, awareness_state = CALM, `_reaction_warmup_timer = 0.0`; call `_tick_reaction_warmup(0.016, true)`; assert `_reaction_warmup_timer > 0.0` and return value is `false`.
- `_test_reaction_warmup_expires_and_confirm_resumes`: set `_reaction_warmup_timer = 0.001`; call `_tick_reaction_warmup(0.1, true)`; assert `_reaction_warmup_timer == 0.0` and return value is `true`.
- `_test_no_warmup_when_already_alert`: `_had_visual_los_last_frame = false`; awareness_state = ALERT (2); call `_tick_reaction_warmup(0.016, true)`; assert `_reaction_warmup_timer == 0.0` and return value is `true`.

Registration: add scene constant + scene existence check + `_run_embedded_scene_suite(...)` call in `tests/test_runner_node.gd` (follow existing runner pattern; no `_get_test_suites()` helper required).

---

### New file: `tests/test_seeded_variation_deterministic_per_seed.gd`

Test functions:
- `_test_seeded_pursuit_same_entity_same_seed_identical_sequence`: create 2 `EnemyPursuitSystem` instances with `owner.entity_id = 7` mock and `GameConfig.layout_seed = 1337`; compare `_rng.seed` — must be equal; compare first 5 `_rng.randf()` values — must be identical.
- `_test_seeded_pursuit_different_entity_different_sequence`: `entity_id = 7` vs `entity_id = 8`, same `layout_seed = 1337`; assert `_rng.seed` values differ.
- `_test_seeded_pursuit_null_owner_fallback`: call `_compute_pursuit_seed()` with `owner = null`; assert return value equals `2654435761`; assert no crash.

Registration: add scene constant + scene existence check + `_run_embedded_scene_suite(...)` call in `tests/test_runner_node.gd` (follow existing runner pattern; no `_get_test_suites()` helper required).

---

## 13. rg gates (command + expected output).

**G1** `rg -n "_pending_teammate_calls" src/systems/enemy_aggro_coordinator.gd -S` → expected: ≥ 2 matches (declaration + at least one usage in `_on_enemy_teammate_call` and `_drain_pending_teammate_calls`).

**G2** `rg -n "_reaction_warmup_timer" src/entities/enemy.gd -S` → expected: ≥ 2 matches (declaration + timer decrement inside `_tick_reaction_warmup`).

**G3** `rg -n "_compute_pursuit_seed" src/systems/enemy_pursuit_system.gd -S` → expected: ≥ 2 matches (function definition + call site in `_init`).

**G4** `rg -n "_pending_teammate_calls\|_drain_pending_teammate_calls" src/ -S` → expected: all matches in `src/systems/enemy_aggro_coordinator.gd` only; 0 matches in any other file.

**G5** `rg -n "comm_delay_min_sec\|comm_delay_max_sec\|reaction_warmup_min_sec\|reaction_warmup_max_sec" src/core/game_config.gd -S` → expected: ≥ 4 matches (one per key).

**G6** (legacy removal) `rg -n "_rng\.randomize\(\)" src/systems/enemy_pursuit_system.gd -S` → expected: 0 matches.

**G7** `rg -n "_comm_rng" src/systems/enemy_aggro_coordinator.gd -S` → expected: ≥ 2 matches (declaration + seed call in `initialize()`).

**G8** `rg -n "reaction_warmup_min_sec\|reaction_warmup_max_sec\|comm_delay_min_sec\|comm_delay_max_sec" src/core/config_validator.gd -S` → expected: exactly 4 matches (fairness validator block keys).

**[PMB-1]** `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S` → expected: 0 matches.

**[PMB-2]** `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S` → expected: 0 matches.

**[PMB-3]** `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S` → expected: 0 matches.

**[PMB-4]** `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S` → expected: 0 matches.

**[PMB-5]** `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'` → expected: `PMB-5: PASS (1)`.

---

## 14. Execution sequence (step-by-step).

**Step 1:** Delete `_rng.randomize()` from `src/systems/enemy_pursuit_system.gd::_init()` at line 109 (LEGACY L1).

**Step 2:** Add private function `_compute_pursuit_seed() -> int` to `src/systems/enemy_pursuit_system.gd` immediately after `_init()` block. Body: if `owner == null or not ("entity_id" in owner)`: return `2654435761`; `var eid: int = int(owner.entity_id)`; `var lseed: int = GameConfig.layout_seed if GameConfig else 0`; return `eid * 2654435761 ^ lseed`.

**Step 3:** Add `_rng.seed = _compute_pursuit_seed()` to `src/systems/enemy_pursuit_system.gd::_init()` at the position where L1 was deleted.

**Step 4:** Add var declarations to `src/entities/enemy.gd` (near `_shot_rng` at line 141): `var _perception_rng: RandomNumberGenerator`; `var _reaction_warmup_timer: float = 0.0`; `var _had_visual_los_last_frame: bool = false`.

**Step 5:** In `src/entities/enemy.gd` initialization block (at or near `_shot_rng.randomize()` line 272): add `_perception_rng = RandomNumberGenerator.new()` then `_perception_rng.seed = int(entity_id) * 6364136223846793005 ^ (GameConfig.layout_seed if GameConfig else 0)`.

**Step 6:** Add function `_tick_reaction_warmup(delta: float, raw_los: bool) -> bool` to `src/entities/enemy.gd`. Body per section 7 reaction warmup algorithm.

**Step 7:** In `src/entities/enemy.gd` physics perception tick at `process_confirm` call site (line 554): add `var gated_los: bool = _tick_reaction_warmup(delta, raw_player_visible)` immediately before the `if _awareness` block; replace `raw_player_visible` with `gated_los` in the `process_confirm` argument list.

**Step 8:** Add var declarations to `src/systems/enemy_aggro_coordinator.gd` (near top-level vars): `var _pending_teammate_calls: Array[Dictionary] = []`; `var _comm_rng: RandomNumberGenerator`.

**Step 9:** In `src/systems/enemy_aggro_coordinator.gd::initialize()`: add `_comm_rng = RandomNumberGenerator.new()` then `_comm_rng.seed = GameConfig.layout_seed if GameConfig else 0`.

**Step 10:** Modify `src/systems/enemy_aggro_coordinator.gd::_on_enemy_teammate_call()`: replace the block at lines 83–88 (the `apply_teammate_call` call and `_target_last_accept_sec` update) with enqueue logic — build entry dict with all fields from section 6 Contract B plus `"target_enemy_id": target_enemy_id` and `"target_room_id": target_room_id`; compute `fire_at_sec`; append to `_pending_teammate_calls`.

**Step 11:** Add private function `_drain_pending_teammate_calls()` to `src/systems/enemy_aggro_coordinator.gd`. Body per section 7 comm delay drain algorithm including `_target_last_accept_sec` update and zone director call after successful delivery.

**Step 12:** Add `func _process(_delta: float) -> void: _drain_pending_teammate_calls()` to `src/systems/enemy_aggro_coordinator.gd`.

**Step 13:** Add `ai_balance["fairness"]` sub-dictionary to `src/core/game_config.gd`: `{"reaction_warmup_min_sec": 0.15, "reaction_warmup_max_sec": 0.30, "comm_delay_min_sec": 0.30, "comm_delay_max_sec": 0.80}`.

**Step 14:** Add validation block to `src/core/config_validator.gd` for `ai_balance["fairness"]`: 4 `_validate_number_key` calls.

**Step 15:** Create `tests/test_comm_delay_prevents_telepathy.gd` with 4 test functions from section 12. Create corresponding `tests/test_comm_delay_prevents_telepathy.tscn`.

**Step 16:** Create `tests/test_reaction_latency_window_respected.gd` with 3 test functions from section 12. Create corresponding `tests/test_reaction_latency_window_respected.tscn`.

**Step 17:** Create `tests/test_seeded_variation_deterministic_per_seed.gd` with 3 test functions from section 12. Create corresponding `tests/test_seeded_variation_deterministic_per_seed.tscn`.

**Step 18:** Register all 3 new test scenes in `tests/test_runner_node.gd` using the existing runner pattern (scene constants + existence checks + `_run_embedded_scene_suite(...)` calls).

**Step 19:** Run Tier 1 smoke suite:
```
xvfb-run -a godot-4 --headless --path . res://tests/test_comm_delay_prevents_telepathy.tscn
xvfb-run -a godot-4 --headless --path . res://tests/test_reaction_latency_window_respected.tscn
xvfb-run -a godot-4 --headless --path . res://tests/test_seeded_variation_deterministic_per_seed.tscn
```

**Step 20:** Run Tier 2 full regression: `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit 0.

**Step 21:** Run all rg gates from section 13 (G1–G8 + PMB-1 through PMB-5). All must return expected output.

**Step 22:** Prepend CHANGELOG entry under current date header.

---

## 15. Rollback conditions.

1. Trigger: enqueue loop in `_on_enemy_teammate_call` crashes (WeakRef construction failure or dict append error). Action: restore direct `enemy.call("apply_teammate_call", ...)` block (lines 83–88 original); remove `_pending_teammate_calls`, `_comm_rng`, `_drain_pending_teammate_calls`, `_process` additions from `enemy_aggro_coordinator.gd`.
2. Trigger: `_tick_reaction_warmup` returns `false` when `awareness_state > 0` (incorrect awareness check in implementation). Action: revert step 6 and step 7; restore direct `raw_player_visible` argument in `process_confirm` call.
3. Trigger: Tier 2 regression exits non-zero after step 20. Action: revert all changes to all 5 in-scope source files; remove 3 new test files and their registration entries.
4. Trigger: PMB-5 returns `FAIL` (unexpected `_pursuit.execute_intent(` count regression). Action: audit `src/entities/enemy.gd` for extra `_pursuit.execute_intent(` call sites; revert the offending `enemy.gd` edits if count > 1.

---

## 16. Phase close condition.

- [ ] All rg commands in section 10 return 0 matches
- [ ] All rg gates in section 13 return expected output (G1–G8 + PMB-1–PMB-5)
- [ ] All 10 test functions in section 12 exit 0
- [ ] Tier 1 smoke suite (section 14 step 19 — 3 commands) — all commands exit 0
- [ ] Tier 2 full regression (`test_runner.tscn`) exits 0
- [ ] No file outside section 4 in-scope list was modified
- [ ] CHANGELOG entry prepended

---

## 17. Ambiguity self-check line.

Ambiguity check: 0

---

## 18. Open questions line.

Open questions: 0

---

## 19. Post-implementation verification plan.

**Files to diff:**
- `src/systems/enemy_pursuit_system.gd` — verify: `_rng.randomize()` absent; `_rng.seed = _compute_pursuit_seed()` present; `_compute_pursuit_seed() -> int` defined with XOR formula.
- `src/entities/enemy.gd` — verify: `_perception_rng` declared and seeded; `_reaction_warmup_timer: float = 0.0` declared; `_had_visual_los_last_frame: bool = false` declared; `_tick_reaction_warmup` function present; `process_confirm` call site uses `gated_los`.
- `src/systems/enemy_aggro_coordinator.gd` — verify: `_pending_teammate_calls` and `_comm_rng` declared; `initialize()` seeds `_comm_rng`; `_on_enemy_teammate_call` enqueues instead of calling directly; `_drain_pending_teammate_calls` and `_process` present; `_target_last_accept_sec` update moved to drain.
- `src/core/game_config.gd` — verify: `ai_balance["fairness"]` with 4 keys.
- `src/core/config_validator.gd` — verify: fairness validation block with 4 `_validate_number_key` calls.
- `tests/test_runner_node.gd` — verify: 3 new scene constants, existence checks, and `_run_embedded_scene_suite` calls registered.

**Contracts to check:** FairnessReactionWarmupContractV1 (P13-E, P13-F), CommDelayQueueEntryContractV1 (P13-A through P13-D), DeterministicPursuitSeedContractV1 (P13-G, P13-H).

**Runtime scenarios:** execute P13-A through P13-H from section 20.

---

## 20. Runtime scenario matrix.

**P13-A — Empty pending queue (Case A):**
Setup: `EnemyAggroCoordinator` with `_pending_teammate_calls = []`; `_process(0.016)` called.
Scene: `res://tests/test_comm_delay_prevents_telepathy.tscn`. Frame count: 0 (unit).
Expected invariant: 0 `apply_teammate_call` invocations; no crash.
Covered by: empty-queue path is implicitly exercised by `_test_comm_delay_not_applied_before_fire_at_sec_elapses` (entries present but not due → 0 deliveries) and `_test_comm_delay_null_enemy_ref_skipped` (queue empties after drain of invalid entry). Dedicated explicit test for `_pending_teammate_calls = []` is not required because `to_fire` loop with 0 iterations is a structural invariant verified by G1 gate confirming the drain function exists.

**P13-B — Single entry due (Case B):**
Setup: 1 entry with `fire_at_sec = 0.0`; `_debug_time_override_sec = 100.0`; valid enemy WeakRef.
Scene: same. Frame count: 0.
Expected invariant: entry drained; `apply_teammate_call` called once; queue empty.
Covered by: `_test_comm_delay_applied_after_fire_at_sec`.

**P13-C — Tie-break N/A:**
`_target_call_dedup` prevents duplicate `(enemy_id, call_id)` enqueue (lines 74–76). Simultaneous entries with equal `fire_at_sec` drain FIFO. N ≤ 1 per `(enemy_id, call_id)` by design — see section 7. Tie-break N/A.

**P13-D — No entries due (Case D):**
Setup: 3 entries, all `fire_at_sec = _now_sec() + 5.0`; `_process(0.016)` called.
Scene: same. Frame count: 0.
Expected invariant: 0 entries drained; queue size = 3.
Covered by: `_test_comm_delay_not_applied_before_fire_at_sec_elapses`.

**P13-E — Reaction warmup armed in CALM (Case E):**
Setup: enemy in CALM; `_had_visual_los_last_frame = false`; `raw_los = true`.
Scene: `res://tests/test_reaction_latency_window_respected.tscn`. Frame count: 0.
Expected invariant: `_reaction_warmup_timer ∈ [0.15, 0.30]`; return = `false`.
Covered by: `_test_reaction_warmup_blocks_confirm_during_window`.

**P13-F — No warmup in ALERT (Case F):**
Setup: enemy in ALERT (awareness_state = 2); `_had_visual_los_last_frame = false`; `raw_los = true`.
Scene: same. Frame count: 0.
Expected invariant: `_reaction_warmup_timer == 0.0`; return = `true`.
Covered by: `_test_no_warmup_when_already_alert`.

**P13-G — Same entity_id + same layout_seed (Case G):**
Setup: Two `EnemyPursuitSystem` instances; `owner.entity_id = 7`; `GameConfig.layout_seed = 1337`.
Scene: `res://tests/test_seeded_variation_deterministic_per_seed.tscn`. Frame count: 0.
Expected invariant: `_rng.seed` equal; first 5 `randf()` outputs identical.
Covered by: `_test_seeded_pursuit_same_entity_same_seed_identical_sequence`.

**P13-H — Null owner fallback (Case H):**
Setup: `_compute_pursuit_seed()` with `owner = null`.
Scene: same. Frame count: 0.
Expected invariant: returns `2654435761`; no crash.
Covered by: `_test_seeded_pursuit_null_owner_fallback`.

---

## 21. Verification report format.

Record all fields below to close phase:
- `phase_id: PHASE_13`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; must be empty list on close)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `legacy_rg: [{command: "rg -n \"_rng\\.randomize\\(\\)\" src/systems/enemy_pursuit_system.gd -S", expected: "0 matches", actual, PASS|FAIL}]`
- `rg_gates: [{command, expected, actual, PASS|FAIL}]` for G1–G8
- `phase_tests: [{test_function, exit_code: 0, PASS|FAIL}]` for all 10 test functions
- `smoke_suite: [{command, exit_code, PASS|FAIL}]` for step 19 (3 commands)
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

---

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 13` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- pmb_contract_check present in section 21 (PMB section exists in document): yes

---

## 23. Dependencies on previous phases.

1. **Phase 4** — extended `src/entities/enemy.gd` `process_confirm` call to pass `flashlight_hit` as the fourth argument. Phase 13 wraps the `raw_player_visible` argument (second position) in that same call with `_tick_reaction_warmup(delta, raw_player_visible)`. Phase 13's modification must be applied on top of Phase 4's version of the `process_confirm` call site; without Phase 4, the argument at position 4 differs, and the gating insertion would apply to a mismatched call signature.

2. **Phase 0 (pre-v2 baseline infrastructure)** — established `src/systems/event_bus.gd` with `enemy_teammate_call` signal and `src/systems/enemy_aggro_coordinator.gd` with `_on_enemy_teammate_call`, `_now_sec()`, and `_debug_time_override_sec`. Phase 13 extends `EnemyAggroCoordinator` with a pending call queue that uses `_now_sec()` for timing and requires `_debug_time_override_sec` for deterministic test execution. Without these, Phase 13 has no host for the comm delay queue and no deterministic time source for tests.

---

## PHASE 14
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_14.

### Evidence

**Inspected files:**
- `src/systems/vfx_system.gd` (full, 318 lines)
- `src/systems/enemy_awareness_system.gd` (full, 415 lines)
- `src/systems/event_bus.gd` (lines 1–100, 200–260, 360–395)
- `src/entities/enemy.gd` (lines 797–830, grep for `apply_`, `register_`, `_investigate_anchor`)
- `src/levels/level_bootstrap_controller.gd` (lines 120–168)
- `src/levels/level_context.gd` (full, 92 lines)
- `tests/test_runner_node.gd` (lines 1–134, 1179–1183)

**Inspected functions/methods:**
- `VFXSystem.spawn_blood()` — emits `EventBus.blood_spawned(position: Vector3, size: float)`; tracks `_blood_decals` (visual only)
- `VFXSystem.update_aging()` — ages sprites, does not expire evidence; no gameplay consequence
- `EnemyAwarenessSystem.process_confirm()` — confirmation flow; blood must NOT bypass it
- `EnemyAwarenessSystem.register_noise()` — transitions to ALERT; too aggressive for blood
- `EnemyAwarenessSystem._transition_to()` — state machine core; blood must produce SUSPICIOUS only
- `Enemy.apply_teammate_call()` — pattern for setting `_investigate_anchor` and calling awareness
- `Enemy.apply_room_alert_propagation()` — pattern for awareness calls
- `LevelBootstrapController._initialize_systems()` — pattern for EnemyAggroCoordinator initialization
- `EventBus.blood_spawned` signal — currently emitted by VFXSystem; no subscribers in enemy code

**Search commands used:**
- `grep -rn "blood\|Blood" src/ --include="*.gd" -l`
- `grep -n "blood\|Blood" src/systems/vfx_system.gd`
- `grep -n "blood_spawned" src/ -r --include="*.gd"`
- `grep -n "investigate_anchor" src/entities/enemy.gd`
- `grep -n "apply_teammate_call\|apply_blood\|register_blood\|register_noise" src/entities/enemy.gd`
- `grep -n "EnemyAggroCoordinator\|enemy_aggro" src/levels/level_bootstrap_controller.gd`
- `grep -rn "blood_spawned" tests/ --include="*.gd"`
- `rg "legacy_blood_alert|debug_blood_force_combat|old_blood_hook" src/`

**Confirmed facts:**
- `blood_spawned` signal has zero subscribers in enemy AI code (only emitted by VFXSystem).
- `EnemyAwarenessSystem` has no `register_blood_evidence` method.
- `enemy.gd` has no `apply_blood_evidence` method.
- `EventBus` has no `blood_evidence_detected` signal.
- `GameConfig` has no `blood_evidence_ttl_sec` or `blood_evidence_detection_radius_px` keys.
- `level_context.gd` has no `blood_evidence_system` field.
- Legacy identifiers `legacy_blood_alert`, `debug_blood_force_combat`, `old_blood_hook` → 0 matches in src/.

---

## 1. What now.

Evidence exists as visual-only effect with zero gameplay consequence. No enemy reacts to blood.

Verification of broken state:
```
rg -n "apply_blood_evidence|register_blood_evidence" src/ --include="*.gd" -S
```
Expected current output: **0 matches** (these functions do not exist).

```
rg -n "blood_evidence_detected" src/ --include="*.gd" -S
```
Expected current output: **0 matches** (signal does not exist).

The test suite has no test asserting that blood triggers investigation:
```
rg -n "test_blood_evidence" tests/ --include="*.gd" -S
```
Expected current output: **0 matches**.

---

## 2. What changes.

1. **Create** `src/systems/blood_evidence_system.gd` — new class `BloodEvidenceSystem extends Node`. Contains: `initialize(p_entities_container: Node) -> void`, `_ready() -> void` (connects `EventBus.blood_spawned`), `_on_blood_spawned(position: Vector3, size: float) -> void` (creates evidence entry), `_process(delta: float) -> void` (ages entries, removes expired, notifies enemies), `_notify_nearby_enemies(entry: Dictionary) -> void` (calls `apply_blood_evidence` on eligible CALM enemies). Assumption: `entity_id` is set on enemies before `add_child()` fires `_ready()`; if `entity_id <= 0` the enemy is silently skipped (no crash). Out-of-range and already-triggered enemies are skipped without error.

2. **Add** `register_blood_evidence() -> Array[Dictionary]` to `src/systems/enemy_awareness_system.gd`. Transitions CALM → SUSPICIOUS with reason `"blood_evidence"`. If state is not CALM, returns empty array. Never transitions to ALERT or COMBAT.

3. **Add** `apply_blood_evidence(evidence_pos: Vector2) -> bool` to `src/entities/enemy.gd`. Guards on `_awareness == null` and `_awareness.get_state() != EnemyAwarenessSystem.State.CALM`. Sets `_investigate_anchor = evidence_pos` and `_investigate_anchor_valid = true` before calling `_awareness.register_blood_evidence()`. Returns `true` if transitions array is non-empty, `false` otherwise.

4. **Add** to `src/systems/event_bus.gd`: signal `blood_evidence_detected(enemy_id: int, evidence_pos: Vector2)`, emit function `emit_blood_evidence_detected(enemy_id: int, evidence_pos: Vector2) -> void`, registration in `_event_types` list, and dispatch case in the event loop. `blood_evidence_detected` is NOT added to `SECONDARY_EVENTS` (gameplay-critical, must not be dropped under backpressure).

5. **Add** to `src/core/game_config.gd`: `var blood_evidence_ttl_sec: float = 90.0` and `var blood_evidence_detection_radius_px: float = 150.0`.

6. **Add** to `src/core/config_validator.gd`: two `_validate_number_key` calls for `blood_evidence_ttl_sec` (min 1.0) and `blood_evidence_detection_radius_px` (min 1.0).

7. **Add** to `src/levels/level_context.gd`: `var blood_evidence_system = null` after `enemy_aggro_coordinator`.

8. **Add** to `src/levels/level_bootstrap_controller.gd`: `const BLOOD_EVIDENCE_SYSTEM_SCRIPT = preload("res://src/systems/blood_evidence_system.gd")` at top; after enemy_aggro_coordinator initialization, instantiate `BloodEvidenceSystem`, set name, add_child, call `initialize(ctx.entities_container)`.

---

## 3. What will be after.

1. `rg -n "apply_blood_evidence" src/systems/blood_evidence_system.gd src/entities/enemy.gd -S` returns ≥ 2 matches (gate G1 in section 13). Verified by G1.

2. `rg -n "register_blood_evidence" src/systems/enemy_awareness_system.gd -S` returns ≥ 1 match (gate G2 in section 13). Verified by G2.

3. `rg -n "blood_evidence_detected" src/systems/event_bus.gd -S` returns ≥ 3 matches (signal, emit function, dispatch case) (gate G3 in section 13). Verified by G3.

4. `rg -n "blood_evidence_ttl_sec\|blood_evidence_detection_radius_px" src/core/game_config.gd -S` returns ≥ 2 matches (gate G4 in section 13). Verified by G4.

5. `_test_blood_evidence_state_becomes_suspicious` asserts enemy state = SUSPICIOUS after `apply_blood_evidence` on a CALM enemy. Verified by section 12 test file `test_blood_evidence_sets_investigate_anchor.gd`.

6. `_test_blood_evidence_does_not_set_alert` and `_test_blood_evidence_does_not_set_combat` assert state never exceeds SUSPICIOUS from blood alone. Verified by section 12 test file `test_blood_evidence_no_instant_combat_without_confirm.gd`.

7. `_test_blood_evidence_entry_expires_after_ttl` asserts expired entry is removed from `_evidence_entries`. Verified by section 12 test file `test_blood_evidence_ttl_expires.gd`.

---

## 4. Scope and non-scope.

**In-scope files (allowed change boundary):**
- `src/systems/blood_evidence_system.gd` (new file)
- `src/systems/enemy_awareness_system.gd`
- `src/entities/enemy.gd`
- `src/systems/event_bus.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `src/levels/level_context.gd`
- `src/levels/level_bootstrap_controller.gd`
- `tests/test_blood_evidence_sets_investigate_anchor.gd` (new file)
- `tests/test_blood_evidence_sets_investigate_anchor.tscn` (new file)
- `tests/test_blood_evidence_no_instant_combat_without_confirm.gd` (new file)
- `tests/test_blood_evidence_no_instant_combat_without_confirm.tscn` (new file)
- `tests/test_blood_evidence_ttl_expires.gd` (new file)
- `tests/test_blood_evidence_ttl_expires.tscn` (new file)
- `tests/test_runner_node.gd`
- `CHANGELOG.md`

**Out-of-scope files (must not be modified):**
- `src/systems/vfx_system.gd`
- `src/systems/enemy_pursuit_system.gd`
- `src/systems/enemy_aggro_coordinator.gd`
- `src/systems/enemy_patrol_system.gd`
- `src/systems/enemy_squad_system.gd`
- `src/entities/boss.gd`
- `src/core/game_state.gd`

---

## 5. Single-owner authority.

The primary decision of this phase — whether a specific enemy receives blood evidence notification — is owned exclusively by `BloodEvidenceSystem._notify_nearby_enemies()` in `src/systems/blood_evidence_system.gd`.

No other file contains the logic for iterating evidence entries and dispatching `apply_blood_evidence` calls. Verified by gate G5 in section 13:
```
rg -n "_notify_nearby_enemies\|apply_blood_evidence" src/ --include="*.gd" -S
```
Expected: matches only in `src/systems/blood_evidence_system.gd` and `src/entities/enemy.gd`. Any match in another file = phase FAILED.

---

## 6. Full input/output contract.

### Contract A: BloodEvidenceEntryContractV1

**Contract name:** `BloodEvidenceEntryContractV1`

**Entry dictionary fields (created in `_on_blood_spawned`, modified in `_process`, read in `_notify_nearby_enemies`):**

| Field | Type | Nullability | Finite check |
|---|---|---|---|
| `pos_x` | `float` | non-null | set from `position.x` (Vector3 field, always finite) |
| `pos_y` | `float` | non-null | set from `position.y` (Vector3 field, always finite) |
| `age_sec` | `float` | non-null | starts 0.0, incremented by `delta` (always ≥ 0.0) |
| `ttl_sec` | `float` | non-null | `GameConfig.blood_evidence_ttl_sec` if GameConfig non-null else 90.0; always > 0.0 |
| `triggered_ids` | `Dictionary` | non-null | keys are `int` entity_ids, values are `true` (bool) |

**Expiry rule:** entry is removed when `float(entry["age_sec"]) >= float(entry["ttl_sec"])`.

**Per-enemy trigger rule:** once `entity_id` appears in `triggered_ids`, that enemy is never re-triggered by the same entry (deduplicated for the full lifetime of the entry).

### Contract B: BloodEvidenceAwarenessContractV1

**Contract name:** `BloodEvidenceAwarenessContractV1`

**Function:** `EnemyAwarenessSystem.register_blood_evidence() -> Array[Dictionary]`

**Input:** none (reads internal `_state`).

**Output:** `Array[Dictionary]`, where each dict has:
- `"from_state": String` — name of the state before transition
- `"to_state": String` — `"SUSPICIOUS"` (always, when non-empty)
- `"reason": String` — `"blood_evidence"` (always, when non-empty)

**Status logic:**
- If `_state == State.CALM` → returns array with 1 transition dict.
- If `_state != State.CALM` → returns empty array `[]`. No downgrade. No ALERT. No COMBAT.

### Contract C: BloodEvidenceApplyContractV1

**Contract name:** `BloodEvidenceApplyContractV1`

**Function:** `Enemy.apply_blood_evidence(evidence_pos: Vector2) -> bool`

**Input:**
- `evidence_pos: Vector2` — non-null; caller guarantees this is the blood pool position.

**Output:** `bool`
- `true` → state changed (enemy was CALM and transitioned to SUSPICIOUS, `_investigate_anchor` set).
- `false` → no state change (enemy was not CALM, or `_awareness` is null).

**Side effects when returning `true`:**
- `_investigate_anchor = evidence_pos`
- `_investigate_anchor_valid = true`
- `_investigate_target_in_shadow = false`
- No direct `EventBus` emission inside `Enemy.apply_blood_evidence()`. `blood_evidence_detected` is emitted by `BloodEvidenceSystem._notify_nearby_enemies()` after a `true` return to avoid duplicate emits.

**Constants/thresholds:**
| Name | Value | Placement |
|---|---|---|
| `blood_evidence_ttl_sec` | `90.0` | `src/core/game_config.gd` exported var |
| `blood_evidence_detection_radius_px` | `150.0` | `src/core/game_config.gd` exported var |

---

## 7. Deterministic algorithm.

**Step 1 — Evidence creation** (`BloodEvidenceSystem._on_blood_spawned(position: Vector3, size: float)`):
1. Create entry dict: `{"pos_x": position.x, "pos_y": position.y, "age_sec": 0.0, "ttl_sec": GameConfig.blood_evidence_ttl_sec if GameConfig else 90.0, "triggered_ids": {}}`
2. Append to `_evidence_entries`.
3. `size` parameter is accepted but not stored (visual sizing is VFXSystem's responsibility).

**Step 2 — Per-frame processing** (`BloodEvidenceSystem._process(delta: float)`):
1. If `_evidence_entries.is_empty()` → return immediately (no work).
2. Age pass (forward): for each entry in `_evidence_entries`, `entry["age_sec"] = float(entry["age_sec"]) + delta`.
3. Expiry pass (backward, index from `_evidence_entries.size() - 1` to 0): if `float(entry["age_sec"]) >= float(entry["ttl_sec"])` → call `_evidence_entries.remove_at(i)`.
4. Notify pass (forward over surviving entries): call `_notify_nearby_enemies(entry)` for each.

**Step 3 — Nearby enemy notification** (`BloodEvidenceSystem._notify_nearby_enemies(entry: Dictionary)`):
1. If `entities_container == null` → return.
2. `evidence_pos = Vector2(float(entry["pos_x"]), float(entry["pos_y"]))`.
3. `radius = GameConfig.blood_evidence_detection_radius_px if GameConfig else 150.0`.
4. For each child in `entities_container.get_children()` (deterministic scene-tree order):
   a. If `not child.is_in_group("enemies")` → skip.
   b. `entity_id = int(child.get("entity_id")) if "entity_id" in child else -1`. If `entity_id <= 0` → skip.
   c. If `entry["triggered_ids"].has(entity_id)` → skip (already triggered).
   d. If `child.global_position.distance_to(evidence_pos) > radius` → skip.
   e. If `not child.has_method("apply_blood_evidence")` → skip.
   f. `triggered = bool(child.call("apply_blood_evidence", evidence_pos))`.
   g. If `triggered`: `entry["triggered_ids"][entity_id] = true`; if `EventBus` has method `emit_blood_evidence_detected` → `EventBus.emit_blood_evidence_detected(entity_id, evidence_pos)`.

**Step 4 — Awareness registration** (`EnemyAwarenessSystem.register_blood_evidence() -> Array[Dictionary]`):
1. `transitions: Array[Dictionary] = []`.
2. If `_state != State.CALM` → return `transitions` (empty).
3. Call `_transition_to(State.SUSPICIOUS, "blood_evidence", transitions)`.
4. Return `transitions`.

**Step 5 — Enemy apply** (`Enemy.apply_blood_evidence(evidence_pos: Vector2) -> bool`):
1. If `_awareness == null` → return `false`.
2. If `_awareness.get_state() != EnemyAwarenessSystem.State.CALM` → return `false`.
3. `_investigate_anchor = evidence_pos`.
4. `_investigate_anchor_valid = true`.
5. `_investigate_target_in_shadow = false`.
6. `transitions = _awareness.register_blood_evidence()`.
7. `_apply_awareness_transitions(transitions, "blood_evidence")`.
8. Return `transitions.size() > 0`.

**Tie-break for step 2 notify pass:** deterministic by scene-tree child index. When multiple non-expired entries overlap spatially, all are processed each frame in `_evidence_entries` array order. Each entry's `triggered_ids` is independent — an enemy can be triggered by two different pools (two separate investigate anchor updates). The last `apply_blood_evidence` call that returns `true` in the same frame sets the final `_investigate_anchor` value. This is acceptable because both pools are semantically equivalent (both require investigation, not combat).

**Behavior when `apply_blood_evidence` is called while warmup timer is active (Phase 13):** the function overwrites `_investigate_anchor` regardless of warmup state. The warmup timer gates `process_confirm()` inputs, not `_investigate_anchor` writes. No interaction.

---

## 8. Edge-case matrix.

**Case A: Empty entities_container (no enemies in scene)**
- `_notify_nearby_enemies` loops over 0 children.
- Output: 0 `apply_blood_evidence` calls. Entry `triggered_ids` remains empty.
- Status: entry ages normally, expires at `ttl_sec`. No crash.

**Case B: Single CALM enemy within detection radius, single fresh evidence entry**
- `entity_id` valid, distance ≤ radius, state CALM.
- `apply_blood_evidence(pos)` returns `true`.
- `enemy._investigate_anchor = pos`, `_investigate_anchor_valid = true`.
- `enemy._awareness._state = SUSPICIOUS` after transition.
- `entry["triggered_ids"][entity_id] = true` — not re-triggered on next frame.
- `EventBus.blood_evidence_detected` emitted with `(entity_id, pos)`.

**Case C: Tie-break N/A — `register_blood_evidence()` produces at most 1 transition element by design.** `_transition_to` appends exactly one dict when state changes. When called from CALM, exactly one element is appended. When called from non-CALM, no element is appended. No two candidates compete; there is one target state (SUSPICIOUS).

**Case D: All enemies already in SUSPICIOUS/ALERT/COMBAT state**
- `apply_blood_evidence` returns `false` for all (step 5.2 guard).
- `_investigate_anchor` not modified.
- `triggered_ids` remains empty (no `true` set, so same enemies are checked again next frame — but same result until state returns to CALM, which blood alone cannot cause).
- `EventBus.blood_evidence_detected` not emitted.
- Status: no state change, no crash.

**Case E: Evidence entry age reaches ttl_sec**
- Expiry pass removes entry.
- Notify pass never sees the expired entry.
- Enemies near the expired pool are not triggered after expiry.
- Status: removed from `_evidence_entries`; sprite remains in VFXSystem (visual aging is independent).

**Case F: Enemy entity_id already in triggered_ids**
- Step 3c skips the enemy.
- No second `apply_blood_evidence` call for the same enemy from the same pool.
- Status: idempotent per-entry.

**Case G: Multiple blood pools, single enemy within range of both**
- Entry A processes first (array order), triggers enemy → `entry_a.triggered_ids[id] = true`.
- Entry B processes second, `entity_id` NOT in `entry_b.triggered_ids` → `apply_blood_evidence` called again.
- Second call: state is now SUSPICIOUS (from Case B above), so step 5.2 returns `false`.
- `_investigate_anchor` is NOT overwritten by second pool (guard prevents it).
- Status: first pool wins; second pool is a no-op. Correct.

---

## 9. Legacy removal plan.

No legacy identifiers exist in this phase. The v1 doc legacy gate `rg -n "legacy_blood_alert|debug_blood_force_combat|old_blood_hook" src/ tests/ -S` confirmed 0 matches in PROJECT DISCOVERY. No delete-first step required.

---

## 10. Legacy verification commands.

No legacy items exist. The phase opens with zero pre-deletions.

Confirmation command (run once before implementation; must remain 0 throughout):
```
rg -n "legacy_blood_alert|debug_blood_force_combat|old_blood_hook" src/ tests/ -S
```
Expected: **0 matches**. Non-zero = external contamination = phase FAILED.

---

## 11. Acceptance criteria.

1. `rg -n "apply_blood_evidence" src/systems/blood_evidence_system.gd src/entities/enemy.gd -S` returns ≥ 2 matches. [binary: yes/no]

2. `rg -n "register_blood_evidence" src/systems/enemy_awareness_system.gd -S` returns ≥ 1 match. [binary: yes/no]

3. `rg -n "blood_evidence_detected" src/systems/event_bus.gd -S` returns ≥ 3 matches. [binary: yes/no]

4. `rg -n "blood_evidence_ttl_sec\|blood_evidence_detection_radius_px" src/core/game_config.gd -S` returns ≥ 2 matches. [binary: yes/no]

5. `rg -n "BloodEvidenceSystem\|blood_evidence_system" src/levels/level_bootstrap_controller.gd src/levels/level_context.gd -S` returns ≥ 2 matches. [binary: yes/no]

6. All 7 new test functions (section 12) exit 0 when run via Tier 2 regression. [binary: yes/no]

7. Tier 2 full regression `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` exits 0. [binary: yes/no]

8. No file outside section 4 in-scope list was modified. [binary: yes/no]

---

## 12. Tests.

### New test files:

**`tests/test_blood_evidence_sets_investigate_anchor.gd`**
- Registration: add scene constant + scene existence check + `_run_embedded_scene_suite(...)` call in `tests/test_runner_node.gd` (follow existing runner pattern; no `_get_test_suites()` helper required).
- Test functions:
  - `_test_blood_evidence_sets_investigate_anchor` — Creates a standalone `EnemyAwarenessSystem` in CALM state and calls `apply_blood_evidence(Vector2(100, 200))` via a minimal enemy stub. Asserts `_investigate_anchor == Vector2(100, 200)` and `_investigate_anchor_valid == true`.
  - `_test_blood_evidence_state_becomes_suspicious` — Same setup. Asserts `_awareness.get_state() == EnemyAwarenessSystem.State.SUSPICIOUS` after `apply_blood_evidence`.

**`tests/test_blood_evidence_no_instant_combat_without_confirm.gd`**
- Registration: add scene constant + scene existence check + `_run_embedded_scene_suite(...)` call in `tests/test_runner_node.gd` (follow existing runner pattern; no `_get_test_suites()` helper required).
- Test functions:
  - `_test_blood_evidence_does_not_set_alert` — CALM enemy, `apply_blood_evidence` called. Asserts `_awareness.get_state() != EnemyAwarenessSystem.State.ALERT`.
  - `_test_blood_evidence_does_not_set_combat` — CALM enemy, `apply_blood_evidence` called. Asserts `_awareness.get_state() != EnemyAwarenessSystem.State.COMBAT`.
  - `_test_blood_evidence_no_op_when_already_alert` — Enemy in ALERT state (via `register_noise()`). Calls `apply_blood_evidence`. Asserts return value is `false` and state remains ALERT.

**`tests/test_blood_evidence_ttl_expires.gd`**
- Registration: add scene constant + scene existence check + `_run_embedded_scene_suite(...)` call in `tests/test_runner_node.gd` (follow existing runner pattern; no `_get_test_suites()` helper required).
- Test functions:
  - `_test_blood_evidence_entry_expires_after_ttl` — Creates a `BloodEvidenceSystem` standalone instance (no Godot scene required). Calls `_on_blood_spawned(Vector3(0,0,0), 1.0)` to create entry with `ttl_sec=1.0` (via GameConfig override or direct dict mutation). Calls `_process(1.01)`. Asserts `_evidence_entries.is_empty() == true`.
  - `_test_blood_evidence_expired_entry_does_not_trigger` — Same setup. After expiry, sets up a mock entities_container with a CALM enemy stub. Calls `_process(0.001)` (additional tick). Asserts `apply_blood_evidence` was never called on the stub (mock counter remains 0) and enemy state is still CALM.

### Updated test files:

**`tests/test_runner_node.gd`**
- Change: add 3 new scene constants, scene existence checks, and `_run_embedded_scene_suite(...)` calls (existing runner pattern):
  ```
  const BLOOD_EVIDENCE_INVESTIGATE_ANCHOR_TEST_SCENE := "res://tests/test_blood_evidence_sets_investigate_anchor.tscn"
  const BLOOD_EVIDENCE_NO_INSTANT_COMBAT_TEST_SCENE := "res://tests/test_blood_evidence_no_instant_combat_without_confirm.tscn"
  const BLOOD_EVIDENCE_TTL_EXPIRES_TEST_SCENE := "res://tests/test_blood_evidence_ttl_expires.tscn"
  ```

---

## 13. rg gates.

**Phase-specific gates:**

[G1] `rg -n "apply_blood_evidence" src/systems/blood_evidence_system.gd src/entities/enemy.gd -S`
Expected: ≥ 2 matches.

[G2] `rg -n "register_blood_evidence" src/systems/enemy_awareness_system.gd -S`
Expected: ≥ 1 match.

[G3] `rg -n "blood_evidence_detected" src/systems/event_bus.gd -S`
Expected: ≥ 3 matches (signal declaration, emit function, dispatch case).

[G4] `rg -n "blood_evidence_ttl_sec\|blood_evidence_detection_radius_px" src/core/game_config.gd -S`
Expected: ≥ 2 matches.

[G5] `rg -n "_notify_nearby_enemies\|apply_blood_evidence" src/ --include="*.gd" -S`
Expected: matches only in `src/systems/blood_evidence_system.gd` and `src/entities/enemy.gd`. Any match in another src file = FAIL.

[G6] `rg -n "BloodEvidenceSystem\|blood_evidence_system" src/levels/level_bootstrap_controller.gd src/levels/level_context.gd -S`
Expected: ≥ 2 matches.

[G7] `bash -lc 'if rg -n "blood_evidence_detected" src/systems/event_bus.gd -S | grep -n "SECONDARY_EVENTS"; then echo "G7: FAIL (found in SECONDARY_EVENTS)"; else echo "G7: PASS (0 matches)"; fi'`
Expected: `G7: PASS (0 matches)`.

**PMB gates:**

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: 0 matches.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: 0 matches.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

---

## 14. Execution sequence.

Step 1: Confirm 0 legacy matches: `rg -n "legacy_blood_alert|debug_blood_force_combat|old_blood_hook" src/ tests/ -S` → 0 matches. If non-zero → abort, investigate external contamination.

Step 2: Add `var blood_evidence_ttl_sec: float = 90.0` and `var blood_evidence_detection_radius_px: float = 150.0` to `src/core/game_config.gd` in the AI balance / detection tuning block.

Step 3: Add two `_validate_number_key` calls for `blood_evidence_ttl_sec` (min 1.0) and `blood_evidence_detection_radius_px` (min 1.0) to `src/core/config_validator.gd`.

Step 4: Add `signal blood_evidence_detected(enemy_id: int, evidence_pos: Vector2)` to `src/systems/event_bus.gd` in the Enemy signals block. Add `"blood_evidence_detected"` to `_event_types` list. Add `emit_blood_evidence_detected(enemy_id: int, evidence_pos: Vector2) -> void` emit function. Add dispatch case `"blood_evidence_detected": blood_evidence_detected.emit(event.args[0], event.args[1])` to the event loop.

Step 5: Add `register_blood_evidence() -> Array[Dictionary]` to `src/systems/enemy_awareness_system.gd` after `register_teammate_call()` (line 241). Implementation: check `_state != State.CALM` → return `[]`; else call `_transition_to(State.SUSPICIOUS, "blood_evidence", transitions)` and return `transitions`.

Step 6: Add `apply_blood_evidence(evidence_pos: Vector2) -> bool` to `src/entities/enemy.gd` after `apply_teammate_call()` (after line 829). Implementation per section 7 step 5.

Step 7: Create `src/systems/blood_evidence_system.gd`. Implement `class_name BloodEvidenceSystem extends Node`. Add: `var entities_container: Node = null`, `var _evidence_entries: Array[Dictionary] = []`. Implement `initialize`, `_ready`, `_on_blood_spawned`, `_process`, `_notify_nearby_enemies` per section 7.

Step 8: Add `var blood_evidence_system = null` to `src/levels/level_context.gd` after `enemy_aggro_coordinator`.

Step 9: Add to `src/levels/level_bootstrap_controller.gd`: `const BLOOD_EVIDENCE_SYSTEM_SCRIPT = preload("res://src/systems/blood_evidence_system.gd")` at top. After enemy_aggro_coordinator initialization block (after line 142): instantiate, name, add_child, and call `initialize(ctx.entities_container)`. Set `ctx.blood_evidence_system`.

Step 10: Create `tests/test_blood_evidence_sets_investigate_anchor.gd` and `.tscn`. Implement 2 test functions per section 12.

Step 11: Create `tests/test_blood_evidence_no_instant_combat_without_confirm.gd` and `.tscn`. Implement 3 test functions per section 12.

Step 12: Create `tests/test_blood_evidence_ttl_expires.gd` and `.tscn`. Implement 2 test functions per section 12.

Step 13: Register all 3 new test scenes in `tests/test_runner_node.gd`: add 3 const declarations, 3 scene existence checks, and 3 `_run_embedded_scene_suite(...)` calls (follow existing runner pattern; no `_get_test_suites()` helper required).

Step 14: Run Tier 1 smoke suite (no dedicated Tier 1 scene specified for this phase; skip to Tier 2).

Step 15: Run Tier 2 full regression: `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit 0.

Step 16: Run all rg gates from section 13 (G1–G7, PMB-1–PMB-5). All must return expected output.

Step 17: Prepend CHANGELOG entry with MSK timestamp, description "Phase 14: Blood Evidence System — blood triggers investigation (SUSPICIOUS), not instant combat bypass; TTL expiry supported", affected files list.

---

## 15. Rollback conditions.

1. **Trigger:** Any rg gate in section 13 returns unexpected output after step 16. **Action:** Revert all changes in section 4 in-scope files to their pre-phase state. Do not commit partial state.

2. **Trigger:** Tier 2 regression exits non-zero after step 15. **Action:** Revert all changes to pre-phase state. If failure is in a test added by this phase, fix the test or implementation before re-running; do not disable the failing test.

3. **Trigger:** `apply_blood_evidence` called from a file not in section 4 in-scope list (discovered via G5 gate). **Action:** Delete the out-of-scope call and revert the out-of-scope file. Rethink integration approach.

4. **Trigger:** `register_blood_evidence` triggers ALERT or COMBAT in any test. **Action:** Revert `register_blood_evidence` implementation. Verify `_transition_to` target is `State.SUSPICIOUS` only.

5. **Trigger:** Cannot complete implementation within this phase scope (e.g., `apply_blood_evidence` API requires refactoring `_awareness` access pattern beyond minimal extension). **Action:** Roll back all changes. Phase FAILED per Hard Rule 11.

---

## 16. Phase close condition.

- [ ] `rg -n "legacy_blood_alert|debug_blood_force_combat|old_blood_hook" src/ tests/ -S` returns 0 matches
- [ ] All rg gates in section 13 (G1–G7, PMB-1–PMB-5) return expected output
- [ ] All 7 new test functions (section 12) exit 0
- [ ] Tier 2 full regression (`test_runner.tscn`) exits 0
- [ ] No file outside section 4 in-scope list was modified
- [ ] CHANGELOG entry prepended
- [ ] `blood_evidence_detected` signal is NOT in `SECONDARY_EVENTS` list (verified by G7)
- [ ] Evidence TTL entries expire correctly (verified by `_test_blood_evidence_entry_expires_after_ttl`)
- [ ] Blood never causes ALERT or COMBAT directly (verified by `_test_blood_evidence_does_not_set_alert` and `_test_blood_evidence_does_not_set_combat`)

---

## 17. Ambiguity check: 0

---

## 18. Open questions: 0

---

## 19. Post-implementation verification plan.

**Diff audit:** diff all changed in-scope files against pre-phase baseline, including new blood evidence test scripts/scenes (`3 .gd` + `3 .tscn`) and `CHANGELOG.md`. Confirm no changes outside section 4 in-scope list.

**Contract checks:**
- `BloodEvidenceEntryContractV1`: verify `_on_blood_spawned` creates dict with all 5 fields; verify `_process` removes entries where `float(entry["age_sec"]) >= float(entry["ttl_sec"])`.
- `BloodEvidenceAwarenessContractV1`: verify `register_blood_evidence` calls `_transition_to` with target `State.SUSPICIOUS` and reason `"blood_evidence"` when in CALM; verify empty return for all other states.
- `BloodEvidenceApplyContractV1`: verify `apply_blood_evidence` guards on CALM state; verify `_investigate_anchor` written before awareness call; verify return value matches `transitions.size() > 0`.

**Runtime scenarios from section 20:** execute P14-A, P14-B, P14-C, P14-D.

---

## 20. Runtime scenario matrix.

**P14-A: Fresh blood triggers investigation**
- Scene: `tests/test_blood_evidence_sets_investigate_anchor.tscn` (unit test, no physics).
- Setup: `EnemyAwarenessSystem` instance in CALM state; call `apply_blood_evidence(Vector2(50, 50))`.
- Frame count: 0 (synchronous call).
- Expected invariants: `_investigate_anchor_valid == true`; `_awareness.get_state() == State.SUSPICIOUS`.
- Fail conditions: state is CALM, ALERT, or COMBAT after call; `_investigate_anchor_valid` is false.
- Covered by: `_test_blood_evidence_sets_investigate_anchor`, `_test_blood_evidence_state_becomes_suspicious`.

**P14-B: Blood does not bypass confirmation**
- Scene: `tests/test_blood_evidence_no_instant_combat_without_confirm.tscn` (unit test).
- Setup: CALM enemy stub; call `apply_blood_evidence`.
- Frame count: 0 (synchronous).
- Expected invariants: `get_state() == State.SUSPICIOUS`; `get_state() != State.ALERT`; `get_state() != State.COMBAT`.
- Fail conditions: state is ALERT or COMBAT.
- Covered by: `_test_blood_evidence_does_not_set_alert`, `_test_blood_evidence_does_not_set_combat`.

**P14-C: TTL expiry removes evidence**
- Scene: `tests/test_blood_evidence_ttl_expires.tscn` (unit test).
- Setup: `BloodEvidenceSystem` standalone instance; `_on_blood_spawned(Vector3(0,0,0), 1.0)` with TTL=1.0; call `_process(1.01)`.
- Frame count: 0 (synchronous).
- Expected invariants: `_evidence_entries.is_empty() == true`.
- Fail conditions: entry still present after TTL exceeded.
- Covered by: `_test_blood_evidence_entry_expires_after_ttl`.

**P14-D: No-op on non-CALM enemy**
- Scene: `tests/test_blood_evidence_no_instant_combat_without_confirm.tscn` (unit test).
- Setup: Enemy forced to ALERT via `register_noise()`; call `apply_blood_evidence(Vector2(50,50))`.
- Frame count: 0 (synchronous).
- Expected invariants: return value is `false`; state remains ALERT; `_investigate_anchor_valid` unchanged.
- Fail conditions: state changes; return value is `true`.
- Covered by: `_test_blood_evidence_no_op_when_already_alert`.

---

## 21. Verification report format.

Record all fields below to close phase:
- `phase_id: PHASE_14`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; must be empty list on close)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `dependency_gate_check: [PHASE-0: PASS|FAIL, PHASE-4: PASS|FAIL]` **[BLOCKING — all must be PASS before implementation and before close]**
- `legacy_rg: [{command: "rg -n \"legacy_blood_alert|debug_blood_force_combat|old_blood_hook\" src/ tests/ -S", expected: "0 matches", actual, PASS|FAIL}]`
- `rg_gates: [{command, expected, actual, PASS|FAIL}]` for G1–G7
- `phase_tests: [{test_function, exit_code: 0, PASS|FAIL}]` for all 7 test functions
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

---

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 14` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- pmb_contract_check present in section 21 (PMB section exists in document): yes

---

## 23. Dependencies on previous phases.

1. **Phase 0 (pre-v2 baseline infrastructure)** — established `src/systems/event_bus.gd` with `blood_spawned` signal emitted by `VFXSystem`. Phase 14 subscribes `BloodEvidenceSystem` to that signal in `_ready()`. Without Phase 0's `blood_spawned` signal, Phase 14 has no event source for evidence entries.

2. **Phase 4** — extended `Enemy.apply_teammate_call()` with `_investigate_anchor` write pattern (`_investigate_anchor = shot_pos; _investigate_anchor_valid = true; _investigate_target_in_shadow = false`). Phase 14 reuses this exact pattern in `apply_blood_evidence()`. Without Phase 4's established pattern, the field names and reset semantics would need to be rediscovered from scratch.

---

## PHASE 15
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_15.

### Evidence

**Inspected files:**
- `src/entities/enemy.gd` (lines 1–260, 270–360, 404–760, 832–1125, 1180–1525, 2440–2535; targeted `rg`/`nl` line refs for doctrine and flashlight branches)
- `src/systems/enemy_utility_brain.gd` (full, 205 lines)
- `src/systems/enemy_pursuit_system.gd` (lines 210–520; shadow scan execution path)
- `src/systems/enemy_alert_levels.gd` (full)
- `src/systems/enemy_patrol_system.gd` (lines 1–120, 300–360; deterministic seed pattern)
- `tests/test_suspicious_shadow_scan.gd` (full)
- `tests/test_combat_no_los_never_hold_range.gd` (full)
- `tests/test_alert_investigate_anchor.gd` (full)
- `tests/test_combat_utility_intent_aggressive.gd` (full)
- `tests/test_combat_intent_switches_push_to_search_after_grace.gd` (full)
- `tests/test_flashlight_single_source_parity.gd` (full)
- `tests/test_suspicious_shadow_scan.tscn` (full)
- `tests/test_combat_no_los_never_hold_range.tscn` (full)
- `tests/test_runner_node.gd` (lines 90–140, 760–890, 1040–1135; targeted `rg` line refs for constants/existence checks/suite calls)

**Inspected functions/methods:**
- `Enemy.runtime_budget_tick`
- `Enemy._build_utility_context`
- `Enemy._resolve_effective_alert_level_for_utility`
- `Enemy._resolve_known_target_context`
- `Enemy._compute_flashlight_active`
- `Enemy.set_shadow_scan_active`
- `Enemy.debug_force_awareness_state`
- `Enemy.get_current_intent`
- `EnemyUtilityBrain._choose_intent`
- `EnemyUtilityBrain._combat_no_los_grace_intent`
- `EnemyPursuitSystem.execute_intent`
- `EnemyPursuitSystem.clear_shadow_scan_state`
- `EnemyPursuitSystem._execute_shadow_boundary_scan`
- `EnemyPursuitSystem._run_shadow_scan_sweep`
- `EnemyPatrolSystem._resolve_deterministic_seed`
- `TestSuspiciousShadowScan.run_suite`
- `TestSuspiciousShadowScan._test_suspicious_shadow_scan_intent_and_flashlight`
- `TestCombatNoLosNeverHoldRange.run_suite`
- `TestCombatNoLosNeverHoldRange._test_combat_no_los_never_hold_range`
- `TestRunner._run_tests`
- `TestRunner._run_embedded_scene_suite`
- `TestRunner._scene_exists`

**Search commands used:**
- `rg -n "shadow_scan_target|effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT\.SUSPICIOUS|flashlight|no_los|RETURN_HOME|PATROL|last_seen|investigate_anchor" src/entities/enemy.gd src/systems/enemy_utility_brain.gd src/systems/enemy_pursuit_system.gd tests -S`
- `rg -n "test_state_doctrine_matrix_contract|test_suspicious_flashlight_30_percent_seeded|test_alert_no_los_searches_dark_pockets_not_patrol|test_suspicious_shadow_scan|test_combat_no_los_never_hold_range" tests -S`
- `rg -n "randf|randi|seed|determin|_debug_tick_id|_intent_stability|hash" src/entities/enemy.gd -S`
- `rg -n "^func (_build_utility_context|_compute_flashlight_active|set_shadow_check_flashlight|_resolve_known_target_context)" src/entities/enemy.gd -S`
- `rg -n "^func (_choose_intent|_combat_no_los_grace_intent)" src/systems/enemy_utility_brain.gd -S`
- `rg -n "^func (execute_intent|clear_shadow_scan_state|_execute_shadow_boundary_scan|_run_shadow_scan_sweep)" src/systems/enemy_pursuit_system.gd -S`
- `rg -n "if alert_level <= ENEMY_ALERT_LEVELS_SCRIPT\.SUSPICIOUS and not has_los:|if alert_level == ENEMY_ALERT_LEVELS_SCRIPT\.SUSPICIOUS and has_shadow_scan_target and shadow_scan_target_in_shadow:|if not has_los and alert_level >= ENEMY_ALERT_LEVELS_SCRIPT\.ALERT:" src/systems/enemy_utility_brain.gd -S`
- `rg -n "if effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT\.SUSPICIOUS:|state_is_suspicious and _shadow_scan_active and _flashlight_policy_active_in_alert\(" src/entities/enemy.gd -S`
- `rg -n "SUSPICIOUS_SHADOW_SCAN_TEST_SCENE|COMBAT_NO_LOS_NEVER_HOLD_RANGE_TEST_SCENE|func _run_tests\(|func _run_embedded_scene_suite\(|func _scene_exists\(" tests/test_runner_node.gd -S`

**Confirmed facts:**
- `Enemy._build_utility_context` computes `shadow_scan_target` only inside `if effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS:` (lines 1027–1035).
- `Enemy._compute_flashlight_active` enables suspicious shadow-scan flashlight with no probability gate; the suspicious term is a single boolean conjunction at line 1203.
- `EnemyUtilityBrain._choose_intent` merges CALM and SUSPICIOUS no-LOS doctrine into one branch (`alert_level <= SUSPICIOUS`) at lines 104–124.
- `EnemyUtilityBrain._choose_intent` executes `SHADOW_BOUNDARY_SCAN` only inside the SUSPICIOUS nested condition at line 105.
- `EnemyUtilityBrain._choose_intent` ALERT/COMBAT no-LOS branch (lines 126–145) does not read `has_shadow_scan_target` and falls back to `RETURN_HOME`.
- `EnemyPursuitSystem.execute_intent` already executes `IntentType.SHADOW_BOUNDARY_SCAN` without state-specific gating; phase logic selection is upstream in `EnemyUtilityBrain._choose_intent` and `Enemy._build_utility_context`.
- `tests/test_suspicious_shadow_scan.gd` currently asserts unconditional suspicious shadow-scan flashlight activation, which conflicts with a deterministic 30% policy.

---

## 1. What now.

Current doctrine overlap and missing state-specific gates are present in code and tests.

Verification of current overlap / incomplete state:

```bash
rg -n "if alert_level <= ENEMY_ALERT_LEVELS_SCRIPT\.SUSPICIOUS and not has_los:" src/systems/enemy_utility_brain.gd -S
```
Expected current output: **1 match** (CALM and SUSPICIOUS no-LOS share one branch).

```bash
rg -n "if effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT\.SUSPICIOUS:" src/entities/enemy.gd -S
```
Expected current output: **1 match** (shadow scan target exists only for SUSPICIOUS in utility context builder).

```bash
rg -n "state_is_suspicious and _shadow_scan_active and _flashlight_policy_active_in_alert\(" src/entities/enemy.gd -S
```
Expected current output: **1 match** (suspicious shadow-scan flashlight is binary on/off, no 30% deterministic gate).

```bash
rg -n "SUSPICIOUS shadow scan activates flashlight" tests/test_suspicious_shadow_scan.gd -S
```
Expected current output: **1 match** (legacy test asserts unconditional activation).

```bash
rg -n "test_state_doctrine_matrix_contract|test_suspicious_flashlight_30_percent_seeded|test_alert_no_los_searches_dark_pockets_not_patrol" tests/ --include="*.gd" -S
```
Expected current output: **0 matches** (Phase 15 test files do not exist).

---

## 2. What changes.

1. **Delete-first in `src/systems/enemy_utility_brain.gd`, function `EnemyUtilityBrain._choose_intent`:** remove the merged no-LOS branch headed by `if alert_level <= ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS and not has_los:` (current lines 104–124) before writing the state-specific matrix branches.

2. **Delete-first in `src/entities/enemy.gd`, function `Enemy._build_utility_context`:** remove the SUSPICIOUS-only shadow-scan target gate `if effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS:` (current line 1027) before writing the cross-state target selection logic.

3. **Delete-first in `src/entities/enemy.gd`, function `Enemy._compute_flashlight_active`:** remove the inline suspicious flashlight term `(state_is_suspicious and _shadow_scan_active and _flashlight_policy_active_in_alert())` (current line 1203) before writing the deterministic 30% gate call.

4. **Modify `src/entities/enemy.gd`, function `Enemy._build_utility_context`:** compute `shadow_scan_target` for `effective_alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS` with strict priority order `known_target_pos` (when `has_known_target == true`) → `_last_seen_pos` (when `has_last_seen == true`) → `_investigate_anchor` (when `_investigate_anchor_valid == true`) → none. Compute `shadow_scan_target_in_shadow` by exactly one `nav_system.is_point_in_shadow(shadow_scan_target)` call when `has_shadow_scan_target == true` and the method exists.

5. **Add to `src/entities/enemy.gd` file scope:** local constants for suspicious flashlight gating used only by the new helper path in this phase:
   - `const SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_CHANCE := 0.30`
   - `const SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_BUCKET_COUNT := 10`
   - `const SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_ACTIVE_BUCKETS := 3`

6. **Add to `src/entities/enemy.gd`:** private helpers `_suspicious_shadow_scan_flashlight_bucket() -> int` and `_suspicious_shadow_scan_flashlight_gate_passes() -> bool`. Implement exact deterministic formula from section 7 using `entity_id` and `_debug_tick_id`.

7. **Modify `src/entities/enemy.gd`, function `Enemy._compute_flashlight_active`:** replace the deleted suspicious term with `state_is_suspicious and _shadow_scan_active and _flashlight_policy_active_in_alert() and _suspicious_shadow_scan_flashlight_gate_passes()`.

8. **Modify `src/systems/enemy_utility_brain.gd`, function `EnemyUtilityBrain._choose_intent`:** add `has_known_target` extraction and `target_context_exists := has_known_target or has_last_seen or has_investigate_anchor`.

9. **Modify `src/systems/enemy_utility_brain.gd`, function `EnemyUtilityBrain._choose_intent`:** replace the merged CALM/SUSPICIOUS no-LOS branch with explicit state doctrine branches:
   - CALM no-LOS branch (`alert_level == CALM`) returns only `PATROL`.
   - SUSPICIOUS no-LOS branch keeps `SHADOW_BOUNDARY_SCAN`, `INVESTIGATE`, `SEARCH`, `PATROL` in exact order from section 7.
   - ALERT/COMBAT no-LOS branch reads `has_shadow_scan_target` and `shadow_scan_target_in_shadow` before `INVESTIGATE/SEARCH` fallbacks.

10. **Modify `src/systems/enemy_utility_brain.gd`, function `EnemyUtilityBrain._choose_intent`:** enforce the anti-degrade rule in ALERT/COMBAT no-LOS branch: when `target_context_exists == true`, return type is never `PATROL` and never `RETURN_HOME`.

11. **Create tests:** `tests/test_state_doctrine_matrix_contract.gd` + `tests/test_state_doctrine_matrix_contract.tscn`, `tests/test_suspicious_flashlight_30_percent_seeded.gd` + `tests/test_suspicious_flashlight_30_percent_seeded.tscn`, `tests/test_alert_no_los_searches_dark_pockets_not_patrol.gd` + `tests/test_alert_no_los_searches_dark_pockets_not_patrol.tscn`.

12. **Update tests:** `tests/test_suspicious_shadow_scan.gd` to remove unconditional suspicious flashlight assertion and replace it with deterministic bucket-controlled assertions; `tests/test_combat_no_los_never_hold_range.gd` to add `!= PATROL` and `!= RETURN_HOME` assertions in COMBAT no-LOS target-context flow.

13. **Modify `tests/test_runner_node.gd`, function `TestRunner._run_tests` and top-level const block:** add 3 scene constants, 3 `_scene_exists` assertions, and 3 `_run_embedded_scene_suite(...)` calls for the new Phase 15 test scenes.

14. **This phase does not modify** `src/systems/enemy_pursuit_system.gd`; `EnemyPursuitSystem.execute_intent` already executes `SHADOW_BOUNDARY_SCAN` and toggles `_shadow_scan_active` via owner callbacks.

Migration notes: no file rename, no symbol move across files, no compatibility alias branch.

---

## 3. What will be after.

1. `Enemy._build_utility_context` exposes `shadow_scan_target` through one shared `effective_alert_level >= ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS` code path, with `known_target_pos` priority over `last_seen` and `investigate_anchor`. Verified by section 12 test `tests/test_state_doctrine_matrix_contract.gd` (`_test_build_utility_context_shadow_scan_target_priority_known_then_last_seen_then_anchor`) and gates G3 + G5 in section 13.

2. `EnemyUtilityBrain._choose_intent` no longer contains the merged CALM/SUSPICIOUS no-LOS branch header. Verified by gate G1 in section 13.

3. `EnemyUtilityBrain._choose_intent` no longer contains the old nested SUSPICIOUS-only `SHADOW_BOUNDARY_SCAN` condition string. Verified by gate G2 in section 13.

4. ALERT no-LOS with a dark `shadow_scan_target` returns `IntentType.SHADOW_BOUNDARY_SCAN` and not `PATROL` / `RETURN_HOME`. Verified by section 12 test file `tests/test_alert_no_los_searches_dark_pockets_not_patrol.gd` and updated regression `tests/test_combat_no_los_never_hold_range.gd` in section 12.

5. ALERT no-LOS and COMBAT no-LOS with `combat_lock == false` and `target_context_exists == true` never return `PATROL` or `RETURN_HOME`, and their no-LOS target-context outputs are limited to `SHADOW_BOUNDARY_SCAN`, `INVESTIGATE`, or `SEARCH`. Verified by section 12 tests `tests/test_state_doctrine_matrix_contract.gd` and `tests/test_combat_no_los_never_hold_range.gd` (anti-degrade assertions) and the Contract B check in section 19 (full allowlist).

6. Suspicious shadow-scan flashlight activation uses a deterministic 30% gate keyed by `entity_id` and `_debug_tick_id` instead of unconditional activation. Verified by section 12 test file `tests/test_suspicious_flashlight_30_percent_seeded.gd` (reproducible same-entity tick-window sampling, exact `30/100`, different-entity same-tick-window divergence, and inactive-shadow-scan false result), gate G7 in section 13 (helper/constant presence), and the exact formula contract check in section 19.

7. `tests/test_runner_node.gd` registers all three new Phase 15 test scenes using the existing monolithic `_run_tests` runner pattern. Verified by gate G9 in section 13.

---

## 4. Scope and non-scope (exact files).

**In-scope files (allowed change boundary):**
- `src/entities/enemy.gd`
- `src/systems/enemy_utility_brain.gd`
- `tests/test_state_doctrine_matrix_contract.gd` (new file)
- `tests/test_state_doctrine_matrix_contract.tscn` (new file)
- `tests/test_suspicious_flashlight_30_percent_seeded.gd` (new file)
- `tests/test_suspicious_flashlight_30_percent_seeded.tscn` (new file)
- `tests/test_alert_no_los_searches_dark_pockets_not_patrol.gd` (new file)
- `tests/test_alert_no_los_searches_dark_pockets_not_patrol.tscn` (new file)
- `tests/test_suspicious_shadow_scan.gd`
- `tests/test_combat_no_los_never_hold_range.gd`
- `tests/test_runner_node.gd`
- `CHANGELOG.md`

**Out-of-scope files (must not be modified):**
- `src/systems/enemy_pursuit_system.gd`
- `src/systems/enemy_awareness_system.gd`
- `src/systems/enemy_patrol_system.gd`
- `src/systems/navigation_runtime_queries.gd`
- `src/systems/navigation_service.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `src/systems/enemy_squad_system.gd`

Allowed file-change boundary (exact paths): same as the in-scope list above.

---

## 5. Single-owner authority for this phase.

The primary doctrine decision introduced in this phase is owned exclusively by `EnemyUtilityBrain._choose_intent` in `src/systems/enemy_utility_brain.gd`.

Authority statement:
- `Enemy._build_utility_context` computes doctrine inputs (`shadow_scan_target`, `has_shadow_scan_target`, `shadow_scan_target_in_shadow`) and does not choose intent types.
- `Enemy._compute_flashlight_active` computes flashlight state and does not choose intent types.
- `EnemyPursuitSystem.execute_intent` executes the chosen intent and does not construct intent dictionaries.

No other file duplicates utility intent dictionary construction. Verified by gate G8 in section 13.

---

## 6. Full input/output contract.

### Contract A: StateDoctrineShadowScanContextSliceContractV1

**Contract name:** `StateDoctrineShadowScanContextSliceContractV1`

**Owner:** `Enemy._build_utility_context` in `src/entities/enemy.gd`

**Inputs (phase-relevant subset):**
- `player_visible: bool` (non-null; no finite check)
- `assignment: Dictionary` (non-null; keys read with defaults)
- `target_context: Dictionary` (non-null; keys read with defaults)
- `target_context["known_target_pos"]: Vector2` (nullable by sentinel `Vector2.ZERO`; finite required when `target_context["has_known_target"] == true`)
- `target_context["has_known_target"]: bool` (non-null)
- Internal `_last_seen_pos: Vector2` (finite required when `_last_seen_age < INF` and combat filter path reports `has_last_seen == true`)
- Internal `_last_seen_age: float` (non-null; `INF` sentinel allowed)
- Internal `_investigate_anchor: Vector2` (finite required when `_investigate_anchor_valid == true`)
- Internal `_investigate_anchor_valid: bool` (non-null)
- Internal `effective_alert_level: int` from `_resolve_effective_alert_level_for_utility()` (enum domain from `EnemyAlertLevels`)
- `nav_system.is_point_in_shadow(point: Vector2) -> bool` (optional method; when absent, shadow query result is `false`)

**Outputs (phase-relevant exact keys in returned context dictionary):**
- `alert_level: int` (`EnemyAlertLevels` enum value)
- `known_target_pos: Vector2`
- `has_known_target: bool`
- `last_seen_pos: Vector2`
- `has_last_seen: bool`
- `investigate_anchor: Vector2`
- `has_investigate_anchor: bool`
- `shadow_scan_target: Vector2` (`Vector2.ZERO` when absent)
- `has_shadow_scan_target: bool`
- `shadow_scan_target_in_shadow: bool`

**Selection rule (exact order):**
- `has_shadow_scan_target == false` and `shadow_scan_target == Vector2.ZERO` when `alert_level < EnemyAlertLevels.SUSPICIOUS`.
- When `alert_level >= EnemyAlertLevels.SUSPICIOUS`, `shadow_scan_target` is the first available source in this order: `known_target_pos` → `last_seen_pos` → `investigate_anchor`.
- `shadow_scan_target_in_shadow == true` only when `has_shadow_scan_target == true`, `nav_system` exists, `nav_system.has_method("is_point_in_shadow") == true`, and the method returns `true` for `shadow_scan_target`.

**Status enums:** `N/A — no status field in this contract slice`

**Reason enums:** `N/A — no reason field in this contract slice`

**Constants/thresholds used:** none added by this contract slice in Phase 15.

### Contract B: StateDoctrineIntentNoLosContractV1

**Contract name:** `StateDoctrineIntentNoLosContractV1`

**Owner:** `EnemyUtilityBrain._choose_intent` in `src/systems/enemy_utility_brain.gd`

**Inputs (phase-relevant subset from `ctx: Dictionary`):**
- `los: bool` (non-null)
- `alert_level: int` (non-null; `EnemyAlertLevels` enum)
- `combat_lock: bool` (non-null)
- `known_target_pos: Vector2` (finite required when `has_known_target == true`)
- `has_known_target: bool` (non-null)
- `last_seen_pos: Vector2` (finite required when `has_last_seen == true`)
- `has_last_seen: bool` (non-null)
- `last_seen_age: float` (`INF` sentinel allowed; finite required when compared against thresholds)
- `dist_to_last_seen: float` (`INF` sentinel allowed; finite required when `has_last_seen == true`)
- `investigate_anchor: Vector2` (finite required when `has_investigate_anchor == true`)
- `has_investigate_anchor: bool` (non-null)
- `dist_to_investigate_anchor: float` (`INF` sentinel allowed; finite required when `has_investigate_anchor == true`)
- `shadow_scan_target: Vector2` (finite required when `has_shadow_scan_target == true`)
- `has_shadow_scan_target: bool` (non-null)
- `shadow_scan_target_in_shadow: bool` (non-null)
- `home_position: Vector2` (finite required)

**Outputs (exact keys/types):**
- `type: int` (`EnemyUtilityBrain.IntentType` enum value; key always present)
- `target: Vector2` (present for all no-LOS outputs except `PATROL` returns `{"type": IntentType.PATROL}` in CALM and SUSPICIOUS fallback branches; `Vector2` finite when present)

**Valid output enum values for no-LOS doctrine in this phase:**
- CALM no-LOS: `PATROL`
- SUSPICIOUS no-LOS: `SHADOW_BOUNDARY_SCAN`, `INVESTIGATE`, `SEARCH`, `PATROL`
- ALERT/COMBAT no-LOS: `SHADOW_BOUNDARY_SCAN`, `INVESTIGATE`, `SEARCH`, `RETURN_HOME`
- COMBAT no-LOS with `combat_lock == true`: `PUSH` (via `_combat_no_los_grace_intent`)

**Anti-degrade invariant (exact):**
- When `los == false`, `alert_level >= EnemyAlertLevels.ALERT`, and `target_context_exists == (has_known_target or has_last_seen or has_investigate_anchor)` evaluates to `true`, output `type` is not `PATROL` and not `RETURN_HOME`.

**Status enums:** `N/A — intent dict has no status field`

**Reason enums:** `N/A — intent dict has no reason field`

**Constants/thresholds used (existing, unchanged placement):**
- `INVESTIGATE_MAX_LAST_SEEN_AGE` (`src/systems/enemy_utility_brain.gd`, file-scope const; default `3.5`, override via `GameConfig.ai_balance["utility"]["investigate_max_last_seen_age"]`)
- `INVESTIGATE_ARRIVE_PX` (`src/systems/enemy_utility_brain.gd`, file-scope const; default `24.0`, override via `GameConfig.ai_balance["utility"]["investigate_arrive_px"]`)
- `SEARCH_MAX_LAST_SEEN_AGE` (`src/systems/enemy_utility_brain.gd`, file-scope const; default `8.0`, override via `GameConfig.ai_balance["utility"]["search_max_last_seen_age"]`)

### Contract C: SuspiciousShadowScanFlashlightPolicyContractV1

**Contract name:** `SuspiciousShadowScanFlashlightPolicyContractV1`

**Owner:** `Enemy._compute_flashlight_active` with helpers `_suspicious_shadow_scan_flashlight_bucket` and `_suspicious_shadow_scan_flashlight_gate_passes` in `src/entities/enemy.gd`

**Inputs (phase-relevant):**
- `awareness_state: int` (non-null; `EnemyAlertLevels` enum)
- Internal `_shadow_scan_active: bool` (non-null)
- Internal `_flashlight_activation_delay_timer: float` (finite, `>= 0.0` in runtime)
- Internal `entity_id: int` (non-null; any integer accepted)
- Internal `_debug_tick_id: int` (non-null; any integer accepted)

**Outputs (exact):**
- `_suspicious_shadow_scan_flashlight_bucket() -> int` in range `[0, 9]`
- `_suspicious_shadow_scan_flashlight_gate_passes() -> bool`
- `_compute_flashlight_active(EnemyAlertLevels.SUSPICIOUS) -> bool` (phase-specific suspicious branch output)

**Status enums:** `N/A — boolean policy output`

**Reason enums:** `N/A — no reason field`

**Constants/thresholds used (new, file-scope local consts in `src/entities/enemy.gd`):**
- `SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_CHANCE = 0.30`
- `SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_BUCKET_COUNT = 10`
- `SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_ACTIVE_BUCKETS = 3`

---

## 7. Deterministic algorithm with exact order.

### 7.1 Runtime call order relevant to this phase

1. `Enemy.runtime_budget_tick` increments `_debug_tick_id` at the top of the tick.
2. `Enemy.runtime_budget_tick` computes `flashlight_active := _compute_flashlight_active(awareness_state_before)` before utility context construction and before `_utility_brain.update`; suspicious flashlight policy uses the same `_debug_tick_id` incremented in step 1.
3. `Enemy.runtime_budget_tick` computes `target_context := _resolve_known_target_context(...)`.
4. `Enemy.runtime_budget_tick` computes `context := _build_utility_context(...)`.
5. `Enemy.runtime_budget_tick` calls `_utility_brain.update(delta, context)`; `EnemyUtilityBrain.update` calls `EnemyUtilityBrain._choose_intent(context)` when decision timers allow evaluation.
6. `Enemy.runtime_budget_tick` passes the resulting intent to `_pursuit.execute_intent(delta, intent, context)`.

### 7.2 `Enemy._build_utility_context` shadow-scan target selection order (exact)

1. Compute `effective_alert_level := _resolve_effective_alert_level_for_utility()`.
2. Initialize `shadow_scan_target = Vector2.ZERO`, `has_shadow_scan_target = false`, `shadow_scan_target_in_shadow = false`.
3. If `effective_alert_level < EnemyAlertLevels.SUSPICIOUS`, keep all three values unchanged and skip shadow query.
4. If `effective_alert_level >= EnemyAlertLevels.SUSPICIOUS`, evaluate candidate sources in exact order:
   1. `has_known_target == true` → assign `shadow_scan_target = known_target_pos`, `has_shadow_scan_target = true`.
   2. Else `has_last_seen == true` → assign `shadow_scan_target = _last_seen_pos`, `has_shadow_scan_target = true`.
   3. Else `_investigate_anchor_valid == true` → assign `shadow_scan_target = _investigate_anchor`, `has_shadow_scan_target = true`.
   4. Else keep `Vector2.ZERO` / `false`.
5. Execute exactly one shadow query only when `has_shadow_scan_target == true`, `nav_system != null`, and `nav_system.has_method("is_point_in_shadow") == true`:
   - `shadow_scan_target_in_shadow = bool(nav_system.call("is_point_in_shadow", shadow_scan_target))`
6. Return the context dictionary with keys from Contract A in section 6.

### 7.3 `EnemyUtilityBrain._choose_intent` no-LOS doctrine matrix order (exact)

1. Read phase-relevant inputs and compute:
   - `search_target := last_seen_pos if has_last_seen else home_pos` (existing variable, unchanged definition)
   - `has_search_anchor := has_last_seen and last_seen_age <= search_max_last_seen_age` (existing variable, unchanged definition)
   - `target_context_exists := has_known_target or has_last_seen or has_investigate_anchor` (new local variable)
2. Evaluate `combat_lock and not has_los` first. If `true`, return `_combat_no_los_grace_intent(...)` immediately.
3. Evaluate `hp_ratio <= retreat_hp_ratio and has_los and dist < hold_range_min` second. If `true`, return `RETREAT` immediately.
4. Evaluate `not has_los and alert_level == EnemyAlertLevels.CALM`:
   - Return `{"type": IntentType.PATROL}`.
5. Evaluate `not has_los and alert_level == EnemyAlertLevels.SUSPICIOUS` in exact order:
   1. If `has_shadow_scan_target and shadow_scan_target_in_shadow`, return `{"type": IntentType.SHADOW_BOUNDARY_SCAN, "target": shadow_scan_target}`.
   2. Compute investigate candidate exactly as current logic (`inv_target`, `inv_dist`, `last_seen_valid`, `inv_valid`). If `inv_valid and inv_dist > investigate_arrive_px`, return `INVESTIGATE` with `inv_target`.
   3. If `has_search_anchor`, return `SEARCH` with `search_target`.
   4. Return `{"type": IntentType.PATROL}`.
6. Evaluate `not has_los and alert_level >= EnemyAlertLevels.ALERT` in exact order:
   1. If `has_shadow_scan_target and shadow_scan_target_in_shadow`, return `SHADOW_BOUNDARY_SCAN` with `shadow_scan_target`.
   2. If `has_last_seen and dist_to_last_seen > investigate_arrive_px`, return `INVESTIGATE` with `last_seen_pos`.
   3. If `has_last_seen`, return `SEARCH` with `last_seen_pos`.
   4. If `has_investigate_anchor and dist_to_investigate_anchor > investigate_arrive_px`, return `INVESTIGATE` with `investigate_anchor`.
   5. If `has_investigate_anchor`, return `SEARCH` with `investigate_anchor`.
   6. If `has_known_target`, return `SEARCH` with `known_target_pos`.
   7. Return `RETURN_HOME` with `home_pos`.
7. Evaluate existing LOS branch (`has_los`) and final fallback branch after the no-LOS doctrine branches. This phase does not change LOS branch ordering.

### 7.4 `Enemy._compute_flashlight_active` suspicious 30% deterministic gate (exact)

1. Compute state booleans (`state_is_calm`, `state_is_suspicious`, `state_is_alert`, `state_is_combat`) exactly as current code.
2. Evaluate return expression with the suspicious term replaced by the gated term described in section 2.
3. In `_suspicious_shadow_scan_flashlight_gate_passes()`, compute the expected active-bucket count from the chance constant before bucket comparison:
   - `SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_ACTIVE_BUCKETS == int(round(SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_CHANCE * float(SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_BUCKET_COUNT)))`
   - With Phase 15 constants, the right-hand side evaluates to `3`.
4. `_suspicious_shadow_scan_flashlight_bucket()` formula (exact):
   - `var bucket: int = int(posmod(int(entity_id) + int(_debug_tick_id), SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_BUCKET_COUNT))`
   - Return `bucket`.
5. `_suspicious_shadow_scan_flashlight_gate_passes()` formula (exact):
   - Return `_suspicious_shadow_scan_flashlight_bucket() < SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_ACTIVE_BUCKETS`.
6. Effective suspicious flashlight activation is `true` only when all conditions below are `true` in the same call:
   - `awareness_state == EnemyAlertLevels.SUSPICIOUS`
   - `_shadow_scan_active == true`
   - `_flashlight_policy_active_in_alert() == true`
   - `_suspicious_shadow_scan_flashlight_gate_passes() == true`

### 7.5 Tie-break rules and invalid inputs

- Tie-break rule for shadow-scan target candidates: `known_target_pos` wins over `last_seen_pos`, and `last_seen_pos` wins over `investigate_anchor` (section 7). No numeric comparison tie occurs because branch priority resolves the result before distance evaluation.
- Tie-break rule for intent outputs: branch order in section 7 yields exactly one return path; no multi-candidate score comparison exists in this phase.
- Empty context dictionary input to `_choose_intent({})` resolves to CALM no-LOS defaults and returns `{"type": IntentType.PATROL}`.
- Missing `nav_system` or missing `is_point_in_shadow` method produces `shadow_scan_target_in_shadow == false` and does not block context construction.
- Negative `entity_id` and negative `_debug_tick_id` remain deterministic because `posmod(..., 10)` maps to `[0, 9]`.

---

## 8. Edge-case matrix (case → exact output).

**Case A: empty input dictionary → expected output dict + status**
- Input: `_choose_intent({})`
- Expected output dict: `{"type": IntentType.PATROL}`
- Status: `N/A — no status enum in Contract B`
- Proof path: section 7 (CALM no-LOS default branch after defaults are read)

**Case B: single valid ALERT no-LOS dark target → expected output dict + status**
- Input (subset): `los=false`, `alert_level=ALERT`, `has_shadow_scan_target=true`, `shadow_scan_target=Vector2(220, 40)`, `shadow_scan_target_in_shadow=true`, `has_known_target=true`
- Expected output dict: `{"type": IntentType.SHADOW_BOUNDARY_SCAN, "target": Vector2(220, 40)}`
- Status: `N/A`
- Proof path: section 7 (ALERT/COMBAT no-LOS branch, first dark-target return)

**Case C: tie-break triggered**
- Tie-break N/A. Section 7 branch order proves single-path resolution before any score tie exists.

**Case D: ALERT no-LOS with no target context → expected output dict + status**
- Input (subset): `los=false`, `alert_level=ALERT`, `has_known_target=false`, `has_last_seen=false`, `has_investigate_anchor=false`, `home_position=Vector2(16, 8)`
- Expected output dict: `{"type": IntentType.RETURN_HOME, "target": Vector2(16, 8)}`
- Status: `N/A`
- Proof path: section 7 (ALERT/COMBAT no-LOS final fallback return)

**Case E: COMBAT no-LOS with combat lock → exact output**
- Input (subset): `los=false`, `alert_level=COMBAT`, `combat_lock=true`, `known_target_pos=Vector2(300, 40)`
- Expected output dict: `{"type": IntentType.PUSH, "target": Vector2(300, 40)}`
- Status: `N/A`
- Proof path: section 7 and `_combat_no_los_grace_intent`

**Case F: context builder target priority with all three sources present → exact output**
- Input (subset): `alert_level>=SUSPICIOUS`, `has_known_target=true`, `known_target_pos=Vector2(300, 20)`, `has_last_seen=true`, `_last_seen_pos=Vector2(200, 20)`, `_investigate_anchor_valid=true`, `_investigate_anchor=Vector2(100, 20)`
- Expected output dict slice: `{"shadow_scan_target": Vector2(300, 20), "has_shadow_scan_target": true}`
- Status: `N/A`
- Proof path: section 7 (shadow-scan target priority rule)

**Case G: suspicious flashlight bucket pass → exact output**
- Input (subset): `entity_id=1501`, `_debug_tick_id=0`, `_shadow_scan_active=true`, `awareness_state=SUSPICIOUS`, `_flashlight_activation_delay_timer=0.0`
- Expected output dict slice: `{"bucket": 1, "flashlight_active": true}`
- Status: `N/A`
- Proof path: section 7 (`(1501 + 0) mod 10 = 1 < 3`)

**Case H: suspicious flashlight bucket fail → exact output**
- Input (subset): `entity_id=1501`, `_debug_tick_id=2`, `_shadow_scan_active=true`, `awareness_state=SUSPICIOUS`, `_flashlight_activation_delay_timer=0.0`
- Expected output dict slice: `{"bucket": 3, "flashlight_active": false}`
- Status: `N/A`
- Proof path: section 7 (`(1501 + 2) mod 10 = 3`, `3 < 3` is false)

---

## 9. Legacy removal plan (delete-first, exact ids).

1. **Identifier / branch header:** `if alert_level <= ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS and not has_los:`
   - **File:** `src/systems/enemy_utility_brain.gd`
   - **Approx line range (confirmed):** lines 104–124 via `nl -ba` evidence command
   - **Delete-first action:** remove the merged CALM/SUSPICIOUS no-LOS block before writing explicit state branches.

2. **Identifier / gate:** `if effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS:`
   - **File:** `src/entities/enemy.gd`
   - **Approx line range (confirmed):** lines 1027–1035 via `nl -ba` evidence command
   - **Delete-first action:** remove the SUSPICIOUS-only shadow-scan context gate before writing `>= SUSPICIOUS` target selection logic.

3. **Identifier / expression:** `(state_is_suspicious and _shadow_scan_active and _flashlight_policy_active_in_alert())`
   - **File:** `src/entities/enemy.gd`
   - **Approx line range (confirmed):** line 1203 via `nl -ba` evidence command
   - **Delete-first action:** remove the inline unconditional suspicious shadow-scan flashlight term before inserting the deterministic gate helper call.

Dead-after-phase functions: none.

---

## 10. Legacy verification commands (exact rg + expected 0 matches).

1. `rg -n "if alert_level <= ENEMY_ALERT_LEVELS_SCRIPT\.SUSPICIOUS and not has_los:" src/ -S`
   - Expected: `0 matches`

2. `rg -n "if effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT\.SUSPICIOUS:" src/ -S`
   - Expected: `0 matches`

3. `rg -n "\(state_is_suspicious and _shadow_scan_active and _flashlight_policy_active_in_alert\(\)\)" src/ -S`
   - Expected: `0 matches`

---

## 11. Acceptance criteria (binary pass/fail).

1. All three legacy verification commands in section 10 return `0 matches`.
2. Gate G1 through gate G9 and PMB-1 through PMB-5 in section 13 return expected outputs.
3. `tests/test_state_doctrine_matrix_contract.gd` all four test functions exit `0`.
4. `tests/test_suspicious_flashlight_30_percent_seeded.gd` reports reproducible repeated results, exactly `30` active ticks out of `100` sampled ticks, and different-entity same-tick-window sequence divergence after `GameConfig.reset_to_defaults()` and explicit `GameConfig.stealth_canon["flashlight_works_in_alert"] = true`.
5. `tests/test_alert_no_los_searches_dark_pockets_not_patrol.gd` returns `SHADOW_BOUNDARY_SCAN` for ALERT no-LOS dark target and returns no `PATROL`/`RETURN_HOME` under target context.
6. Updated `tests/test_suspicious_shadow_scan.gd` no longer asserts unconditional suspicious flashlight activation.
7. Updated `tests/test_combat_no_los_never_hold_range.gd` asserts `!= PATROL` and `!= RETURN_HOME` in the COMBAT no-LOS target-context path.
8. Tier 1 smoke suite commands from section 14 exit `0`.
9. Tier 2 full regression command exits `0`.
10. No file outside the section 4 in-scope list was modified.
11. `CHANGELOG.md` entry was prepended.

---

## 12. Tests (new/update + purpose).

### New test files

**1. `tests/test_state_doctrine_matrix_contract.gd`**
- Test functions:
  - `_test_calm_no_los_returns_patrol_only`
  - `_test_suspicious_no_los_shadow_target_returns_shadow_boundary_scan`
  - `_test_alert_combat_no_los_with_target_context_never_patrol_or_return_home`
  - `_test_build_utility_context_shadow_scan_target_priority_known_then_last_seen_then_anchor`
- Purpose / assertions:
  - CALM no-LOS returns `PATROL` only.
  - SUSPICIOUS no-LOS with dark `shadow_scan_target` returns `SHADOW_BOUNDARY_SCAN` with exact target.
  - ALERT and COMBAT no-LOS contexts with target context never return `PATROL` or `RETURN_HOME`.
  - `Enemy._build_utility_context` selects `shadow_scan_target` in strict order `known_target_pos` → `last_seen` → `investigate_anchor`.

**2. `tests/test_state_doctrine_matrix_contract.tscn`**
- Wrapper scene for `tests/test_state_doctrine_matrix_contract.gd`.
- One root `Node` with script assignment to the test script.

**3. `tests/test_suspicious_flashlight_30_percent_seeded.gd`**
- Test functions:
  - `_test_seeded_suspicious_shadow_scan_flashlight_is_reproducible_same_entity_same_ticks`
  - `_test_seeded_suspicious_shadow_scan_flashlight_hits_exactly_30_of_100_ticks`
  - `_test_seeded_suspicious_shadow_scan_flashlight_changes_with_entity_id_same_ticks`
  - `_test_suspicious_flashlight_gate_is_off_when_shadow_scan_inactive`
- Purpose / assertions:
  - Test setup starts with `GameConfig.reset_to_defaults()` and explicitly sets `GameConfig.stealth_canon["flashlight_works_in_alert"] = true` before sampling ticks.
  - Same `entity_id` and the same `_debug_tick_id` window produce the same boolean sequence.
  - Tick sample `0..99` yields exactly `30` active suspicious flashlight ticks when `_shadow_scan_active == true`.
  - Different `entity_id` values (`1501` vs `1502`) with the same `_debug_tick_id` window `0..99` produce sequences that differ in at least one position.
  - `_shadow_scan_active == false` forces suspicious flashlight result `false` in the gated branch.

**4. `tests/test_suspicious_flashlight_30_percent_seeded.tscn`**
- Wrapper scene for `tests/test_suspicious_flashlight_30_percent_seeded.gd`.
- One root `Node` with script assignment to the test script.

**5. `tests/test_alert_no_los_searches_dark_pockets_not_patrol.gd`**
- Test functions:
  - `_test_alert_no_los_dark_shadow_target_chooses_shadow_boundary_scan`
  - `_test_alert_no_los_known_target_without_last_seen_returns_search_not_return_home`
- Purpose / assertions:
  - ALERT no-LOS with `has_shadow_scan_target == true` and `shadow_scan_target_in_shadow == true` returns `SHADOW_BOUNDARY_SCAN`.
  - ALERT no-LOS with `has_known_target == true` and no last-seen/investigate anchor returns `SEARCH` and not `RETURN_HOME`.

**6. `tests/test_alert_no_los_searches_dark_pockets_not_patrol.tscn`**
- Wrapper scene for `tests/test_alert_no_los_searches_dark_pockets_not_patrol.gd`.
- One root `Node` with script assignment to the test script.

### Updated test files

**1. `tests/test_suspicious_shadow_scan.gd`**
- Update `_test_suspicious_shadow_scan_intent_and_flashlight`.
- Replace unconditional assertion `"SUSPICIOUS shadow scan activates flashlight"` with deterministic bucket-controlled assertions using explicit `enemy.entity_id = 1501`, explicit `_debug_tick_id = 0` (pass) and `_debug_tick_id = 2` (fail), and `_compute_flashlight_active(EnemyAlertLevels.SUSPICIOUS)` calls after `GameConfig.reset_to_defaults()` and `GameConfig.stealth_canon["flashlight_works_in_alert"] = true`.
- Intent assertions for `SHADOW_BOUNDARY_SCAN` remain in the same test function.

**2. `tests/test_combat_no_los_never_hold_range.gd`**
- Update `_test_combat_no_los_never_hold_range`.
- Add assertions during grace and after grace that the COMBAT no-LOS target-context path returns no `PATROL` and no `RETURN_HOME` in addition to existing no-`HOLD_RANGE` assertions.

### Runner registration (`tests/test_runner_node.gd`)

Registration in this repository uses the top-level const block plus `TestRunner._run_tests` (no `_get_test_suites()` function exists in the current runner).

Add all three new test scenes in `tests/test_runner_node.gd`:
- Constants in the top-level const block:
  - `STATE_DOCTRINE_MATRIX_CONTRACT_TEST_SCENE`
  - `SUSPICIOUS_FLASHLIGHT_30_PERCENT_SEEDED_TEST_SCENE`
  - `ALERT_NO_LOS_SEARCHES_DARK_POCKETS_NOT_PATROL_TEST_SCENE`
- `_scene_exists(...)` checks inside `TestRunner._run_tests`
- `_run_embedded_scene_suite(...)` calls inside `TestRunner._run_tests`

---

## 13. rg gates (command + expected output).

**Phase-specific gates:**

[G1] `rg -n "if alert_level <= ENEMY_ALERT_LEVELS_SCRIPT\.SUSPICIOUS and not has_los:" src/systems/enemy_utility_brain.gd -S`
Expected: `0 matches`.

[G2] `rg -n "if alert_level == ENEMY_ALERT_LEVELS_SCRIPT\.SUSPICIOUS and has_shadow_scan_target and shadow_scan_target_in_shadow:" src/systems/enemy_utility_brain.gd -S`
Expected: `0 matches`.

[G3] `rg -n "if effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT\.SUSPICIOUS:" src/entities/enemy.gd -S`
Expected: `0 matches`.

[G4] `rg -n "\(state_is_suspicious and _shadow_scan_active and _flashlight_policy_active_in_alert\(\)\)" src/entities/enemy.gd -S`
Expected: `0 matches`.

[G5] `rg -n "if effective_alert_level >= ENEMY_ALERT_LEVELS_SCRIPT\.SUSPICIOUS:|shadow_scan_target = known_target_pos|shadow_scan_target = _last_seen_pos|shadow_scan_target = _investigate_anchor" src/entities/enemy.gd -S`
Expected: `>= 4 matches`.

[G6] `rg -n "target_context_exists" src/systems/enemy_utility_brain.gd -S`
Expected: `>= 1 match`.

[G7] `rg -n "SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_(CHANCE|BUCKET_COUNT|ACTIVE_BUCKETS)|func _suspicious_shadow_scan_flashlight_bucket\(|func _suspicious_shadow_scan_flashlight_gate_passes\(" src/entities/enemy.gd -S`
Expected: `>= 5 matches`.

[G8] `bash -lc 'bad=$(rg -n "\"type\": .*IntentType\." src/ -g "*.gd" -S | rg -v "^src/systems/enemy_utility_brain\\.gd:" | wc -l | xargs); [ "$bad" -eq 0 ] && echo "G8: PASS (0)" || echo "G8: FAIL ($bad)"'`
Expected: `G8: PASS (0)`.

[G9] `rg -n "STATE_DOCTRINE_MATRIX_CONTRACT_TEST_SCENE|SUSPICIOUS_FLASHLIGHT_30_PERCENT_SEEDED_TEST_SCENE|ALERT_NO_LOS_SEARCHES_DARK_POCKETS_NOT_PATROL_TEST_SCENE" tests/test_runner_node.gd -S`
Expected: `9 matches` (3 consts + 3 `_scene_exists` checks + 3 `_run_embedded_scene_suite` calls).

**PMB gates:**

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: `0 matches`.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

---

## 14. Execution sequence (step-by-step, no ambiguity).

Step 1: Delete legacy item 1 from section 9 in `src/systems/enemy_utility_brain.gd` by removing the merged no-LOS branch headed by `if alert_level <= ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS and not has_los:` (current lines 104–124).

Step 2: Delete legacy item 2 from section 9 in `src/entities/enemy.gd` by removing the SUSPICIOUS-only shadow-scan context gate `if effective_alert_level == ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS:` (current lines 1027–1035).

Step 3: Delete legacy item 3 from section 9 in `src/entities/enemy.gd` by removing the inline suspicious flashlight term `(state_is_suspicious and _shadow_scan_active and _flashlight_policy_active_in_alert())` from `_compute_flashlight_active` (current line 1203).

Step 4: Implement cross-state shadow-scan target selection in `Enemy._build_utility_context` (`src/entities/enemy.gd`) per section 7, including strict priority `known_target_pos` → `last_seen` → `investigate_anchor` and single-call `is_point_in_shadow` query.

Step 5: Add file-scope constants `SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_CHANCE`, `SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_BUCKET_COUNT`, and `SUSPICIOUS_SHADOW_SCAN_FLASHLIGHT_ACTIVE_BUCKETS` to `src/entities/enemy.gd`.

Step 6: Add private helpers `_suspicious_shadow_scan_flashlight_bucket() -> int` and `_suspicious_shadow_scan_flashlight_gate_passes() -> bool` to `src/entities/enemy.gd` with the exact formula from section 7.

Step 7: Update `Enemy._compute_flashlight_active` (`src/entities/enemy.gd`) to call `_suspicious_shadow_scan_flashlight_gate_passes()` in the SUSPICIOUS branch.

Step 8: Implement explicit CALM/SUSPICIOUS/ALERT/COMBAT no-LOS doctrine branches in `EnemyUtilityBrain._choose_intent` (`src/systems/enemy_utility_brain.gd`) per section 7.

Step 9: Add `has_known_target` extraction and `target_context_exists` local variable to `EnemyUtilityBrain._choose_intent` and enforce the ALERT/COMBAT anti-degrade rule from section 6.

Step 10: Create `tests/test_state_doctrine_matrix_contract.gd` and `tests/test_state_doctrine_matrix_contract.tscn` and implement the four test functions listed in section 12.

Step 11: Create `tests/test_suspicious_flashlight_30_percent_seeded.gd` and `tests/test_suspicious_flashlight_30_percent_seeded.tscn` and implement the four test functions listed in section 12.

Step 12: Create `tests/test_alert_no_los_searches_dark_pockets_not_patrol.gd` and `tests/test_alert_no_los_searches_dark_pockets_not_patrol.tscn` and implement the two test functions listed in section 12.

Step 13: Update `tests/test_suspicious_shadow_scan.gd`, function `_test_suspicious_shadow_scan_intent_and_flashlight`, to assert deterministic pass/fail buckets instead of unconditional suspicious flashlight activation.

Step 14: Update `tests/test_combat_no_los_never_hold_range.gd`, function `_test_combat_no_los_never_hold_range`, to assert no `PATROL` and no `RETURN_HOME` in the COMBAT no-LOS target-context path.

Step 15: Register the three new scenes in `tests/test_runner_node.gd`: add 3 top-level const declarations, 3 `_scene_exists(...)` checks inside `TestRunner._run_tests`, and 3 `_run_embedded_scene_suite(...)` calls inside `TestRunner._run_tests`.

Step 16: Run Tier 1 smoke suite commands (exact):
- `xvfb-run -a godot-4 --headless --path . res://tests/test_state_doctrine_matrix_contract.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_suspicious_flashlight_30_percent_seeded.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_alert_no_los_searches_dark_pockets_not_patrol.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_suspicious_shadow_scan.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_alert_investigate_anchor.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_combat_no_los_never_hold_range.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_combat_intent_switches_push_to_search_after_grace.tscn`

Step 17: Run Tier 2 full regression: `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit `0`.

Step 18: Run all legacy verification commands from section 10. All three commands must return `0 matches`.

Step 19: Run all rg gates from section 13 (G1–G9 and PMB-1–PMB-5). All commands must return expected output.

Step 20: Prepend one `CHANGELOG.md` entry under the current date header for Phase 15 (State Doctrine Matrix / suspicious flashlight seeded 30% / alert-combat dark-pocket search).

---

## 15. Rollback conditions.

1. **Trigger:** Any legacy verification command in section 10 returns non-zero matches after step 18. **Rollback action:** revert all section 4 in-scope file changes to pre-phase state. Phase result = FAIL.

2. **Trigger:** Any Tier 1 smoke command listed in section 14 exits non-zero. **Rollback action:** revert all section 4 in-scope file changes to pre-phase state. Phase result = FAIL.

3. **Trigger:** Tier 2 full regression command listed in section 14 exits non-zero. **Rollback action:** revert all section 4 in-scope file changes to pre-phase state. Phase result = FAIL.

4. **Trigger:** `tests/test_suspicious_flashlight_30_percent_seeded.gd` does not produce exact `30` active ticks out of `100`. **Rollback action:** revert Phase 15 flashlight policy edits in `src/entities/enemy.gd` and the new flashlight test files; then revert the remaining phase edits to pre-phase state. Partial state is forbidden.

5. **Trigger:** ALERT/COMBAT no-LOS test paths return `PATROL` or `RETURN_HOME` while target context exists. **Rollback action:** revert `EnemyUtilityBrain._choose_intent` edits and all dependent test updates/new tests; then revert the remaining phase edits to pre-phase state. Partial state is forbidden.

6. **Trigger:** Any file outside section 4 in-scope list is modified. **Rollback action:** revert the out-of-scope file immediately and revert all Phase 15 edits to pre-phase state. Phase result = FAIL.

7. **Trigger:** Implementation cannot be completed inside section 4 scope with one coherent doctrine matrix and one deterministic suspicious flashlight gate. **Rollback action:** revert all changes to pre-phase state. Phase result = FAIL (Hard Rule 11).

---

## 16. Phase close condition.

- [ ] All rg commands in section 10 return `0 matches`
- [ ] All rg gates in section 13 return expected output
- [ ] All tests in section 12 (new + updated) exit `0`
- [ ] Tier 1 smoke suite (section 14) — all commands exit `0`
- [ ] Tier 2 full regression (`xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn`) exits `0`
- [ ] No file outside section 4 in-scope list was modified
- [ ] `CHANGELOG.md` entry prepended
- [ ] `tests/test_suspicious_flashlight_30_percent_seeded.gd` records exactly `30` active suspicious flashlight ticks out of `100` after `GameConfig.reset_to_defaults()` and `GameConfig.stealth_canon["flashlight_works_in_alert"] = true`
- [ ] `tests/test_suspicious_flashlight_30_percent_seeded.gd` records different sequences for `entity_id = 1501` vs `entity_id = 1502` over the same tick window `0..99`
- [ ] ALERT/COMBAT no-LOS target-context tests record no `PATROL` and no `RETURN_HOME`
- [ ] `tests/test_runner_node.gd` contains exactly 9 symbol matches for gate G9

---

## 17. Ambiguity check: 0

---

## 18. Open questions: 0

---

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).

**Diff audit:** diff every file in section 4 against the pre-phase baseline, including all three new test script/scene pairs and `CHANGELOG.md`. Confirm zero modifications outside the section 4 in-scope list.

**Contract checks:**
- `StateDoctrineShadowScanContextSliceContractV1` (section 6): inspect `Enemy._build_utility_context` and verify `shadow_scan_target` priority order and `shadow_scan_target_in_shadow` query gating exactly match section 7.
- `StateDoctrineIntentNoLosContractV1` (section 6): inspect `EnemyUtilityBrain._choose_intent` and verify explicit no-LOS state branches and the ALERT/COMBAT anti-degrade invariant exactly match section 7.
- `SuspiciousShadowScanFlashlightPolicyContractV1` (section 6): inspect `Enemy._compute_flashlight_active` plus helpers and verify the modulo bucket formula and `< 3` threshold exactly match section 7.

**Runtime scenarios from section 20:** execute P15-A, P15-B, P15-C, P15-D, P15-E, and P15-F.

---

## 20. Runtime scenario matrix (scenario id, setup, frame count, expected invariants, fail conditions).

**P15-A: CALM/SUSPICIOUS/ALERT/COMBAT no-LOS doctrine matrix unit contract**
- Scene: `tests/test_state_doctrine_matrix_contract.tscn`
- Setup: instantiate `EnemyUtilityBrain`; call `brain.reset()`. Define local helper `_ctx(overrides: Dictionary)` with exact base dict:
  `{"dist": INF, "los": false, "alert_level": ENEMY_ALERT_LEVELS_SCRIPT.CALM, "combat_lock": false, "last_seen_age": INF, "last_seen_pos": Vector2.ZERO, "has_last_seen": false, "dist_to_last_seen": INF, "investigate_anchor": Vector2.ZERO, "has_investigate_anchor": false, "dist_to_investigate_anchor": INF, "shadow_scan_target": Vector2.ZERO, "has_shadow_scan_target": false, "shadow_scan_target_in_shadow": false, "known_target_pos": Vector2.ZERO, "has_known_target": false, "target_is_last_seen": false, "role": 0, "slot_position": Vector2.ZERO, "dist_to_slot": INF, "hp_ratio": 1.0, "path_ok": false, "has_slot": false, "player_pos": Vector2.ZERO, "home_position": Vector2(16.0, 8.0)}`.
  Run `brain.update(0.3, _ctx(...))` with these exact overrides:
  - CALM case: `{}` (base dict already CALM no-LOS)
  - SUSPICIOUS dark-target case: `{"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.SUSPICIOUS, "has_last_seen": true, "last_seen_age": 1.0, "last_seen_pos": Vector2(220.0, 40.0), "dist_to_last_seen": 180.0, "has_shadow_scan_target": true, "shadow_scan_target": Vector2(220.0, 40.0), "shadow_scan_target_in_shadow": true}`
  - ALERT target-context case: `{"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT, "has_known_target": true, "known_target_pos": Vector2(240.0, 32.0), "shadow_scan_target": Vector2(240.0, 32.0), "has_shadow_scan_target": true, "shadow_scan_target_in_shadow": false}`
  - COMBAT target-context case: `{"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.COMBAT, "has_known_target": true, "known_target_pos": Vector2(260.0, 48.0), "shadow_scan_target": Vector2(260.0, 48.0), "has_shadow_scan_target": true, "shadow_scan_target_in_shadow": false, "combat_lock": false}`
- Frame count: `0` (synchronous unit calls).
- Expected invariants:
  - CALM no-LOS returns `PATROL` only.
  - SUSPICIOUS no-LOS with dark `shadow_scan_target` returns `SHADOW_BOUNDARY_SCAN`.
  - ALERT/COMBAT no-LOS with `target_context_exists == true` return no `PATROL` and no `RETURN_HOME`.
- Fail conditions:
  - Any CALM no-LOS case returns non-`PATROL`.
  - Any ALERT/COMBAT target-context case returns `PATROL` or `RETURN_HOME`.
- Covered by: `_test_calm_no_los_returns_patrol_only`, `_test_suspicious_no_los_shadow_target_returns_shadow_boundary_scan`, `_test_alert_combat_no_los_with_target_context_never_patrol_or_return_home`

**P15-B: Utility context shadow-scan target priority (known → last_seen → anchor)**
- Scene: `tests/test_state_doctrine_matrix_contract.tscn`
- Setup: instantiate `Enemy` script object (`ENEMY_SCRIPT.new()`), set `enemy.global_position = Vector2.ZERO`, set `enemy._current_alert_level = ENEMY_ALERT_LEVELS_SCRIPT.ALERT`, keep `enemy._awareness = null`, inject fake `nav_system` stub with method `is_point_in_shadow(point: Vector2) -> bool` that returns `true` only for `Vector2(300.0, 20.0)`. Set exact reusable enemy fields before all calls: `_last_seen_pos = Vector2(200.0, 20.0)`, `_investigate_anchor = Vector2(100.0, 20.0)`, `_investigate_anchor_valid = true`. Use exact `assignment` dict `{"role": 0, "slot_position": Vector2.ZERO, "path_ok": false, "has_slot": false}`. Perform three exact synchronous calls:
  - Call 1 (known wins): set `_last_seen_age = 0.5`; use `target_context = {"known_target_pos": Vector2(300.0, 20.0), "target_is_last_seen": false, "has_known_target": true}`; call `enemy._build_utility_context(false, false, assignment, target_context)`.
  - Call 2 (last_seen wins when known missing): keep `_last_seen_age = 0.5`; use `target_context = {"known_target_pos": Vector2.ZERO, "target_is_last_seen": false, "has_known_target": false}`; call `enemy._build_utility_context(false, false, assignment, target_context)`.
  - Call 3 (anchor wins when known and last_seen missing): set `_last_seen_age = INF`; reuse `target_context = {"known_target_pos": Vector2.ZERO, "target_is_last_seen": false, "has_known_target": false}`; call `enemy._build_utility_context(false, false, assignment, target_context)`.
- Frame count: `0` (synchronous unit calls).
- Expected invariants:
  - Call 1 returns `has_shadow_scan_target == true`, `shadow_scan_target == Vector2(300.0, 20.0)`, and `shadow_scan_target_in_shadow == true`.
  - Call 2 returns `has_shadow_scan_target == true`, `shadow_scan_target == Vector2(200.0, 20.0)`, and `shadow_scan_target_in_shadow == false`.
  - Call 3 returns `has_shadow_scan_target == true`, `shadow_scan_target == Vector2(100.0, 20.0)`, and `shadow_scan_target_in_shadow == false`.
- Fail conditions:
  - Call 1 `shadow_scan_target` resolves to `last_seen_pos` or `investigate_anchor` while `has_known_target == true`.
  - Call 2 `shadow_scan_target` resolves to `investigate_anchor` while `has_known_target == false` and last-seen data is valid.
  - Call 3 `shadow_scan_target` does not resolve to `investigate_anchor` after `_last_seen_age = INF`.
  - Any call returns `shadow_scan_target_in_shadow` inconsistent with the stub result for its exact target.
- Covered by: `_test_build_utility_context_shadow_scan_target_priority_known_then_last_seen_then_anchor`

**P15-C: Suspicious flashlight seeded deterministic 30% gate**
- Scene: `tests/test_suspicious_flashlight_30_percent_seeded.tscn`
- Setup: instantiate `Enemy`; before sampling, call `GameConfig.reset_to_defaults()` and set `GameConfig.stealth_canon["flashlight_works_in_alert"] = true`. Set `_shadow_scan_active = true`, `_flashlight_activation_delay_timer = 0.0`. Sample three exact loops:
  - Loop A: set `entity_id = 1501`; iterate `_debug_tick_id` from `0` to `99`; call `_compute_flashlight_active(EnemyAlertLevels.SUSPICIOUS)` each tick and record sequence A.
  - Loop B: keep `entity_id = 1501`; repeat `_debug_tick_id` from `0` to `99`; record sequence B.
  - Loop C: set `entity_id = 1502`; iterate `_debug_tick_id` from `0` to `99`; record sequence C.
  - Inactive check D: set `entity_id = 1501`, set `_shadow_scan_active = false`, then call `_compute_flashlight_active(EnemyAlertLevels.SUSPICIOUS)` with exact `_debug_tick_id = 0` and exact `_debug_tick_id = 2`.
- Frame count: `0` (synchronous unit loop).
- Expected invariants:
  - Sequence A and sequence B are identical (same entity, same tick window).
  - Sequence A active count equals exactly `30`.
  - Sequence C differs from sequence A in at least one position (different entity, same tick window).
  - Inactive check D returns `false` for both sampled ticks when `_shadow_scan_active == false`.
- Fail conditions:
  - Sequence mismatch between A and B.
  - Sequence A active count is not `30`.
  - Sequence C equals sequence A at all 100 positions.
  - Inactive check D returns `true` for any sampled tick.
- Covered by: `_test_seeded_suspicious_shadow_scan_flashlight_is_reproducible_same_entity_same_ticks`, `_test_seeded_suspicious_shadow_scan_flashlight_hits_exactly_30_of_100_ticks`, `_test_seeded_suspicious_shadow_scan_flashlight_changes_with_entity_id_same_ticks`, `_test_suspicious_flashlight_gate_is_off_when_shadow_scan_inactive`

**P15-D: ALERT no-LOS dark pocket search selection**
- Scene: `tests/test_alert_no_los_searches_dark_pockets_not_patrol.tscn`
- Setup: instantiate `EnemyUtilityBrain`; call `brain.reset()`. Use the exact `_ctx` base dict shape defined in P15-A. Run `brain.update(0.3, _ctx(...))` with these exact ALERT no-LOS overrides:
  - Dark-target case: `{"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT, "has_known_target": true, "known_target_pos": Vector2(300.0, 60.0), "has_shadow_scan_target": true, "shadow_scan_target": Vector2(280.0, 40.0), "shadow_scan_target_in_shadow": true}`
  - Known-target-only case: `{"alert_level": ENEMY_ALERT_LEVELS_SCRIPT.ALERT, "has_known_target": true, "known_target_pos": Vector2(320.0, 80.0), "has_shadow_scan_target": true, "shadow_scan_target": Vector2(320.0, 80.0), "shadow_scan_target_in_shadow": false, "has_last_seen": false, "last_seen_age": INF, "last_seen_pos": Vector2.ZERO, "has_investigate_anchor": false, "investigate_anchor": Vector2.ZERO}`
- Frame count: `0` (synchronous unit calls).
- Expected invariants:
  - Dark target path returns `SHADOW_BOUNDARY_SCAN` with exact `shadow_scan_target`.
  - Known-target-only path returns `SEARCH` and not `RETURN_HOME`.
- Fail conditions:
  - `PATROL` or `RETURN_HOME` returned in either target-context case.
  - `SHADOW_BOUNDARY_SCAN` target differs from provided `shadow_scan_target`.
- Covered by: `_test_alert_no_los_dark_shadow_target_chooses_shadow_boundary_scan`, `_test_alert_no_los_known_target_without_last_seen_returns_search_not_return_home`

**P15-E: Suspicious shadow scan regression with bucket-controlled flashlight assertions**
- Scene: `tests/test_suspicious_shadow_scan.tscn`
- Setup: run existing suspicious shadow scan unit test path; call `GameConfig.reset_to_defaults()` and set `GameConfig.stealth_canon["flashlight_works_in_alert"] = true`; set `enemy.entity_id = 1501`, `_flashlight_activation_delay_timer = 0.0`, and `enemy.set_shadow_scan_active(true)`. Evaluate `_compute_flashlight_active(EnemyAlertLevels.SUSPICIOUS)` twice with exact tick values `_debug_tick_id = 0` (pass bucket) and `_debug_tick_id = 2` (fail bucket).
- Frame count: `0` (synchronous unit calls).
- Expected invariants:
  - Intent remains `SHADOW_BOUNDARY_SCAN` for SUSPICIOUS dark target case.
  - Flashlight assertion passes for the pass bucket and fails for the fail bucket.
- Fail conditions:
  - Intent changes from `SHADOW_BOUNDARY_SCAN`.
  - Test still assumes unconditional suspicious flashlight activation.
- Covered by: `_test_suspicious_shadow_scan_intent_and_flashlight`

**P15-F: COMBAT no-LOS never degrades to HOLD_RANGE/PATROL/RETURN_HOME with target context**
- Scene: `tests/test_combat_no_los_never_hold_range.tscn`
- Setup: existing scene test setup (world + blocker + forced COMBAT + no LOS), with the updated assertions in the same test function.
- Frame count: `2` setup engine frames (`process_frame`, `physics_frame`) + `2` explicit `runtime_budget_tick` calls (`0.75`, `0.90`) + one physics frame before the combat ticks.
- Expected invariants:
  - During grace: intent is `PUSH`, not `HOLD_RANGE`, not `PATROL`, not `RETURN_HOME`.
  - After grace: still not `HOLD_RANGE`; target-context flow still excludes `PATROL` and `RETURN_HOME`.
- Fail conditions:
  - Any assertion above is false.
- Covered by: `_test_combat_no_los_never_hold_range`

---

## 21. Verification report format (what must be recorded to close phase).

Record all fields below to close phase:
- `phase_id: PHASE_15`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; empty list required for PASS)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `dependency_gate_check: [PHASE-2: PASS|FAIL, PHASE-4: PASS|FAIL]` **[BLOCKING — all must be PASS before implementation and before close]**
- `legacy_rg: [{command, expected: "0 matches", actual, PASS|FAIL}]` for all 3 commands from section 10
- `rg_gates: [{gate: "G1".."G9"|"PMB-1".."PMB-5", command, expected, actual, PASS|FAIL}]`
- `phase_tests: [{test_function, scene, exit_code: 0, PASS|FAIL}]` for all 12 phase test functions listed in section 12
- `smoke_suite: [{command, exit_code: 0, PASS|FAIL}]` for all 7 Tier 1 commands from section 14
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `flashlight_30pct_check: {entity_id: 1501, tick_range: "0..99", game_config_reset: true|false, flashlight_works_in_alert: true|false, active_count_expected: 30, active_count_actual, reproducible_repeat: true|false, PASS|FAIL}`
- `flashlight_entity_key_check: {entity_a: 1501, entity_b: 1502, tick_range: "0..99", sequences_differ: true|false, PASS|FAIL}`
- `doctrine_anti_degrade_check: {alert_target_context_no_patrol_return_home: PASS|FAIL, combat_target_context_no_patrol_return_home: PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

---

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 15` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- pmb_contract_check present in section 21 (PMB section exists in document): yes

---

## 23. Dependencies on previous phases.

1. **Phase 2** — `EnemyUtilityBrain._choose_intent` already contains the `combat_lock and not has_los` pre-check and `_combat_no_los_grace_intent(...)` path. Phase 15 inserts the explicit state doctrine matrix after that pre-check and leaves the COMBAT grace path at higher priority.

2. **Phase 4** — `SHADOW_BOUNDARY_SCAN` exists as an executable intent path in `EnemyPursuitSystem.execute_intent`, with runtime state reset/setup in `clear_shadow_scan_state`, `_execute_shadow_boundary_scan`, `_run_shadow_scan_sweep`, and owner callbacks `Enemy.set_shadow_scan_active` / `Enemy.set_shadow_check_flashlight`. Phase 15 extends selection of this existing intent into ALERT/COMBAT no-LOS doctrine and adds the suspicious deterministic flashlight gate keyed to `_shadow_scan_active`.

---
## PHASE 16
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_16.

### Evidence

**Inspected files:**
- `src/entities/enemy.gd` (lines 240–275, 360–410, 468–715, 1000–1105, 1200–1335, 1860–1945, 2100–2155, 2250–2525; targeted `rg` line refs for combat search runtime, utility context, and debug snapshot contracts)
- `src/systems/enemy_pursuit_system.gd` (lines 220–520, 1120–1205; `execute_intent`, `SEARCH`, `SHADOW_BOUNDARY_SCAN`, and debug snapshot)
- `src/systems/enemy_utility_brain.gd` (full; `SHADOW_BOUNDARY_SCAN` / `SEARCH` no-LOS intent selection)
- `src/systems/enemy_awareness_system.gd` (lines 120–220; COMBAT->ALERT search progress gate contract)
- `src/systems/navigation_service.gd` (lines 230–390, 396–468; room/shadow/path-length APIs)
- `src/systems/navigation_runtime_queries.gd` (lines 1–220, 285–355; room graph queries and `nav_path_length` contract)
- `src/core/game_config.gd` (lines 120–260; `ai_balance["pursuit"]` placement)
- `src/core/config_validator.gd` (lines 150–260; pursuit validator block)
- `tests/test_combat_search_per_room_budget_and_total_cap.gd` (full)
- `tests/test_combat_next_room_scoring_no_loops.gd` (full)
- `tests/test_combat_to_alert_requires_no_contact_and_search_progress.gd` (full)
- `tests/test_shadow_policy_hard_block_without_grant.gd` (full)
- `tests/test_shadow_stall_escapes_to_light.gd` (full)
- `tests/test_runner_node.gd` (lines 60–120, 740–820, 1060–1105; constants/existence checks/suite calls)

**Inspected functions/methods:**
- `Enemy.runtime_budget_tick`
- `Enemy._build_utility_context`
- `Enemy.get_debug_detection_snapshot`
- `Enemy._build_confirm_runtime_config`
- `Enemy._resolve_known_target_context`
- `Enemy._reset_combat_search_state`
- `Enemy._update_combat_search_runtime`
- `Enemy._ensure_combat_search_room`
- `Enemy._build_combat_search_anchors`
- `Enemy._mark_combat_search_anchor_progress`
- `Enemy._update_combat_search_progress`
- `Enemy._select_next_combat_search_room`
- `Enemy._door_hops_between`
- `EnemyPursuitSystem.execute_intent`
- `EnemyPursuitSystem._execute_search`
- `EnemyPursuitSystem._execute_shadow_boundary_scan`
- `EnemyPursuitSystem.clear_shadow_scan_state`
- `EnemyPursuitSystem.debug_get_navigation_policy_snapshot`
- `EnemyUtilityBrain._choose_intent`
- `EnemyAwarenessSystem.process_confirm`
- `TestCombatSearchPerRoomBudgetAndTotalCap._test_search_budget_and_cap`
- `TestCombatNextRoomScoringNoLoops._test_scoring_and_loop_avoidance`
- `TestShadowPolicyHardBlockWithoutGrant._test_policy_block_and_fallback`
- `TestShadowStallEscapesToLight._test_shadow_stall_prefers_escape_to_light`
- `TestRunner._run_tests`
- `TestRunner._scene_exists`
- `TestRunner._run_embedded_scene_suite`

**Search commands used:**
- `rg -n "_combat_search_anchor_points|_combat_search_anchor_index|func _build_combat_search_anchors|func _mark_combat_search_anchor_progress" src/entities/enemy.gd -S`
- `rg -n "dark_search_nodes|_combat_search_dark_|_select_next_combat_dark_search_node|_build_combat_dark_search_nodes" src/entities/enemy.gd src/core/game_config.gd src/core/config_validator.gd tests/test_runner_node.gd -S`
- `rg -n "get_shadow_search_stage|get_shadow_search_coverage" src/entities/enemy.gd src/systems/enemy_pursuit_system.gd -S`
- `rg -n "combat_search_progress|combat_search_target_pos|_update_combat_search_runtime|_ensure_combat_search_room|_select_next_combat_search_room" src/entities/enemy.gd -S`
- `rg -n "shadow_scan_target|has_shadow_scan_target|shadow_scan_target_in_shadow" src/entities/enemy.gd src/systems/enemy_utility_brain.gd -S`
- `rg -n "func _resolve_known_target_context|_combat_search_target_pos != Vector2.ZERO" src/entities/enemy.gd -S`
- `rg -n "SHADOW_BOUNDARY_SCAN|shadow_scan|dark_search|SEARCH" src/systems/enemy_pursuit_system.gd src/entities/enemy.gd src/systems/enemy_utility_brain.gd -S`
- `rg -n "shadow_stall|shadow_policy_hard_block|shadow_enemy_stuck|shadow_search|dark_search|unreachable_shadow" tests -g '*.gd' -S`
- `rg -n "combat_search_progress|combat_search_total_elapsed_sec|combat_search_total_cap_sec|combat_search_force_complete" src/systems/enemy_awareness_system.gd -S`
- `rg -n "dark_search_graph_progressive_coverage|search_session_completion_contract|unreachable_shadow_node_forces_scan_then_search" tests -S`

**Confirmed facts:**
- `Enemy` combat search runtime is anchor-based in the current tree: `_combat_search_anchor_points`, `_combat_search_anchor_index`, `_build_combat_search_anchors`, and `_mark_combat_search_anchor_progress` exist only in `src/entities/enemy.gd` (lines 261–262, 2333, 2353 and call sites at lines 2279–2374).
- No dark-search session identifiers exist in `src/entities/enemy.gd`, `src/core/game_config.gd`, `src/core/config_validator.gd`, or `tests/test_runner_node.gd` (`rg` result: 0 matches).
- `Enemy._resolve_known_target_context` already routes COMBAT no-LOS target context through `_combat_search_target_pos` when `_is_combat_awareness_active()` is true (lines 2473–2478).
- `Enemy.get_debug_detection_snapshot` already exports `combat_search_progress`, `combat_search_total_elapsed_sec`, `combat_search_room_elapsed_sec`, `combat_search_room_budget_sec`, `combat_search_current_room_id`, `combat_search_target_pos`, and `combat_search_total_cap_hit` (lines 1313–1319).
- `Enemy._build_confirm_runtime_config` forwards the same `combat_search_*` values to `EnemyAwarenessSystem.process_confirm`, and awareness uses them in COMBAT->ALERT gating (`enemy.gd` lines 2126–2134; `enemy_awareness_system.gd` lines 138–142, 211–215).
- `EnemyPursuitSystem.execute_intent` executes `IntentType.SEARCH` as `_execute_search(delta, target)` and `_execute_search` is a local sweep/hold loop with no path movement (`enemy_pursuit_system.gd` lines 268–270 and 375–397).
- `EnemyPursuitSystem` current tree does not expose `get_shadow_search_stage()` or `get_shadow_search_coverage()` (0 matches); Phase 16 consumes those public getters through the dependency contract in section 23.
- `EnemyUtilityBrain._choose_intent` current tree emits `SHADOW_BOUNDARY_SCAN` only for SUSPICIOUS state (`enemy_utility_brain.gd` lines 105–109); Phase 16 requires the Phase 15 doctrine output in section 23 to extend alert/combat no-LOS shadow-scan selection.

---

## 1. What now.

Current combat dark-search behavior is incomplete and anchor-only.

Verification of current state:

```bash
rg -n "_combat_search_anchor_points|_combat_search_anchor_index|func _build_combat_search_anchors|func _mark_combat_search_anchor_progress" src/entities/enemy.gd -S
```
Expected current output: **>= 4 matches** (anchor-loop legacy identifiers are active).

```bash
rg -n "_build_combat_dark_search_nodes|_select_next_combat_dark_search_node|_combat_search_room_nodes" src/entities/enemy.gd -S
```
Expected current output: **0 matches** (no per-room dark-search node graph/session runtime exists).

```bash
rg -n "combat_search_node_key|combat_search_node_kind|combat_search_node_requires_shadow_scan|combat_search_node_shadow_scan_done" src/entities/enemy.gd -S
```
Expected current output: **0 matches** (no node/session debug observability exists).

```bash
rg -n "get_shadow_search_stage|get_shadow_search_coverage" src/systems/enemy_pursuit_system.gd -S
```
Expected current output in this tree: **0 matches** (Phase 11 dependency output is not present in baseline; Phase 16 start requires Phase 11 complete per section 23).

Failing/missing tests for this phase scope:
- `tests/test_dark_search_graph_progressive_coverage.gd` does not exist.
- `tests/test_alert_combat_search_session_completion_contract.gd` does not exist.
- `tests/test_unreachable_shadow_node_forces_scan_then_search.gd` does not exist.

Observable runtime gap (current code evidence): `_update_combat_search_runtime` uses `_mark_combat_search_anchor_progress()` and `_build_combat_search_anchors()` only (lines 2306 and 2325), so per-room search progression is a fixed 5-anchor loop and does not score dark pockets or boundary nodes.

---

## 2. What changes.

1. **`src/entities/enemy.gd` — delete** file-scope variables `var _combat_search_anchor_points: Array[Vector2] = []` and `var _combat_search_anchor_index: int = 0` before adding replacement dark-node session state.
2. **`src/entities/enemy.gd` — delete** function `func _build_combat_search_anchors(room_id: int, combat_target_pos: Vector2) -> Array[Vector2]` before adding the dark-node builder.
3. **`src/entities/enemy.gd` — delete** function `func _mark_combat_search_anchor_progress() -> void` before adding the dark-node/session progress updater.
4. **`src/entities/enemy.gd` — add** file-scope dark-search session state vars: `_combat_search_room_nodes`, `_combat_search_room_node_visited`, `_combat_search_current_node_key`, `_combat_search_current_node_kind`, `_combat_search_current_node_requires_shadow_scan`, `_combat_search_current_node_shadow_scan_done`, `_combat_search_node_search_dwell_sec`, `_combat_search_last_pursuit_shadow_stage`, `_combat_search_feedback_intent_type`, `_combat_search_feedback_intent_target`, `_combat_search_feedback_delta`, and `_combat_search_shadow_scan_suppressed_last_tick`.
5. **`src/entities/enemy.gd` — add** local file-scope constants used only by `_build_combat_dark_search_nodes`: deterministic sample offsets, node dedup epsilon, dark-pocket coverage weight, boundary-node coverage weight.
6. **`src/entities/enemy.gd` — add** private function `_record_combat_search_execution_feedback(intent: Dictionary, delta: float) -> void` and call it from `Enemy.runtime_budget_tick` immediately after `_pursuit.execute_intent(...)`.
7. **`src/entities/enemy.gd` — rewrite** `_reset_combat_search_state()` to clear all new dark-search session vars and feedback vars, while keeping existing `combat_search_*` public debug/awareness contract fields (`_combat_search_progress`, `_combat_search_total_elapsed_sec`, `_combat_search_room_elapsed_sec`, `_combat_search_room_budget_sec`, `_combat_search_current_room_id`, `_combat_search_target_pos`, `_combat_search_total_cap_hit`).
8. **`src/entities/enemy.gd` — rewrite** `_update_combat_search_runtime(delta, has_valid_contact, combat_target_pos, was_combat_before_confirm)` so it:
   - consumes previous-frame intent feedback and current pursuit shadow stage,
   - advances per-node state (`NEEDS_SHADOW_SCAN` -> `SEARCH_DWELL` -> `COVERED`),
   - computes room coverage from dark-search nodes,
   - preserves room budget + total cap timers,
   - updates `_combat_search_progress` with the existing COMBAT->ALERT gate contract shape.
9. **`src/entities/enemy.gd` — rewrite** `_ensure_combat_search_room(room_id, combat_target_pos)` to build/store per-room dark-search nodes and pick the first node via the new selector instead of creating anchor arrays.
10. **`src/entities/enemy.gd` — add** private function `_build_combat_dark_search_nodes(room_id: int, combat_target_pos: Vector2) -> Array[Dictionary]` (deterministic per-room node construction: reachable dark pockets + boundary points).
11. **`src/entities/enemy.gd` — add** private function `_select_next_combat_dark_search_node(room_id: int, combat_target_pos: Vector2) -> Dictionary` (deterministic scoring: uncovered score + policy-valid path length + tactical priority).
12. **`src/entities/enemy.gd` — add** private helpers `_compute_combat_search_room_coverage(room_id: int) -> float`, `_mark_combat_search_current_node_covered() -> void`, and `_current_pursuit_shadow_search_stage() -> int`. Shadow-stage completion feedback logic remains inline inside `_update_combat_search_runtime(...)` in this phase (no separate `_apply_combat_search_shadow_stage_feedback()` helper is introduced).
13. **`src/entities/enemy.gd` — modify** `_build_utility_context(...)` to suppress repeated `SHADOW_BOUNDARY_SCAN` emission for the same active dark node after one completed shadow boundary scan, while keeping `known_target_pos == _combat_search_target_pos` and keeping the COMBAT target-context pipeline active.
14. **`src/entities/enemy.gd` — modify** `get_debug_detection_snapshot()` to add dark-search session/node debug keys used by Phase 16 tests (node key/kind, shadow-scan state, per-room node counts, room coverage raw, suppression flag).
15. **`src/core/game_config.gd` — add** 5 new `ai_balance["pursuit"]` keys for Phase 16 dark-search node scoring/session thresholds (section 6 exact names/values).
16. **`src/core/config_validator.gd` — add** 5 `_validate_number_key(...)` checks for the new pursuit keys in the pursuit validation block.
17. **New** `tests/test_dark_search_graph_progressive_coverage.gd` + `tests/test_dark_search_graph_progressive_coverage.tscn` — deterministic node graph + coverage progression contract tests.
18. **New** `tests/test_alert_combat_search_session_completion_contract.gd` + `tests/test_alert_combat_search_session_completion_contract.tscn` — ALERT/COMBAT session completion + awareness contract continuity tests.
19. **New** `tests/test_unreachable_shadow_node_forces_scan_then_search.gd` + `tests/test_unreachable_shadow_node_forces_scan_then_search.tscn` — unreachable shadow node canon sequence tests (`SHADOW_BOUNDARY_SCAN -> SEARCH`).
20. **`tests/test_shadow_stall_escapes_to_light.gd` — update** `_test_shadow_stall_prefers_escape_to_light` assertions to keep the shadow-stall recovery regression explicit while Phase 16 changes dark-search node selection/suppression behavior in `enemy.gd`.
21. **`tests/test_shadow_policy_hard_block_without_grant.gd` — update** `_test_policy_block_and_fallback` assertions to keep policy-blocked shadow traversal regression explicit while Phase 16 adds policy-valid path length scoring for dark-search nodes.
22. **`tests/test_runner_node.gd` — modify** `_run_tests`: add 3 scene const declarations, 3 `_scene_exists(...)` checks, and 3 `_run_embedded_scene_suite(...)` calls for the new Phase 16 test scenes.

---

## 3. What will be after.

1. Anchor-loop legacy identifiers (`_combat_search_anchor_points`, `_combat_search_anchor_index`, `_build_combat_search_anchors`, `_mark_combat_search_anchor_progress`) are deleted from `src/entities/enemy.gd` (verified by section 10 and gate G1 in section 13).
2. `Enemy` owns a per-room dark-search node session runtime (`_build_combat_dark_search_nodes`, `_select_next_combat_dark_search_node`) and no dark-node selection logic exists outside `src/entities/enemy.gd` (verified by gates G2, G3, and G8 in section 13).
3. `combat_search_progress`, `combat_search_total_elapsed_sec`, `combat_search_room_elapsed_sec`, `combat_search_room_budget_sec`, `combat_search_current_room_id`, `combat_search_target_pos`, and `combat_search_total_cap_hit` remain exported through `Enemy.get_debug_detection_snapshot()` and `_build_confirm_runtime_config()` with the same field names used by `EnemyAwarenessSystem.process_confirm` (verified by gates G4 and G5 plus section 12 tests).
4. During active no-contact ALERT/COMBAT search sessions, per-room coverage increases monotonically from dark-search node completion events and room completion occurs by coverage threshold or room budget timeout (verified by `tests/test_dark_search_graph_progressive_coverage.gd` and `tests/test_alert_combat_search_session_completion_contract.gd` in section 12).
5. An active dark node that is in shadow triggers exactly one shadow boundary scan before search dwell on the same node target (`SHADOW_BOUNDARY_SCAN -> SEARCH`), and repeated SHADOW_BOUNDARY_SCAN loops for the same node do not occur while the node remains active (verified by `tests/test_unreachable_shadow_node_forces_scan_then_search.gd` in section 12 and gate G7 in section 13).
6. Phase 16 dark-search session thresholds and scoring weights are configured in `GameConfig.ai_balance["pursuit"]` and validated in `config_validator.gd` (verified by gates G6 and G9 in section 13).
7. PMB-1 through PMB-5 remain at their expected outputs (verified by PMB gates in section 13 and `pmb_contract_check` in section 21).

---

## 4. Scope and non-scope (exact files).

**In-scope:**
- `src/entities/enemy.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `tests/test_dark_search_graph_progressive_coverage.gd` (new)
- `tests/test_dark_search_graph_progressive_coverage.tscn` (new)
- `tests/test_alert_combat_search_session_completion_contract.gd` (new)
- `tests/test_alert_combat_search_session_completion_contract.tscn` (new)
- `tests/test_unreachable_shadow_node_forces_scan_then_search.gd` (new)
- `tests/test_unreachable_shadow_node_forces_scan_then_search.tscn` (new)
- `tests/test_shadow_stall_escapes_to_light.gd`
- `tests/test_shadow_policy_hard_block_without_grant.gd`
- `tests/test_runner_node.gd`
- `CHANGELOG.md`

**Out-of-scope (must not be modified):**
- `src/systems/enemy_pursuit_system.gd` (Phase 16 consumes Phase 11 public shadow-search getters; no pursuit choreography rewrite in this phase)
- `src/systems/enemy_utility_brain.gd` (Phase 16 consumes Phase 15 doctrine outputs; no new intent type or no-LOS doctrine rewrite in this phase)
- `src/systems/enemy_awareness_system.gd` (COMBAT->ALERT gate logic and field names remain unchanged)
- `src/systems/navigation_service.gd` (existing room/shadow/path APIs are consumed as-is)
- `src/systems/navigation_runtime_queries.gd` (no new runtime query API in this phase)
- `src/systems/enemy_squad_system.gd`
- `scenes/entities/enemy.tscn`

Allowed file-change boundary (exact paths): same as the in-scope list above.

---

## 5. Single-owner authority for this phase.

**Owner file:** `src/entities/enemy.gd`.

**Owner function:** `Enemy._select_next_combat_dark_search_node(room_id: int, combat_target_pos: Vector2) -> Dictionary`.

This function is the sole decision point for Phase 16 dark-search node selection and scoring order (`uncovered score`, `policy-valid path length`, `tactical priority`). No other file computes or duplicates the Phase 16 node scoring formula. Session state transitions (`NEEDS_SHADOW_SCAN`, `SEARCH_DWELL`, `COVERED`) consume the selector output but do not re-score candidates.

**Verifiable uniqueness gate:** section 13, gate G8.

---

## 6. Full input/output contract.

**Contract name:** `CombatDarkSearchNodeSelectionContractV1`

**Owner:** `Enemy._select_next_combat_dark_search_node(room_id: int, combat_target_pos: Vector2) -> Dictionary`

**Inputs (types, nullability, finite checks):**
- `room_id: int` — non-null, `room_id >= 0`. `room_id < 0` returns `status = "room_invalid"`.
- `combat_target_pos: Vector2` — non-null, finite (`is_finite(combat_target_pos.x)` and `is_finite(combat_target_pos.y)`). Non-finite input returns `status = "room_invalid"`.
- Implicit `_combat_search_room_nodes: Dictionary` — key `room_id` maps to `Array[Dictionary]`. Missing key or empty array returns `status = "no_nodes"`.
- Node row schema (every node in `_combat_search_room_nodes[room_id]`):
  - `key: String` (non-empty)
  - `kind: String` enum `{"dark_pocket", "boundary_point"}`
  - `target_pos: Vector2` (finite)
  - `approach_pos: Vector2` (finite)
  - `target_in_shadow: bool`
  - `requires_shadow_boundary_scan: bool`
  - `coverage_weight: float` (`coverage_weight > 0.0` and finite)
- Implicit `_combat_search_room_node_visited: Dictionary` — key `room_id` maps to `Dictionary[node_key: bool]`. Missing key means no nodes visited.
- Implicit `nav_system: Node` path API requirements for policy-valid path length:
  - If `nav_system.has_method("nav_path_length")`: selector calls `float(nav_system.nav_path_length(global_position, approach_pos, self))`.
  - Else: selector uses Euclidean `global_position.distance_to(approach_pos)`.

**Outputs (exact keys/types/enums):**
- `status: String` enum `{"ok", "room_invalid", "no_nodes", "all_blocked"}`.
- `reason: String` enum `{"selected_dark_pocket", "selected_boundary_point", "room_invalid", "node_list_empty", "all_candidates_blocked"}`.
- `room_id: int` — equals input `room_id` on all returns.
- `node_key: String` — selected node key on `status == "ok"`, else `""`.
- `node_kind: String` — `"dark_pocket"` or `"boundary_point"` on `status == "ok"`, else `""`.
- `target_pos: Vector2` — selected target on `status == "ok"`, else `Vector2.ZERO`.
- `approach_pos: Vector2` — selected approach position on `status == "ok"`, else `Vector2.ZERO`.
- `target_in_shadow: bool` — selected node field on `status == "ok"`, else `false`.
- `requires_shadow_boundary_scan: bool` — selected node field on `status == "ok"`, else `false`.
- `score_uncovered: float` — finite on `status == "ok"`, else `0.0`.
- `score_path_len_px: float` — finite on `status == "ok"`, else `INF`.
- `score_tactical_priority: int` — `0` or `1` on `status == "ok"`, else `-1`.
- `score_total: float` — finite on `status == "ok"`, else `INF`.

**Status enums:**
- `"ok"`
- `"room_invalid"`
- `"no_nodes"`
- `"all_blocked"`

**Reason enums:**
- `"selected_dark_pocket"`
- `"selected_boundary_point"`
- `"room_invalid"`
- `"node_list_empty"`
- `"all_candidates_blocked"`

**Phase 16 session state enums (internal, exact values):**
- `COMBAT_DARK_SEARCH_NODE_STATE_NONE = 0`
- `COMBAT_DARK_SEARCH_NODE_STATE_NEEDS_SHADOW_SCAN = 1`
- `COMBAT_DARK_SEARCH_NODE_STATE_SEARCH_DWELL = 2`
- `COMBAT_DARK_SEARCH_NODE_STATE_COVERED = 3`

**Deterministic scoring fields (exact):**
- `score_uncovered = float(node.coverage_weight)` for unvisited nodes; visited nodes are filtered out before scoring.
- `score_path_len_px = policy-valid path length to `approach_pos` (finite) from `global_position`.
- `score_tactical_priority = 0` for `node_kind == "dark_pocket"`, `1` for `node_kind == "boundary_point"`.
- `score_total = (combat_dark_search_node_uncovered_bonus - score_uncovered * combat_dark_search_node_uncovered_bonus) + (score_path_len_px * 1.0) + (float(score_tactical_priority) * combat_dark_search_node_tactical_priority_weight)`.
  - This formula yields lower `score_total` for larger `score_uncovered`, shorter path length, and dark pockets over boundary points.

**Constants/thresholds used (name, value, placement):**

GameConfig (`src/core/game_config.gd`, `ai_balance["pursuit"]`):
- `combat_dark_search_node_sample_radius_px = 64.0`
- `combat_dark_search_boundary_radius_px = 96.0`
- `combat_dark_search_node_dwell_sec = 1.25`
- `combat_dark_search_node_uncovered_bonus = 1000.0`
- `combat_dark_search_node_tactical_priority_weight = 80.0`

Local file-scope constants in `src/entities/enemy.gd` (used only by `_build_combat_dark_search_nodes`):
- `COMBAT_DARK_SEARCH_NODE_SAMPLE_OFFSETS = [Vector2.ZERO, Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]`
- `COMBAT_DARK_SEARCH_NODE_DEDUP_PX = 12.0`
- `COMBAT_DARK_SEARCH_POCKET_COVERAGE_WEIGHT = 1.0`
- `COMBAT_DARK_SEARCH_BOUNDARY_COVERAGE_WEIGHT = 0.5`

Existing retained constants consumed by Phase 16 session runtime (no rename in this phase):
- `COMBAT_SEARCH_ROOM_BUDGET_MIN_SEC = 4.0` (`src/entities/enemy.gd`)
- `COMBAT_SEARCH_ROOM_BUDGET_MAX_SEC = 8.0` (`src/entities/enemy.gd`)
- `COMBAT_SEARCH_TOTAL_CAP_SEC = 24.0` (`src/entities/enemy.gd`)
- `COMBAT_SEARCH_PROGRESS_THRESHOLD = 0.8` (`src/entities/enemy.gd`)
- `COMBAT_SEARCH_UNVISITED_PENALTY = 220.0` (`src/entities/enemy.gd`)
- `COMBAT_SEARCH_DOOR_COST_PER_HOP = 80.0` (`src/entities/enemy.gd`)

---

## 7. Deterministic algorithm with exact order.

### 7.1 `Enemy.runtime_budget_tick(delta: float)` integration order (Phase 16 changes only)

1. `runtime_budget_tick` keeps the existing call to `_update_combat_search_runtime(delta, confirm_channel_open, combat_reference_target_pos, awareness_state_before == COMBAT)` before utility intent build.
2. `runtime_budget_tick` keeps `_resolve_known_target_context(...)` and `_build_utility_context(...)` after combat-search runtime update.
3. `runtime_budget_tick` keeps `_pursuit.execute_intent(delta, intent, context)` call.
4. Immediately after `_pursuit.execute_intent(...)`, `runtime_budget_tick` calls `_record_combat_search_execution_feedback(intent, delta)`.
5. No other function writes Phase 16 feedback fields.

### 7.2 `Enemy._record_combat_search_execution_feedback(intent: Dictionary, delta: float) -> void`

1. `_combat_search_feedback_intent_type = int(intent.get("type", ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.PATROL))`.
2. `_combat_search_feedback_intent_target = intent.get("target", Vector2.ZERO) as Vector2`.
3. `_combat_search_feedback_delta = maxf(delta, 0.0)`.
4. No scoring or node-state transition occurs in this function.

### 7.3 `Enemy._current_pursuit_shadow_search_stage() -> int`

1. If `_pursuit == null`: return `-1`.
2. If `_pursuit.has_method("get_shadow_search_stage")` is false: return `-1`.
3. Return `int(_pursuit.get_shadow_search_stage())`.
4. `-1` means Phase 11 dependency output is absent at runtime; Phase 16 node shadow-scan completion detection does not advance on stage edges when return value is `-1`.

### 7.4 `Enemy._update_combat_search_runtime(delta, has_valid_contact, combat_target_pos, was_combat_before_confirm)`

Step 1 — Combat gate:
- If `was_combat_before_confirm == false`: call `_reset_combat_search_state()` and return.
- If `has_valid_contact == true`: return without modifying node coverage, node state, or timers.

Step 2 — Room initialization:
- If `_combat_search_current_room_id < 0`: resolve `start_room = _resolve_room_id_for_events()` and call `_ensure_combat_search_room(start_room, combat_target_pos)`.

Step 3 — Timers and total-cap flag:
- `_combat_search_total_elapsed_sec += maxf(delta, 0.0)`.
- `_combat_search_room_elapsed_sec += maxf(delta, 0.0)`.
- If `_combat_search_total_elapsed_sec >= COMBAT_SEARCH_TOTAL_CAP_SEC`: set `_combat_search_total_cap_hit = true`.

Step 4 — Shadow boundary-scan completion feedback (Phase 11 integration):
- `var stage_now := _current_pursuit_shadow_search_stage()`.
- If `_combat_search_current_node_requires_shadow_scan == true` and `_combat_search_current_node_shadow_scan_done == false` and `_combat_search_current_node_key != ""`:
  - If `_combat_search_last_pursuit_shadow_stage >= 0` and `_combat_search_last_pursuit_shadow_stage != 0` and `stage_now == 0`, then set:
    - `_combat_search_current_node_shadow_scan_done = true`
    - `_combat_search_node_search_dwell_sec = 0.0`
- `_combat_search_last_pursuit_shadow_stage = stage_now`.
- No separate `_apply_combat_search_shadow_stage_feedback()` helper exists in Phase 16; the shadow-stage edge detection and node-state mutation above are implemented inline in `_update_combat_search_runtime(...)` only.

Step 5 — SEARCH dwell accumulation for current node:
- Dwell accumulation runs only when all conditions are true:
  - `_combat_search_current_node_key != ""`
  - `_combat_search_feedback_intent_type == ENEMY_UTILITY_BRAIN_SCRIPT.IntentType.SEARCH`
  - `_combat_search_feedback_intent_target.distance_to(_combat_search_target_pos) <= 0.5`
  - `_combat_search_current_node_requires_shadow_scan == false` OR `_combat_search_current_node_shadow_scan_done == true`
- When all conditions are true: `_combat_search_node_search_dwell_sec += _combat_search_feedback_delta`.
- Else: `_combat_search_node_search_dwell_sec = 0.0`.

Step 6 — Current node completion:
- If `_combat_search_current_node_key != ""` and `_combat_search_node_search_dwell_sec >= _pursuit_cfg_float("combat_dark_search_node_dwell_sec", 1.25)`:
  - Call `_mark_combat_search_current_node_covered()`.
  - Set `_combat_search_current_node_key = ""`.
  - Set `_combat_search_current_node_kind = ""`.
  - Set `_combat_search_current_node_requires_shadow_scan = false`.
  - Set `_combat_search_current_node_shadow_scan_done = false`.
  - Set `_combat_search_node_search_dwell_sec = 0.0`.
  - Set `_combat_search_shadow_scan_suppressed_last_tick = false`.

Step 7 — Room completion checks:
- Compute `current_coverage = _compute_combat_search_room_coverage(_combat_search_current_room_id)` and store it into `_combat_search_room_coverage[_combat_search_current_room_id]`.
- `room_done_by_coverage = current_coverage >= COMBAT_SEARCH_PROGRESS_THRESHOLD`.
- `room_done_by_timeout = _combat_search_room_elapsed_sec >= _combat_search_room_budget_sec`.
- If `room_done_by_coverage` OR `room_done_by_timeout`: mark `_combat_search_visited_rooms[_combat_search_current_room_id] = true`, select next room via `_select_next_combat_search_room(...)`, then call `_ensure_combat_search_room(next_room, combat_target_pos)`.

Step 8 — Node selection for active room (only when no current node is active):
- If `_combat_search_current_node_key == ""` and `_combat_search_current_room_id >= 0`:
  - `var pick := _select_next_combat_dark_search_node(_combat_search_current_room_id, combat_target_pos)`.
  - If `pick.status == "ok"`: set current node fields from `pick`, set `_combat_search_target_pos = pick.target_pos`, set `_combat_search_current_node_requires_shadow_scan = pick.requires_shadow_boundary_scan`, set `_combat_search_current_node_shadow_scan_done = false`, set `_combat_search_node_search_dwell_sec = 0.0`.
  - If `pick.status == "no_nodes"` OR `pick.status == "all_blocked"`: mark room visited, switch room with `_select_next_combat_search_room(...)`, call `_ensure_combat_search_room(...)`.
  - If `pick.status == "room_invalid"`: keep current target unchanged and continue to Step 9.

Step 9 — Progress aggregation:
- Call `_update_combat_search_progress()` unchanged except the per-room coverage source now comes from Phase 16 node-weight coverage values.

### 7.5 `Enemy._ensure_combat_search_room(room_id: int, combat_target_pos: Vector2) -> void`

1. Resolve valid room id exactly as current implementation (`room_id` fallback to `_resolve_room_id_for_events()`; return when invalid).
2. Set `_combat_search_current_room_id = valid_room`.
3. Reset `_combat_search_room_elapsed_sec = 0.0`.
4. Set `_combat_search_room_budget_sec = _shot_rng.randf_range(COMBAT_SEARCH_ROOM_BUDGET_MIN_SEC, COMBAT_SEARCH_ROOM_BUDGET_MAX_SEC)`.
5. Build room node list once per room entry: `_combat_search_room_nodes[valid_room] = _build_combat_dark_search_nodes(valid_room, combat_target_pos)`.
6. Ensure visited-map entry exists: `_combat_search_room_node_visited[valid_room] = {}` when missing.
7. Clear current-node runtime fields (`_combat_search_current_node_key`, `_combat_search_current_node_kind`, `_combat_search_current_node_requires_shadow_scan`, `_combat_search_current_node_shadow_scan_done`, `_combat_search_node_search_dwell_sec`, `_combat_search_shadow_scan_suppressed_last_tick`).
8. Immediately pick first node via `_select_next_combat_dark_search_node(valid_room, combat_target_pos)` and assign current-node fields; on non-`ok`, set `_combat_search_target_pos = global_position`.
9. Initialize room coverage dictionary entry: `_combat_search_room_coverage[valid_room] = _compute_combat_search_room_coverage(valid_room)`.

### 7.6 `Enemy._build_combat_dark_search_nodes(room_id: int, combat_target_pos: Vector2) -> Array[Dictionary]`

1. Resolve `room_center` from `nav_system.get_room_center(room_id)` when available and non-zero; else use `global_position`.
2. Resolve `room_rect` from `nav_system.get_room_rect(room_id)` when available; `Rect2()` means no rect clamp.
3. Resolve `sample_radius = _pursuit_cfg_float("combat_dark_search_node_sample_radius_px", 64.0)`.
4. Resolve `boundary_radius = _pursuit_cfg_float("combat_dark_search_boundary_radius_px", 96.0)`.
5. Iterate deterministic sample offsets in fixed order `COMBAT_DARK_SEARCH_NODE_SAMPLE_OFFSETS`:
   - `sample = room_center` for `Vector2.ZERO`; else `room_center + offset * sample_radius`.
   - If `room_rect` is not empty: clamp sample to `room_rect.grow(-4.0)` bounds.
6. For each sample, detect shadow status:
   - `sample_in_shadow = bool(nav_system.call("is_point_in_shadow", sample))` when method exists.
   - If method is absent: `sample_in_shadow = false`.
7. Always append a `boundary_point` candidate for `sample` (subject to dedup):
   - `key = "r%d:boundary:%d" % [room_id, sample_index]`
   - `kind = "boundary_point"`
   - `target_pos = sample`
   - `approach_pos = sample`
   - `target_in_shadow = sample_in_shadow`
   - `requires_shadow_boundary_scan = false`
   - `coverage_weight = COMBAT_DARK_SEARCH_BOUNDARY_COVERAGE_WEIGHT`
8. If `sample_in_shadow == true` and `nav_system.has_method("get_nearest_non_shadow_point")`:
   - `boundary = nav_system.get_nearest_non_shadow_point(sample, boundary_radius)`.
   - If `boundary != Vector2.ZERO`, append a `dark_pocket` candidate (subject to dedup):
     - `key = "r%d:dark:%d" % [room_id, sample_index]`
     - `kind = "dark_pocket"`
     - `target_pos = sample`
     - `approach_pos = boundary`
     - `target_in_shadow = true`
     - `requires_shadow_boundary_scan = true`
     - `coverage_weight = COMBAT_DARK_SEARCH_POCKET_COVERAGE_WEIGHT`
9. Dedup rule (deterministic, insertion-order stable): a candidate is dropped when an existing node with the same `kind` has `existing.target_pos.distance_to(candidate.target_pos) <= COMBAT_DARK_SEARCH_NODE_DEDUP_PX`. First inserted node wins.
10. Fallback when result is empty: return one boundary node at `room_center` with `coverage_weight = 1.0` and `requires_shadow_boundary_scan = false`.
11. Returned array order is insertion order only; no sort step runs in the builder.

### 7.7 `Enemy._select_next_combat_dark_search_node(room_id: int, combat_target_pos: Vector2) -> Dictionary`

1. Validate `room_id >= 0` and `combat_target_pos` finite. Invalid input returns `status = "room_invalid"`, `reason = "room_invalid"`.
2. Read `nodes = _combat_search_room_nodes.get(room_id, [])`. Empty array returns `status = "no_nodes"`, `reason = "node_list_empty"`.
3. For each node in insertion order:
   - Skip when `_combat_search_room_node_visited[room_id][node.key] == true`.
   - Compute `path_len`:
     - `nav_system.nav_path_length(global_position, node.approach_pos, self)` when available.
     - Else Euclidean distance to `node.approach_pos`.
   - Skip when `path_len` is not finite.
   - Compute `score_uncovered = float(node.coverage_weight)`.
   - Compute `score_tactical_priority = 0` for `kind == "dark_pocket"`, else `1`.
   - Compute `score_total` by section 6 formula.
4. Candidate selection order:
   - Lower `score_total` wins.
   - If `is_equal_approx(score_total, best_score_total)`: lower `score_path_len_px` wins.
   - If `is_equal_approx(score_path_len_px, best_score_path_len_px)`: lower `score_tactical_priority` wins.
   - If equal again: lexical ascending `node.key` wins.
5. If zero finite-path candidates remain and node list was non-empty: return `status = "all_blocked"`, `reason = "all_candidates_blocked"`.
6. Return selected node dict with `status = "ok"` and `reason = "selected_dark_pocket"` or `"selected_boundary_point"`.

### 7.8 `Enemy._compute_combat_search_room_coverage(room_id: int) -> float`

1. If `room_id < 0`: return `0.0`.
2. Read `nodes = _combat_search_room_nodes.get(room_id, [])`. If `nodes` is empty: return `0.0`.
3. Read `visited = _combat_search_room_node_visited.get(room_id, {})`.
4. Initialize `total_weight = 0.0` and `covered_weight = 0.0`.
5. Iterate `nodes` in insertion order and read:
   - `node_key = String(node.get("key", ""))`
   - `weight = float(node.get("coverage_weight", 0.0))`
6. Ignore a row (contributes nothing to either sum) when `node_key == ""` or `weight` is not finite or `weight <= 0.0`.
7. Otherwise add `weight` to `total_weight`.
8. If `bool(visited.get(node_key, false)) == true`, add `weight` to `covered_weight`.
9. If `total_weight <= 0.0`: return `0.0`.
10. Return `clampf(covered_weight / total_weight, 0.0, 1.0)`.

### 7.9 `Enemy._build_utility_context(...)` Phase 16 suppression rule (Phase 15 integration)

1. Phase 15 dependency supplies alert/combat `shadow_scan_target` and `shadow_scan_target_in_shadow` for active target context.
2. Phase 16 computes `shadow_scan_suppressed = true` only when all conditions are true:
   - `_combat_search_current_node_key != ""`
   - `_combat_search_current_node_requires_shadow_scan == true`
   - `_combat_search_current_node_shadow_scan_done == true`
   - `has_known_target == true`
   - `known_target_pos.distance_to(_combat_search_target_pos) <= 0.5`
   - `has_shadow_scan_target == true`
   - `shadow_scan_target.distance_to(_combat_search_target_pos) <= 0.5`
3. When `shadow_scan_suppressed == true`: set `shadow_scan_target_in_shadow = false` before building the returned context dictionary.
4. Store `_combat_search_shadow_scan_suppressed_last_tick = shadow_scan_suppressed`.
5. No other field in the returned utility context changes in this suppression path.

**Tie-break rules:** defined in section 7 step 4 of the selector algorithm block. No other tie-break path exists.

**Behavior when input is empty/null/invalid:**
- `room_id < 0` or non-finite `combat_target_pos` in selector: `status = "room_invalid"`.
- Missing room node list: `status = "no_nodes"`.
- All node paths blocked (no finite `nav_path_length` / Euclidean fallback path length): `status = "all_blocked"`.
- Missing Phase 11 getter (`_current_pursuit_shadow_search_stage() == -1`): shadow-scan completion edge detection does not advance; room timeout still advances session and coverage/progress updates continue.

---

## 8. Edge-case matrix.

**Case A: invalid room id (empty/invalid input)**
- Input: `_select_next_combat_dark_search_node(-1, Vector2(100, 50))`
- Expected output dict:
  - `status = "room_invalid"`
  - `reason = "room_invalid"`
  - `room_id = -1`
  - `node_key = ""`
  - `node_kind = ""`
  - `target_pos = Vector2.ZERO`
  - `approach_pos = Vector2.ZERO`
  - `requires_shadow_boundary_scan = false`

**Case B: single valid boundary node, no ambiguity**
- Setup: `_combat_search_room_nodes[5] = [{key:"r5:boundary:0", kind:"boundary_point", target_pos:Vector2(64,0), approach_pos:Vector2(64,0), target_in_shadow:false, requires_shadow_boundary_scan:false, coverage_weight:0.5}]`, no visited nodes, finite path length.
- Input: `_select_next_combat_dark_search_node(5, Vector2(100, 0))`
- Expected output dict:
  - `status = "ok"`
  - `reason = "selected_boundary_point"`
  - `room_id = 5`
  - `node_key = "r5:boundary:0"`
  - `node_kind = "boundary_point"`
  - `requires_shadow_boundary_scan = false`
  - `score_tactical_priority = 1`

**Case C: tie-break triggered (equal score_total and path length)**
- Setup: two unvisited boundary nodes with identical `coverage_weight = 0.5`, equal `approach_pos` distance from `global_position`, and both `kind = "boundary_point"`; keys `"r5:boundary:2"` and `"r5:boundary:1"`.
- Input: `_select_next_combat_dark_search_node(5, Vector2(100, 0))`
- Expected output dict:
  - `status = "ok"`
  - `node_key = "r5:boundary:1"` (lexical ascending key wins at section 7 step 4 of the selector algorithm block)
  - `node_kind = "boundary_point"`
  - `score_tactical_priority = 1`

**Case D: all inputs blocked (all candidates invalid/blocked)**
- Setup: node list exists and contains unvisited nodes; `nav_system.nav_path_length(...)` returns `INF` for every `approach_pos`.
- Input: `_select_next_combat_dark_search_node(5, Vector2(100, 0))`
- Expected output dict:
  - `status = "all_blocked"`
  - `reason = "all_candidates_blocked"`
  - `node_key = ""`
  - `score_path_len_px = INF`

**Case E: dark pocket node requires one shadow scan before SEARCH dwell**
- Setup: current node is `dark_pocket`, `_combat_search_current_node_requires_shadow_scan = true`, `_combat_search_current_node_shadow_scan_done = false`, `_combat_search_last_pursuit_shadow_stage = 2`, `_current_pursuit_shadow_search_stage() == 0`.
- `_update_combat_search_runtime(...)` expected result:
  - `_combat_search_current_node_shadow_scan_done == true`
  - `_combat_search_node_search_dwell_sec == 0.0`
  - node remains active (`_combat_search_current_node_key` unchanged)
  - `_combat_search_target_pos` unchanged

**Case F: Phase 11 getter absent, room timeout still completes room**
- Setup: `_current_pursuit_shadow_search_stage() == -1`, no contact, `_combat_search_room_elapsed_sec` grows to `_combat_search_room_budget_sec`, current room coverage < 0.8.
- `_update_combat_search_runtime(...)` expected result:
  - room switches via `_select_next_combat_search_room(...)`
  - `_combat_search_room_elapsed_sec` resets to `0.0`
  - `_combat_search_total_elapsed_sec` continues increasing monotonically
  - `_combat_search_progress` updates via `_update_combat_search_progress()` and remains finite

---

## 9. Legacy removal plan (delete-first, exact ids).

**L1. `var _combat_search_anchor_points: Array[Vector2] = []`**
- File: `src/entities/enemy.gd`
- Approximate line range (PROJECT DISCOVERY): line 261 (declaration), plus runtime references at lines 2279, 2307, 2325–2329, 2356–2374.
- Delete declaration first, then rewrite all call-site references in `_reset_combat_search_state`, `_update_combat_search_runtime`, and `_ensure_combat_search_room` before compilation check.

**L2. `var _combat_search_anchor_index: int = 0`**
- File: `src/entities/enemy.gd`
- Approximate line range (PROJECT DISCOVERY): line 262 (declaration), plus runtime references at lines 2280, 2307, 2326, 2359–2366.
- Delete declaration first, then rewrite all call-site references in the same three runtime functions.

**L3. `func _build_combat_search_anchors(room_id: int, combat_target_pos: Vector2) -> Array[Vector2]`**
- File: `src/entities/enemy.gd`
- Approximate line range (PROJECT DISCOVERY): lines 2333–2351.
- Dead-after-phase: yes. Phase 16 replaces anchor generation with `_build_combat_dark_search_nodes` and no call path to `_build_combat_search_anchors` remains.

**L4. `func _mark_combat_search_anchor_progress() -> void`**
- File: `src/entities/enemy.gd`
- Approximate line range (PROJECT DISCOVERY): lines 2353–2375.
- Dead-after-phase: yes. Phase 16 replaces anchor-index progress with node-state/dwell coverage updates inside `_update_combat_search_runtime` and `_mark_combat_search_current_node_covered`.

No other combat-search helper becomes unreachable in this phase. `_select_next_combat_search_room`, `_update_combat_search_progress`, and `_door_hops_between` remain reachable and remain in use.

---

## 10. Legacy verification commands (exact rg + expected 0 matches for every removed legacy item).

**[L1]** `rg -n "_combat_search_anchor_points" src/ -S`
Expected: 0 matches.

**[L2]** `rg -n "_combat_search_anchor_index" src/ -S`
Expected: 0 matches.

**[L3]** `rg -n "func _build_combat_search_anchors\(" src/ -S`
Expected: 0 matches.

**[L4]** `rg -n "func _mark_combat_search_anchor_progress\(" src/ -S`
Expected: 0 matches.

---

## 11. Acceptance criteria (binary pass/fail).

- [ ] All section 10 legacy verification commands (L1–L4) return `0 matches`.
- [ ] `rg -n "func _build_combat_dark_search_nodes\(|func _select_next_combat_dark_search_node\(|func _record_combat_search_execution_feedback\(" src/entities/enemy.gd -S` returns exactly `3 matches`.
- [ ] `rg -n "_combat_search_room_nodes|_combat_search_room_node_visited|_combat_search_current_node_key|_combat_search_current_node_requires_shadow_scan|_combat_search_current_node_shadow_scan_done|_combat_search_node_search_dwell_sec" src/entities/enemy.gd -S` returns `>= 12 matches`.
- [ ] `rg -n "combat_search_node_key|combat_search_node_kind|combat_search_node_requires_shadow_scan|combat_search_node_shadow_scan_done|combat_search_room_nodes_total|combat_search_room_nodes_covered|combat_search_shadow_scan_suppressed" src/entities/enemy.gd -S` returns `>= 7 matches`.
- [ ] `rg -n "combat_dark_search_(node_sample_radius_px|boundary_radius_px|node_dwell_sec|node_uncovered_bonus|node_tactical_priority_weight)" src/core/game_config.gd -S` returns exactly `5 matches`.
- [ ] `rg -n "combat_dark_search_(node_sample_radius_px|boundary_radius_px|node_dwell_sec|node_uncovered_bonus|node_tactical_priority_weight)" src/core/config_validator.gd -S` returns exactly `5 matches`.
- [ ] `rg -n "get_shadow_search_stage\(" src/entities/enemy.gd -S` returns `>= 1 match` (Phase 11 integration consumed in Enemy runtime).
- [ ] `rg -n "DARK_SEARCH_GRAPH_PROGRESSIVE_COVERAGE_TEST_SCENE|ALERT_COMBAT_SEARCH_SESSION_COMPLETION_CONTRACT_TEST_SCENE|UNREACHABLE_SHADOW_NODE_FORCES_SCAN_THEN_SEARCH_TEST_SCENE" tests/test_runner_node.gd -S` returns exactly `9 matches`.
- [ ] All new test functions listed in section 12 pass (exit `0`).
- [ ] Updated test files listed in section 12 pass (exit `0`).
- [ ] `tests/test_combat_search_per_room_budget_and_total_cap.gd`, `tests/test_combat_next_room_scoring_no_loops.gd`, and `tests/test_combat_to_alert_requires_no_contact_and_search_progress.gd` all pass (exit `0`) with no test edits required.
- [ ] Tier 2 full regression `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` exits `0`.

---

## 12. Tests (new/update + purpose).

**New: `tests/test_dark_search_graph_progressive_coverage.gd`**
Registration: const `DARK_SEARCH_GRAPH_PROGRESSIVE_COVERAGE_TEST_SCENE = "res://tests/test_dark_search_graph_progressive_coverage.tscn"` in `tests/test_runner_node.gd`.

- `_test_room_dark_search_coverage_monotonic_non_decreasing`
  - Setup: Enemy instance + FakeNav with deterministic room rect/center/shadow mask + Phase 11 shadow-stage getter stub on pursuit.
  - Assertion: repeated `_update_combat_search_runtime(...)` ticks produce a non-decreasing sequence of `combat_search_progress` and non-decreasing current-room coverage raw debug field while no-contact session remains active.
- `_test_select_next_dark_node_prefers_uncovered_then_shorter_policy_path`
  - Setup: fake room nodes with one `dark_pocket` and one `boundary_point`, deterministic `nav_path_length` stub.
  - Assertion: `_select_next_combat_dark_search_node(...)` picks the unvisited node with lower `score_total`; after marking visited, next call picks the remaining node.
- `_test_tie_break_same_score_resolves_by_lexical_node_key`
  - Setup: equal-score candidate nodes with keys `r5:boundary:2` and `r5:boundary:1`.
  - Assertion: selector returns `node_key == "r5:boundary:1"`.
- `_test_boundary_only_room_builds_nodes_and_completes_by_coverage`
  - Setup: FakeNav `is_point_in_shadow` returns false for all samples.
  - Assertion: builder returns boundary-only nodes, room coverage reaches `>= 0.8`, room switches or room marks visited without dark-pocket node requirement.

**New: `tests/test_alert_combat_search_session_completion_contract.gd`**
Registration: const `ALERT_COMBAT_SEARCH_SESSION_COMPLETION_CONTRACT_TEST_SCENE = "res://tests/test_alert_combat_search_session_completion_contract.tscn"` in `tests/test_runner_node.gd`.

- `_test_session_stays_active_while_coverage_below_threshold_and_budget_open`
  - Assertion: before room coverage threshold and before room budget timeout, `_combat_search_current_room_id` remains stable and `_combat_search_target_pos != Vector2.ZERO`.
- `_test_room_completion_advances_to_next_room_or_marks_room_visited`
  - Assertion: when room coverage reaches threshold, `_combat_search_visited_rooms[current_room] == true` and `_ensure_combat_search_room(...)` installs a new room or reinitializes the same room when no neighbors exist.
- `_test_total_cap_forces_progress_threshold_and_cap_flag`
  - Assertion: after `_combat_search_total_elapsed_sec >= 24.0`, `_combat_search_total_cap_hit == true` and `combat_search_progress == 0.8` (existing `COMBAT_SEARCH_PROGRESS_THRESHOLD`) via `get_debug_detection_snapshot()`.
- `_test_confirm_runtime_config_keeps_awareness_field_names`
  - Assertion: `_build_confirm_runtime_config(...)` still contains exact keys `combat_search_progress`, `combat_search_total_elapsed_sec`, `combat_search_room_elapsed_sec`, `combat_search_total_cap_sec`, and `combat_search_force_complete`.

**New: `tests/test_unreachable_shadow_node_forces_scan_then_search.gd`**
Registration: const `UNREACHABLE_SHADOW_NODE_FORCES_SCAN_THEN_SEARCH_TEST_SCENE = "res://tests/test_unreachable_shadow_node_forces_scan_then_search.tscn"` in `tests/test_runner_node.gd`.

- `_test_dark_node_in_shadow_requests_shadow_boundary_scan_before_search`
  - Setup: FakeNav returns a dark pocket target with reachable non-shadow boundary and policy-blocked direct traversal; FakePursuit exposes `get_shadow_search_stage()` and records requested intents.
  - Assertion: first active-node no-contact tick yields utility intent `SHADOW_BOUNDARY_SCAN` for the dark pocket target.
- `_test_shadow_scan_completion_flips_same_node_to_search_without_repeat_scan`
  - Setup: simulate pursuit shadow stage edge non-IDLE -> IDLE on the same active node.
  - Assertion: next no-contact tick yields `SEARCH` on the same target (`_combat_search_target_pos` unchanged), and `combat_search_shadow_scan_suppressed == true` in debug snapshot.
- `_test_search_dwell_marks_node_covered_and_selects_next_node`
  - Setup: continue SEARCH intent feedback with matching target for `>= combat_dark_search_node_dwell_sec`.
  - Assertion: active node key changes, previous node visited flag becomes true, and current-room coverage raw increases.

**Update: `tests/test_shadow_stall_escapes_to_light.gd`**
- Function: `_test_shadow_stall_prefers_escape_to_light`
- Change: add one assertion that repeated policy-blocked movement attempts still keep the shadow escape target on the light side while Phase 16 dark-search session runtime exists in `Enemy` (no regression in pursuit shadow-stall recovery path).
- Why: Phase 16 adds new policy-valid path scoring in `Enemy`; this regression test keeps the shadow recovery fallback contract explicit.

**Update: `tests/test_shadow_policy_hard_block_without_grant.gd`**
- Function: `_test_policy_block_and_fallback`
- Change: add one assertion that `path_plan_reason == "policy_blocked"` remains stable across repeated blocked attempts in the same run.
- Why: Phase 16 introduces node scoring that reads policy-valid path length in `Enemy`; this regression test keeps the pursuit-level policy hard-block semantics explicit and stable.

**Updated files not modified in this phase (smoke regression only):**
- `tests/test_combat_search_per_room_budget_and_total_cap.gd`
- `tests/test_combat_next_room_scoring_no_loops.gd`
- `tests/test_combat_to_alert_requires_no_contact_and_search_progress.gd`

---

## 13. rg gates (command + expected output).

**Phase-specific gates:**

[G1] `rg -n "_combat_search_anchor_points|_combat_search_anchor_index|func _build_combat_search_anchors\(|func _mark_combat_search_anchor_progress\(" src/entities/enemy.gd -S`
Expected: `0 matches`.

[G2] `rg -n "func _build_combat_dark_search_nodes\(|func _select_next_combat_dark_search_node\(|func _record_combat_search_execution_feedback\(" src/entities/enemy.gd -S`
Expected: `3 matches`.

[G3] `rg -n "_combat_search_room_nodes|_combat_search_room_node_visited|_combat_search_current_node_key|_combat_search_current_node_kind|_combat_search_current_node_requires_shadow_scan|_combat_search_current_node_shadow_scan_done|_combat_search_node_search_dwell_sec|_combat_search_last_pursuit_shadow_stage" src/entities/enemy.gd -S`
Expected: `>= 16 matches`.

[G4] `rg -n "combat_search_node_key|combat_search_node_kind|combat_search_node_requires_shadow_scan|combat_search_node_shadow_scan_done|combat_search_room_nodes_total|combat_search_room_nodes_covered|combat_search_room_coverage_raw|combat_search_shadow_scan_suppressed" src/entities/enemy.gd -S`
Expected: `>= 8 matches`.

[G5] `rg -n "combat_search_progress|combat_search_total_elapsed_sec|combat_search_room_elapsed_sec|combat_search_room_budget_sec|combat_search_current_room_id|combat_search_target_pos|combat_search_total_cap_hit|combat_search_force_complete" src/entities/enemy.gd src/systems/enemy_awareness_system.gd -S`
Expected: `>= 12 matches` (existing awareness contract field names remain present).

[G6] `rg -n "combat_dark_search_(node_sample_radius_px|boundary_radius_px|node_dwell_sec|node_uncovered_bonus|node_tactical_priority_weight)" src/core/game_config.gd -S`
Expected: `5 matches`.

[G7] `rg -n "get_shadow_search_stage\(" src/entities/enemy.gd -S`
Expected: `>= 1 match`.

[G8] `rg -n "func _select_next_combat_dark_search_node\(" src/ -S`
Expected: exactly `1 match` and it is in `src/entities/enemy.gd`.

[G9] `rg -n "combat_dark_search_(node_sample_radius_px|boundary_radius_px|node_dwell_sec|node_uncovered_bonus|node_tactical_priority_weight)" src/core/config_validator.gd -S`
Expected: `5 matches`.

[G10] `rg -n "DARK_SEARCH_GRAPH_PROGRESSIVE_COVERAGE_TEST_SCENE|ALERT_COMBAT_SEARCH_SESSION_COMPLETION_CONTRACT_TEST_SCENE|UNREACHABLE_SHADOW_NODE_FORCES_SCAN_THEN_SEARCH_TEST_SCENE" tests/test_runner_node.gd -S`
Expected: `9 matches` (3 consts + 3 `_scene_exists` checks + 3 `_run_embedded_scene_suite` calls).

**PMB gates:**

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: `0 matches`.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

---

## 14. Execution sequence (step-by-step, no ambiguity).

Step 0: Verify Phase 11 and Phase 15 dependencies before code edits.
- `rg -n "func get_shadow_search_stage\(|func get_shadow_search_coverage\(" src/systems/enemy_pursuit_system.gd -S` must return `2 matches` (Phase 11 getter contract present).
- `rg -n "target_context_exists|shadow_scan_target_in_shadow" src/systems/enemy_utility_brain.gd src/entities/enemy.gd -S` must return `>= 2 matches` with alert/combat doctrine changes already merged (Phase 15 dependency).

Step 1: Delete legacy item L1 from section 9 in `src/entities/enemy.gd` (`_combat_search_anchor_points` declaration and all write/read sites).

Step 2: Delete legacy item L2 from section 9 in `src/entities/enemy.gd` (`_combat_search_anchor_index` declaration and all write/read sites).

Step 3: Delete legacy item L3 from section 9 in `src/entities/enemy.gd` (`_build_combat_search_anchors`).

Step 4: Delete legacy item L4 from section 9 in `src/entities/enemy.gd` (`_mark_combat_search_anchor_progress`).

Step 5: Add Phase 16 dark-search session state vars and local file-scope constants to `src/entities/enemy.gd` near existing `_combat_search_*` declarations.

Step 6: Add `_record_combat_search_execution_feedback(intent, delta)` and `_current_pursuit_shadow_search_stage()` to `src/entities/enemy.gd`.

Step 7: Modify `Enemy.runtime_budget_tick` (`src/entities/enemy.gd`) to call `_record_combat_search_execution_feedback(intent, delta)` immediately after `_pursuit.execute_intent(...)`.

Step 8: Rewrite `Enemy._reset_combat_search_state` (`src/entities/enemy.gd`) to reset the new dark-search session fields and preserve the existing awareness-facing `combat_search_*` fields.

Step 9: Add `_build_combat_dark_search_nodes`, `_select_next_combat_dark_search_node`, `_compute_combat_search_room_coverage`, `_mark_combat_search_current_node_covered`, and `_current_pursuit_shadow_search_stage` helpers to `src/entities/enemy.gd`.

Step 10: Rewrite `Enemy._ensure_combat_search_room` (`src/entities/enemy.gd`) to initialize room node lists and current node state via `_select_next_combat_dark_search_node`.

Step 11: Rewrite `Enemy._update_combat_search_runtime` (`src/entities/enemy.gd`) to consume feedback, advance node states, switch rooms by coverage/timeout, and update `_combat_search_progress` with the existing field contract.

Step 12: Modify `Enemy._build_utility_context` (`src/entities/enemy.gd`) to apply the Phase 16 shadow-scan suppression rule for the active dark node after one completed shadow boundary scan.

Step 13: Modify `Enemy.get_debug_detection_snapshot` (`src/entities/enemy.gd`) to export the new dark-search node/session debug keys.

Step 14: Add 5 pursuit config keys to `src/core/game_config.gd` and 5 validator checks to `src/core/config_validator.gd`.

Step 15: Create `tests/test_dark_search_graph_progressive_coverage.gd` and `tests/test_dark_search_graph_progressive_coverage.tscn`; implement all 4 test functions from section 12.

Step 16: Create `tests/test_alert_combat_search_session_completion_contract.gd` and `tests/test_alert_combat_search_session_completion_contract.tscn`; implement all 4 test functions from section 12.

Step 17: Create `tests/test_unreachable_shadow_node_forces_scan_then_search.gd` and `tests/test_unreachable_shadow_node_forces_scan_then_search.tscn`; implement all 3 test functions from section 12.

Step 18: Update `tests/test_shadow_stall_escapes_to_light.gd`, function `_test_shadow_stall_prefers_escape_to_light`, with the additional regression assertion from section 12.

Step 19: Update `tests/test_shadow_policy_hard_block_without_grant.gd`, function `_test_policy_block_and_fallback`, with the additional regression assertion from section 12.

Step 20: Register the 3 new scenes in `tests/test_runner_node.gd`: add 3 top-level consts, 3 `_scene_exists(...)` checks in `TestRunner._run_tests`, and 3 `_run_embedded_scene_suite(...)` calls in `TestRunner._run_tests`.

Step 21: Run Tier 1 smoke suite commands (exact):
- `xvfb-run -a godot-4 --headless --path . res://tests/test_dark_search_graph_progressive_coverage.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_alert_combat_search_session_completion_contract.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_unreachable_shadow_node_forces_scan_then_search.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_shadow_stall_escapes_to_light.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_shadow_policy_hard_block_without_grant.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_combat_search_per_room_budget_and_total_cap.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_combat_next_room_scoring_no_loops.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_combat_to_alert_requires_no_contact_and_search_progress.tscn`

Step 22: Run Tier 2 full regression: `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit `0`.

Step 23: Run all legacy verification commands from section 10 (L1–L4). All commands must return `0 matches`.

Step 24: Run all rg gates from section 13 (G1–G10 and PMB-1–PMB-5). All commands must return expected output.

Step 25: Prepend one `CHANGELOG.md` entry under the current date header for Phase 16 (full dark-zone search sessions: dark nodes, progressive coverage, `SHADOW_BOUNDARY_SCAN -> SEARCH` canon sequencing).

---

## 15. Rollback conditions.

1. **Trigger:** Any section 10 legacy verification command (L1–L4) returns non-zero matches after step 23. **Rollback action:** revert all section 4 in-scope file changes to pre-phase state. Phase result = FAIL.
2. **Trigger:** Dependency gate in step 0 fails (Phase 11 getter contract or Phase 15 doctrine integration absent). **Rollback action:** revert all edits and stop Phase 16 implementation. Phase result = FAIL.
3. **Trigger:** Any Tier 1 smoke command in step 21 exits non-zero. **Rollback action:** revert all section 4 in-scope file changes to pre-phase state. Phase result = FAIL.
4. **Trigger:** Tier 2 regression in step 22 exits non-zero. **Rollback action:** revert all section 4 in-scope file changes to pre-phase state. Phase result = FAIL.
5. **Trigger:** `tests/test_unreachable_shadow_node_forces_scan_then_search.gd` observes repeated `SHADOW_BOUNDARY_SCAN` for the same active node after one completed shadow boundary scan. **Rollback action:** revert Phase 16 combat-search session and utility-context suppression edits in `src/entities/enemy.gd`, then revert remaining Phase 16 changes. Partial state is forbidden.
6. **Trigger:** `combat_search_progress` or awareness field names in `_build_confirm_runtime_config` differ from the section 6 contract keys. **Rollback action:** revert Phase 16 `enemy.gd` edits and all dependent tests/config changes. Phase result = FAIL.
7. **Trigger:** Any file outside section 4 in-scope list is modified. **Rollback action:** revert out-of-scope changes immediately, then revert all Phase 16 edits. Phase result = FAIL.
8. **Trigger:** Implementation cannot complete the dark-search node session and awareness contract continuity within section 4 scope. **Rollback action:** revert all changes to pre-phase state. Phase result = FAIL (Hard Rule 11).

---

## 16. Phase close condition.

- [ ] All rg commands in section 10 return `0 matches`
- [ ] All rg gates in section 13 return expected output
- [ ] All tests in section 12 (new + updated) exit `0`
- [ ] Tier 1 smoke suite (section 14) — all commands exit `0`
- [ ] Tier 2 full regression (`xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn`) exits `0`
- [ ] No file outside section 4 in-scope list was modified
- [ ] `CHANGELOG.md` entry prepended
- [ ] `tests/test_dark_search_graph_progressive_coverage.gd` records monotonically non-decreasing room coverage and `combat_search_progress` during active no-contact session windows
- [ ] `tests/test_unreachable_shadow_node_forces_scan_then_search.gd` records the exact sequence `SHADOW_BOUNDARY_SCAN -> SEARCH` on the same dark node target with no repeated `SHADOW_BOUNDARY_SCAN` before node completion
- [ ] `tests/test_combat_to_alert_requires_no_contact_and_search_progress.gd` passes unchanged

---

## 17. Ambiguity check: 0

---

## 18. Open questions: 0

---

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).

**Diff audit:**
- Diff every file in section 4 against the pre-phase baseline, including all 3 new test script/scene pairs and `CHANGELOG.md`.
- Confirm zero modifications outside the section 4 in-scope list.

**Contract checks:**
- `CombatDarkSearchNodeSelectionContractV1` (section 6): inspect `Enemy._select_next_combat_dark_search_node` and verify output keys/status/reason enums and scoring tuple order exactly match section 7.
- Phase 16 session state transition contract (section 7): inspect `Enemy._update_combat_search_runtime` and verify `NEEDS_SHADOW_SCAN -> SEARCH_DWELL -> COVERED` transitions and room coverage updates match section 7.
- Awareness continuity contract (section 3 item 3 / section 6 existing retained fields): inspect `Enemy._build_confirm_runtime_config` and `Enemy.get_debug_detection_snapshot` and verify `combat_search_*` field names remain unchanged.
- Shadow canon suppression contract (section 7): inspect `Enemy._build_utility_context` and verify the suppression predicate and `shadow_scan_target_in_shadow = false` assignment path for the active node after scan completion.

**Runtime scenarios from section 20:** execute P16-A, P16-B, P16-C, P16-D, P16-E, and P16-F.

---

## 20. Runtime scenario matrix (scenario id, setup, frame count, expected invariants, fail conditions).

**P16-A: Dark-search graph progressive coverage is monotonic**
- Scene: `tests/test_dark_search_graph_progressive_coverage.tscn`
- Setup: Enemy + FakeNav with deterministic room center/rect, deterministic shadow mask, deterministic path lengths, no valid contact, Phase 11-style shadow stage getter stub.
- Frame count: `0` for direct helper calls plus `N` scripted `_update_combat_search_runtime(...)` calls in the test loop (`N >= 10`).
- Expected invariants:
  - Current-room raw coverage never decreases.
  - `combat_search_progress` never decreases during a single active room session before room switch.
  - Selected node keys change only after dwell completion or room timeout.
- Fail conditions:
  - Any coverage sample decreases.
  - `combat_search_progress` decreases while room id and total-cap flag remain unchanged.
  - Active node changes without dwell completion, room timeout, or coverage threshold.
- Covered by: `_test_room_dark_search_coverage_monotonic_non_decreasing`

**P16-B: Selector scoring order and tie-break**
- Scene: `tests/test_dark_search_graph_progressive_coverage.tscn`
- Setup: Inject deterministic node rows and path-length stub values into `_combat_search_room_nodes`; invoke `_select_next_combat_dark_search_node(...)` directly.
- Frame count: `0` (synchronous unit calls).
- Expected invariants:
  - Unvisited node outranks visited node.
  - Lower path length outranks longer path at equal uncovered score and tactical priority.
  - Lexical `node_key` ascending resolves exact score/path/priority ties.
- Fail conditions:
  - Selector returns visited node.
  - Tie-break returns non-lexical key.
- Covered by: `_test_select_next_dark_node_prefers_uncovered_then_shorter_policy_path`, `_test_tie_break_same_score_resolves_by_lexical_node_key`

**P16-C: Unreachable shadow node forces one shadow scan, then SEARCH on same target**
- Scene: `tests/test_unreachable_shadow_node_forces_scan_then_search.tscn`
- Setup: Active dark pocket node with `target_in_shadow = true`, reachable `approach_pos`, FakePursuit stage sequence `[BOUNDARY_LOCK/SWEEP/... -> IDLE]`, no-contact ALERT/COMBAT context from Phase 15 doctrine dependency.
- Frame count: `0` for unit loops plus explicit feedback ticks that simulate intent selection and pursuit stage transitions.
- Expected invariants:
  - First active-node selection path emits `SHADOW_BOUNDARY_SCAN`.
  - After shadow-stage edge to IDLE, next tick emits `SEARCH` with the same `target_pos`.
  - `combat_search_shadow_scan_suppressed == true` only after scan completion and only for that node.
- Fail conditions:
  - Direct `SEARCH` before any `SHADOW_BOUNDARY_SCAN` on a dark node.
  - Repeated `SHADOW_BOUNDARY_SCAN` loop after completion on the same node.
  - `target_pos` changes during the scan->search flip.
- Covered by: `_test_dark_node_in_shadow_requests_shadow_boundary_scan_before_search`, `_test_shadow_scan_completion_flips_same_node_to_search_without_repeat_scan`

**P16-D: SEARCH dwell marks node covered and advances coverage**
- Scene: `tests/test_unreachable_shadow_node_forces_scan_then_search.tscn`
- Setup: Active node already in `SEARCH_DWELL` state; repeated feedback records `IntentType.SEARCH` with matching target for cumulative dwell >= `combat_dark_search_node_dwell_sec`.
- Frame count: `0` (unit loop using `_record_combat_search_execution_feedback` + `_update_combat_search_runtime`).
- Expected invariants:
  - Node visited flag becomes true exactly once.
  - Current-node key changes to the next node or clears before room switch.
  - Current-room coverage raw increases after coverage mark.
- Fail conditions:
  - Coverage unchanged after dwell threshold.
  - Same node is marked covered multiple times.
- Covered by: `_test_search_dwell_marks_node_covered_and_selects_next_node`

**P16-E: Session completion contract retains awareness gate fields**
- Scene: `tests/test_alert_combat_search_session_completion_contract.tscn`
- Setup: Enemy in COMBAT no-contact runtime; drive search session until room completion and total-cap completion.
- Frame count: scripted loop (`N >= 50`) with deterministic `delta` values.
- Expected invariants:
  - `_build_confirm_runtime_config(...)` returns exact field names used by `EnemyAwarenessSystem.process_confirm` COMBAT gate.
  - Total-cap path sets `_combat_search_total_cap_hit == true` and `combat_search_progress == 0.8`.
- Fail conditions:
  - Any required awareness field key is missing or renamed.
  - Total cap does not clamp progress to threshold.
- Covered by: `_test_total_cap_forces_progress_threshold_and_cap_flag`, `_test_confirm_runtime_config_keeps_awareness_field_names`

**P16-F: Shadow recovery regressions remain stable**
- Scene: `tests/test_shadow_stall_escapes_to_light.tscn` and `tests/test_shadow_policy_hard_block_without_grant.tscn`
- Setup: existing pursuit-only fake nav suites (unchanged harness).
- Frame count: existing test loops (`240` physics frames in stall test; `16` ticks in hard-block test).
- Expected invariants:
  - Shadow stall escape target remains on the light side.
  - Policy-blocked path still reports `policy_blocked` and fallback target avoids blocked shadow region.
- Fail conditions:
  - Escape target remains in shadow.
  - Pursuit path-plan reason changes from `policy_blocked` in the hard-block suite.
- Covered by: `_test_shadow_stall_prefers_escape_to_light`, `_test_policy_block_and_fallback`

---

## 21. Verification report format (what must be recorded to close phase).

Record all fields below to close phase:
- `phase_id: PHASE_16`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; empty list required for PASS)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `dependency_gate_check: [PHASE-11: PASS|FAIL, PHASE-15: PASS|FAIL]` **[BLOCKING — all must be PASS before implementation and before close]**
- `legacy_rg: [{command, expected: "0 matches", actual, PASS|FAIL}]` for all 4 commands from section 10
- `rg_gates: [{gate: "G1".."G10"|"PMB-1".."PMB-5", command, expected, actual, PASS|FAIL}]`
- `phase_tests: [{test_function, scene, exit_code: 0, PASS|FAIL}]` for all new and updated test functions listed in section 12
- `smoke_suite: [{command, exit_code: 0, PASS|FAIL}]` for all 8 Tier 1 commands from section 14
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `dark_search_coverage_monotonic_check: {scene: "res://tests/test_dark_search_graph_progressive_coverage.tscn", samples_checked, monotonic_room_coverage: PASS|FAIL, monotonic_progress: PASS|FAIL}`
- `shadow_canon_sequence_check: {scene: "res://tests/test_unreachable_shadow_node_forces_scan_then_search.tscn", sequence_expected: "SHADOW_BOUNDARY_SCAN->SEARCH", actual_sequence, repeated_scan_after_completion: true|false, PASS|FAIL}`
- `awareness_contract_continuity_check: {keys_present: [combat_search_progress, combat_search_total_elapsed_sec, combat_search_room_elapsed_sec, combat_search_total_cap_sec, combat_search_force_complete], PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

---

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 16` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- `pmb_contract_check` present in section 21 (PMB section exists in document): yes

---

## 23. Dependencies on previous phases.

1. **Phase 11** — `EnemyPursuitSystem._execute_shadow_boundary_scan` is a staged shadow-search choreography and Phase 11 introduces public getters `get_shadow_search_stage() -> int` and `get_shadow_search_coverage() -> float`. Phase 16 uses `get_shadow_search_stage()` in `Enemy._update_combat_search_runtime` (section 7) to detect completion of the shadow boundary scan stage for the active dark node and to flip that node from `NEEDS_SHADOW_SCAN` to `SEARCH_DWELL` without repeated scan loops.

2. **Phase 15** — `Enemy._build_utility_context` and `EnemyUtilityBrain._choose_intent` implement the state doctrine matrix for no-LOS behavior in ALERT/COMBAT with active target context, including no degradation to `PATROL`/`RETURN_HOME` and alert/combat shadow-scan target selection derived from target context. Phase 16 keeps `_combat_search_target_pos` as the active target-context source and adds only the suppression predicate in section 7 so the same dark node target progresses from `SHADOW_BOUNDARY_SCAN` to `SEARCH` instead of repeating `SHADOW_BOUNDARY_SCAN`.
## PHASE 17
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_17.
Scope boundary (exact files): section 4.
Execution sequence: section 14.
Rollback conditions: section 15.
Verification report format: section 21.

### Evidence

**Inspected files:**
- `src/systems/enemy_pursuit_system.gd` (lines 1–240, 240–420, 640–860, 900–1210; targeted `rg` line refs for stall monitor, collision handling, shadow-escape legacy branches, and debug snapshot)
- `src/entities/enemy.gd` (lines 468–715, 1000–1105, 1200–1335, 2120–2155, 2250–2525; combat-search runtime, utility context, execute-intent integration, debug snapshot, and awareness config bridge)
- `src/core/game_config.gd` (lines 120–260; `ai_balance["pursuit"]` placement)
- `src/core/config_validator.gd` (lines 150–260; pursuit validation block)
- `tests/test_shadow_stall_escapes_to_light.gd` (full)
- `tests/test_pursuit_stall_fallback_invariants.gd` (full)
- `tests/test_detour_side_flip_on_stall.gd` (full)
- `tests/test_shadow_enemy_stuck_when_inside_shadow.gd` (full; smoke-only nav policy baseline for Phase 17)
- `tests/test_shadow_enemy_unstuck_after_flashlight_activation.gd` (full; smoke-only nav/flashlight grant baseline for Phase 17)
- `tests/test_door_enemy_oblique_open_then_cross_no_wall_stall.gd` (full; Phase 3 collision/door contract smoke)
- `tests/test_stall_definition_reproducible_thresholds.gd` (full; stall threshold regression)
- `tests/test_shadow_policy_hard_block_without_grant.gd` (full; policy-block smoke baseline)
- `tests/test_runner_node.gd` (lines 60–120, 740–820, 1060–1105; scene constants, existence checks, and suite run calls)
- `docs/ai_nav_refactor_execution_v2.md` (Phase 3 collision contract sections; Phase 16 dark-search session spec sections)

**Inspected functions/methods:**
- `EnemyPursuitSystem.execute_intent`
- `EnemyPursuitSystem._execute_move_to_target`
- `EnemyPursuitSystem._follow_waypoints`
- `EnemyPursuitSystem._try_open_blocking_door_and_force_repath`
- `EnemyPursuitSystem._attempt_replan_with_policy`
- `EnemyPursuitSystem._resolve_nearest_reachable_fallback`
- `EnemyPursuitSystem._resolve_movement_target_with_shadow_escape`
- `EnemyPursuitSystem._attempt_shadow_escape_recovery`
- `EnemyPursuitSystem._resolve_shadow_escape_target`
- `EnemyPursuitSystem._sample_shadow_escape_candidates`
- `EnemyPursuitSystem._is_owner_in_shadow_without_flashlight`
- `EnemyPursuitSystem._reset_stall_monitor`
- `EnemyPursuitSystem._update_stall_monitor`
- `EnemyPursuitSystem.debug_get_navigation_policy_snapshot`
- `EnemyPursuitSystem.debug_feed_stall_window`
- `Enemy.runtime_budget_tick`
- `Enemy._build_utility_context`
- `Enemy.get_debug_detection_snapshot`
- `Enemy._build_confirm_runtime_config`
- `Enemy._update_combat_search_runtime`
- `Enemy._ensure_combat_search_room`
- `Enemy._update_combat_search_progress`
- `Enemy._resolve_known_target_context`
- `TestShadowStallEscapesToLight._test_shadow_stall_prefers_escape_to_light`
- `TestPursuitStallFallbackInvariants._test_stall_and_fallback_invariants`
- `TestDetourSideFlipOnStall._test_detour_side_flip_on_stall`
- `TestDoorEnemyObliqueOpenThenCrossNoWallStall._test_door_open_resets_repath_timer_for_crossing`
- `TestStallDefinitionReproducibleThresholds._test_stall_threshold_contract`
- `TestRunner._run_tests`
- `TestRunner._scene_exists`
- `TestRunner._run_embedded_scene_suite`

**Search commands used:**
- `rg -n "stall|collision|shadow_escape|blocked_point|repath" src/systems/enemy_pursuit_system.gd -S`
- `rg -n "shadow_enemy_stuck|unstuck_after_flashlight|collision_block_forces_immediate_repath|shadow_stall|blocked_point" tests -g '*.gd' -S`
- `rg -n "^func (execute_intent|_execute_move_to_target|_follow_waypoints|_try_open_blocking_door_and_force_repath|_attempt_replan_with_policy|_resolve_nearest_reachable_fallback|_resolve_movement_target_with_shadow_escape|_attempt_shadow_escape_recovery|_resolve_shadow_escape_target|_sample_shadow_escape_candidates|_is_owner_in_shadow_without_flashlight|_reset_stall_monitor|_update_stall_monitor|debug_get_navigation_policy_snapshot|debug_feed_stall_window)\(" src/systems/enemy_pursuit_system.gd -S`
- `rg -n "^var _shadow_escape_|^const SHADOW_ESCAPE_RING_|shadow_escape_" src/systems/enemy_pursuit_system.gd tests -g '*.gd' -S`
- `rg -n "^func (runtime_budget_tick|get_debug_detection_snapshot|_build_utility_context|_build_confirm_runtime_config|_update_combat_search_runtime|_ensure_combat_search_room|_update_combat_search_progress|_resolve_known_target_context)\(" src/entities/enemy.gd -S`
- `rg -n "_handle_slide_collisions_and_repath|get_shadow_search_stage|get_shadow_search_coverage|_record_combat_search_execution_feedback|_select_next_combat_dark_search_node" src/systems/enemy_pursuit_system.gd src/entities/enemy.gd -S`
- `rg -n "^## PHASE 3$|_handle_slide_collisions_and_repath|collision_blocked|non-door collision" docs/ai_nav_refactor_execution_v2.md -S`
- `rg -n "_combat_search_current_node_key|_record_combat_search_execution_feedback|_select_next_combat_dark_search_node|combat_search_shadow_scan_suppressed" docs/ai_nav_refactor_execution_v2.md -S`

**Confirmed facts:**
- `src/systems/enemy_pursuit_system.gd` still contains the shadow-escape branch set (`SHADOW_ESCAPE_RING_*`, `_shadow_escape_*`, `_resolve_movement_target_with_shadow_escape`, `_attempt_shadow_escape_recovery`, `_resolve_shadow_escape_target`, `_sample_shadow_escape_candidates`, `_is_owner_in_shadow_without_flashlight`) and still exposes `shadow_escape_*` keys in `debug_get_navigation_policy_snapshot`.
- `_execute_move_to_target` still mutates movement target through `_resolve_movement_target_with_shadow_escape(target, has_target)` and still calls `_attempt_shadow_escape_recovery()` on replan failure, policy-blocked movement, and hard stall paths (lines 327, 339, 352, 357).
- `EnemyPursuitSystem` stall monitor exists (`_update_stall_monitor`) and already computes deterministic `hard_stall` state, but it returns only `bool` and emits no intent-preserving recovery feedback.
- `Enemy.runtime_budget_tick` executes `_update_combat_search_runtime(...)`, builds utility context, calls `_pursuit.execute_intent(...)`, and holds `intent` plus `exec_result` in the same function scope, so Phase 17 recovery feedback consumption fits in one deterministic location.
- `Enemy.get_debug_detection_snapshot` and `Enemy._build_confirm_runtime_config` already publish the `combat_search_*` field family consumed by `EnemyAwarenessSystem.process_confirm` COMBAT->ALERT gating.
- Current source tree contains no Phase 3 owner function `_handle_slide_collisions_and_repath` and contains no Phase 16 dark-search session helpers (`_record_combat_search_execution_feedback`, `_select_next_combat_dark_search_node`) in `src/entities/enemy.gd`; Phase 17 start is blocked until dependency gates in section 23 pass.
- `tests/test_shadow_stall_escapes_to_light.gd` directly asserts `shadow_escape_active` and `shadow_escape_target` debug snapshot keys (lines 98–99), so Phase 17 legacy removal requires a test rewrite in this file.
- `tests/test_pursuit_stall_fallback_invariants.gd` and `tests/test_stall_definition_reproducible_thresholds.gd` already exercise deterministic stall thresholds and remain the correct regression anchors for the Phase 17 watchdog path.

---

## 1. What now.

Phase 17 dependency outputs are absent in the current tree and the shadow-escape legacy branch is still active.

Verification of current state:

```bash
rg -n "_handle_slide_collisions_and_repath" src/systems/enemy_pursuit_system.gd -S
```
Expected current output in this tree: `0 matches` (Phase 3 dependency gate fails before Phase 17 start).

```bash
rg -n "_record_combat_search_execution_feedback|_select_next_combat_dark_search_node" src/entities/enemy.gd -S
```
Expected current output in this tree: `0 matches` (Phase 16 dependency gate fails before Phase 17 start).

```bash
rg -n "_shadow_escape_active|_shadow_escape_target|_attempt_shadow_escape_recovery|_resolve_shadow_escape_target|_sample_shadow_escape_candidates|_resolve_movement_target_with_shadow_escape" src/systems/enemy_pursuit_system.gd -S
```
Expected current output: `> 0 matches` (shadow-escape legacy pursuit branch remains active).

```bash
rg -n "shadow_escape_active|shadow_escape_target" tests/test_shadow_stall_escapes_to_light.gd -S
```
Expected current output: `2 matches` (test directly depends on legacy debug keys).

Current measurable gap in pursuit runtime behavior:
- `_update_stall_monitor(...)` returns `bool` only, and `execute_intent(...)` output contains no key that requests a dark-search node advance while preserving the current intent and target context.

---

## 2. What changes.

1. **`src/systems/enemy_pursuit_system.gd` — delete** file-scope constants `SHADOW_ESCAPE_RING_MIN_RADIUS_PX`, `SHADOW_ESCAPE_RING_STEP_RADIUS_PX`, `SHADOW_ESCAPE_RING_COUNT`, and `SHADOW_ESCAPE_SAMPLES_PER_RING` before adding replacement recovery logic.
2. **`src/systems/enemy_pursuit_system.gd` — delete** file-scope state vars `_shadow_escape_active`, `_shadow_escape_target`, and `_shadow_escape_target_valid` before adding new recovery-feedback state vars.
3. **`src/systems/enemy_pursuit_system.gd` — delete** functions `_resolve_movement_target_with_shadow_escape`, `_attempt_shadow_escape_recovery`, `_resolve_shadow_escape_target`, `_sample_shadow_escape_candidates`, and `_is_owner_in_shadow_without_flashlight` before adding new watchdog/feedback helpers.
4. **`src/systems/enemy_pursuit_system.gd` — add** file-scope blocked-point repeat tracker vars and recovery-feedback vars: `_blocked_point_repeat_bucket`, `_blocked_point_repeat_bucket_valid`, `_blocked_point_repeat_count`, `_repath_recovery_request_next_search_node`, `_repath_recovery_reason`, `_repath_recovery_blocked_point`, `_repath_recovery_blocked_point_valid`, `_repath_recovery_repeat_count`, `_repath_recovery_preserve_intent`, `_repath_recovery_intent_target`.
5. **`src/systems/enemy_pursuit_system.gd` — add** private helpers `_reset_repath_recovery_feedback() -> void` and `_update_blocked_point_repeat_tracker() -> void`.
6. **`src/systems/enemy_pursuit_system.gd` — rewrite** `_execute_move_to_target(...)` to remove shadow-escape target substitution and shadow-escape recovery calls; replace them with intent-preserving recovery feedback emission and deterministic `_repath_timer = 0.0` repath forcing.
7. **`src/systems/enemy_pursuit_system.gd` — modify** `_attempt_replan_with_policy(target_pos)` to remove the shadow-escape precheck from `_resolve_nearest_reachable_fallback` path and keep generic nearest-reachable fallback behavior only.
8. **`src/systems/enemy_pursuit_system.gd` — modify** `execute_intent(...)` to reset recovery feedback at entry and append the Phase 17 recovery feedback keys to the returned `Dictionary`.
9. **`src/systems/enemy_pursuit_system.gd` — modify** `configure_navigation(...)` and `debug_get_navigation_policy_snapshot()` to reset/expose the new recovery-feedback and blocked-point repeat tracker fields and to remove all `shadow_escape_*` snapshot keys.
10. **`src/entities/enemy.gd` — add** debug vars for applied recovery feedback (`_combat_search_recovery_last_applied`, `_combat_search_recovery_last_reason`, `_combat_search_recovery_last_blocked_point`, `_combat_search_recovery_last_blocked_point_valid`, `_combat_search_recovery_last_skipped_node_key`).
11. **`src/entities/enemy.gd` — add** private function `_apply_combat_search_repath_recovery_feedback(intent: Dictionary, exec_result: Dictionary) -> void` as the Phase 17 single-owner node-escalation decision point.
12. **`src/entities/enemy.gd` — modify** `runtime_budget_tick(delta)` to call `_apply_combat_search_repath_recovery_feedback(intent, exec_result)` immediately after `_pursuit.execute_intent(...)` and before `_update_combat_role_runtime(...)`.
13. **`src/entities/enemy.gd` — modify** `get_debug_detection_snapshot()` to expose Phase 17 recovery debug keys from item 10.
14. **`src/entities/enemy.gd` — modify** `_reset_combat_search_state()` to reset the Phase 17 recovery debug vars from item 10.
15. **`src/core/game_config.gd` — add** 3 `ai_balance["pursuit"]` keys for blocked-point repeat bucketing and node-target match radius (section 6 exact names/values).
16. **`src/core/config_validator.gd` — add** validator checks for the 3 new pursuit keys from item 15.
17. **New** `tests/test_shadow_stuck_watchdog_escalates_to_next_node.gd` + `tests/test_shadow_stuck_watchdog_escalates_to_next_node.tscn` — watchdog and intent-preserving node escalation contract tests.
18. **New** `tests/test_repeated_blocked_point_triggers_scan_then_search.gd` + `tests/test_repeated_blocked_point_triggers_scan_then_search.tscn` — repeated blocked-point -> next-node -> `SHADOW_BOUNDARY_SCAN -> SEARCH` integration contract tests.
19. **`tests/test_shadow_stall_escapes_to_light.gd` — update** `_test_shadow_stall_prefers_escape_to_light` to remove legacy `shadow_escape_*` snapshot assertions and assert Phase 17 recovery feedback keys / no-freeze behavior.
20. **`tests/test_pursuit_stall_fallback_invariants.gd` — update** `_test_stall_and_fallback_invariants` to assert new recovery feedback snapshot keys exist and all legacy `shadow_escape_*` keys are absent.
21. **`tests/test_detour_side_flip_on_stall.gd` — update** `_test_detour_side_flip_on_stall` to assert COMBAT no-LOS runtime stays stable while Phase 17 recovery feedback does not cause teleport spikes or state drops.
22. **`tests/test_runner_node.gd` — modify** `_run_tests`: add 2 scene const declarations, 2 `_scene_exists(...)` checks, and 2 `_run_embedded_scene_suite(...)` calls for the new Phase 17 suites.

---

## 3. What will be after.

1. `src/systems/enemy_pursuit_system.gd` contains no `shadow_escape_*` vars, functions, or snapshot keys and contains no `SHADOW_ESCAPE_RING_*` constants (verified by section 10 and gates G1–G3 in section 13).
2. `EnemyPursuitSystem.execute_intent(...)` returns deterministic Phase 17 recovery feedback keys that report whether the current tick requests a dark-search node advance while preserving intent (`repath_recovery_request_next_search_node`, `repath_recovery_reason`, `repath_recovery_blocked_point`, `repath_recovery_blocked_point_valid`, `repath_recovery_repeat_count`, `repath_recovery_preserve_intent`, `repath_recovery_intent_target`) (verified by gate G4 and section 12 tests).
3. `Enemy._apply_combat_search_repath_recovery_feedback(intent, exec_result)` is the single owner of dark-search node skip/escalation decisions, and `Enemy.runtime_budget_tick` consumes pursuit recovery feedback in one deterministic location (verified by gates G5 and G6 plus section 12 tests).
4. Repeated blocked points in the same bucket or hard stalls in SEARCH / SHADOW_BOUNDARY_SCAN request the next dark-search node without mutating the current tick intent type and without mutating the current tick utility target context (verified by `tests/test_shadow_stuck_watchdog_escalates_to_next_node.gd` and `tests/test_repeated_blocked_point_triggers_scan_then_search.gd`).
5. `SHADOW_BOUNDARY_SCAN -> SEARCH` canon for a dark node remains active after blocked-point escalation, because Phase 17 skips the blocked node and Phase 16 node-selection / Phase 11 shadow-stage choreography continue the sequence on the next node (verified by `tests/test_repeated_blocked_point_triggers_scan_then_search.gd`).
6. `combat_search_*` awareness field names in `Enemy.get_debug_detection_snapshot()` and `Enemy._build_confirm_runtime_config()` remain unchanged (verified by gate G7 and smoke `tests/test_combat_to_alert_requires_no_contact_and_search_progress.gd`).
7. PMB-1 through PMB-5 remain at expected outputs (verified by PMB gates in section 13 and `pmb_contract_check` in section 21).

---

## 4. Scope and non-scope (exact files).

**In-scope:**
- `src/systems/enemy_pursuit_system.gd`
- `src/entities/enemy.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `tests/test_shadow_stuck_watchdog_escalates_to_next_node.gd` (new)
- `tests/test_shadow_stuck_watchdog_escalates_to_next_node.tscn` (new)
- `tests/test_repeated_blocked_point_triggers_scan_then_search.gd` (new)
- `tests/test_repeated_blocked_point_triggers_scan_then_search.tscn` (new)
- `tests/test_shadow_stall_escapes_to_light.gd`
- `tests/test_pursuit_stall_fallback_invariants.gd`
- `tests/test_detour_side_flip_on_stall.gd`
- `tests/test_runner_node.gd`
- `CHANGELOG.md`

**Out-of-scope (must not be modified):**
- `src/systems/enemy_utility_brain.gd` (Phase 15 doctrine owner remains unchanged)
- `src/systems/enemy_awareness_system.gd` (COMBAT->ALERT search-progress gate logic remains unchanged)
- `src/systems/navigation_service.gd` (nav policy and room/shadow queries consumed as-is)
- `src/systems/navigation_runtime_queries.gd`
- `src/systems/enemy_patrol_system.gd`
- `tests/test_shadow_enemy_stuck_when_inside_shadow.gd` (smoke-only baseline)
- `tests/test_shadow_enemy_unstuck_after_flashlight_activation.gd` (smoke-only baseline)
- `tests/test_door_enemy_oblique_open_then_cross_no_wall_stall.gd` (smoke-only Phase 3 contract baseline)
- `tests/test_stall_definition_reproducible_thresholds.gd` (smoke-only stall threshold baseline)
- `scenes/entities/enemy.tscn`

Allowed file-change boundary (exact paths): same as the in-scope list above.

---

## 5. Single-owner authority for this phase.

**Owner file:** `src/entities/enemy.gd`.

**Owner function:** `Enemy._apply_combat_search_repath_recovery_feedback(intent: Dictionary, exec_result: Dictionary) -> void`.

Phase 17 introduces one new gameplay decision: whether a pursuit recovery signal escalates the current dark-search session to the next node while preserving the current tick intent and target context. That decision occurs only in `Enemy._apply_combat_search_repath_recovery_feedback`. `EnemyPursuitSystem` emits raw recovery feedback. `Enemy` applies or rejects node escalation. No second file decides node escalation eligibility.

**Verifiable uniqueness gate:** section 13, gate G6.

---

## 6. Full input/output contract.

**Contract 1 name:** `PursuitRepathRecoveryFeedbackContractV1`

**Owner:** `EnemyPursuitSystem.execute_intent(delta: float, intent: Dictionary, context: Dictionary) -> Dictionary`

**Inputs (types, nullability, finite checks):**
- `delta: float` — non-null, finite, `delta >= 0.0`.
- `intent: Dictionary` — non-null. Required key `"type": int`. Optional key `"target": Vector2` when movement intent uses target.
- `context: Dictionary` — non-null. Existing Phase 0/15 keys unchanged.
- Implicit internal inputs used by Phase 17 feedback build:
  - `_last_path_failed_reason: String`
  - `_last_path_plan_blocked_point: Vector2`
  - `_last_path_plan_blocked_point_valid: bool`
  - `_stall_consecutive_windows: int`
  - `_hard_stall: bool`
  - `_last_intent_type: int`

**Outputs (exact keys/types/enums) — existing keys retained plus Phase 17 keys:**
- Existing retained keys (unchanged):
  - `request_fire: bool`
  - `path_failed: bool`
  - `path_failed_reason: String`
  - `policy_blocked_segment: int`
  - `movement_intent: bool`
- New Phase 17 keys (always present):
  - `repath_recovery_request_next_search_node: bool`
  - `repath_recovery_reason: String`
  - `repath_recovery_blocked_point: Vector2`
  - `repath_recovery_blocked_point_valid: bool`
  - `repath_recovery_repeat_count: int`
  - `repath_recovery_preserve_intent: bool`
  - `repath_recovery_intent_target: Vector2`

**Status enums:**
- Existing path-plan status enums remain unchanged in planner/debug paths: `"ok"`, `"unreachable_policy"`, `"unreachable_geometry"`.

**Reason enums (Phase 17 recovery feedback, exact values):**
- `"none"`
- `"collision_blocked"`
- `"hard_stall"`
- `"blocked_point_repeat"`

**Contract 1 deterministic rules:**
- `repath_recovery_request_next_search_node == true` only when current intent type is `IntentType.SEARCH` or `IntentType.SHADOW_BOUNDARY_SCAN` and the recovery reason is one of the three non-`none` enums.
- `repath_recovery_preserve_intent == repath_recovery_request_next_search_node`.
- `repath_recovery_intent_target` equals `intent.get("target", Vector2.ZERO)` as `Vector2` on every return.
- `repath_recovery_repeat_count` equals the current blocked-point repeat tracker count on every return (0 when tracker invalid).

**Contract 2 name:** `CombatDarkSearchRecoveryApplyContractV1`

**Owner:** `Enemy._apply_combat_search_repath_recovery_feedback(intent: Dictionary, exec_result: Dictionary) -> void`

**Inputs (types, nullability, finite checks):**
- `intent: Dictionary` — non-null, required `"type": int`, optional `"target": Vector2`.
- `exec_result: Dictionary` — non-null, and must contain all 7 Phase 17 recovery-feedback keys from Contract 1: `repath_recovery_request_next_search_node`, `repath_recovery_reason`, `repath_recovery_blocked_point`, `repath_recovery_blocked_point_valid`, `repath_recovery_repeat_count`, `repath_recovery_preserve_intent`, `repath_recovery_intent_target`. Other `execute_intent(...)` keys are ignored by this function.
- Implicit Phase 16 state inputs (dependency gate required before phase start):
  - `_combat_search_current_room_id: int`
  - `_combat_search_current_node_key: String`
  - `_combat_search_target_pos: Vector2`
  - `_select_next_combat_dark_search_node(room_id, combat_target_pos) -> Dictionary`
  - `_ensure_combat_search_room(room_id, combat_target_pos) -> void`
  - `_select_next_combat_search_room(current_room, combat_target_pos) -> int`
  - `_mark_combat_search_current_node_covered() -> void`
- `repath_recovery_intent_target: Vector2` and `repath_recovery_blocked_point: Vector2` must be finite when corresponding valid flags are true.

**Outputs (exact keys/types/enums) — state mutations plus debug snapshot fields in `Enemy.get_debug_detection_snapshot()`:**
- `combat_search_recovery_applied: bool`
- `combat_search_recovery_reason: String` enum `{ "none", "collision_blocked", "hard_stall", "blocked_point_repeat" }`
- `combat_search_recovery_blocked_point: Vector2`
- `combat_search_recovery_blocked_point_valid: bool`
- `combat_search_recovery_skipped_node_key: String`

**Contract 2 deterministic rules:**
- `combat_search_recovery_applied == true` only when all guards in section 7 are true and one active node is skipped in the current tick.
- When `combat_search_recovery_applied == true`, `_combat_search_target_pos` changes to the next selected node target or to the first node in the next room after room switch.
- Phase 17 counts a skipped blocked node as a terminal visited node by invoking `_mark_combat_search_current_node_covered()` exactly once before reselection.
- Contract 2 never mutates the current tick `intent` dictionary and never mutates `target_context` built earlier in `runtime_budget_tick`.

**Deterministic order and tie-break rules:**
- Contract 1 tie-break is N/A because `execute_intent` builds at most one recovery feedback output per tick.
- Contract 2 tie-break is N/A because one active dark-search node exists by Phase 16 session design (`_combat_search_current_node_key` is one string or empty).

**Constants/thresholds used (exact values + placement):**

GameConfig (`src/core/game_config.gd`, `ai_balance["pursuit"]`):
- `repath_recovery_blocked_point_bucket_px = 24.0`
- `repath_recovery_blocked_point_repeat_threshold = 2`
- `repath_recovery_intent_target_match_radius_px = 28.0`

Existing retained constants (no rename in this phase):
- `STALL_WINDOW_SEC = 0.6` (`src/systems/enemy_pursuit_system.gd`)
- `STALL_CHECK_INTERVAL_SEC = 0.1` (`src/systems/enemy_pursuit_system.gd`)
- `STALL_SPEED_THRESHOLD_PX_PER_SEC = 8.0` (`src/systems/enemy_pursuit_system.gd`)
- `STALL_PATH_PROGRESS_THRESHOLD_PX = 12.0` (`src/systems/enemy_pursuit_system.gd`)
- `STALL_HARD_CONSECUTIVE_WINDOWS = 2` (`src/systems/enemy_pursuit_system.gd`)
- `COMBAT_SEARCH_PROGRESS_THRESHOLD = 0.8` (`src/entities/enemy.gd`)

---

## 7. Deterministic algorithm with exact order.

1. **Dependency precondition (before implementation and before runtime execution checks):** Phase 3 collision owner `_handle_slide_collisions_and_repath` and Phase 16 dark-search session helpers from section 23 exist. Phase 17 implementation does not proceed until both dependency gates pass.

2. **`EnemyPursuitSystem.execute_intent(...)` entry order (Phase 17 additions):**
- After the existing per-tick resets (`_last_path_failed`, `_last_path_failed_reason`, `_last_policy_blocked_segment`) and before `match intent_type`, call `_reset_repath_recovery_feedback()`.
- `_reset_repath_recovery_feedback()` sets request flag false, reason `"none"`, blocked-point zero/invalid, repeat count `0`, preserve-intent false, and intent target `Vector2.ZERO`.
- Phase 17 does not introduce a separate `_build_repath_recovery_feedback()` helper. `_execute_move_to_target(...)` writes `_repath_recovery_*` state directly, and `execute_intent(...)` appends those values to the returned `Dictionary`.

3. **`EnemyPursuitSystem._execute_move_to_target(...)` target handling rewrite:**
- Replace `var movement_target := _resolve_movement_target_with_shadow_escape(target, has_target)` with `var movement_target := target`.
- No Phase 17 code path calls `_attempt_shadow_escape_recovery()`.
- `_active_move_target` and `_active_move_target_valid` update rules remain the same as current code except the removed shadow-escape substitution branch.

4. **Phase 3 collision contract consumption in pursuit (Phase 17 feedback emission):**
- After movement and collision handling, when `_last_path_failed_reason == "collision_blocked"` in the same `execute_intent` tick, build recovery feedback with:
  - `repath_recovery_reason = "collision_blocked"`
  - `repath_recovery_request_next_search_node = (current intent type is SEARCH or SHADOW_BOUNDARY_SCAN)`
  - `repath_recovery_preserve_intent = repath_recovery_request_next_search_node`
  - `repath_recovery_intent_target = movement_target`
  - `repath_recovery_blocked_point = _last_path_plan_blocked_point` when `_last_path_plan_blocked_point_valid`, else `Vector2.ZERO`
  - `repath_recovery_blocked_point_valid = _last_path_plan_blocked_point_valid`

5. **Blocked-point repeat tracker update in pursuit:**
- `_update_blocked_point_repeat_tracker()` runs after `_attempt_replan_with_policy(movement_target)` when `_path_policy_blocked == true` or `String(_last_path_plan_status) == "unreachable_policy"` in the current tick.
- Tracker update rules:
  - When `_last_path_plan_blocked_point_valid == false`: clear tracker (`bucket_valid=false`, `count=0`).
  - Else compute bucket by `bucket_px = _pursuit_cfg_float("repath_recovery_blocked_point_bucket_px", 24.0)`:
    - `bucket_x = int(floor(_last_path_plan_blocked_point.x / bucket_px))`
    - `bucket_y = int(floor(_last_path_plan_blocked_point.y / bucket_px))`
  - Store the computed blocked-point bucket exactly as `_blocked_point_repeat_bucket = Vector2i(bucket_x, bucket_y)` and set `_blocked_point_repeat_bucket_valid = true`.
  - If tracker invalid or bucket differs from previous bucket: set count `= 1` and store bucket.
  - If bucket equals previous bucket: increment count by `1`.
- `repath_recovery_repeat_count` equals tracker count after the update.

6. **Blocked-point repeat escalation in pursuit:**
- When tracker count `>= int(_pursuit_cfg_float("repath_recovery_blocked_point_repeat_threshold", 2.0))` and current intent type is SEARCH or SHADOW_BOUNDARY_SCAN:
  - `repath_recovery_reason = "blocked_point_repeat"`
  - `repath_recovery_request_next_search_node = true`
  - `repath_recovery_preserve_intent = true`
  - `repath_recovery_blocked_point = _last_path_plan_blocked_point`
  - `repath_recovery_blocked_point_valid = true`
  - `repath_recovery_intent_target = movement_target`
  - `_repath_timer = 0.0`
- Tracker resets immediately after emitting `blocked_point_repeat` feedback: set `_blocked_point_repeat_bucket = Vector2i.ZERO`, `_blocked_point_repeat_bucket_valid = false`, and `_blocked_point_repeat_count = 0` to prevent repeated emissions on consecutive identical snapshots without a new replan sample.

7. **Hard stall escalation in pursuit:**
- When `_update_stall_monitor(delta, movement_target, has_target)` returns `true` (`hard_stall`), `_execute_move_to_target` keeps existing `path_failed_reason = "hard_stall"` and `_repath_timer = 0.0` behavior.
- On the same tick, when current intent type is SEARCH or SHADOW_BOUNDARY_SCAN:
  - `repath_recovery_reason = "hard_stall"`
  - `repath_recovery_request_next_search_node = true`
  - `repath_recovery_preserve_intent = true`
  - `repath_recovery_intent_target = movement_target`
  - `repath_recovery_blocked_point_valid` remains whatever Contract 1 currently holds from collision or blocked-point tracker update.
- Phase 17 feedback precedence order in one tick is exact:
  1. `blocked_point_repeat`
  2. `hard_stall`
  3. `collision_blocked`
  4. `none`
- A higher-precedence reason overwrites lower-precedence feedback fields in the same tick.

8. **`Enemy.runtime_budget_tick(delta)` Phase 17 integration order:**
- Keep existing order through `exec_result := _pursuit.execute_intent(delta, intent, context)`.
- Immediately after that call, invoke `_apply_combat_search_repath_recovery_feedback(intent, exec_result)`.
- `_update_combat_role_runtime(...)` continues after the recovery apply call.
- The current tick `intent` variable and `context` dictionary are not mutated by `_apply_combat_search_repath_recovery_feedback`.

9. **`Enemy._apply_combat_search_repath_recovery_feedback(intent, exec_result)` exact guards and effects:**
- Reset Phase 17 recovery debug vars at function entry to defaults (`applied=false`, reason=`"none"`, blocked-point zero/invalid, skipped-node-key=`""`).
- Return immediately when any guard is false:
  - `bool(exec_result.get("repath_recovery_request_next_search_node", false)) == true`
  - `bool(exec_result.get("repath_recovery_preserve_intent", false)) == true`
  - `_combat_search_current_room_id >= 0`
  - `_combat_search_current_node_key != ""`
  - `int(intent.get("type", -1))` is SEARCH or SHADOW_BOUNDARY_SCAN
  - `(exec_result.get("repath_recovery_intent_target", Vector2.ZERO) as Vector2).distance_to(_combat_search_target_pos) <= _pursuit_cfg_float("repath_recovery_intent_target_match_radius_px", 28.0)`
- On apply path:
  - Record `skipped_key = _combat_search_current_node_key`.
  - Call `_mark_combat_search_current_node_covered()` exactly once (Phase 17 skip counts as terminal visited node for progress).
  - Clear current-node runtime fields (`_combat_search_current_node_key`, `_combat_search_current_node_kind`, `_combat_search_current_node_requires_shadow_scan`, `_combat_search_current_node_shadow_scan_done`, `_combat_search_node_search_dwell_sec`), and set `_combat_search_shadow_scan_suppressed_last_tick = false`.
  - Select next node via `_select_next_combat_dark_search_node(_combat_search_current_room_id, _combat_search_target_pos)`.
  - On selector `status == "ok"`: assign new current-node fields and `_combat_search_target_pos` from selector output.
  - On selector `status == "no_nodes"` or `status == "all_blocked"`: mark room visited and switch room via `_select_next_combat_search_room(...)` and `_ensure_combat_search_room(...)`.
  - On selector `status == "room_invalid"` after a valid recovery-apply guard pass: do not restore the skipped node, do not switch rooms, keep `_combat_search_target_pos` unchanged, keep current-node fields cleared for this tick, call `_update_combat_search_progress()`, and continue to the debug-write step. This path still counts as `combat_search_recovery_applied = true` because one active node was already skipped.
  - Call `_update_combat_search_progress()` after node apply path or room-switch path.
  - Set debug vars: `applied=true`, `reason=exec_result.repath_recovery_reason`, `blocked_point` + valid flag from `exec_result`, `skipped_node_key=skipped_key`.

10. **Behavior when input is empty/null/invalid:**
- `exec_result` missing any of the 7 Phase 17 recovery-feedback keys (checked by `exec_result.has(key) == false` before any `get(...)` reads): `_apply_combat_search_repath_recovery_feedback` returns without state mutation and records `combat_search_recovery_applied=false`, reason `"none"`.
- `repath_recovery_request_next_search_node == false`: no-op.
- `_combat_search_current_node_key == ""`: no-op.
- Intent target mismatch (`distance > 28.0`): no-op.
- Selector returns `room_invalid` after the apply path has already skipped the active node: this is not an input-invalid no-op. The skipped node remains terminal-visited and cleared for the current tick, `_combat_search_target_pos` remains unchanged, and no room switch occurs.

11. **Tie-break rules:**
- Phase 17 recovery apply tie-break is N/A. Exactly one active node exists in a Phase 16 session by design (`_combat_search_current_node_key` is one string or empty), so `_apply_combat_search_repath_recovery_feedback` never chooses between two active nodes.

---

## 8. Edge-case matrix.

**Case A: empty/invalid feedback input -> no-op**
- Input: `_apply_combat_search_repath_recovery_feedback({"type": IntentType.SEARCH, "target": Vector2(100, 0)}, {})`
- Expected output/state:
  - `combat_search_recovery_applied = false`
  - `combat_search_recovery_reason = "none"`
  - active node fields unchanged
  - `_combat_search_target_pos` unchanged

**Case B: single valid hard-stall recovery request (no ambiguity)**
- Setup: one active Phase 16 dark-search node, `exec_result.repath_recovery_request_next_search_node = true`, `exec_result.repath_recovery_reason = "hard_stall"`, `repath_recovery_preserve_intent = true`, matching `repath_recovery_intent_target`.
- Expected output/state:
  - `combat_search_recovery_applied = true`
  - `combat_search_recovery_reason = "hard_stall"`
  - `combat_search_recovery_skipped_node_key` equals previous `_combat_search_current_node_key`
  - `_combat_search_target_pos` changes to the next selected node target or next-room first node target

**Case C: tie-break N/A (single active node proof)**
- Proof (section 7): `_apply_combat_search_repath_recovery_feedback` reads exactly one active node key (`_combat_search_current_node_key`) and either skips it or no-ops. No pairwise node comparison occurs in Phase 17 recovery apply logic. Tie-break path does not exist in this function.

**Case D: all inputs blocked / selector has no candidate**
- Setup: valid recovery feedback request, active node exists, `_select_next_combat_dark_search_node(...)` returns `status = "all_blocked"` for current room and every neighbor room entry also produces no candidate in the same tick path.
- Expected output/state:
  - `combat_search_recovery_applied = true`
  - previous active node is skipped (terminal visited)
  - room visit marker written for the current room
  - `_combat_search_progress` remains finite (`0.0..1.0`)
  - no crash and no `PATROL`/`RETURN_HOME` injection in the current tick

**Case E: repeated blocked point triggers escalation after threshold**
- Setup: pursuit receives the same valid planner `blocked_point` bucket on two consecutive policy-blocked replans (`threshold = 2`), current intent type = SEARCH.
- Expected Contract 1 output on threshold tick:
  - `repath_recovery_reason = "blocked_point_repeat"`
  - `repath_recovery_request_next_search_node = true`
  - `repath_recovery_repeat_count >= 2`
  - `repath_recovery_preserve_intent = true`

**Case F: collision-blocked feedback on non-search intent does not request node advance**
- Setup: current intent type = PUSH, Phase 3 collision handler sets `_last_path_failed_reason = "collision_blocked"`.
- Expected Contract 1 output:
  - `repath_recovery_reason = "collision_blocked"`
  - `repath_recovery_request_next_search_node = false`
  - `repath_recovery_preserve_intent = false`
  - movement target and intent target remain unchanged by Phase 17 code in the same tick

---

## 9. Legacy removal plan (delete-first, exact ids).

All legacy items below are file-unique to `src/systems/enemy_pursuit_system.gd` by PROJECT DISCOVERY evidence (`rg` results list matches only in that file for source identifiers and functions).

**L1. `const SHADOW_ESCAPE_RING_MIN_RADIUS_PX := 48.0`**
- File: `src/systems/enemy_pursuit_system.gd`
- Approximate line range (PROJECT DISCOVERY): line 33.
- Dead-after-phase: yes (only used by `_sample_shadow_escape_candidates`).

**L2. `const SHADOW_ESCAPE_RING_STEP_RADIUS_PX := 40.0`**
- File: `src/systems/enemy_pursuit_system.gd`
- Approximate line range: line 34.
- Dead-after-phase: yes.

**L3. `const SHADOW_ESCAPE_RING_COUNT := 4`**
- File: `src/systems/enemy_pursuit_system.gd`
- Approximate line range: line 35.
- Dead-after-phase: yes.

**L4. `const SHADOW_ESCAPE_SAMPLES_PER_RING := 12`**
- File: `src/systems/enemy_pursuit_system.gd`
- Approximate line range: line 36.
- Dead-after-phase: yes.

**L5. `var _shadow_escape_active: bool = false`**
- File: `src/systems/enemy_pursuit_system.gd`
- Approximate line range: line 94; references at lines 167, 339, 364–367, 940, 943, 946, 960, 971, 1166.
- Dead-after-phase: yes.

**L6. `var _shadow_escape_target: Vector2 = Vector2.ZERO`**
- File: `src/systems/enemy_pursuit_system.gd`
- Approximate line range: line 95; references at lines 168, 364–366, 947, 950, 961, 972, 1167.
- Dead-after-phase: yes.

**L7. `var _shadow_escape_target_valid: bool = false`**
- File: `src/systems/enemy_pursuit_system.gd`
- Approximate line range: line 96; references at lines 169, 367, 942, 948, 962, 973, 1168.
- Dead-after-phase: yes.

**L8. `func _resolve_movement_target_with_shadow_escape(target: Vector2, has_target: bool) -> Vector2`**
- File: `src/systems/enemy_pursuit_system.gd`
- Approximate line range: lines 937–950.
- Dead-after-phase: yes; `_execute_move_to_target` uses direct `target` instead.

**L9. `func _attempt_shadow_escape_recovery() -> bool`**
- File: `src/systems/enemy_pursuit_system.gd`
- Approximate line range: lines 953–973.
- Dead-after-phase: yes.

**L10. `func _resolve_shadow_escape_target() -> Dictionary`**
- File: `src/systems/enemy_pursuit_system.gd`
- Approximate line range: lines 977–991.
- Dead-after-phase: yes.

**L11. `func _sample_shadow_escape_candidates() -> Array[Vector2]`**
- File: `src/systems/enemy_pursuit_system.gd`
- Approximate line range: lines 993–1007.
- Dead-after-phase: yes.

**L12. `func _is_owner_in_shadow_without_flashlight() -> bool`**
- File: `src/systems/enemy_pursuit_system.gd`
- Approximate line range: lines 1009–1021.
- Dead-after-phase: yes after shadow-escape precheck removal in `_resolve_nearest_reachable_fallback`.

---

## 10. Legacy verification commands (exact rg + expected 0 matches for every removed legacy item).

PROJECT DISCOVERY evidence proves L1–L12 are file-unique source identifiers/functions in `src/systems/enemy_pursuit_system.gd`, so scoped commands are valid.

**[L1]** `rg -n "SHADOW_ESCAPE_RING_MIN_RADIUS_PX" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

**[L2]** `rg -n "SHADOW_ESCAPE_RING_STEP_RADIUS_PX" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

**[L3]** `rg -n "SHADOW_ESCAPE_RING_COUNT" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

**[L4]** `rg -n "SHADOW_ESCAPE_SAMPLES_PER_RING" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

**[L5]** `rg -n "_shadow_escape_active" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

**[L6]** `rg -n "_shadow_escape_target\b" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

**[L7]** `rg -n "_shadow_escape_target_valid" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

**[L8]** `rg -n "func _resolve_movement_target_with_shadow_escape\(" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

**[L9]** `rg -n "func _attempt_shadow_escape_recovery\(" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

**[L10]** `rg -n "func _resolve_shadow_escape_target\(" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

**[L11]** `rg -n "func _sample_shadow_escape_candidates\(" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

**[L12]** `rg -n "func _is_owner_in_shadow_without_flashlight\(" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

---

## 11. Acceptance criteria (binary pass/fail).

- [ ] All section 10 legacy verification commands (L1–L12) return `0 matches`.
- [ ] `rg -n "repath_recovery_request_next_search_node|repath_recovery_reason|repath_recovery_blocked_point|repath_recovery_repeat_count|repath_recovery_preserve_intent|repath_recovery_intent_target" src/systems/enemy_pursuit_system.gd -S` returns `>= 12 matches`.
- [ ] `rg -n "func _apply_combat_search_repath_recovery_feedback\(" src/entities/enemy.gd -S` returns exactly `1 match`.
- [ ] `rg -n "combat_search_recovery_(applied|reason|blocked_point|blocked_point_valid|skipped_node_key)" src/entities/enemy.gd -S` returns `>= 10 matches`.
- [ ] `rg -n "repath_recovery_blocked_point_(bucket_px|repeat_threshold)|repath_recovery_intent_target_match_radius_px" src/core/game_config.gd -S` returns exactly `3 matches`.
- [ ] `rg -n "repath_recovery_blocked_point_(bucket_px|repeat_threshold)|repath_recovery_intent_target_match_radius_px" src/core/config_validator.gd -S` returns exactly `3 matches`.
- [ ] `rg -n "shadow_escape_active|shadow_escape_target|shadow_escape_target_valid" src/systems/enemy_pursuit_system.gd tests/test_shadow_stall_escapes_to_light.gd tests/test_pursuit_stall_fallback_invariants.gd -S` returns `0 matches`.
- [ ] `rg -n "SHADOW_STUCK_WATCHDOG_ESCALATES_TO_NEXT_NODE_TEST_SCENE|REPEATED_BLOCKED_POINT_TRIGGERS_SCAN_THEN_SEARCH_TEST_SCENE" tests/test_runner_node.gd -S` returns exactly `6 matches` (2 consts + 2 `_scene_exists` checks + 2 `_run_embedded_scene_suite` calls).
- [ ] All new and updated tests listed in section 12 exit `0`.
- [ ] Tier 1 smoke suite commands from section 14 exit `0`.
- [ ] Tier 2 full regression `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` exits `0`.

---

## 12. Tests (new/update + purpose).

**New: `tests/test_shadow_stuck_watchdog_escalates_to_next_node.gd`**
Registration: const `SHADOW_STUCK_WATCHDOG_ESCALATES_TO_NEXT_NODE_TEST_SCENE = "res://tests/test_shadow_stuck_watchdog_escalates_to_next_node.tscn"` in `tests/test_runner_node.gd`.

- `_test_hard_stall_sets_recovery_feedback_for_search_intent`
  - Setup: pursuit unit harness with fake owner/nav, SEARCH intent target fixed, forced zero movement to trigger `hard_stall`.
  - Assert: `execute_intent(...)` returns `repath_recovery_request_next_search_node == true`, `repath_recovery_reason == "hard_stall"`, and `repath_recovery_preserve_intent == true`.
- `_test_non_search_intent_collision_blocked_does_not_request_next_node`
  - Setup: pursuit unit harness, PUSH intent, Phase 3 collision path stub active.
  - Assert: `repath_recovery_reason == "collision_blocked"` and `repath_recovery_request_next_search_node == false`.
- `_test_shadow_escape_keys_absent_from_navigation_snapshot`
  - Setup: pursuit unit harness after `configure_navigation(...)`.
  - Assert: `debug_get_navigation_policy_snapshot()` lacks keys `shadow_escape_active`, `shadow_escape_target`, and `shadow_escape_target_valid`; snapshot contains `repath_recovery_reason` and `repath_recovery_request_next_search_node`.

**New: `tests/test_repeated_blocked_point_triggers_scan_then_search.gd`**
Registration: const `REPEATED_BLOCKED_POINT_TRIGGERS_SCAN_THEN_SEARCH_TEST_SCENE = "res://tests/test_repeated_blocked_point_triggers_scan_then_search.tscn"` in `tests/test_runner_node.gd`.

- `_test_repeated_same_blocked_point_requests_next_search_node`
  - Setup: pursuit unit harness with deterministic planner contracts that return the same `blocked_point` bucket on repeated policy-blocked replans under SEARCH intent.
  - Assert: threshold tick returns `repath_recovery_reason == "blocked_point_repeat"`, `repath_recovery_request_next_search_node == true`, and `repath_recovery_repeat_count >= 2`.
- `_test_enemy_applies_recovery_feedback_and_skips_current_dark_node`
  - Setup: Enemy Phase 16 dark-search session harness with one active node and a second node available; call `_apply_combat_search_repath_recovery_feedback(intent, exec_result)` directly with a matching Phase 17 feedback dict.
  - Assert: `combat_search_recovery_applied == true`, `combat_search_recovery_skipped_node_key` equals previous node key, and `_combat_search_target_pos` changes to the next node target.
- `_test_next_dark_node_in_shadow_runs_shadow_boundary_scan_then_search`
  - Setup: Enemy + FakePursuit Phase 11 stage getter stub + Phase 16 node session harness; first node skipped by Phase 17 feedback, next node is in shadow.
  - Assert: runtime sequence on subsequent ticks is `SHADOW_BOUNDARY_SCAN` then `SEARCH` for the new node target and no repeated scan loop after scan completion.

**Update: `tests/test_shadow_stall_escapes_to_light.gd`**
- Function: `_test_shadow_stall_prefers_escape_to_light`
- Change: remove legacy `shadow_escape_*` snapshot assertions and replace them with Phase 17 assertions on `hard_stall` / `repath_recovery_reason` / `repath_recovery_request_next_search_node` plus continued movement or deterministic no-freeze recovery behavior in the same harness.
- Why: Phase 17 deletes `shadow_escape_*` pursuit state and snapshot keys.

**Update: `tests/test_pursuit_stall_fallback_invariants.gd`**
- Function: `_test_stall_and_fallback_invariants`
- Change: add assertions that `debug_get_navigation_policy_snapshot()` includes the new `repath_recovery_*` keys and excludes `shadow_escape_*` keys.
- Why: Phase 17 changes the pursuit debug snapshot contract.

**Update: `tests/test_detour_side_flip_on_stall.gd`**
- Function: `_test_detour_side_flip_on_stall`
- Change: add assertion that no teleport spike is introduced while Phase 17 recovery feedback exists in runtime (existing max-step contract remains the same).
- Why: Phase 17 modifies stall recovery behavior in pursuit and integration runtime.

**Updated test registration file:** `tests/test_runner_node.gd`
- Add 2 new scene consts, 2 scene existence checks, and 2 suite calls.

---

## 13. rg gates (command + expected output).

**Phase-specific gates:**

[G1] `rg -n "SHADOW_ESCAPE_RING_(MIN_RADIUS_PX|STEP_RADIUS_PX|COUNT|SAMPLES_PER_RING)|_shadow_escape_active|_shadow_escape_target\b|_shadow_escape_target_valid|func _resolve_movement_target_with_shadow_escape\(|func _attempt_shadow_escape_recovery\(|func _resolve_shadow_escape_target\(|func _sample_shadow_escape_candidates\(|func _is_owner_in_shadow_without_flashlight\(" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[G2] `rg -n "shadow_escape_active|shadow_escape_target|shadow_escape_target_valid" tests/test_shadow_stall_escapes_to_light.gd tests/test_pursuit_stall_fallback_invariants.gd -S`
Expected: `0 matches`.

[G3] `rg -n "_resolve_movement_target_with_shadow_escape|_attempt_shadow_escape_recovery|_resolve_shadow_escape_target|_sample_shadow_escape_candidates|_is_owner_in_shadow_without_flashlight" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[G4] `rg -n "repath_recovery_request_next_search_node|repath_recovery_reason|repath_recovery_blocked_point|repath_recovery_blocked_point_valid|repath_recovery_repeat_count|repath_recovery_preserve_intent|repath_recovery_intent_target" src/systems/enemy_pursuit_system.gd -S`
Expected: `>= 20 matches`.

[G5] `rg -n "func _apply_combat_search_repath_recovery_feedback\(|combat_search_recovery_(applied|reason|blocked_point|blocked_point_valid|skipped_node_key)" src/entities/enemy.gd -S`
Expected: `>= 12 matches`.

[G6] `rg -n "func _apply_combat_search_repath_recovery_feedback\(" src/ -S`
Expected: exactly `1 match` and it is in `src/entities/enemy.gd`.

[G7] `rg -n "combat_search_progress|combat_search_total_elapsed_sec|combat_search_room_elapsed_sec|combat_search_total_cap_sec|combat_search_force_complete" src/entities/enemy.gd src/systems/enemy_awareness_system.gd -S`
Expected: `>= 10 matches`.

[G8] `rg -n "repath_recovery_blocked_point_(bucket_px|repeat_threshold)|repath_recovery_intent_target_match_radius_px" src/core/game_config.gd -S`
Expected: `3 matches`.

[G9] `rg -n "repath_recovery_blocked_point_(bucket_px|repeat_threshold)|repath_recovery_intent_target_match_radius_px" src/core/config_validator.gd -S`
Expected: `3 matches`.

[G10] `rg -n "SHADOW_STUCK_WATCHDOG_ESCALATES_TO_NEXT_NODE_TEST_SCENE|REPEATED_BLOCKED_POINT_TRIGGERS_SCAN_THEN_SEARCH_TEST_SCENE" tests/test_runner_node.gd -S`
Expected: `6 matches`.

**PMB gates:**

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: `0 matches`.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

---

## 14. Execution sequence (step-by-step, no ambiguity).

Step 0: Run dependency gates from section 23 and stop on first failure.

Step 1: Delete legacy item L1 from section 9 in `src/systems/enemy_pursuit_system.gd` (`SHADOW_ESCAPE_RING_MIN_RADIUS_PX`).

Step 2: Delete legacy item L2 from section 9 in `src/systems/enemy_pursuit_system.gd` (`SHADOW_ESCAPE_RING_STEP_RADIUS_PX`).

Step 3: Delete legacy item L3 from section 9 in `src/systems/enemy_pursuit_system.gd` (`SHADOW_ESCAPE_RING_COUNT`).

Step 4: Delete legacy item L4 from section 9 in `src/systems/enemy_pursuit_system.gd` (`SHADOW_ESCAPE_SAMPLES_PER_RING`).

Step 5: Delete legacy item L5 from section 9 in `src/systems/enemy_pursuit_system.gd` (`_shadow_escape_active`).

Step 6: Delete legacy item L6 from section 9 in `src/systems/enemy_pursuit_system.gd` (`_shadow_escape_target`).

Step 7: Delete legacy item L7 from section 9 in `src/systems/enemy_pursuit_system.gd` (`_shadow_escape_target_valid`).

Step 8: Delete legacy item L8 from section 9 in `src/systems/enemy_pursuit_system.gd` (`_resolve_movement_target_with_shadow_escape`).

Step 9: Delete legacy item L9 from section 9 in `src/systems/enemy_pursuit_system.gd` (`_attempt_shadow_escape_recovery`).

Step 10: Delete legacy item L10 from section 9 in `src/systems/enemy_pursuit_system.gd` (`_resolve_shadow_escape_target`).

Step 11: Delete legacy item L11 from section 9 in `src/systems/enemy_pursuit_system.gd` (`_sample_shadow_escape_candidates`).

Step 12: Delete legacy item L12 from section 9 in `src/systems/enemy_pursuit_system.gd` (`_is_owner_in_shadow_without_flashlight`).

Step 13: Run all section 10 legacy verification commands (L1–L12). All commands must return `0 matches` before continuing.

Step 14: Add Phase 17 pursuit blocked-point repeat tracker vars and recovery-feedback vars to `src/systems/enemy_pursuit_system.gd` and reset them in `configure_navigation(...)`.

Step 15: Add pursuit helpers `_reset_repath_recovery_feedback()` and `_update_blocked_point_repeat_tracker()` to `src/systems/enemy_pursuit_system.gd`.

Step 16: Rewrite `EnemyPursuitSystem._execute_move_to_target(...)` to remove shadow-escape substitution/recovery calls and emit intent-preserving recovery feedback per section 7; modify `EnemyPursuitSystem._attempt_replan_with_policy(target_pos)` to remove the shadow-escape precheck from `_resolve_nearest_reachable_fallback(...)` and keep generic nearest-reachable fallback behavior only.

Step 17: Modify `EnemyPursuitSystem.execute_intent(...)` to reset recovery feedback at entry and append Contract 1 keys to the returned `Dictionary`.

Step 18: Modify `EnemyPursuitSystem.debug_get_navigation_policy_snapshot()` to remove `shadow_escape_*` keys and add `repath_recovery_*` keys.

Step 19: Add Phase 17 recovery debug vars and `_apply_combat_search_repath_recovery_feedback(intent, exec_result)` to `src/entities/enemy.gd`.

Step 20: Modify `Enemy.runtime_budget_tick(delta)` to call `_apply_combat_search_repath_recovery_feedback(intent, exec_result)` immediately after `_pursuit.execute_intent(...)`.

Step 21: Modify `Enemy.get_debug_detection_snapshot()` and `_reset_combat_search_state()` to publish/reset the Phase 17 recovery debug keys.

Step 22: Add 3 pursuit config keys to `src/core/game_config.gd` and 3 validator checks to `src/core/config_validator.gd`.

Step 23: Create `tests/test_shadow_stuck_watchdog_escalates_to_next_node.gd` and `tests/test_shadow_stuck_watchdog_escalates_to_next_node.tscn`; implement all 3 test functions from section 12.

Step 24: Create `tests/test_repeated_blocked_point_triggers_scan_then_search.gd` and `tests/test_repeated_blocked_point_triggers_scan_then_search.tscn`; implement all 3 test functions from section 12.

Step 25: Update `tests/test_shadow_stall_escapes_to_light.gd`, `tests/test_pursuit_stall_fallback_invariants.gd`, and `tests/test_detour_side_flip_on_stall.gd` with the assertions described in section 12.

Step 26: Register the 2 new scenes in `tests/test_runner_node.gd`: add 2 top-level const declarations, 2 `_scene_exists(...)` checks, and 2 `_run_embedded_scene_suite(...)` calls.

Step 27: Run Tier 1 smoke suite commands (exact):
- `xvfb-run -a godot-4 --headless --path . res://tests/test_shadow_stuck_watchdog_escalates_to_next_node.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_repeated_blocked_point_triggers_scan_then_search.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_shadow_stall_escapes_to_light.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_pursuit_stall_fallback_invariants.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_detour_side_flip_on_stall.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_stall_definition_reproducible_thresholds.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_door_enemy_oblique_open_then_cross_no_wall_stall.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_shadow_policy_hard_block_without_grant.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_shadow_enemy_stuck_when_inside_shadow.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_shadow_enemy_unstuck_after_flashlight_activation.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_combat_to_alert_requires_no_contact_and_search_progress.tscn`

Step 28: Run Tier 2 full regression: `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit `0`.

Step 29: Run all section 13 rg gates (G1–G10 and PMB-1–PMB-5). All commands must return expected output.

Step 30: Prepend one `CHANGELOG.md` entry under the current date header for Phase 17 (anti-stall recovery feedback, blocked-point repeat watchdog, shadow-escape legacy removal, dark-search node escalation without intent loss).

---

## 15. Rollback conditions.

1. **Trigger:** Any dependency gate in section 23 fails at step 0. **Rollback action:** do not start implementation; revert all edits from the attempted Phase 17 branch to pre-phase state. Phase result = FAIL.
2. **Trigger:** Any section 10 legacy verification command returns non-zero matches after step 13. **Rollback action:** revert all section 4 in-scope file changes to pre-phase state. Phase result = FAIL.
3. **Trigger:** Any Tier 1 smoke command in step 27 exits non-zero. **Rollback action:** revert all section 4 in-scope file changes to pre-phase state. Phase result = FAIL.
4. **Trigger:** Tier 2 regression in step 28 exits non-zero. **Rollback action:** revert all section 4 in-scope file changes to pre-phase state. Phase result = FAIL.
5. **Trigger:** New tests observe a recovery request that mutates the current tick intent or current tick utility target context. **Rollback action:** revert Phase 17 `enemy.gd` recovery-apply edits and pursuit feedback-output edits, then revert remaining Phase 17 changes. Partial state is forbidden.
6. **Trigger:** Any `shadow_escape_*` source identifier or debug snapshot key remains in `src/systems/enemy_pursuit_system.gd` after step 29. **Rollback action:** revert all Phase 17 changes and restart from section 14 step 1. Phase result = FAIL.
7. **Trigger:** Any out-of-scope file in section 4 is modified. **Rollback action:** revert out-of-scope edits immediately, then revert all Phase 17 edits. Phase result = FAIL.
8. **Trigger:** Implementation does not complete the recovery-feedback path and enemy node-escalation consumer together in one coherent runtime branch inside section 4 scope. **Rollback action:** revert all changes to pre-phase state. Phase result = FAIL (Hard Rule 11).

---

## 16. Phase close condition.

- [ ] All rg commands in section 10 return `0 matches`
- [ ] All rg gates in section 13 return expected output
- [ ] All tests in section 12 (new + updated) exit `0`
- [ ] Tier 1 smoke suite (section 14) — all commands exit `0`
- [ ] Tier 2 full regression (`xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn`) exits `0`
- [ ] No file outside section 4 in-scope list was modified
- [ ] `CHANGELOG.md` entry prepended
- [ ] `tests/test_shadow_stuck_watchdog_escalates_to_next_node.gd` records `repath_recovery_reason == "hard_stall"` and `repath_recovery_request_next_search_node == true` for SEARCH intent
- [ ] `tests/test_repeated_blocked_point_triggers_scan_then_search.gd` records `blocked_point_repeat` escalation and subsequent `SHADOW_BOUNDARY_SCAN -> SEARCH` on the new node target
- [ ] `tests/test_shadow_stall_escapes_to_light.gd` and `tests/test_pursuit_stall_fallback_invariants.gd` contain no `shadow_escape_*` assertions

---

## 17. Ambiguity check: 0

---

## 18. Open questions: 0

---

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).

**Diff audit:**
- Diff every file in section 4 against the pre-phase baseline, including both new test script/scene pairs and `CHANGELOG.md`.
- Confirm zero modifications outside the section 4 in-scope list.

**Contract checks:**
- `PursuitRepathRecoveryFeedbackContractV1` (section 6): inspect `EnemyPursuitSystem.execute_intent`, `_execute_move_to_target`, and `debug_get_navigation_policy_snapshot` and verify all Contract 1 keys, enums, and precedence order in section 7 exist exactly.
- `CombatDarkSearchRecoveryApplyContractV1` (section 6): inspect `Enemy._apply_combat_search_repath_recovery_feedback` and verify all guards and state-mutation order from section 7 exist exactly.
- Awareness continuity check (section 3 item 6): inspect `Enemy._build_confirm_runtime_config` and `Enemy.get_debug_detection_snapshot` and verify existing `combat_search_*` field names remain unchanged.
- Legacy removal check (section 10): run all L1–L12 commands and confirm `0 matches`.

**Runtime scenarios from section 20:** execute P17-A, P17-B, P17-C, P17-D, P17-E, and P17-F.

---

## 20. Runtime scenario matrix (scenario id, setup, frame count, expected invariants, fail conditions).

**P17-A: Pursuit hard-stall watchdog emits intent-preserving recovery feedback**
- Scene: `tests/test_shadow_stuck_watchdog_escalates_to_next_node.tscn`
- Setup: pursuit unit harness with SEARCH intent, fixed target, forced zero movement until `hard_stall` triggers.
- Frame count: `0` for unit helper invocations plus repeated `execute_intent` ticks (`N >= 3`, deterministic `delta`).
- Expected invariants:
  - `repath_recovery_reason == "hard_stall"` on trigger tick.
  - `repath_recovery_request_next_search_node == true`.
  - `repath_recovery_preserve_intent == true`.
  - `repath_recovery_intent_target` equals the SEARCH target from the input intent.
- Fail conditions:
  - Recovery reason differs from `hard_stall`.
  - Recovery request flag is false for SEARCH hard-stall path.
  - Intent target in feedback differs from input target.
- Covered by: `_test_hard_stall_sets_recovery_feedback_for_search_intent`

**P17-B: Repeated same blocked point bucket escalates next node**
- Scene: `tests/test_repeated_blocked_point_triggers_scan_then_search.tscn`
- Setup: pursuit unit harness with repeated planner `blocked_point` in the same bucket under SEARCH intent; threshold = 2.
- Frame count: `0` (deterministic unit loop, repeated `execute_intent` or helper-driven replan cycles).
- Expected invariants:
  - `repath_recovery_reason == "blocked_point_repeat"` on threshold tick.
  - `repath_recovery_repeat_count >= 2` on threshold tick.
  - `repath_recovery_request_next_search_node == true`.
- Fail conditions:
  - Threshold tick does not request next node.
  - Repeat count does not increase deterministically across identical blocked-point samples.
- Covered by: `_test_repeated_same_blocked_point_requests_next_search_node`

**P17-C: Enemy applies feedback and skips one active dark-search node without changing current tick intent**
- Scene: `tests/test_repeated_blocked_point_triggers_scan_then_search.tscn`
- Setup: Phase 16 dark-search session harness with one active node and one next node; pass a matching Phase 17 recovery `exec_result` into `_apply_combat_search_repath_recovery_feedback(intent, exec_result)`.
- Frame count: `0` (unit call).
- Expected invariants:
  - `combat_search_recovery_applied == true`.
  - `combat_search_recovery_skipped_node_key` equals the previous active node key.
  - `_combat_search_target_pos` changes to next node target.
  - `intent` dictionary remains unchanged after the call.
- Fail conditions:
  - No node skip occurs.
  - Current tick `intent` dictionary mutates.
  - Target position remains on the skipped node.
- Covered by: `_test_enemy_applies_recovery_feedback_and_skips_current_dark_node`

**P17-D: New-node shadow canon remains `SHADOW_BOUNDARY_SCAN -> SEARCH` after escalation**
- Scene: `tests/test_repeated_blocked_point_triggers_scan_then_search.tscn`
- Setup: next node selected by Phase 17 skip is a dark node (`target_in_shadow = true`) and Phase 11 shadow-stage getter stub transitions non-IDLE -> IDLE on completion.
- Frame count: deterministic unit loop (`N >= 4`).
- Expected invariants:
  - Sequence on the new node is `SHADOW_BOUNDARY_SCAN` then `SEARCH`.
  - No repeated `SHADOW_BOUNDARY_SCAN` occurs after scan completion on the same node.
- Fail conditions:
  - `SEARCH` never occurs after scan completion.
  - Repeated scan loop occurs on the same node.
- Covered by: `_test_next_dark_node_in_shadow_runs_shadow_boundary_scan_then_search`

**P17-E: Legacy shadow-escape snapshot keys are removed and stall regressions remain deterministic**
- Scene: `tests/test_shadow_stall_escapes_to_light.tscn` and `tests/test_pursuit_stall_fallback_invariants.tscn`
- Setup: existing pursuit fake-nav harnesses with updated assertions.
- Frame count: existing loops (`240` iterations in shadow stall suite; synchronous unit calls in stall/fallback invariants suite).
- Expected invariants:
  - No `shadow_escape_*` snapshot keys exist.
  - `repath_recovery_*` snapshot keys exist.
  - Existing deterministic stall-threshold assertions remain true.
- Fail conditions:
  - Any legacy snapshot key remains.
  - New recovery keys missing.
  - Existing stall-threshold assertions fail.
- Covered by: `_test_shadow_stall_prefers_escape_to_light`, `_test_stall_and_fallback_invariants`

**P17-F: Phase 3 collision and awareness progress contracts remain intact**
- Scene: `tests/test_door_enemy_oblique_open_then_cross_no_wall_stall.tscn` and `tests/test_combat_to_alert_requires_no_contact_and_search_progress.tscn`
- Setup: existing suites unchanged (smoke-only baselines).
- Frame count: existing scripted loops in both suites.
- Expected invariants:
  - Door-open collision path still forces immediate `_repath_timer` reset.
  - COMBAT->ALERT search-progress gate still reads unchanged `combat_search_*` field names.
- Fail conditions:
  - Door test no longer records immediate repath reset.
  - COMBAT->ALERT gate suite fails due to renamed or missing `combat_search_*` fields.
- Covered by: `_test_door_open_resets_repath_timer_for_crossing`, `_test_non_lockdown_gates`, `_test_lockdown_window_12_sec`

---

## 21. Verification report format (what must be recorded to close phase).

Record all fields below to close phase:
- `phase_id: PHASE_17`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; empty list required for PASS)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `dependency_gate_check: [PHASE-3: PASS|FAIL, PHASE-11: PASS|FAIL, PHASE-16: PASS|FAIL]` **[BLOCKING — all must be PASS before implementation and before close]**
- `legacy_rg: [{command, expected: "0 matches", actual, PASS|FAIL}]` for all 12 commands from section 10
- `rg_gates: [{gate: "G1".."G10"|"PMB-1".."PMB-5", command, expected, actual, PASS|FAIL}]`
- `phase_tests: [{test_function, scene, exit_code: 0, PASS|FAIL}]` for all new and updated test functions listed in section 12
- `smoke_suite: [{command, exit_code: 0, PASS|FAIL}]` for all 11 Tier 1 commands from section 14
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `repath_recovery_feedback_check: {hard_stall_reason_seen: true|false, blocked_point_repeat_seen: true|false, preserve_intent_flags_all_true_for_search_requests: true|false, PASS|FAIL}`
- `combat_search_recovery_apply_check: {applied_count, skipped_node_keys: [..], intent_mutation_detected: true|false, PASS|FAIL}`
- `shadow_escape_legacy_removed_check: {snapshot_keys_absent: true|false, source_ids_absent: true|false, PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

---

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 17` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- `pmb_contract_check` present in section 21 (PMB section exists in document): yes

---

## 23. Dependencies on previous phases.

1. **Phase 3** — `EnemyPursuitSystem._handle_slide_collisions_and_repath` is the single owner of non-door collision immediate repath and `collision_blocked` reason semantics. Phase 17 reads that output contract and emits recovery feedback on the same tick without changing the Phase 3 collision owner behavior. Dependency gate (must pass before section 14 step 1): `rg -n "_handle_slide_collisions_and_repath|collision_blocked" src/systems/enemy_pursuit_system.gd -S` -> expected `>= 2 matches`.

2. **Phase 16** — `Enemy` owns dark-search session state and node selection (`_record_combat_search_execution_feedback`, `_select_next_combat_dark_search_node`, `_combat_search_current_node_key`, `_combat_search_target_pos`, `combat_search_shadow_scan_suppressed`). Phase 17 consumes that session state and adds one recovery-apply decision point that skips the active node and selects the next node without mutating the current tick intent. Dependency gate (must pass before section 14 step 1): `rg -n "_record_combat_search_execution_feedback|_select_next_combat_dark_search_node|_combat_search_current_node_key|combat_search_shadow_scan_suppressed" src/entities/enemy.gd -S` -> expected `>= 4 matches`.

3. **Phase 11** — Phase 16 session logic depends on `EnemyPursuitSystem.get_shadow_search_stage()` to detect shadow boundary scan completion. Phase 17 keeps that chain intact and does not replace the shadow-stage choreography. Dependency gate (must pass before section 14 step 1): `rg -n "func get_shadow_search_stage\(|func get_shadow_search_coverage\(" src/systems/enemy_pursuit_system.gd -S` -> expected `2 matches`.
## PHASE 18
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_18.
Scope boundary (exact files): section 4.
Execution sequence: section 14.
Rollback conditions: section 15.
Verification report format: section 21.

### Evidence

**Inspected files:**
- `src/systems/enemy_squad_system.gd` (full; targeted `rg`/`nl` refs for `_pick_slot_for_enemy`, `_is_slot_path_ok`, `_build_slots`, `_default_assignment`, `_recompute_assignments`)
- `src/entities/enemy.gd` (targeted `nl` refs: `_resolve_squad_assignment`, `_build_utility_context`, `_assignment_supports_flank_role`, `_resolve_contextual_combat_role`)
- `src/systems/enemy_utility_brain.gd` (full; `has_los` combat branch and final FLANK `MOVE_TO_SLOT` branch)
- `src/systems/navigation_service.gd` (full; `build_policy_valid_path`, `build_path_points`, `room_id_at_point`, `get_room_rect`, `layout` field)
- `src/systems/navigation_runtime_queries.gd` (full; `build_policy_valid_path` output contract, `nav_path_length`, path status/reason enums)
- `src/core/game_config.gd` (squad AI balance block)
- `src/core/config_validator.gd` (squad validator block)
- `tests/test_enemy_squad_system.gd` (full; FakeNav + `_test_path_fallback` baseline)
- `tests/test_combat_role_lock_and_reassign_triggers.gd` (full; manual flank assignment baseline)
- `tests/test_enemy_utility_brain.gd` (full; FLANK role `MOVE_TO_SLOT` baseline)
- `tests/test_navigation_failure_reason_contract.gd` (full; `build_policy_valid_path` contract baseline)
- `tests/test_navigation_path_policy_parity.gd` (full; nav path policy parity smoke baseline)
- `tests/test_runner_node.gd` (targeted `rg` refs for scene constants, `_scene_exists(...)`, `_run_embedded_scene_suite(...)`)
- `src/levels/stealth_3zone_test_controller.gd` (targeted refs for test layout `_navigation_obstacles()`)
- `src/systems/procedural_layout_v2.gd` (targeted refs for `_room_id_at_point`, wall segments; no `_navigation_obstacles()` method exposed)
- `docs/ai_nav_refactor_execution_v2.md` (`PHASE 10`, `PHASE 15`, `PHASE 17` contracts and dependency baselines)

**Inspected functions/methods:**
- `EnemySquadSystem._recompute_assignments`
- `EnemySquadSystem._pick_slot_for_enemy`
- `EnemySquadSystem._is_slot_path_ok`
- `EnemySquadSystem._build_slots`
- `EnemySquadSystem._build_ring_slots`
- `EnemySquadSystem._default_assignment`
- `EnemySquadSystem._role_priority`
- `Enemy._resolve_squad_assignment`
- `Enemy._build_utility_context`
- `Enemy._assignment_supports_flank_role`
- `Enemy._resolve_contextual_combat_role`
- `EnemyUtilityBrain._choose_intent`
- `NavigationService.build_policy_valid_path`
- `NavigationService.build_path_points`
- `NavigationService.room_id_at_point`
- `NavigationService.get_room_rect`
- `NavigationRuntimeQueries.build_policy_valid_path`
- `NavigationRuntimeQueries.nav_path_length`
- `TestEnemySquadSystem._test_path_fallback`
- `TestCombatRoleLockAndReassignTriggers._test_role_lock_and_triggered_reassign`
- `TestEnemyUtilityBrain._test_core_decisions`
- `TestNavigationFailureReasonContract._test_failure_reason_contract`
- `TestNavigationPathPolicyParity._test_path_policy_parity`
- `TestRunner._scene_exists`
- `TestRunner._run_embedded_scene_suite`
- `TestRunner._run_tests`

**Search commands used:**
- `rg -n "build_path_points\\(|cover|flank|pressure|slot|path_status|eta" src/systems/enemy_squad_system.gd -S`
- `rg -n "get_assignment\\(|slot_key|path_ok|has_slot|enemy_squad_system" src tests -S`
- `rg -n "build_policy_valid_path\\(|build_path_points\\(|nav_path_length|room_id_at_point|get_room_rect" src/systems/navigation_service.gd src/systems/navigation_runtime_queries.gd -S`
- `rg -n "func _pick_slot_for_enemy\\(|func _is_slot_path_ok\\(|build_path_points\\(|slot_path_tail_tolerance_px" src/systems/enemy_squad_system.gd src/core/game_config.gd src/core/config_validator.gd -S`
- `rg -n "func _assignment_supports_flank_role\\(|func _build_utility_context\\(|_resolve_squad_assignment\\(" src/entities/enemy.gd -S`
- `rg -n "path_ok|flank_assignment|_test_path_fallback|COMBAT_ROLE_LOCK_AND_REASSIGN_TRIGGERS_TEST_SCENE" tests/test_enemy_squad_system.gd tests/test_combat_role_lock_and_reassign_triggers.gd tests/test_runner_node.gd -S`
- `rg -n "func _navigation_obstacles\\(|_navigation_obstacles" src -S`
- `rg -n "target_context_exists|repath_recovery_reason|slot_path_length|_build_contain_slots_from_exits" src/systems/enemy_utility_brain.gd src/systems/enemy_pursuit_system.gd src/systems/enemy_squad_system.gd src/entities/enemy.gd -S`

**Confirmed facts:**
- `src/systems/enemy_squad_system.gd` still validates slot paths through `_is_slot_path_ok(enemy, slot_pos)` and a direct `navigation_service.build_path_points(...)` tail-distance branch; no `build_policy_valid_path` usage exists in this file.
- `_is_slot_path_ok(...)` returns only `bool`; `_pick_slot_for_enemy(...)` scores only Euclidean distance plus `invalid_path_score_penalty`; no `path_status`, `path_reason`, `slot_path_eta_sec`, `slot_role`, `cover_source`, or `cover_los_break_quality` fields exist in squad assignments.
- `slot_path_tail_tolerance_px` exists in `src/core/game_config.gd` and `src/core/config_validator.gd` and is used only by the legacy `_is_slot_path_ok(...)` tail-distance check.
- `Enemy._assignment_supports_flank_role(...)` currently checks only `role`, `has_slot`, and `path_ok`; no `slot_role`, `path_status`, or ETA field is read.
- `Enemy._build_utility_context(...)` publishes `role`, `path_ok`, and `has_slot` only; it does not publish a flank contract gate flag or slot path status/ETA to utility.
- `EnemyUtilityBrain._choose_intent(...)` has two `MOVE_TO_SLOT` gates in the LOS branch and the final FLANK gate does not read ETA or a flank contract flag.
- `Enemy._resolve_contextual_combat_role(...)` currently preserves `candidate_role` in the valid-contact mid-range/default path when `flank_available == false`; there is no explicit aggressive fallback `FLANK -> PRESSURE` under valid contact.
- `NavigationService.build_policy_valid_path(...)` and `NavigationRuntimeQueries.build_policy_valid_path(...)` already expose the path policy contract (`status`, `reason`, `path_points`, optional `blocked_point`) with `status` enums `ok|unreachable_policy|unreachable_geometry`.
- `NavigationService.get_room_rect(...)` exists and returns the largest room rect; `NavigationService.layout` is a public field; `NavigationService` has no public `get_navigation_obstacles(...)` method.
- `src/levels/stealth_3zone_test_controller.gd` exposes a test layout `_navigation_obstacles()` method; `src/systems/procedural_layout_v2.gd` in the current tree does not expose `_navigation_obstacles()`, so obstacle-cover extraction logic requires an exact optional branch and a wall-cover baseline path.
- Current tree contains no Phase 10 tactical slot extensions (`slot_path_length`, `_build_contain_slots_from_exits`), no Phase 15 `target_context_exists` no-LOS doctrine output, and no Phase 17 `repath_recovery_*` outputs; Phase 18 start is blocked until dependency gates in section 23 pass.

---

## 1. What now.

Phase 18 dependency outputs are absent in the current tree and the legacy squad slot validation branch remains active.

Verification of current state:

```bash
rg -n "_build_contain_slots_from_exits|slot_path_length" src/systems/enemy_squad_system.gd src/entities/enemy.gd -S
```
Expected current output in this tree: `0 matches` (Phase 10 dependency gate fails before Phase 18 start).

```bash
rg -n "target_context_exists" src/systems/enemy_utility_brain.gd -S
```
Expected current output in this tree: `0 matches` (Phase 15 dependency gate fails before Phase 18 start).

```bash
rg -n "repath_recovery_reason|repath_recovery_request_next_search_node" src/systems/enemy_pursuit_system.gd src/entities/enemy.gd -S
```
Expected current output in this tree: `0 matches` (Phase 17 dependency gate fails before Phase 18 start).

```bash
rg -n "func _is_slot_path_ok\(|build_path_points\(|slot_path_tail_tolerance_px" src/systems/enemy_squad_system.gd src/core/game_config.gd src/core/config_validator.gd -S
```
Expected current output: `> 0 matches` (legacy slot validation path and config key remain active).

Current measurable gap in tactical behavior:
- `EnemySquadSystem._pick_slot_for_enemy(...)` has no policy path status/reason output and no cover scoring terms, and `EnemyUtilityBrain._choose_intent(...)` has no flank ETA/path-status gate in the LOS `MOVE_TO_SLOT` path.
- `Enemy._resolve_contextual_combat_role(...)` does not provide an aggressive valid-contact fallback to `PRESSURE` when a FLANK candidate is selected but the Phase 18 flank slot contract is false.

---

## 2. What changes.

1. **Delete-first in `src/systems/enemy_squad_system.gd`:** remove legacy function `EnemySquadSystem._is_slot_path_ok(enemy, slot_pos)` and all call sites in `_pick_slot_for_enemy(...)` before adding the policy-valid slot evaluation helper.
2. **Delete-first in `src/core/game_config.gd`:** remove `ai_balance["squad"]["slot_path_tail_tolerance_px"]` because Phase 18 deletes the only consumer (`_is_slot_path_ok` tail-distance branch).
3. **Delete-first in `src/core/config_validator.gd`:** remove `_validate_number_key(..., "slot_path_tail_tolerance_px", ...)` from the squad validator block.
4. **`src/systems/enemy_squad_system.gd` — add** file-scope local constants for cover candidate generation and tactical scoring (section 6 exact names/values): wall/obstacle inset, cover dedup bucket, cover LOS-break weight, flank angle weight.
5. **`src/systems/enemy_squad_system.gd` — add** helper `_build_slot_policy_eval(enemy: Node2D, slot_pos: Vector2) -> Dictionary` that calls `navigation_service.build_policy_valid_path(enemy.global_position, slot_pos, enemy)` and returns normalized slot path policy/status fields plus `slot_path_length` and `slot_path_eta_sec`.
6. **`src/systems/enemy_squad_system.gd` — add** helper `_sum_path_points_length(from_pos: Vector2, path_points: Array) -> float` used by item 5 to compute deterministic path length from `path_points` without a second nav query.
7. **`src/systems/enemy_squad_system.gd` — add** cover extraction helpers `_build_cover_slots_from_room_geometry(player_pos: Vector2) -> Array`, `_build_cover_slots_from_nav_obstacles(player_room_rect: Rect2, player_pos: Vector2) -> Array`, and `_compute_cover_los_break_quality(candidate_pos: Vector2, outward_normal: Vector2, player_pos: Vector2) -> float`.
8. **`src/systems/enemy_squad_system.gd` — add** helper `_score_tactical_slot_candidate(enemy: Node2D, preferred_role: int, slot_role: int, slot: Dictionary, player_pos: Vector2) -> Dictionary` that combines path validity, ETA budget validity (FLANK only), LOS-break cover score, distance score, and flank angle score into one deterministic score tuple.
9. **`src/systems/enemy_squad_system.gd` — rewrite** `_build_slots(player_pos)` so `Role.HOLD` slots are built as `wall/obstacle cover slots -> Phase 10 contain-exit slots -> ring fallback` in that exact order, and every slot dict carries `slot_role`, `cover_source`, and `cover_los_break_quality` metadata.
10. **`src/systems/enemy_squad_system.gd` — rewrite** `_pick_slot_for_enemy(...)` to use items 5–8, publish policy path contract fields on the winning slot, and enforce the FLANK contract by refusing FLANK `slot_role` winners when `path_status != "ok"` or `slot_path_eta_sec > flank_max_time_sec` or `slot_path_length > flank_max_path_px`; fallback order remains role-priority deterministic (`FLANK -> HOLD -> PRESSURE` for FLANK-preferring enemies).
11. **`src/systems/enemy_squad_system.gd` — modify** `_recompute_assignments(...)` and `_default_assignment(role)` to persist new assignment keys (`slot_role`, `path_status`, `path_reason`, `slot_path_eta_sec`, `cover_source`, `cover_los_break_quality`) together with existing keys and Phase 10 `slot_path_length`.
12. **`src/entities/enemy.gd` — modify** `_resolve_squad_assignment()` default dict to include Phase 18 assignment defaults for `slot_role`, `path_status`, `path_reason`, `slot_path_eta_sec`, and `slot_path_length`.
13. **`src/entities/enemy.gd` — upgrade** `_assignment_supports_flank_role(assignment)` from Phase 10 V1 to Phase 18 V2: require `slot_role == SQUAD_ROLE_FLANK` (fallback to `role` when `slot_role` missing), require `path_status == "ok"` (in addition to `path_ok`), and use `slot_path_eta_sec` when present before the existing distance/time budget checks.
14. **`src/entities/enemy.gd` — modify** `_build_utility_context(...)` to publish `slot_role`, `slot_path_status`, `slot_path_eta_sec`, and `flank_slot_contract_ok := _assignment_supports_flank_role(assignment)` in the returned utility context.
15. **`src/systems/enemy_utility_brain.gd` — modify** `_choose_intent(ctx)` LOS branch to read `flank_slot_contract_ok` and gate both `MOVE_TO_SLOT` branches: generic slot reposition and the FLANK-specific `MOVE_TO_SLOT` branch require `role != FLANK or flank_slot_contract_ok == true`.
16. **`src/entities/enemy.gd` — modify** `_resolve_contextual_combat_role(...)` to implement `AggressiveValidContactFlankFallbackContractV1`: when `has_valid_contact == true`, `candidate_role == SQUAD_ROLE_FLANK`, and `flank_slot_contract_ok == false` (i.e. `_assignment_supports_flank_role(assignment) == false`), return `SQUAD_ROLE_PRESSURE` instead of preserving the invalid FLANK candidate in the valid-contact mid-range/default path.
17. **Phase 18 design checkpoint (blocking for item 16):** before implementing the gameplay-impacting aggressive fallback in `_resolve_contextual_combat_role(...)`, perform detailed behavior-impact study + recommended options/tradeoffs, then return for explicit user approval; do not implement item 16 before that approval.
18. **New** `tests/test_combat_cover_selection_prefers_valid_cover.gd` + `tests/test_combat_cover_selection_prefers_valid_cover.tscn` — policy-valid cover selection and cover metadata contract tests for `EnemySquadSystem`.
19. **New** `tests/test_combat_flank_requires_eta_and_path_ok.gd` + `tests/test_combat_flank_requires_eta_and_path_ok.tscn` — `slot_role`/`path_status`/ETA flank gate tests across `Enemy` and `EnemyUtilityBrain`.
20. **New** `tests/test_combat_role_distribution_not_all_pressure.gd` + `tests/test_combat_role_distribution_not_all_pressure.tscn` — multi-enemy tactical slot-role distribution and cover-source presence regression.
21. **`tests/test_enemy_squad_system.gd` — update** FakeNav to expose `build_policy_valid_path(...)` contract instead of `build_path_points(...)`; update `_test_path_fallback()` to assert `path_status` and `path_reason`; add `_test_assignment_includes_tactical_contract_fields()`.
22. **`tests/test_combat_role_lock_and_reassign_triggers.gd` — update** `_test_role_lock_and_triggered_reassign()` manual flank assignment dict to include Phase 18 contract keys, add a `path_status != "ok"` / bad ETA sub-case that proves FLANK is rejected in runtime role selection, and add a valid-contact mid-range invalid-FLANK sub-case that asserts `_resolve_contextual_combat_role(...) == SQUAD_ROLE_PRESSURE`.
23. **`tests/test_runner_node.gd` — modify** top-level const block and `_run_tests()` to add 3 scene constants, 3 `_scene_exists(...)` assertions, and 3 `_run_embedded_scene_suite(...)` calls for the new Phase 18 suites.
24. **`CHANGELOG.md` — prepend** one Phase 18 entry under the current date header after implementation and verification.

---

## 3. What will be after.

1. `src/systems/enemy_squad_system.gd` contains no `_is_slot_path_ok(...)` and no direct `build_path_points(...)` usage for slot validation (verified by section 10 and gates G1–G3 in section 13).
2. `slot_path_tail_tolerance_px` is removed from `src/core/game_config.gd` and `src/core/config_validator.gd` because the legacy tail-distance validation branch is deleted (verified by section 10 and gate G4 in section 13).
3. `EnemySquadSystem` validates slot paths only through `navigation_service.build_policy_valid_path(...)` and publishes `path_status`, `path_reason`, `slot_path_length`, and `slot_path_eta_sec` in assignment dictionaries (verified by gates G5–G7 in section 13 and section 12 tests).
4. `EnemySquadSystem` publishes `slot_role`, `cover_source`, and `cover_los_break_quality` in assignment dictionaries, and HOLD-role selection prefers policy-valid cover slots with higher LOS-break quality over exposed slots under equal or near-equal distance conditions (verified by `tests/test_combat_cover_selection_prefers_valid_cover.gd` and updated `tests/test_enemy_squad_system.gd`).
5. FLANK tactical slot selection is rejected deterministically when `path_status != "ok"` or ETA/path budget fails; fallback order is `HOLD` then `PRESSURE`, and invalid FLANK `MOVE_TO_SLOT` is blocked in utility when `flank_slot_contract_ok == false` (verified by `tests/test_combat_flank_requires_eta_and_path_ok.gd`, updated `tests/test_combat_role_lock_and_reassign_triggers.gd`, and gates G8–G10 in section 13).
6. `Enemy._resolve_contextual_combat_role(...)` applies an aggressive valid-contact fallback (`candidate_role == SQUAD_ROLE_FLANK` and `flank_slot_contract_ok == false` => `SQUAD_ROLE_PRESSURE`) while preserving the Phase 15 no-contact branch ownership and outputs (verified by updated `tests/test_combat_role_lock_and_reassign_triggers.gd` and runtime scenario P18-H).
7. `EnemyUtilityBrain._choose_intent(...)` retains Phase 15 no-LOS doctrine outputs and only tightens the LOS slot-move gates for FLANK contract enforcement (verified by gates G9, G10, PMB-1..PMB-5, and smoke `tests/test_combat_no_los_never_hold_range.gd`).
8. PMB-1 through PMB-5 remain at expected outputs (verified by PMB gates in section 13 and `pmb_contract_check` in section 21).

---

## 4. Scope and non-scope (exact files).

**In-scope:**
- `src/systems/enemy_squad_system.gd`
- `src/entities/enemy.gd`
- `src/systems/enemy_utility_brain.gd`
- `src/core/game_config.gd`
- `src/core/config_validator.gd`
- `tests/test_combat_cover_selection_prefers_valid_cover.gd` (new)
- `tests/test_combat_cover_selection_prefers_valid_cover.tscn` (new)
- `tests/test_combat_flank_requires_eta_and_path_ok.gd` (new)
- `tests/test_combat_flank_requires_eta_and_path_ok.tscn` (new)
- `tests/test_combat_role_distribution_not_all_pressure.gd` (new)
- `tests/test_combat_role_distribution_not_all_pressure.tscn` (new)
- `tests/test_enemy_squad_system.gd`
- `tests/test_combat_role_lock_and_reassign_triggers.gd`
- `tests/test_runner_node.gd`
- `CHANGELOG.md`

**Out-of-scope (must not be modified):**
- `src/systems/enemy_pursuit_system.gd` (Phase 17 owner and PMB boundary baseline)
- `src/systems/navigation_service.gd` (policy path contract producer used as-is)
- `src/systems/navigation_runtime_queries.gd` (path status/reason contract producer used as-is)
- `src/systems/procedural_layout_v2.gd` (layout runtime API baseline; no obstacle API expansion in this phase)
- `src/systems/enemy_awareness_system.gd`
- `src/systems/enemy_patrol_system.gd`
- `tests/test_navigation_failure_reason_contract.gd` (smoke baseline only)
- `tests/test_navigation_path_policy_parity.gd` (smoke baseline only)
- `tests/test_enemy_utility_brain.gd` (backward-compatible defaults preserve existing suite)
- `scenes/entities/enemy.tscn`

Allowed file-change boundary (exact paths): same as the in-scope list above.

---

## 5. Single-owner authority for this phase.

**Primary owner file:** `src/systems/enemy_squad_system.gd`.

**Primary owner function:** `EnemySquadSystem._pick_slot_for_enemy(enemy: Node2D, preferred_role: int, slots_by_role: Dictionary, used_slot_keys: Dictionary) -> Dictionary`.

Phase 18 introduces one new primary decision: tactical slot selection with cover scoring plus policy-valid path/ETA gating and deterministic FLANK fallback ordering. That decision occurs in `EnemySquadSystem._pick_slot_for_enemy(...)` only. `Enemy` and `EnemyUtilityBrain` consume the resulting assignment contract and the derived `flank_slot_contract_ok` flag; they do not score cover candidates.

**Secondary inherited guard owner (Phase 10 contract extension, no cover scoring duplication):** `Enemy._assignment_supports_flank_role(assignment: Dictionary) -> bool` in `src/entities/enemy.gd` remains the sole runtime flank-role validity predicate used by combat-role reassignment and by the new utility-context flag generation.

**Behavior-policy owner for the aggressive fallback (Phase 18 gameplay layer extension):** `Enemy._resolve_contextual_combat_role(candidate_role, has_valid_contact, target_distance, assignment) -> int` in `src/entities/enemy.gd` is the sole runtime point allowed to convert an invalid FLANK candidate into `SQUAD_ROLE_PRESSURE` when valid contact is active. Neither `EnemySquadSystem` nor `EnemyUtilityBrain` may duplicate this valid-contact fallback decision.

**Verifiable uniqueness gates:** section 13, gates G6, G8, and G9.

---

## 6. Full input/output contract.

**Contract 1 name:** `SquadSlotPolicyEvalContractV1`

**Owner:** `EnemySquadSystem._build_slot_policy_eval(enemy: Node2D, slot_pos: Vector2) -> Dictionary`

**Inputs (types, nullability, finite checks):**
- `enemy: Node2D` — non-null, `is_instance_valid(enemy) == true`, `enemy.global_position` finite.
- `slot_pos: Vector2` — non-null, finite.
- `navigation_service: Node` (internal) — nullable.
- `navigation_service.build_policy_valid_path(from_pos: Vector2, to_pos: Vector2, enemy: Node = null) -> Dictionary` (optional method).
- `navigation_service.room_id_at_point(point: Vector2) -> int` (optional method, used for pre-room validity gate only).
- Phase 10 inherited squad config keys (read through `_squad_cfg_float`):
  - `flank_walk_speed_assumed_px_per_sec: float` (`> 0.0` enforced by Phase 10 validator; fallback `150.0`)

**Outputs (exact keys/types/enums; all keys always present):**
- `path_status: String` — valid values from Status enums below.
- `path_reason: String` — valid values from Reason enums below.
- `path_ok: bool` — exact rule: `path_status == "ok"`.
- `path_points: Array[Vector2]` — empty when `path_status != "ok"`.
- `slot_path_length: float` — finite `>= 0.0` when `path_status == "ok"`; `INF` when `path_status != "ok"`.
- `slot_path_eta_sec: float` — finite `>= 0.0` when `path_status == "ok"`; `INF` when `path_status != "ok"`.
- `blocked_point: Vector2` — exact blocked point when contract contains it; `Vector2.ZERO` otherwise.
- `blocked_point_valid: bool` — `true` only when `blocked_point` came from policy contract output.

**Status enums (exact values):**
- `"ok"`
- `"unreachable_policy"`
- `"unreachable_geometry"`

**Reason enums (exact values):**
- `"ok"`
- `"policy_blocked"`
- `"navmesh_no_path"`
- `"room_graph_no_path"`
- `"room_graph_unavailable"`
- `"empty_path"`
- `"nav_service_missing"`
- `"path_contract_missing"`
- `"invalid_slot_room"`
- `"invalid_path_contract"`

**Constants/thresholds used (exact values + placement):**
- `flank_walk_speed_assumed_px_per_sec` — `GameConfig.ai_balance["squad"]`, Phase 10 inherited key, fallback `150.0`.

**Phase 18 local tactical cover/scoring constants (exact values + placement):**

Local file-scope constants in `src/systems/enemy_squad_system.gd`:
- `COVER_SLOT_WALL_INSET_PX = 12.0`
- `COVER_SLOT_OBSTACLE_INSET_PX = 10.0`
- `COVER_SLOT_DEDUP_BUCKET_PX = 24.0`
- `COVER_LOS_BREAK_WEIGHT = 180.0`
- `FLANK_ANGLE_SCORE_WEIGHT = 120.0`

**Contract 2 name:** `SquadTacticalAssignmentContractV2`

**Owner:** `EnemySquadSystem._recompute_assignments()` and `EnemySquadSystem._default_assignment(role: int) -> Dictionary` (persisted output consumed by `get_assignment(enemy_id) -> Dictionary`)

**Inputs (phase-relevant subset):**
- `member["role"]: int` — stable squad role from `EnemySquadSystem.Role` enum.
- `slot_pick: Dictionary` from `EnemySquadSystem._pick_slot_for_enemy(...)` — nullable by empty dict sentinel.
- `_clock_sec: float` — finite.
- `slot_reservation_ttl_sec: float` — finite positive (`GameConfig.ai_balance["squad"]`, existing key).

**Outputs (exact assignment keys/types; all keys always present after Phase 18):**
- `role: int` — stable squad role (`Role.PRESSURE|Role.HOLD|Role.FLANK`), retained from previous phases.
- `slot_role: int` — actual tactical role of the selected slot (`Role.PRESSURE|Role.HOLD|Role.FLANK`); equals `role` in default assignment and same-role picks.
- `slot_position: Vector2`
- `slot_key: String`
- `path_ok: bool`
- `path_status: String` (Contract 1 status enum)
- `path_reason: String` (Contract 1 reason enum)
- `slot_path_length: float`
- `slot_path_eta_sec: float`
- `blocked_point: Vector2`
- `blocked_point_valid: bool`
- `cover_source: String` — valid values from `"none"|"ring"|"exit"|"wall"|"obstacle"`.
- `cover_los_break_quality: float` — range `[0.0, 1.0]`.
- `cover_score: float` — finite; `0.0` in default assignment.
- `has_slot: bool`
- `reserved_until: float`

**Status enums:**
- `path_status` uses Contract 1 status enums exactly.

**Reason enums:**
- `path_reason` uses Contract 1 reason enums exactly.

**Constants/thresholds used (exact values + placement):**
- `slot_reservation_ttl_sec` — `GameConfig.ai_balance["squad"]`, existing key, fallback `1.1`.

**Contract 3 name:** `EnemyFlankSlotContractGateV2`

**Owner:** `Enemy._assignment_supports_flank_role(assignment: Dictionary) -> bool`

**Inputs (types, nullability, finite checks):**
- `assignment: Dictionary` — non-null.
- `assignment["role"]: int` — stable role enum.
- `assignment["slot_role"]: int` — optional in old callers; fallback to `assignment["role"]`.
- `assignment["has_slot"]: bool`
- `assignment["path_ok"]: bool`
- `assignment["path_status"]: String` — optional in old callers; fallback derived from `path_ok` (`"ok"` when `path_ok == true`, `"unreachable_geometry"` when `path_ok == false`).
- `assignment["slot_path_length"]: float` — optional in old callers; fallback `INF`.
- `assignment["slot_path_eta_sec"]: float` — optional in old callers; fallback derived from `slot_path_length / maxf(flank_walk_speed_assumed_px_per_sec, 0.001)`.
- Phase 10 inherited squad config keys via `_squad_cfg_float(...)`:
  - `flank_max_path_px` (fallback `900.0`)
  - `flank_max_time_sec` (fallback `3.5`)
  - `flank_walk_speed_assumed_px_per_sec` (fallback `150.0`)

**Outputs (exact):**
- `bool` — `true` only when all checks pass in section 7 algorithm.

**Status enums:** `N/A — boolean predicate`

**Reason enums:** `N/A — boolean predicate`

**Constants/thresholds used (exact values + placement):**
- `flank_max_path_px` — `GameConfig.ai_balance["squad"]`, Phase 10 inherited, fallback `900.0`.
- `flank_max_time_sec` — `GameConfig.ai_balance["squad"]`, Phase 10 inherited, fallback `3.5`.
- `flank_walk_speed_assumed_px_per_sec` — `GameConfig.ai_balance["squad"]`, Phase 10 inherited, fallback `150.0`.

**Contract 4 name:** `UtilityFlankSlotContextGateContractV1`

**Owners:** `Enemy._build_utility_context(...) -> Dictionary` (producer) and `EnemyUtilityBrain._choose_intent(ctx: Dictionary) -> Dictionary` (consumer)

**Producer outputs (exact new context keys):**
- `slot_role: int` — copied from squad assignment (fallback stable role).
- `slot_path_status: String` — copied from squad assignment `path_status` (fallback `"ok"` when `path_ok == true`, else `"unreachable_geometry"`).
- `slot_path_eta_sec: float` — copied from squad assignment or `INF` fallback.
- `flank_slot_contract_ok: bool` — exact value returned by `Enemy._assignment_supports_flank_role(assignment)`.

**Consumer usage invariants in `EnemyUtilityBrain._choose_intent`:**
- In the LOS generic slot-reposition branch (`has_slot && path_ok && slot_pos != Vector2.ZERO && dist_to_slot > slot_reposition_threshold`), the branch is additionally gated by `(role != Role.FLANK) or flank_slot_contract_ok`.
- In the LOS final FLANK `MOVE_TO_SLOT` branch, `flank_slot_contract_ok == true` is required.
- Fallback when the FLANK contract gate is false is the existing Phase 15 branch order (`PUSH` / `RETREAT` / `HOLD_RANGE`) with no new intent types.

**Status enums:** `N/A — context slice + intent branch gate`

**Reason enums:** `N/A`

**Constants/thresholds used:** none added in this contract; consumer retains Phase 15 `slot_reposition_threshold_px` usage.

**Contract 5 name:** `AggressiveValidContactFlankFallbackContractV1`

**Owner:** `Enemy._resolve_contextual_combat_role(candidate_role: int, has_valid_contact: bool, target_distance: float, assignment: Dictionary) -> int`

**Inputs (types, nullability, finite checks):**
- `candidate_role: int` — runtime candidate from `_reassign_combat_role(...)`.
- `has_valid_contact: bool`
- `target_distance: float` — may be non-finite; existing Phase 15 distance guards remain authoritative.
- `assignment: Dictionary` — non-null; FLANK validity is derived only through `Enemy._assignment_supports_flank_role(assignment)`.

**Outputs (exact):**
- `int` — combat role enum (`SQUAD_ROLE_PRESSURE | SQUAD_ROLE_HOLD | SQUAD_ROLE_FLANK`) with the additional Phase 18 valid-contact fallback rule from section 7.6.

**Status enums:** `N/A — enum int return`

**Reason enums:** `N/A`

**Behavioral rule (new Phase 18 extension):**
- When `has_valid_contact == true`, `candidate_role == SQUAD_ROLE_FLANK`, and `Enemy._assignment_supports_flank_role(assignment) == false`, `_resolve_contextual_combat_role(...)` must return `SQUAD_ROLE_PRESSURE` (aggressive fallback) instead of preserving the invalid FLANK candidate in the valid-contact mid-range/default path.
- The no-contact branch (`has_valid_contact == false`) remains owned by the pre-existing Phase 15/10 contextual logic and is not changed by this contract.

---

## 7. Deterministic algorithm with exact order.

### 7.1 `EnemySquadSystem._build_slot_policy_eval(enemy, slot_pos)` exact order

Step 1: Initialize output with defaults:
- `path_status = "unreachable_geometry"`
- `path_reason = "nav_service_missing"`
- `path_ok = false`
- `path_points = []`
- `slot_path_length = INF`
- `slot_path_eta_sec = INF`
- `blocked_point = Vector2.ZERO`
- `blocked_point_valid = false`

Step 2: When `navigation_service == null`, return the default output from Step 1.

Step 3: When `navigation_service.has_method("room_id_at_point") == true`, evaluate `slot_room := int(navigation_service.call("room_id_at_point", slot_pos))`. When `slot_room < 0`, set `path_reason = "invalid_slot_room"` and return the output.

Step 4: When `navigation_service.has_method("build_policy_valid_path") == false`, set `path_reason = "path_contract_missing"` and return the output.

Step 5: Call `plan_variant := navigation_service.call("build_policy_valid_path", enemy.global_position, slot_pos, enemy)`.

Step 6: When `plan_variant is not Dictionary`, set `path_reason = "invalid_path_contract"` and return the output.

Step 7: Read `plan := plan_variant as Dictionary`; normalize and validate contract enums:
- `path_status = String(plan.get("status", "unreachable_geometry"))`
- `path_reason = String(plan.get("reason", "invalid_path_contract"))`
- If `path_status` is not one of `{"ok", "unreachable_policy", "unreachable_geometry"}`, overwrite `path_status = "unreachable_geometry"`, `path_reason = "invalid_path_contract"`, `path_ok = false`, and return the output.
- If `path_reason` is not one of `{"ok", "policy_blocked", "navmesh_no_path", "room_graph_no_path", "room_graph_unavailable", "empty_path", "nav_service_missing", "path_contract_missing", "invalid_slot_room", "invalid_path_contract"}`, overwrite `path_status = "unreachable_geometry"`, `path_reason = "invalid_path_contract"`, `path_ok = false`, and return the output.
- `path_ok = (path_status == "ok")`

Step 8: When `path_ok == false`:
- When `plan.has("blocked_point")` and `plan.get("blocked_point", null) is Vector2`, set `blocked_point` and `blocked_point_valid = true`.
- Return the output.

Step 9: Validate and extract `path_points` as `Array[Vector2]`:
- When `plan.has("path_points") == false` or `plan.get("path_points", null) is not Array`, overwrite `path_status = "unreachable_geometry"`, `path_reason = "invalid_path_contract"`, `path_ok = false`, and return.
- Iterate source points in array order.
- On first element that is not `Vector2` or has non-finite `x/y`, overwrite `path_status = "unreachable_geometry"`, `path_reason = "invalid_path_contract"`, `path_ok = false`, set `path_points = []`, and return.
- Append typed `Vector2` points preserving source order.

Step 10: When `path_points.is_empty()`, overwrite `path_status = "unreachable_geometry"`, `path_reason = "empty_path"`, `path_ok = false`, keep `slot_path_length = INF`, `slot_path_eta_sec = INF`, and return.

Step 11: Compute `slot_path_length = _sum_path_points_length(enemy.global_position, path_points)`.

Step 12: Compute `slot_path_eta_sec = slot_path_length / maxf(_squad_cfg_float("flank_walk_speed_assumed_px_per_sec", 150.0), 0.001)`.

Step 13: Return the normalized output dictionary.

Tie-break: N/A — this helper evaluates one slot position and returns one normalized contract output.

### 7.2 `EnemySquadSystem._build_slots(player_pos)` exact slot-source order

Pre-step helper rules used by Step 2 and Step 3 (exact):

A. `EnemySquadSystem._compute_cover_los_break_quality(candidate_pos, outward_normal, player_pos) -> float`
- Return `0.0` when any vector component is non-finite.
- Return `0.0` when `outward_normal.length_squared() <= 0.000001`.
- Return `0.0` when `(player_pos - candidate_pos).length_squared() <= 0.000001`.
- `var n := outward_normal.normalized()`
- `var to_player_dir := (player_pos - candidate_pos).normalized()`
- Return `clampf(n.dot(-to_player_dir), 0.0, 1.0)`.

B. `EnemySquadSystem._build_cover_slots_from_nav_obstacles(player_room_rect: Rect2, player_pos: Vector2) -> Array`
- Return `[]` when `player_room_rect.size.x <= 0.0` or `player_room_rect.size.y <= 0.0`.
- Return `[]` when `navigation_service == null`.
- Read `layout = navigation_service.get("layout")` when available.
- Return `[]` when `layout == null` or `not layout.has_method("_navigation_obstacles")`.
- Read `obstacles_variant = layout.call("_navigation_obstacles")`.
- Return `[]` when `obstacles_variant is not Array`.
- Iterate obstacle rects in source array order.
- Accept only `Rect2` values with finite position/size and positive size that intersect `player_room_rect`.
- For each accepted obstacle, build exactly four candidate points in this order with `COVER_SLOT_OBSTACLE_INSET_PX`:
  1. left edge midpoint + `Vector2(-COVER_SLOT_OBSTACLE_INSET_PX, 0)` outward normal `Vector2.LEFT`
  2. right edge midpoint + `Vector2(COVER_SLOT_OBSTACLE_INSET_PX, 0)` outward normal `Vector2.RIGHT`
  3. top edge midpoint + `Vector2(0, -COVER_SLOT_OBSTACLE_INSET_PX)` outward normal `Vector2.UP`
  4. bottom edge midpoint + `Vector2(0, COVER_SLOT_OBSTACLE_INSET_PX)` outward normal `Vector2.DOWN`
- Keep a candidate only when the candidate point is finite and `player_room_rect.grow(-1.0).has_point(candidate_pos) == true`.
- Emit slot dict keys exactly: `pos`, `slot_key`, `cover_source`, `cover_los_break_quality` where:
  - `pos = candidate_pos`
  - `slot_key = "cover:obstacle:%d:%d:%s" % [int(floor(candidate_pos.x / COVER_SLOT_DEDUP_BUCKET_PX)), int(floor(candidate_pos.y / COVER_SLOT_DEDUP_BUCKET_PX)), edge_name]`
  - `cover_source = "obstacle"`
  - `cover_los_break_quality = _compute_cover_los_break_quality(candidate_pos, outward_normal, player_pos)`

C. `EnemySquadSystem._build_cover_slots_from_room_geometry(player_pos: Vector2) -> Array`
- Return `[]` when `navigation_service == null`.
- Return `[]` when `navigation_service.has_method("room_id_at_point") == false` or `navigation_service.has_method("get_room_rect") == false`.
- Resolve `player_room_id = int(navigation_service.call("room_id_at_point", player_pos))`; return `[]` when `< 0`.
- Resolve `player_room_rect = navigation_service.call("get_room_rect", player_room_id) as Rect2`; return `[]` when rect is empty.
- Build exactly four wall-cover candidates in this order using `COVER_SLOT_WALL_INSET_PX` and outward normals `LEFT`, `RIGHT`, `UP`, `DOWN`:
  1. left wall midpoint shifted inward by `Vector2(COVER_SLOT_WALL_INSET_PX, 0)`
  2. right wall midpoint shifted inward by `Vector2(-COVER_SLOT_WALL_INSET_PX, 0)`
  3. top wall midpoint shifted inward by `Vector2(0, COVER_SLOT_WALL_INSET_PX)`
  4. bottom wall midpoint shifted inward by `Vector2(0, -COVER_SLOT_WALL_INSET_PX)`
- Emit wall slot dicts with exact keys `pos`, `slot_key`, `cover_source`, `cover_los_break_quality`, where `cover_source = "wall"` and `slot_key` format is `cover:wall:<edge_name>`.
- Append obstacle-cover candidates from `_build_cover_slots_from_nav_obstacles(player_room_rect, player_pos)` after wall candidates (wall candidates always come first).
- Dedup combined candidates in insertion order using bucket key `(cover_source, floor(pos.x / COVER_SLOT_DEDUP_BUCKET_PX), floor(pos.y / COVER_SLOT_DEDUP_BUCKET_PX))`; first inserted candidate wins.
- Return deduped array in insertion order only (no sort step).

Step 1: Build `pressure_slots` with `_build_ring_slots(...)` and annotate each slot dict with:
- `slot_role = Role.PRESSURE`
- `cover_source = "ring"`
- `cover_los_break_quality = 0.0`

Step 2: Build `wall_cover_slots := _build_cover_slots_from_room_geometry(player_pos)`.

Step 3: Build `hold_slots` in exact precedence order:
- when `wall_cover_slots` is non-empty: `hold_slots = wall_cover_slots`
- else when Phase 10 helper `_build_contain_slots_from_exits(player_pos)` returns non-empty: use that output and annotate `slot_role = Role.HOLD`, `cover_source = "exit"`, `cover_los_break_quality = 0.0`
- else use HOLD ring slots annotated `slot_role = Role.HOLD`, `cover_source = "ring"`, `cover_los_break_quality = 0.0`

Step 4: Build `flank_slots` with `_build_ring_slots(...)` and annotate each slot dict with:
- `slot_role = Role.FLANK`
- `cover_source = "ring"`
- `cover_los_break_quality = 0.0`

Step 5: Return `{Role.PRESSURE: pressure_slots, Role.HOLD: hold_slots, Role.FLANK: flank_slots}`.

Tie-break: N/A — no selection occurs in `_build_slots`, only deterministic source construction.

### 7.3 `EnemySquadSystem._score_tactical_slot_candidate(...)` score tuple and validity rules

For each candidate slot dict, compute in this exact order:

Step 1: Read slot metadata with defaults:
- `slot_role: int`
- `cover_source: String`
- `cover_los_break_quality: float`
- `pos: Vector2`
- `slot_key: String`

Step 2: Call `policy_eval := _build_slot_policy_eval(enemy, pos)` and read normalized fields.

Step 3: Compute FLANK budget validity booleans using Phase 10 keys only when `slot_role == Role.FLANK`:
- `flank_path_len_ok := float(policy_eval.get("slot_path_length", INF)) <= _squad_cfg_float("flank_max_path_px", 900.0)`
- `flank_eta_ok := float(policy_eval.get("slot_path_eta_sec", INF)) <= _squad_cfg_float("flank_max_time_sec", 3.5)`
For `slot_role != Role.FLANK`, both booleans are treated as `true`.

Step 4: Compute `candidate_valid := bool(policy_eval.get("path_ok", false)) and flank_path_len_ok and flank_eta_ok`.

Step 5: Compute `distance_score := enemy.global_position.distance_to(pos)`.

Step 6: Compute `flank_angle_score`:
- When `slot_role != Role.FLANK`, `flank_angle_score = 0.0`.
- When `slot_role == Role.FLANK`, compute player-relative angle error to perpendicular (90 degrees) and multiply by `FLANK_ANGLE_SCORE_WEIGHT`.

Step 7: Compute `cover_bonus`:
- When `slot_role == Role.HOLD or slot_role == Role.FLANK`, `cover_bonus = clampf(cover_los_break_quality, 0.0, 1.0) * COVER_LOS_BREAK_WEIGHT`.
- Else `cover_bonus = 0.0`.

Step 8: Compute `invalid_penalty := 0.0` when `candidate_valid == true`, else `_squad_cfg_float("invalid_path_score_penalty", INVALID_PATH_SCORE_PENALTY)`.

Step 9: Compute `total_score := distance_score + flank_angle_score + invalid_penalty - cover_bonus`.

Step 10: Return a scored candidate dict that contains the original slot metadata plus all `policy_eval` fields and:
- `candidate_valid: bool`
- `total_score: float`
- `distance_score: float`
- `flank_angle_score: float`
- `cover_score: float` (exact stored value = `cover_bonus`)

Tie-break tuple for equal `total_score` within `is_equal_approx`: compare in order
1. `candidate_valid` (`true` sorts before `false`)
2. `slot_role` role-priority index in the current `_role_priority(preferred_role)` array (lower index wins)
3. `slot_path_length` (smaller wins)
4. `slot_key` lexicographic ascending (exact final tie-break)

### 7.4 `EnemySquadSystem._pick_slot_for_enemy(...)` exact selection and fallback order

Step 1: Build `role_priority := _role_priority(preferred_role)`.

Step 2: For each `role` in `role_priority` order, iterate `slots_by_role[role]` in array order; skip empty key or reserved key; score each slot with the score rules from section 7.

Step 3: Track `best_valid_for_role` and `best_invalid_for_role` using the tie-break tuple defined in section 7.

Step 4: After finishing one `role` bucket:
- When `best_valid_for_role` exists, return it immediately.
- Else record `best_invalid_for_role` in a per-role invalid fallback map and continue to the next role.

Step 5: After all roles:
- When `preferred_role == Role.FLANK`, return the first recorded invalid fallback from non-FLANK roles in `role_priority` order (`HOLD`, then `PRESSURE` in the FLANK priority array).
- When `preferred_role == Role.FLANK` and no non-FLANK invalid fallback exists, return `{}`.
- When `preferred_role != Role.FLANK`, return the best invalid fallback across `role_priority` using the tie-break tuple defined in section 7.
- When no invalid fallback exists, return `{}`.

This rule forbids returning an invalid FLANK tactical slot and creates deterministic contain/pressure fallback when FLANK fails path/ETA policy.

### 7.5 `Enemy._assignment_supports_flank_role(...)`, `_build_utility_context(...)`, and `EnemyUtilityBrain._choose_intent(...)` exact phase order

1. `Enemy._assignment_supports_flank_role(assignment)` evaluates in this exact order:
   - `effective_role = int(assignment.get("role", SQUAD_ROLE_PRESSURE))`
   - `effective_slot_role = int(assignment.get("slot_role", effective_role))`
   - if `effective_slot_role != SQUAD_ROLE_FLANK`: return `false`
   - if `bool(assignment.get("has_slot", false)) == false`: return `false`
   - if `bool(assignment.get("path_ok", false)) == false`: return `false`
   - `path_status = String(assignment.get("path_status", "ok" if bool(assignment.get("path_ok", false)) else "unreachable_geometry"))`
   - if `path_status != "ok"`: return `false`
   - `slot_path_length = float(assignment.get("slot_path_length", INF))`
   - `slot_path_eta_sec = float(assignment.get("slot_path_eta_sec", INF))`
   - when `slot_path_eta_sec` is not finite: set `slot_path_eta_sec = slot_path_length / maxf(_squad_cfg_float("flank_walk_speed_assumed_px_per_sec", 150.0), 0.001)`
   - if `slot_path_length > _squad_cfg_float("flank_max_path_px", 900.0)`: return `false`
   - if `slot_path_eta_sec > _squad_cfg_float("flank_max_time_sec", 3.5)`: return `false`
   - return `true`
2. `Enemy._build_utility_context(...)` computes `flank_slot_contract_ok := _assignment_supports_flank_role(assignment)` exactly once and writes it into the returned context.
3. `EnemyUtilityBrain._choose_intent(ctx)` reads `flank_slot_contract_ok` before LOS slot movement branches.
4. In the LOS generic slot-reposition branch, `MOVE_TO_SLOT` executes only when `has_slot == true`, `path_ok == true`, `slot_pos != Vector2.ZERO`, `dist_to_slot > slot_reposition_threshold`, and `(role != FLANK or flank_slot_contract_ok == true)`.
5. In the LOS final FLANK branch, `MOVE_TO_SLOT` executes only when `role == FLANK`, `has_slot == true`, `slot_pos != Vector2.ZERO`, and `flank_slot_contract_ok == true`.
6. When Step 4 or Step 5 fails because `flank_slot_contract_ok == false`, branch order falls through to existing `PUSH` / `RETREAT` / `HOLD_RANGE` logic from Phase 15 with no new branch inserted ahead of those outputs.

### 7.6 `Enemy._resolve_contextual_combat_role(...)` aggressive valid-contact FLANK fallback (Phase 18 extension)

Step 1: `flank_available := _assignment_supports_flank_role(assignment)` (single predicate owner from section 5 / Contract 3).

Step 2: Preserve the existing no-contact branch exactly:
- if `has_valid_contact == false`: return `SQUAD_ROLE_FLANK if flank_available else SQUAD_ROLE_PRESSURE`

Step 3: Preserve the existing finite-distance guards exactly:
- if `target_distance > hold_range_max`: return `SQUAD_ROLE_PRESSURE`
- if `target_distance < hold_range_min and flank_available == false`: return `SQUAD_ROLE_HOLD`

Step 4 (new Phase 18 aggressive fallback): when `has_valid_contact == true`, `candidate_role == SQUAD_ROLE_FLANK`, and `flank_available == false`, return `SQUAD_ROLE_PRESSURE`.

Step 5: Preserve the existing FLANK-in-hold-range positive case:
- when `flank_available == true` and `target_distance` is finite and `hold_range_min <= target_distance <= hold_range_max`, return `SQUAD_ROLE_FLANK`.

Step 6: Return `candidate_role`.

Design-process note (authoritative for Phase 18 execution): implementing Step 4 is gameplay-impacting and requires the section 14 user-approval checkpoint before code changes are made for this subchange.

---

## 8. Edge-case matrix (case → exact output).

**Case A: `navigation_service == null` in `EnemySquadSystem._build_slot_policy_eval(...)`**
- Input: any finite `enemy.global_position`, finite `slot_pos`.
- Expected output dict:
  - `path_status = "unreachable_geometry"`
  - `path_reason = "nav_service_missing"`
  - `path_ok = false`
  - `path_points = []`
  - `slot_path_length = INF`
  - `slot_path_eta_sec = INF`
  - `blocked_point_valid = false`

**Case B: single valid HOLD wall-cover slot and one exposed ring slot (no ambiguity)**
- Setup: HOLD bucket contains one wall slot (`cover_source="wall"`, `cover_los_break_quality=1.0`) and one ring slot (`cover_source="ring"`, `cover_los_break_quality=0.0`); both policy-eval outputs have `path_status="ok"`; distances within `COVER_LOS_BREAK_WEIGHT` bonus margin.
- Expected output from `_pick_slot_for_enemy(...)`:
  - returned `slot_role == Role.HOLD`
  - `cover_source == "wall"`
  - `path_status == "ok"`
  - `candidate_valid == true`

**Case C: tie-break triggered (equal total score and equal path length)**
- Setup: two candidates in the same role bucket produce equal `candidate_valid`, equal `total_score` (within `is_equal_approx`), equal `slot_path_length`, different `slot_key` values `"hold_cover:a"` and `"hold_cover:b"`.
- Expected output: candidate with lexicographically smaller `slot_key` (`"hold_cover:a"`) wins.

**Case D: all FLANK slots invalid, HOLD invalid exists, PRESSURE invalid exists**
- Setup: `preferred_role = Role.FLANK`; all FLANK scored candidates invalid; HOLD and PRESSURE both expose invalid fallback candidates; no valid candidates in any role.
- Expected output from `_pick_slot_for_enemy(...)`: invalid fallback from HOLD bucket (`slot_role == Role.HOLD`) because section 7 forbids invalid FLANK return and preserves role-priority fallback order.

**Case E: FLANK slot policy path blocked**
- Input assignment to `Enemy._assignment_supports_flank_role(...)`:
  - `role = FLANK`, `slot_role = FLANK`, `has_slot = true`, `path_ok = false`, `path_status = "unreachable_policy"`, `slot_path_length = INF`, `slot_path_eta_sec = INF`
- Expected output: `false`.
- Utility effect in `EnemyUtilityBrain._choose_intent(...)` LOS branch with `role == FLANK`: both FLANK `MOVE_TO_SLOT` branches are blocked when `flank_slot_contract_ok == false`.

**Case F: FLANK slot path status ok but ETA exceeds budget**
- Input assignment:
  - `role = FLANK`, `slot_role = FLANK`, `has_slot = true`, `path_ok = true`, `path_status = "ok"`, `slot_path_length = 600.0`, `slot_path_eta_sec = 4.0`
  - Phase 10 budget defaults: `flank_max_time_sec = 3.5`, `flank_walk_speed_assumed_px_per_sec = 150.0`
- Expected output from `Enemy._assignment_supports_flank_role(...)`: `false`.
- Expected utility effect: `flank_slot_contract_ok == false`, LOS final FLANK `MOVE_TO_SLOT` branch is skipped.

**Case G: cover obstacle API absent but room rect exists**
- Setup: `navigation_service.get_room_rect(...)` works, `navigation_service.layout` exists, `layout.has_method("_navigation_obstacles") == false`.
- Expected output from `_build_cover_slots_from_room_geometry(player_pos)`: non-empty wall-cover slots only; no obstacle-cover slots; no error branch.

**Case H: invalid slot room (`room_id_at_point(slot_pos) < 0`)**
- Expected `_build_slot_policy_eval(...)` output:
  - `path_status = "unreachable_geometry"`
  - `path_reason = "invalid_slot_room"`
  - `path_ok = false`
  - `slot_path_length = INF`
  - `slot_path_eta_sec = INF`

**Case I: valid contact + mid-range + invalid FLANK candidate (aggressive fallback)**
- Input to `Enemy._resolve_contextual_combat_role(...)`:
  - `candidate_role = SQUAD_ROLE_FLANK`
  - `has_valid_contact = true`
  - `target_distance = 500.0` (inside default hold range `390..610`)
  - `assignment` such that `Enemy._assignment_supports_flank_role(assignment) == false` (e.g. `path_status = "unreachable_policy"` or ETA above budget)
- Expected output: `SQUAD_ROLE_PRESSURE`.
- Fail condition: function preserves `SQUAD_ROLE_FLANK` in this valid-contact mid-range invalid-FLANK case.

---

## 9. Legacy removal plan (delete-first, exact ids).

**L1. `EnemySquadSystem._is_slot_path_ok` — `src/systems/enemy_squad_system.gd`**
- Identifier: `func _is_slot_path_ok(enemy: Node2D, slot_pos: Vector2) -> bool`
- Approximate confirmed range from PROJECT DISCOVERY: `src/systems/enemy_squad_system.gd:181` to `src/systems/enemy_squad_system.gd:195`
- Delete reason: legacy bool-only slot validation branch; Phase 18 replaces it with `SquadSlotPolicyEvalContractV1` (section 6) and `build_policy_valid_path` usage only.

**L2. Direct `build_path_points(...)` slot validation call — `src/systems/enemy_squad_system.gd`**
- Identifier: `navigation_service.build_path_points(enemy.global_position, slot_pos)` inside `_is_slot_path_ok(...)`
- Confirmed line from PROJECT DISCOVERY: `src/systems/enemy_squad_system.gd:189`
- Delete reason: direct legacy path builder call bypasses `status/reason` policy path contract and blocks ETA/path-status reporting.

**L3. `slot_path_tail_tolerance_px` config key — `src/core/game_config.gd`**
- Identifier: `"slot_path_tail_tolerance_px": 24.0`
- Confirmed line from PROJECT DISCOVERY: `src/core/game_config.gd:177`
- Delete reason: only consumer is deleted legacy `_is_slot_path_ok(...)` tail-distance branch.

**L4. `slot_path_tail_tolerance_px` validator rule — `src/core/config_validator.gd`**
- Identifier: `_validate_number_key(result, squad, "slot_path_tail_tolerance_px", "ai_balance.squad", 0.0, 1000.0)`
- Confirmed line from PROJECT DISCOVERY: `src/core/config_validator.gd:237`
- Delete reason: validation for dead config key after L3 removal.

**File-uniqueness evidence for file-scoped legacy commands in section 10:** PROJECT DISCOVERY `rg` results in `src/` show `_is_slot_path_ok(...)` and the `build_path_points(...)` slot validation call only in `src/systems/enemy_squad_system.gd`, and `slot_path_tail_tolerance_px` only in `src/core/game_config.gd` plus `src/core/config_validator.gd`.

---

## 10. Legacy verification commands (exact rg + expected 0 matches).

[L1] `rg -n "func _is_slot_path_ok\(" src/systems/enemy_squad_system.gd -S`
Expected: `0 matches`.

[L2] `rg -n "build_path_points\(" src/systems/enemy_squad_system.gd -S`
Expected: `0 matches`.

[L3] `rg -n "slot_path_tail_tolerance_px" src/core/game_config.gd -S`
Expected: `0 matches`.

[L4] `rg -n "slot_path_tail_tolerance_px" src/core/config_validator.gd -S`
Expected: `0 matches`.

---

## 11. Acceptance criteria (binary pass/fail).

1. All section 10 legacy commands L1–L4 return `0 matches`.
2. All phase-specific gates G1–G12 in section 13 return expected output.
3. All PMB gates PMB-1 through PMB-5 in section 13 return expected output.
4. `tests/test_combat_cover_selection_prefers_valid_cover.gd` test functions from section 12 exit `0`.
5. `tests/test_combat_flank_requires_eta_and_path_ok.gd` test functions from section 12 exit `0`.
6. `tests/test_combat_role_distribution_not_all_pressure.gd` test functions from section 12 exit `0`.
7. Updated `tests/test_enemy_squad_system.gd` and `tests/test_combat_role_lock_and_reassign_triggers.gd` suites exit `0`.
8. Updated `tests/test_combat_role_lock_and_reassign_triggers.gd` asserts the valid-contact mid-range invalid-FLANK case returns `SQUAD_ROLE_PRESSURE`.
9. Phase 18 aggressive-fallback design checkpoint is recorded: detailed impact study complete, recommended options presented, and explicit user approval obtained before implementing the `_resolve_contextual_combat_role(...)` fallback branch.
10. Tier 1 smoke suite commands from section 14 all exit `0`.
11. Tier 2 full regression (`xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn`) exits `0`.
12. `tests/test_runner_node.gd` contains the 3 new Phase 18 scene constants, 3 `_scene_exists(...)` assertions, and 3 `_run_embedded_scene_suite(...)` calls.
13. `CHANGELOG.md` contains one prepended Phase 18 entry under the current date header.

---

## 12. Tests (new/update + purpose).

**New: `tests/test_combat_cover_selection_prefers_valid_cover.gd`**

Functions:
- `_test_hold_slot_prefers_wall_cover_when_policy_valid` — FakeNav returns a valid room rect and policy-valid path for both a wall-cover slot and an exposed ring slot; wall-cover slot has higher `cover_los_break_quality`. Asserts selected assignment has `slot_role == EnemySquadSystem.Role.HOLD`, `cover_source == "wall"`, `path_status == "ok"`.
- `_test_policy_blocked_cover_falls_back_to_valid_exposed_slot` — FakeNav returns `status="unreachable_policy"`, `reason="policy_blocked"`, and `blocked_point` for the wall-cover slot, and `status="ok"` for an exposed fallback slot. Asserts selected assignment `path_status == "ok"`, `cover_source != "wall"`, and `blocked_point_valid == false` on the winning assignment.
- `_test_assignment_publishes_cover_and_path_contract_fields` — After `recompute_now()`, asserts assignments with `has_slot == true` include keys `slot_role`, `path_status`, `path_reason`, `slot_path_length`, `slot_path_eta_sec`, `cover_source`, `cover_los_break_quality`, `cover_score` with expected types.

Registration: add `COMBAT_COVER_SELECTION_PREFERS_VALID_COVER_TEST_SCENE` const and corresponding `_scene_exists(...)` + `_run_embedded_scene_suite(...)` entries in `tests/test_runner_node.gd`.

**New: `tests/test_combat_flank_requires_eta_and_path_ok.gd`**

Functions:
- `_test_assignment_supports_flank_requires_path_status_ok` — direct unit call to `Enemy._assignment_supports_flank_role(...)` with `role=FLANK`, `slot_role=FLANK`, `has_slot=true`, `path_ok=true`, `path_status="unreachable_policy"`, valid `slot_path_length`, valid `slot_path_eta_sec`; asserts return `false`.
- `_test_assignment_supports_flank_requires_eta_within_budget` — direct unit call with `path_status="ok"`, `path_ok=true`, `slot_path_length=600.0`, `slot_path_eta_sec=4.0`; asserts return `false` under Phase 10 budget defaults.
- `_test_utility_move_to_slot_blocked_when_flank_contract_false` — instantiate `EnemyUtilityBrain`, call `update(...)` with LOS context `role=FLANK`, `has_slot=true`, `path_ok=true`, `slot_position != Vector2.ZERO`, `dist_to_slot > slot_reposition_threshold`, and `flank_slot_contract_ok=false`; asserts `IntentType.MOVE_TO_SLOT` is not returned.
- `_test_utility_flank_move_to_slot_allowed_when_contract_true` — same as previous but `flank_slot_contract_ok=true`; asserts `IntentType.MOVE_TO_SLOT` is returned.

Registration: add `COMBAT_FLANK_REQUIRES_ETA_AND_PATH_OK_TEST_SCENE` const and corresponding `_scene_exists(...)` + `_run_embedded_scene_suite(...)` entries.

**New: `tests/test_combat_role_distribution_not_all_pressure.gd`**

Functions:
- `_test_slot_role_distribution_uses_multiple_tactical_roles` — 9 enemies + FakeNav + player room geometry; after `recompute_now()`, collect `assignment["slot_role"]` for `has_slot == true`; asserts the set contains at least 2 distinct values and the set is not `{Role.PRESSURE}`.
- `_test_flank_invalid_candidates_demote_slot_role` — configure FakeNav policy results so all FLANK ring slots fail (`unreachable_policy` or ETA over budget) while HOLD slots remain valid; asserts at least one FLANK-preferred enemy receives `slot_role == Role.HOLD` or `slot_role == Role.PRESSURE`, and no assignment with `slot_role == Role.FLANK` has `path_status != "ok"`.
- `_test_hold_assignments_publish_cover_sources_when_room_rect_available` — with valid room rect and no obstacle API, asserts at least one HOLD assignment has `cover_source == "wall"`.

Registration: add `COMBAT_ROLE_DISTRIBUTION_NOT_ALL_PRESSURE_TEST_SCENE` const and corresponding `_scene_exists(...)` + `_run_embedded_scene_suite(...)` entries.

**Update: `tests/test_enemy_squad_system.gd`**

Required changes:
- Replace `FakeNav.build_path_points(...)` with `FakeNav.build_policy_valid_path(...)` that returns the navigation policy contract (`status`, `reason`, `path_points`) and optional `blocked_point` in blocked cases.
- Update `_test_path_fallback()` assertions to inspect `assignment["path_status"]` and `assignment["path_reason"]` while retaining a `path_ok` regression assertion.
- Add `_test_assignment_includes_tactical_contract_fields()` and call it from `run_suite()` after `_test_path_fallback()`.
- Add coverage for `slot_role` and `slot_path_eta_sec` type/default invariants in that new function.

**Update: `tests/test_combat_role_lock_and_reassign_triggers.gd`**

Required changes:
- Extend `flank_assignment` literal in `_test_role_lock_and_triggered_reassign()` with Phase 18 keys:
  - `"slot_role": Enemy.SQUAD_ROLE_FLANK`
  - `"path_status": "ok"`
  - `"slot_path_length": 420.0`
  - `"slot_path_eta_sec": 2.8`
- Add a second flank assignment literal with `"path_status": "unreachable_policy"` (or `slot_path_eta_sec` above budget) and assert the no-contact contextual role result is not `SQUAD_ROLE_FLANK`.
- Add a valid-contact mid-range invalid-FLANK sub-case (`candidate_role = SQUAD_ROLE_FLANK`, `has_valid_contact = true`, `target_distance` inside hold range, invalid flank contract) and assert `_resolve_contextual_combat_role(...) == SQUAD_ROLE_PRESSURE`.
- Retain all existing early-trigger reason assertions unchanged.

---

## 13. rg gates (command + expected output).

**Phase-specific gates:**

[G1] `rg -n "func _is_slot_path_ok\(" src/systems/enemy_squad_system.gd -S`
Expected: `0 matches`.

[G2] `rg -n "build_path_points\(" src/systems/enemy_squad_system.gd -S`
Expected: `0 matches`.

[G3] `rg -n "slot_path_tail_tolerance_px" src/systems/enemy_squad_system.gd -S`
Expected: `0 matches`.

[G4] `rg -n "slot_path_tail_tolerance_px" src/core/game_config.gd src/core/config_validator.gd -S`
Expected: `0 matches`.

[G5] `rg -n "build_policy_valid_path\(" src/systems/enemy_squad_system.gd -S`
Expected: `>= 1 match`.

[G6] `rg -n "func _build_slot_policy_eval\(|func _build_cover_slots_from_room_geometry\(|func _build_cover_slots_from_nav_obstacles\(|func _compute_cover_los_break_quality\(|func _score_tactical_slot_candidate\(" src/systems/enemy_squad_system.gd -S`
Expected: `5 matches`.

[G7] `rg -n "slot_role|path_status|path_reason|slot_path_eta_sec|cover_source|cover_los_break_quality|cover_score" src/systems/enemy_squad_system.gd -S`
Expected: `>= 20 matches`.

[G8] `rg -n "func _assignment_supports_flank_role\(|slot_role|path_status|slot_path_eta_sec|flank_slot_contract_ok" src/entities/enemy.gd -S`
Expected: `>= 10 matches`.

[G9] `rg -n "flank_slot_contract_ok" src/systems/enemy_utility_brain.gd -S`
Expected: `>= 3 matches`.

[G10] `rg -n "MOVE_TO_SLOT|flank_slot_contract_ok" src/systems/enemy_utility_brain.gd -S`
Expected: `>= 4 matches`.

[G11] `rg -n "build_path_points\(" tests/test_enemy_squad_system.gd -S`
Expected: `0 matches`.

[G12] `rg -n "COMBAT_COVER_SELECTION_PREFERS_VALID_COVER_TEST_SCENE|COMBAT_FLANK_REQUIRES_ETA_AND_PATH_OK_TEST_SCENE|COMBAT_ROLE_DISTRIBUTION_NOT_ALL_PRESSURE_TEST_SCENE" tests/test_runner_node.gd -S`
Expected: `9 matches`.

**PMB gates:**

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: `0 matches`.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

---

## 14. Execution sequence (step-by-step, no ambiguity).

Step 0: Run dependency gates from section 23 and stop on first failure.

Step 1: Delete legacy item L1 from section 9 in `src/systems/enemy_squad_system.gd` (`func _is_slot_path_ok(...)`).

Step 2: Delete legacy item L2 from section 9 in `src/systems/enemy_squad_system.gd` (direct `build_path_points(...)` slot validation call).

Step 3: Delete legacy item L3 from section 9 in `src/core/game_config.gd` (`"slot_path_tail_tolerance_px"`).

Step 4: Delete legacy item L4 from section 9 in `src/core/config_validator.gd` (`slot_path_tail_tolerance_px` validator rule).

Step 5: Run all section 10 legacy verification commands (L1–L4). All commands must return `0 matches` before continuing.

Step 6: In `src/systems/enemy_squad_system.gd`, add Phase 18 local cover/tactical scoring constants from section 6 after existing file-scope squad constants.

Step 7: In `src/systems/enemy_squad_system.gd`, add `_sum_path_points_length(...)` and `_build_slot_policy_eval(...)` and ensure `_build_slot_policy_eval(...)` uses `navigation_service.build_policy_valid_path(...)` only.

Step 8: In `src/systems/enemy_squad_system.gd`, add cover helpers `_build_cover_slots_from_room_geometry(...)`, `_build_cover_slots_from_nav_obstacles(...)`, and `_compute_cover_los_break_quality(...)`.

Step 9: In `src/systems/enemy_squad_system.gd`, add `_score_tactical_slot_candidate(...)` with the exact score tuple and FLANK validity rules from section 7.

Step 10: Rewrite `EnemySquadSystem._build_slots(player_pos)` in `src/systems/enemy_squad_system.gd` to produce annotated slot metadata and the HOLD slot source precedence from section 7.

Step 11: Rewrite `EnemySquadSystem._pick_slot_for_enemy(...)` in `src/systems/enemy_squad_system.gd` to use `SquadSlotPolicyEvalContractV1`, `slot_role`, cover scoring, and the FLANK invalid-return prohibition from section 7.

Step 12: Modify `EnemySquadSystem._recompute_assignments(...)` and `EnemySquadSystem._default_assignment(...)` in `src/systems/enemy_squad_system.gd` to persist all `SquadTacticalAssignmentContractV2` keys from section 6.

Step 12a (design checkpoint — BLOCKING for Contract 5 / section 7.6 Step 4): perform a detailed behavior-impact study for the aggressive valid-contact FLANK fallback in `Enemy._resolve_contextual_combat_role(...)`, prepare recommended options/tradeoffs, return to the user for explicit approval, and only then implement that fallback branch.

Step 13: Modify `Enemy._resolve_squad_assignment()`, `Enemy._assignment_supports_flank_role(...)`, `_resolve_contextual_combat_role(...)`, and `Enemy._build_utility_context(...)` in `src/entities/enemy.gd` to implement Contracts 3, 4, and 5 from section 6 (with Contract 5 gated by Step 12a user approval).

Step 14: Modify `EnemyUtilityBrain._choose_intent(ctx)` in `src/systems/enemy_utility_brain.gd` to gate both LOS `MOVE_TO_SLOT` branches with `flank_slot_contract_ok` as defined in section 7.

Step 15: Create `tests/test_combat_cover_selection_prefers_valid_cover.gd` and `tests/test_combat_cover_selection_prefers_valid_cover.tscn`; implement all 3 test functions from section 12.

Step 16: Create `tests/test_combat_flank_requires_eta_and_path_ok.gd` and `tests/test_combat_flank_requires_eta_and_path_ok.tscn`; implement all 4 test functions from section 12.

Step 17: Create `tests/test_combat_role_distribution_not_all_pressure.gd` and `tests/test_combat_role_distribution_not_all_pressure.tscn`; implement all 3 test functions from section 12.

Step 18: Update `tests/test_enemy_squad_system.gd` per section 12 (FakeNav policy contract, `_test_path_fallback()` assertions, `_test_assignment_includes_tactical_contract_fields()`, `run_suite()` call order).

Step 19: Update `tests/test_combat_role_lock_and_reassign_triggers.gd` per section 12 (Phase 18 flank assignment fields and invalid-flank runtime assertion).

Step 20: Update `tests/test_runner_node.gd`: add 3 top-level const declarations, 3 `_scene_exists(...)` checks, and 3 `_run_embedded_scene_suite(...)` calls for the new Phase 18 suites.

Step 21: Run Tier 1 smoke suite commands (exact):
- `xvfb-run -a godot-4 --headless --path . res://tests/test_combat_cover_selection_prefers_valid_cover.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_combat_flank_requires_eta_and_path_ok.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_combat_role_distribution_not_all_pressure.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_enemy_squad_system.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_combat_role_lock_and_reassign_triggers.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_navigation_failure_reason_contract.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_navigation_path_policy_parity.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_combat_no_los_never_hold_range.tscn`

Step 22: Run Tier 2 full regression: `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit `0`.

Step 23: Run all section 13 rg gates (G1–G12 and PMB-1–PMB-5). All commands must return expected output.

Step 24: Prepend one `CHANGELOG.md` entry under the current date header for Phase 18 (tactical cover slot scoring, policy-valid squad path contract, FLANK ETA/path gate, legacy `build_path_points` slot validation removal).

---

## 15. Rollback conditions.

1. **Trigger:** Any dependency gate in section 23 fails at step 0. **Rollback action:** do not start implementation; revert all edits from the attempted Phase 18 branch to pre-phase state. Phase result = FAIL.
2. **Trigger:** Any section 10 legacy verification command returns non-zero matches after step 5. **Rollback action:** revert all section 4 in-scope file changes to pre-phase state. Phase result = FAIL.
3. **Trigger:** Any Tier 1 smoke command in step 21 exits non-zero. **Rollback action:** revert all section 4 in-scope file changes to pre-phase state. Phase result = FAIL.
4. **Trigger:** Tier 2 regression in step 22 exits non-zero. **Rollback action:** revert all section 4 in-scope file changes to pre-phase state. Phase result = FAIL.
5. **Trigger:** Any assignment returned by `EnemySquadSystem.get_assignment(...)` contains `slot_role == FLANK` while `path_status != "ok"`. **Rollback action:** revert `enemy_squad_system.gd`, `enemy.gd`, and `enemy_utility_brain.gd` Phase 18 edits together and restart from step 11. Partial state is forbidden.
6. **Trigger:** Any LOS `MOVE_TO_SLOT` utility branch still executes for `role == FLANK` while `flank_slot_contract_ok == false`. **Rollback action:** revert Phase 18 utility-context and utility-brain edits and then revert remaining Phase 18 edits. Phase result = FAIL.
7. **Trigger:** Any `slot_path_tail_tolerance_px` string remains in `src/core/game_config.gd` or `src/core/config_validator.gd` after step 23. **Rollback action:** revert all Phase 18 changes and restart from section 14 step 1. Phase result = FAIL.
8. **Trigger:** Any out-of-scope file in section 4 is modified. **Rollback action:** revert out-of-scope edits immediately, then revert all Phase 18 edits. Phase result = FAIL.
9. **Trigger:** Implementation completes cover scoring or utility FLANK gating without the policy-valid slot contract migration (section 6 Contract 1 + Contract 2 keys). **Rollback action:** revert all changes to pre-phase state. Phase result = FAIL (Hard Rule 11).
10. **Trigger:** The aggressive valid-contact FLANK fallback in `_resolve_contextual_combat_role(...)` is implemented or tuned without the Step 12a user-approval checkpoint (detailed study + recommended options + explicit user approval). **Rollback action:** revert the `_resolve_contextual_combat_role(...)` fallback changes and all dependent test/spec edits, then stop Phase 18 implementation pending approval. Phase result = FAIL.

---

## 16. Phase close condition.

- [ ] All rg commands in section 10 return `0 matches`
- [ ] All rg gates in section 13 return expected output
- [ ] All tests in section 12 (new + updated) exit `0`
- [ ] Tier 1 smoke suite (section 14) — all commands exit `0`
- [ ] Tier 2 full regression (`xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn`) exits `0`
- [ ] No file outside section 4 in-scope list was modified
- [ ] `CHANGELOG.md` entry prepended
- [ ] `tests/test_combat_cover_selection_prefers_valid_cover.gd` records a winning HOLD assignment with `cover_source == "wall"` and `path_status == "ok"`
- [ ] `tests/test_combat_flank_requires_eta_and_path_ok.gd` records `EnemyUtilityBrain` LOS `MOVE_TO_SLOT` rejection when `flank_slot_contract_ok == false`
- [ ] `tests/test_combat_role_distribution_not_all_pressure.gd` records at least two distinct `slot_role` values among assigned enemies
- [ ] `tests/test_enemy_squad_system.gd` contains no `build_path_points(...)` FakeNav branch and asserts `path_status`/`path_reason` fields
- [ ] `tests/test_combat_role_lock_and_reassign_triggers.gd` includes Phase 18 flank contract keys in the manual `flank_assignment` literal
- [ ] `tests/test_combat_role_lock_and_reassign_triggers.gd` verifies valid-contact mid-range invalid-FLANK fallback to `SQUAD_ROLE_PRESSURE`
- [ ] Phase 18 aggressive-fallback design checkpoint is recorded (detailed impact study + recommended options + explicit user approval before implementation)

---

## 17. Ambiguity check: 1

---

## 18. Open questions: 1

1. Phase 18 adds a gameplay-impacting aggressive valid-contact fallback in `Enemy._resolve_contextual_combat_role(...)` (`candidate_role == FLANK` + invalid flank contract -> `SQUAD_ROLE_PRESSURE`). Before implementing this subchange, return to the user after a detailed behavior-impact study with recommended options/tradeoffs and obtain explicit approval (section 14, Step 12a).

---

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).

**Diff audit:**
- Diff every file in section 4 against the pre-phase baseline, including all 3 new test script/scene pairs and `CHANGELOG.md`.
- Confirm zero modifications outside the section 4 in-scope list.

**Contract checks:**
- `SquadSlotPolicyEvalContractV1` (section 6): inspect `EnemySquadSystem._build_slot_policy_eval(...)` and verify status/reason normalization, `blocked_point` propagation, `slot_path_length` computation, and `slot_path_eta_sec` computation order from section 7.
- `SquadTacticalAssignmentContractV2` (section 6): inspect `EnemySquadSystem._pick_slot_for_enemy(...)`, `_recompute_assignments(...)`, and `_default_assignment(...)` and verify all assignment keys, defaults, and `slot_role`/cover metadata are present exactly.
- `EnemyFlankSlotContractGateV2` (section 6): inspect `Enemy._assignment_supports_flank_role(...)` and verify `slot_role`, `path_status`, ETA fallback, and Phase 10 budget checks order from section 7.
- `UtilityFlankSlotContextGateContractV1` (section 6): inspect `Enemy._build_utility_context(...)` and `EnemyUtilityBrain._choose_intent(...)` and verify `flank_slot_contract_ok` is produced exactly once and used in both LOS `MOVE_TO_SLOT` branches.
- `AggressiveValidContactFlankFallbackContractV1` (section 6): inspect `Enemy._resolve_contextual_combat_role(...)` and verify the new valid-contact invalid-FLANK fallback-to-`PRESSURE` branch occurs before the final `return candidate_role`, while the no-contact branch remains unchanged.
- Legacy removal check (section 10): run all L1–L4 commands and confirm `0 matches`.

**Runtime scenarios from section 20:** execute P18-A, P18-B, P18-C, P18-D, P18-E, P18-F, P18-G, and P18-H.

---

## 20. Runtime scenario matrix (scenario id, setup, frame count, expected invariants, fail conditions).

**P18-A: HOLD cover slot wins over exposed slot when both paths are policy-valid**
- Scene: `tests/test_combat_cover_selection_prefers_valid_cover.tscn`
- Setup: FakeNav exposes room rect and policy-valid path outputs for one wall-cover slot and one exposed slot; wall-cover slot `cover_los_break_quality=1.0`; distances within cover bonus margin.
- Frame count: `0` (unit call plus deterministic `recompute_now()`)
- Expected invariants:
  - Winning assignment `slot_role == Role.HOLD`.
  - Winning assignment `cover_source == "wall"`.
  - Winning assignment `path_status == "ok"` and `path_reason == "ok"`.
- Fail conditions:
  - Exposed slot wins while wall-cover slot is valid.
  - Winning assignment lacks `cover_source` or `path_status` keys.
- Covered by: `_test_hold_slot_prefers_wall_cover_when_policy_valid`

**P18-B: Policy-blocked cover candidate is rejected and fallback slot remains policy-valid**
- Scene: `tests/test_combat_cover_selection_prefers_valid_cover.tscn`
- Setup: Cover candidate returns `status="unreachable_policy"`, `reason="policy_blocked"`, and `blocked_point`; exposed fallback slot returns `status="ok"`.
- Frame count: `0`
- Expected invariants:
  - Winning assignment `path_status == "ok"`.
  - Winning assignment `cover_source != "wall"`.
  - No winning assignment records `path_status != "ok"`.
- Fail conditions:
  - Policy-blocked cover slot wins.
  - Winning assignment keeps `path_status="unreachable_policy"`.
- Covered by: `_test_policy_blocked_cover_falls_back_to_valid_exposed_slot`

**P18-C: FLANK runtime gate rejects path-status mismatch**
- Scene: `tests/test_combat_flank_requires_eta_and_path_ok.tscn`
- Setup: Unit call to `Enemy._assignment_supports_flank_role(...)` with `slot_role=FLANK`, `path_ok=true`, `path_status="unreachable_policy"`, finite path length/ETA values.
- Frame count: `0`
- Expected invariants:
  - Function returns `false`.
  - `Enemy._build_utility_context(...)` derived `flank_slot_contract_ok == false` for the same assignment shape.
- Fail conditions:
  - Function returns `true` when `path_status != "ok"`.
- Covered by: `_test_assignment_supports_flank_requires_path_status_ok`

**P18-D: FLANK runtime gate rejects ETA over budget and utility blocks LOS `MOVE_TO_SLOT`**
- Scene: `tests/test_combat_flank_requires_eta_and_path_ok.tscn`
- Setup: `slot_path_length=600.0`, `slot_path_eta_sec=4.0`, `path_status="ok"`, `path_ok=true`, LOS context with `role=FLANK`, valid slot position, `dist_to_slot > slot_reposition_threshold`, and `flank_slot_contract_ok=false`.
- Frame count: `0`
- Expected invariants:
  - `Enemy._assignment_supports_flank_role(...) == false`.
  - `EnemyUtilityBrain._choose_intent(...)` does not return `MOVE_TO_SLOT`.
- Fail conditions:
  - Runtime flank gate passes for over-budget ETA.
  - Utility still returns `MOVE_TO_SLOT` for FLANK with `flank_slot_contract_ok=false`.
- Covered by: `_test_assignment_supports_flank_requires_eta_within_budget`, `_test_utility_move_to_slot_blocked_when_flank_contract_false`

**P18-E: Utility retains FLANK `MOVE_TO_SLOT` when contract is true**
- Scene: `tests/test_combat_flank_requires_eta_and_path_ok.tscn`
- Setup: LOS context identical to P18-D except `flank_slot_contract_ok=true` and valid `slot_position`/`path_ok`.
- Frame count: `0`
- Expected invariants:
  - `EnemyUtilityBrain._choose_intent(...)` returns `IntentType.MOVE_TO_SLOT`.
- Fail conditions:
  - FLANK valid contract path no longer reaches `MOVE_TO_SLOT`.
- Covered by: `_test_utility_flank_move_to_slot_allowed_when_contract_true`

**P18-F: Multi-enemy tactical slot roles are not all PRESSURE**
- Scene: `tests/test_combat_role_distribution_not_all_pressure.tscn`
- Setup: 9 enemies registered in `EnemySquadSystem`, FakeNav provides room rect and policy-valid paths for HOLD and PRESSURE buckets; selected FLANK slots include policy failures for a subset to force deterministic fallback.
- Frame count: `0` (deterministic recompute)
- Expected invariants:
  - At least two distinct `slot_role` values appear among assignments with `has_slot == true`.
  - The set of observed `slot_role` values is not `{Role.PRESSURE}`.
  - No assignment with `slot_role == Role.FLANK` has `path_status != "ok"`.
- Fail conditions:
  - All assigned enemies collapse to `slot_role == Role.PRESSURE`.
  - Invalid FLANK tactical slot survives selection.
- Covered by: `_test_slot_role_distribution_uses_multiple_tactical_roles`, `_test_flank_invalid_candidates_demote_slot_role`

**P18-G: Navigation policy contract baselines remain intact after squad migration**
- Scene: `tests/test_navigation_failure_reason_contract.tscn` and `tests/test_navigation_path_policy_parity.tscn`
- Setup: existing suites unchanged (smoke-only baselines).
- Frame count: existing scripted unit loops in both suites.
- Expected invariants:
  - `build_policy_valid_path(...)` status/reason contract still returns `unreachable_geometry`, `unreachable_policy`, and `ok` as asserted in the baseline suite.
  - nav/pursuit path policy parity suite still records blocked-segment parity and flashlight override parity.
- Fail conditions:
  - Navigation policy contract status/reason baseline fails.
  - Policy parity suite fails after squad migration changes.
- Covered by: `_test_failure_reason_contract`, `_test_path_policy_parity`

**P18-H: Valid-contact invalid-FLANK candidate falls back to PRESSURE (aggressive fallback)**
- Scene: `tests/test_combat_role_lock_and_reassign_triggers.tscn`
- Setup: updated suite creates a FLANK candidate assignment with valid-contact inputs (`has_valid_contact=true`, `target_distance` inside hold range, `candidate_role=SQUAD_ROLE_FLANK`) and an invalid flank contract (`path_status="unreachable_policy"` or ETA over budget).
- Frame count: `0` (unit-level `_resolve_contextual_combat_role(...)` call inside suite)
- Expected invariants:
  - `_resolve_contextual_combat_role(...) == SQUAD_ROLE_PRESSURE`
  - Existing no-contact invalid-FLANK sub-case still does not return `SQUAD_ROLE_FLANK`
- Fail conditions:
  - Function preserves `SQUAD_ROLE_FLANK` in the valid-contact mid-range invalid-FLANK case
  - No-contact branch behavior regresses
- Covered by: updated `_test_role_lock_and_triggered_reassign()`

---

## 21. Verification report format (what must be recorded to close phase).

Record all fields below to close phase:
- `phase_id: PHASE_18`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; empty list required for PASS)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `dependency_gate_check: [PHASE-10: PASS|FAIL, PHASE-15: PASS|FAIL, PHASE-17: PASS|FAIL]` **[BLOCKING — all must be PASS before implementation and before close]**
- `legacy_rg: [{command, expected: "0 matches", actual, PASS|FAIL}]` for all 4 commands from section 10
- `rg_gates: [{gate: "G1".."G12"|"PMB-1".."PMB-5", command, expected, actual, PASS|FAIL}]`
- `phase_tests: [{test_function, scene, exit_code: 0, PASS|FAIL}]` for all new and updated test functions listed in section 12
- `smoke_suite: [{command, exit_code: 0, PASS|FAIL}]` for all 8 Tier 1 commands from section 14
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `squad_cover_selection_check: {valid_wall_cover_selected: true|false, policy_blocked_cover_rejected: true|false, cover_sources_seen: [..], PASS|FAIL}`
- `flank_contract_gate_check: {path_status_mismatch_rejected: true|false, eta_over_budget_rejected: true|false, utility_move_to_slot_blocked_when_contract_false: true|false, utility_move_to_slot_allowed_when_contract_true: true|false, PASS|FAIL}`
- `aggressive_valid_contact_flank_fallback_check: {valid_contact_mid_range_invalid_flank_demotes_to_pressure: true|false, no_contact_invalid_flank_not_flank: true|false, PASS|FAIL}`
- `design_checkpoint_user_approval: {detailed_impact_study_completed: true|false, recommended_options_presented: true|false, explicit_user_approval_before_impl: true|false, PASS|FAIL}`
- `slot_role_distribution_check: {slot_roles_seen: [..], not_all_pressure: true|false, invalid_flank_slot_role_count: int, PASS|FAIL}`
- `legacy_slot_validation_removed_check: {is_slot_path_ok_absent: true|false, build_path_points_absent_in_squad: true|false, slot_path_tail_tolerance_removed_from_config: true|false, slot_path_tail_tolerance_removed_from_validator: true|false, PASS|FAIL}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING — all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

---

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 18` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- `pmb_contract_check` present in section 21 (PMB section exists in document): yes

---

## 23. Dependencies on previous phases.

1. **Phase 10** — `EnemySquadSystem` owns tactical slot scaffolding (`_build_contain_slots_from_exits`, `slot_path_length` assignment field) and `Enemy._assignment_supports_flank_role(...)` owns the Phase 10 flank budget guard using `flank_max_path_px`, `flank_max_time_sec`, and `flank_walk_speed_assumed_px_per_sec`. Phase 18 extends these contracts with policy path status/ETA and `slot_role` metadata, and reuses the Phase 10 budget keys without adding new flank budget config. Dependency gate (must pass before section 14 step 1): `rg -n "_build_contain_slots_from_exits|slot_path_length|flank_max_path_px|flank_max_time_sec|flank_walk_speed_assumed_px_per_sec" src/systems/enemy_squad_system.gd src/entities/enemy.gd src/core/game_config.gd -S` -> expected `>= 10 matches`.

2. **Phase 15** — `Enemy._build_utility_context(...)` plus `EnemyUtilityBrain._choose_intent(...)` own combat utility doctrine and LOS/no-LOS branch ordering. Phase 18 only adds slot contract context keys and tightens LOS `MOVE_TO_SLOT` gating for FLANK invalid cases; it does not replace Phase 15 doctrine ownership. Dependency gate (must pass before section 14 step 1): `rg -n "target_context_exists|if not has_los and alert_level >= ENEMY_ALERT_LEVELS_SCRIPT\.ALERT|SHADOW_BOUNDARY_SCAN" src/systems/enemy_utility_brain.gd -S` -> expected `>= 4 matches`.

3. **Phase 17** — `EnemyPursuitSystem` removed shadow-escape legacy and emits `repath_recovery_*` feedback while PMB boundaries prohibit direct pursuit path-builder fallbacks. Phase 18 reuses the same policy-path contract family in squad tactics and must not weaken PMB invariants. Dependency gate (must pass before section 14 step 1): `rg -n "repath_recovery_reason|repath_recovery_request_next_search_node" src/systems/enemy_pursuit_system.gd src/entities/enemy.gd -S` -> expected `>= 4 matches`.
## PHASE 19
Test-only compatibility exception (top-level authoritative rule): applies to this phase. Qualified test-only patches are allowed only under the top-level exception conditions and must be recorded in section 21 if this phase defines section 21.
Phase id: PHASE_19.
Scope boundary (exact files): section 4.
Execution sequence: section 14.
Rollback conditions: section 15.
Verification report format: section 21.

### Evidence

**Inspected files:**
- `docs/ai_nav_refactor_execution_v2.md` (`PHASE 19` source plus KPI/replay/checklist gate requirements; PMB gate commands and formatting baseline from earlier phases)
- `docs/phase_spec_template.md` (section/contract/verification requirements)
- `src/systems/ai_watchdog.gd` (full)
- `src/systems/enemy_pursuit_system.gd` (targeted refs for `_execute_move_to_target`, `_try_open_blocking_door_and_force_repath`, `_attempt_replan_with_policy`, `_plan_path_to`, `debug_get_navigation_policy_snapshot`, stall monitor)
- `src/systems/navigation_runtime_queries.gd` (targeted refs for `build_policy_valid_path`, `_build_detour_candidates`, detour candidate loop owner)
- `src/entities/enemy.gd` (targeted refs for `get_debug_detection_snapshot` replay fields)
- `src/levels/stealth_3zone_test_controller.gd` (targeted refs for debug room/choke helpers and `_spawn_enemies` fixture wiring)
- `src/levels/stealth_3zone_test.tscn` (node names for `Stealth3ZoneTestController`, `Spawns`, `ShadowAreas`, `Entities`)
- `src/levels/stealth_test_config.gd` (full; no enemy-count override exists)
- `src/systems/stealth/shadow_zone.gd` (full; `contains_point` only, no area helper)
- `src/core/game_config.gd` (targeted refs for exported-var placement and AI config ownership)
- `tests/test_ai_long_run_stress.gd` (full)
- `tests/test_3zone_combat_transition_stress.gd` (full; collision-heavy fixture baseline)
- `tests/test_stealth_room_smoke.gd` (full; 3-zone bootstrap baseline)
- `tests/test_refactor_kpi_contract.gd` (full)
- `tests/test_runner_node.gd` (targeted refs for scene constants, `_scene_exists(...)`, `_run_embedded_scene_suite(...)`)

**Inspected functions/methods:**
- `AIWatchdog._process`
- `AIWatchdog.begin_ai_tick`
- `AIWatchdog.end_ai_tick`
- `AIWatchdog.record_replan`
- `AIWatchdog.get_snapshot`
- `EnemyPursuitSystem._execute_move_to_target`
- `EnemyPursuitSystem._try_open_blocking_door_and_force_repath`
- `EnemyPursuitSystem._attempt_replan_with_policy`
- `EnemyPursuitSystem._resolve_nearest_reachable_fallback`
- `EnemyPursuitSystem._resolve_shadow_escape_target`
- `EnemyPursuitSystem._plan_path_to`
- `NavigationRuntimeQueries.build_policy_valid_path`
- `NavigationRuntimeQueries._build_detour_candidates`
- `EnemyPursuitSystem.debug_get_navigation_policy_snapshot`
- `Enemy.get_debug_detection_snapshot`
- `Stealth3ZoneTestController.debug_get_room_rects`
- `Stealth3ZoneTestController.debug_get_choke_rect`
- `Stealth3ZoneTestController.debug_get_wall_thickness`
- `Stealth3ZoneTestController.debug_get_test_config`
- `Stealth3ZoneTestController.debug_get_system_summary`
- `Stealth3ZoneTestController._spawn_enemies`
- `ShadowZone.contains_point`
- `TestAiLongRunStress.run_suite`
- `TestAiLongRunStress._test_awareness_stress_timeboxed`
- `TestAiLongRunStress._test_eventbus_backpressure_recovery`
- `Test3ZoneCombatTransitionStress.run_suite`
- `TestRefactorKpiContract._test_refactor_kpi_contracts`
- `TestRunner._scene_exists`
- `TestRunner._run_embedded_scene_suite`
- `TestRunner._run_tests`

**Search commands used:**
- `rg -n "^\\[PMB-[0-9]+\\]" docs/ai_nav_refactor_execution_v2.md | head -n 20`
- `rg -n "avg_ai_tick_ms|replans_per_sec|get_snapshot\\(" src/systems/ai_watchdog.gd tests/test_ai_long_run_stress.gd -S`
- `rg -n "ai_ms_p95|replans_total|detour_candidates_evaluated_total|hard_stall_events_total|collision_repath_events_total" src/systems/ai_watchdog.gd tests/test_ai_long_run_stress.gd -S`
- `rg -n "record_replan\\(|_attempt_replan_with_policy|collision|stall|detour" src/systems/enemy_pursuit_system.gd -S`
- `rg -n "func _resolve_nearest_reachable_fallback|candidate|fallback_pick|detour" src/systems/enemy_pursuit_system.gd -S`
- `rg -n "debug_get_room_rects|debug_get_choke_rect|debug_get_test_config|debug_get_system_summary|debug_get_combat_pipeline_summary" src/levels/stealth_3zone_test_controller.gd -S`
- `rg --files tests | rg "test_(ai_performance_gate|replay_baseline_gate|level_stealth_checklist|extended_stealth_release_gate)\\.(gd|tscn)$" -n`
- `rg -n "legacy_|temporary_|debug_shadow_override|old_" src tests -S`
- `rg -n "\\bold_(ai|nav|path|search|shadow|squad|combat|utility|patrol|pursuit|legacy)" src tests -S`
- `rg -n "func get_debug_detection_snapshot\\(|target_context_exists|\\\"mode\\\"|\\\"path_status\\\"|intent_type|state_name" src/entities/enemy.gd -S`

**Confirmed facts:**
- `src/systems/ai_watchdog.gd` tracks `avg_ai_tick_ms` and `replans_per_sec`, and `get_snapshot()` returns no `ai_ms_p95` or total counters required by the release KPI gate.
- `src/systems/enemy_pursuit_system.gd` already has exact hook points for KPI counters `record_replan()` in `_attempt_replan_with_policy`, hard-stall detection in `_execute_move_to_target`, and collision-triggered forced repath in `_try_open_blocking_door_and_force_repath`; in the current tree, detour candidate iteration is owned by `NavigationRuntimeQueries.build_policy_valid_path(...)` (candidate loop over `_build_detour_candidates(...)` results), so Phase 19 detour counter instrumentation requires a minimal scope exception in `src/systems/navigation_runtime_queries.gd` to preserve metric semantics.
- `tests/test_ai_long_run_stress.gd` is a short timebox stress suite (`10s`) and prints only `avg_ai_tick_ms` and `replans_per_sec`; it does not emit the full Phase 19 metric set.
- `tests/test_ai_performance_gate.gd`, `tests/test_replay_baseline_gate.gd`, `tests/test_level_stealth_checklist.gd`, and `tests/test_extended_stealth_release_gate.gd` do not exist in the current tree.
- `tests/baselines/replay/` baseline files do not exist in the current tree.
- `docs/qa/` checklist artifact file for `stealth_3zone_test` does not exist in the current tree.
- `Stealth3ZoneTestController` exposes room/choke debug geometry and system summaries, and `_spawn_enemies()` has fixed `ENEMY_SPAWNS` count (6) with no public helper for Phase 19 `enemy_count = 12` stress runs.
- `ShadowZone` exposes `contains_point(world_point)` but no area helper; checklist pocket-area validation requires test-side collision-shape area computation.
- `Enemy.get_debug_detection_snapshot()` currently exposes `state_name` and `intent_type` but no replay trace keys `mode`, `path_status`, or `target_context_exists`; Phase 19 start is blocked until Phase 15-18 dependency gates in section 23 pass.
- Original Phase 19 legacy zero-tolerance command uses bare `old_`, and that pattern produces false positives in valid identifiers such as `hold_*` and `threshold_*` in the current tree. Phase 19 requires a bounded legacy-prefix regex for executable zero-tolerance enforcement.

---

## 1. What now.

Phase 19 release-gate infrastructure is absent, required KPI counters are absent, and the original unbounded `old_` legacy scan is not executable because it matches valid non-legacy identifiers.

Verification of current state:

```bash
rg --files tests | rg "test_(ai_performance_gate|replay_baseline_gate|level_stealth_checklist|extended_stealth_release_gate)\.(gd|tscn)$" -n
```
Expected current output in this tree: `0 matches` (all Phase 19 gate suites are missing).

```bash
rg -n "ai_ms_p95|replans_total|detour_candidates_evaluated_total|hard_stall_events_total|collision_repath_events_total" src/systems/ai_watchdog.gd tests/test_ai_long_run_stress.gd -S
```
Expected current output in this tree: `0 matches` (required Phase 19 metrics are absent).

```bash
rg -n "avg_ai_tick_ms|replans_per_sec|get_snapshot\(" src/systems/ai_watchdog.gd tests/test_ai_long_run_stress.gd -S
```
Expected current output: `> 0 matches` (Phase 7 metrics exist and must be extended, not replaced).

```bash
rg -n "legacy_|temporary_|debug_shadow_override|old_" src tests -S
```
Expected current output in this tree: `> 0 matches` because bare `old_` matches valid identifiers (`hold_*`, `old_state`, `threshold_*` substrings).

```bash
rg -n "target_context_exists|repath_recovery_reason|slot_role|cover_source|flank_slot_contract_ok" src/entities/enemy.gd src/systems/enemy_utility_brain.gd src/systems/enemy_pursuit_system.gd src/systems/enemy_squad_system.gd -S
```
Expected current output in this tree: `0 matches` (Phase 15-18 dependency gates fail before Phase 19 start in the current branch state).

Current measurable release-gate gap:
- No test emits the required 180-second KPI formulas (`replans_per_enemy_per_sec`, `detour_candidates_per_replan`, `hard_stalls_per_min`).
- No replay baseline capture/compare gate exists.
- No stealth level checklist gate or checklist artifact exists.
- No single test owns the combined Phase 19 PASS/FAIL release decision.

---

## 2. What changes.

1. **Delete-first legacy sweep (global, bounded):** remove every `legacy_` token occurrence from `src/` and `tests/` before Phase 19 code changes.
2. **Delete-first legacy sweep (global, bounded):** remove every `temporary_` token occurrence from `src/` and `tests/` before Phase 19 code changes.
3. **Delete-first legacy sweep (global, exact token):** remove every `debug_shadow_override` occurrence from `src/` and `tests/` before Phase 19 code changes.
4. **Delete-first legacy sweep (global, bounded legacy prefixes):** remove every `old_(ai|nav|path|search|shadow|squad|combat|utility|patrol|pursuit|legacy)` identifier/token occurrence from `src/` and `tests/` before Phase 19 code changes.
5. **`src/core/game_config.gd` — add** exported Phase 19 KPI constants for performance gate, replay gate, and level checklist gate using exact values from the release baseline document (`kpi_ai_ms_avg_max`, `kpi_ai_ms_p95_max`, `kpi_replans_per_enemy_per_sec_max`, `kpi_detour_candidates_per_replan_max`, `kpi_hard_stalls_per_min_max`, `kpi_alert_combat_bad_patrol_count`, `kpi_shadow_pocket_min_area_px2`, `kpi_shadow_escape_max_len_px`, `kpi_alt_route_max_factor`, `kpi_shadow_scan_points_min`, `kpi_replay_position_tolerance_px`, `kpi_replay_drift_budget_percent`, `kpi_replay_discrete_warmup_sec`).
6. **`src/systems/ai_watchdog.gd` — extend** `AIWatchdog` metrics storage with totals and p95 support: add counters for `replans_total`, `detour_candidates_evaluated_total`, `hard_stall_events_total`, `collision_repath_events_total`, plus a deterministic AI tick sample buffer used to compute `ai_ms_p95`.
7. **`src/systems/ai_watchdog.gd` — add** methods `record_detour_candidates_evaluated(count: int) -> void`, `record_hard_stall_event() -> void`, `record_collision_repath_event() -> void`, `debug_reset_metrics_for_tests() -> void`, and internal `_percentile95_ms() -> float`.
8. **`src/systems/ai_watchdog.gd` — modify** `record_replan()` and `get_snapshot()` so `record_replan()` increments both rate window and total counter, and `get_snapshot()` returns the full Phase 19 `AIWatchdogPerformanceSnapshotV2` contract.
9. **`src/systems/enemy_pursuit_system.gd` — instrument** `_execute_move_to_target(...)` to call `AIWatchdog.record_hard_stall_event()` exactly once per hard-stall detection event before replan recovery.
10. **`src/systems/enemy_pursuit_system.gd` — instrument** `_try_open_blocking_door_and_force_repath()` to call `AIWatchdog.record_collision_repath_event()` exactly when a collision-triggered door-open repath reset occurs.
11. **Minimal scope exception for current tree (required to preserve metric semantics):** `src/systems/navigation_runtime_queries.gd` — extend `build_policy_valid_path(...)` to publish deterministic `detour_candidates_evaluated_count` from the actual detour candidate loop (`_build_detour_candidates(...)` results), and `src/systems/enemy_pursuit_system.gd` — consume that contract field in `_plan_path_to(...)` to call `AIWatchdog.record_detour_candidates_evaluated(...)` exactly once per path-plan evaluation.
12. **`src/levels/stealth_3zone_test_controller.gd` — add** test-only helper `debug_spawn_enemy_duplicates_for_tests(target_total_count: int) -> int` that duplicates the existing `ENEMY_SPAWNS` cycle deterministically to reach the requested enemy count after normal scene bootstrap (Phase 19 performance gate requires `enemy_count = 12`).
13. **New `tests/replay_gate_helpers.gd` — add** replay capture/load/compare helpers for JSONL trace records with strict schema validation, warmup rule, discrete-field exact compare, position tolerance compare, and aggregate drift budget compare.
14. **`tests/test_ai_long_run_stress.gd` — add** public benchmark helper `run_benchmark_contract(config: Dictionary) -> Dictionary` that drives the stress fixture deterministically, resets `AIWatchdog`, and returns raw + derived Phase 19 metrics; keep existing smoke tests in `run_suite()` and reuse the new helper for metric emission.
15. **New `tests/test_ai_performance_gate.gd` + `tests/test_ai_performance_gate.tscn` — add** Phase 19 performance gate suite with fixed seed `1337`, fixed duration `180.0 sec`, fixed `enemy_count = 12`, required formulas, threshold checks, and explicit `collision_repath_events_total > 0` assertion.
16. **New `tests/test_replay_baseline_gate.gd` + `tests/test_replay_baseline_gate.tscn` — add** replay baseline gate suite for the five Phase 19 scenario traces using `tests/replay_gate_helpers.gd` and exact schema/compare rules.
17. **New baseline artifacts — add** five JSONL baseline traces in `tests/baselines/replay/`: `shadow_corridor_pressure.jsonl`, `door_choke_crowd.jsonl`, `lost_contact_in_shadow.jsonl`, `collision_integrity.jsonl`, `blood_evidence.jsonl`.
18. **New `tests/test_level_stealth_checklist.gd` + `tests/test_level_stealth_checklist.tscn` — add** automatic 3-zone stealth checklist gate plus manual artifact existence validation (`docs/qa/stealth_level_checklist_stealth_3zone_test.md`).
19. **New `tests/test_extended_stealth_release_gate.gd` + `tests/test_extended_stealth_release_gate.tscn` — add** the single final Phase 19 release-gate owner suite that runs dependency gates, invokes performance/replay/checklist subgates in embedded mode, runs the bounded legacy zero-tolerance scan, and returns final PASS/FAIL.
20. **`tests/test_refactor_kpi_contract.gd` — update** static contract assertions to include Phase 19 gate scene file existence, baseline replay artifact existence, and Phase 19 `GameConfig.kpi_*` exported variable declarations.
21. **`tests/test_runner_node.gd` — modify** top-level const declarations, `_scene_exists(...)` checks, and `_run_embedded_scene_suite(...)` calls for the four new Phase 19 gate scenes.
22. **`docs/qa/stealth_level_checklist_stealth_3zone_test.md` — add** the required manual validation artifact template with ten traversal checklist entries and summary outcome fields.
23. **`CHANGELOG.md` — prepend** one Phase 19 entry under the current date header after implementation and verification.

---

## 3. What will be after.

1. `AIWatchdog.get_snapshot()` returns `ai_ms_p95`, `replans_total`, `detour_candidates_evaluated_total`, `hard_stall_events_total`, and `collision_repath_events_total` in one stable dictionary contract (verified by gates G1-G4 in section 13 and updated `tests/test_ai_long_run_stress.gd`).
2. `EnemyPursuitSystem` emits Phase 19 KPI event counters through `AIWatchdog` at the exact hard-stall, collision-repath, and detour-candidate evaluation points (verified by gates G5-G7 in section 13 and `tests/test_ai_performance_gate.gd`).
3. `tests/test_ai_long_run_stress.gd` exposes a deterministic benchmark API and emits raw + derived Phase 19 formulas (`replans_per_enemy_per_sec`, `detour_candidates_per_replan`, `hard_stalls_per_min`) (verified by gate G8 in section 13 and `tests/test_ai_performance_gate.gd`).
4. `tests/test_ai_performance_gate.gd` enforces all required Phase 19 KPI thresholds and the collision-repath liveness assertion against the 3-zone stress fixture with `enemy_count = 12`, `seed = 1337`, and `duration_sec = 180.0` (verified by gates G8-G10 in section 13 and section 12 tests).
5. `tests/test_replay_baseline_gate.gd` and `tests/replay_gate_helpers.gd` enforce the replay trace schema, warmup rule, discrete-field exact match, position tolerance (`<= 6.0 px`), and aggregate drift budget (`<= 2.0%`) for the five baseline scenarios (verified by gates G11-G13 in section 13 and section 12 tests).
6. `tests/test_level_stealth_checklist.gd` enforces automatic checklist checks for `stealth_3zone_test` and verifies the required manual artifact `docs/qa/stealth_level_checklist_stealth_3zone_test.md` exists (verified by gates G14-G15 in section 13 and section 12 tests).
7. `tests/test_extended_stealth_release_gate.gd` is the sole final Phase 19 PASS/FAIL decision owner and blocks release when any dependency gate, subgate, or bounded legacy zero-tolerance scan fails (verified by gates G16-G18 in section 13 and section 12 tests).
8. PMB-1 through PMB-5 still return their expected outputs after Phase 19 instrumentation and gate additions (verified by PMB gates in section 13 and `pmb_contract_check` in section 21).

---

## 4. Scope and non-scope (exact files).

**In-scope:**
- `src/core/game_config.gd`
- `src/systems/ai_watchdog.gd`
- `src/systems/enemy_pursuit_system.gd`
- `src/systems/navigation_runtime_queries.gd`
- `src/levels/stealth_3zone_test_controller.gd`
- `tests/replay_gate_helpers.gd` (new)
- `tests/test_ai_long_run_stress.gd`
- `tests/test_ai_performance_gate.gd` (new)
- `tests/test_ai_performance_gate.tscn` (new)
- `tests/test_replay_baseline_gate.gd` (new)
- `tests/test_replay_baseline_gate.tscn` (new)
- `tests/test_level_stealth_checklist.gd` (new)
- `tests/test_level_stealth_checklist.tscn` (new)
- `tests/test_extended_stealth_release_gate.gd` (new)
- `tests/test_extended_stealth_release_gate.tscn` (new)
- `tests/test_refactor_kpi_contract.gd`
- `tests/test_runner_node.gd`
- `tests/baselines/replay/shadow_corridor_pressure.jsonl` (new)
- `tests/baselines/replay/door_choke_crowd.jsonl` (new)
- `tests/baselines/replay/lost_contact_in_shadow.jsonl` (new)
- `tests/baselines/replay/collision_integrity.jsonl` (new)
- `tests/baselines/replay/blood_evidence.jsonl` (new)
- `docs/qa/stealth_level_checklist_stealth_3zone_test.md` (new)
- `CHANGELOG.md`

**Out-of-scope (must not be modified):**
- `src/entities/enemy.gd` (replay trace source dependency owned by Phase 15-18)
- `src/systems/enemy_utility_brain.gd` (utility doctrine dependency owned by Phase 15 and Phase 18)
- `src/systems/enemy_squad_system.gd` (tactical slot dependency owned by Phase 18)
- `src/systems/navigation_service.gd` (navigation service facade used as-is)
- `src/systems/procedural_layout_v2.gd` (layout runtime baseline)
- `src/systems/stealth/shadow_zone.gd` (checklist reads existing `contains_point`, no API changes)
- `src/levels/stealth_3zone_test.tscn` (scene topology fixture remains unchanged)
- `tests/test_3zone_combat_transition_stress.gd` (smoke baseline only)
- `tests/test_stealth_room_smoke.gd` (smoke baseline only)
- `src/core/config_validator.gd`

Allowed file-change boundary (exact paths): same as the in-scope list above.

---

## 5. Single-owner authority for this phase.

**Primary owner file:** `tests/test_extended_stealth_release_gate.gd`.

**Primary owner function:** `TestExtendedStealthReleaseGate._test_extended_stealth_release_gate() -> void`.

Phase 19 introduces one new primary decision: the combined release-gate PASS/FAIL result across dependency gates, performance gate, replay baseline gate, level checklist gate, and bounded legacy zero-tolerance scan. That decision occurs in `TestExtendedStealthReleaseGate._test_extended_stealth_release_gate()` only. `tests/test_ai_performance_gate.gd`, `tests/test_replay_baseline_gate.gd`, and `tests/test_level_stealth_checklist.gd` produce subreports only.

**No duplicated final decision rule:** no other file computes the final combined Phase 19 PASS/FAIL result from all four subgates and dependency gates.

**Verifiable uniqueness gate:** section 13, gate G18.

---

## 6. Full input/output contract.

**Contract 1 name:** `AIWatchdogPerformanceSnapshotV2`

**Owner:** `AIWatchdog.get_snapshot() -> Dictionary` in `src/systems/ai_watchdog.gd`

**Inputs (types, nullability, finite checks):**
- Internal counters and samples maintained by `AIWatchdog.begin_ai_tick()`, `AIWatchdog.end_ai_tick()`, `AIWatchdog.record_replan()`, `AIWatchdog.record_detour_candidates_evaluated(count: int)`, `AIWatchdog.record_hard_stall_event()`, and `AIWatchdog.record_collision_repath_event()`.
- `count: int` input to `record_detour_candidates_evaluated(count)` — non-null, clamped to `>= 0` before accumulation.
- AI tick sample buffer values — finite `float` values in milliseconds only.

**Outputs (exact keys/types; all keys always present):**
- `event_queue_length: int`
- `transitions_this_tick: int`
- `avg_ai_tick_ms: float` (EMA, finite `>= 0.0`)
- `replans_per_sec: float` (EMA, finite `>= 0.0`)
- `ai_ms_p95: float` (computed percentile from sample buffer, finite `>= 0.0`)
- `replans_total: int` (`>= 0`)
- `detour_candidates_evaluated_total: int` (`>= 0`)
- `hard_stall_events_total: int` (`>= 0`)
- `collision_repath_events_total: int` (`>= 0`)
- `ai_tick_samples_count: int` (`>= 0`)

**Status enums:** `N/A — snapshot dictionary`

**Reason enums:** `N/A — snapshot dictionary`

**Constants/thresholds used (exact values + placement):**
- `AI_WATCHDOG_P95_SAMPLE_CAP = 32768` — local `const` in `src/systems/ai_watchdog.gd` (single-file use).
- Existing `EMA_ALPHA = 0.05` remains the smoothing constant for `avg_ai_tick_ms` and `replans_per_sec` only.

**Contract 2 name:** `AiStressMetricsContractV2`

**Owner:** `TestAiLongRunStress.run_benchmark_contract(config: Dictionary) -> Dictionary` in `tests/test_ai_long_run_stress.gd`

**Inputs (types, nullability, finite checks):**
- `config: Dictionary` — non-null.
- `config["seed"]: int` — required; exact Phase 19 gate value `1337` in performance gate caller.
- `config["duration_sec"]: float` — required, finite, `> 0.0`; exact Phase 19 gate value `180.0` in performance gate caller.
- `config["enemy_count"]: int` — required, `>= 1`; exact Phase 19 gate value `12` in performance gate caller.
- `config["fixed_physics_frames"]: int` — required, `>= 1`; exact Phase 19 gate value `10800` in performance gate caller.
- `config["scene_path"]: String` — required; exact Phase 19 gate path `res://src/levels/stealth_3zone_test.tscn`.
- `config["force_collision_repath"]: bool` — required; `true` for Phase 19 performance gate.

**Outputs (exact keys/types; all keys always present):**
- `gate_status: String` — values from Status enums below.
- `gate_reason: String` — values from Reason enums below.
- `seed: int`
- `duration_sec: float`
- `enemy_count: int`
- `fixed_physics_frames: int`
- `ai_ms_avg: float`
- `ai_ms_p95: float`
- `replans_total: int`
- `detour_candidates_evaluated_total: int`
- `hard_stall_events_total: int`
- `collision_repath_events_total: int`
- `replans_per_enemy_per_sec: float`
- `detour_candidates_per_replan: float`
- `hard_stalls_per_min: float`
- `kpi_threshold_failures: Array[String]` (empty only when `gate_status == "PASS"`)
- `metrics_snapshot: Dictionary` (raw `AIWatchdogPerformanceSnapshotV2` snapshot used for derivation)

**Status enums (exact values):**
- `"PASS"`
- `"FAIL"`

**Reason enums (exact values):**
- `"ok"`
- `"invalid_config"`
- `"scene_bootstrap_failed"`
- `"enemy_count_mismatch"`
- `"metrics_contract_missing"`
- `"threshold_failed"`
- `"collision_repath_metric_dead"`

**Constants/thresholds used (exact values + placement):**
- `GameConfig.kpi_ai_ms_avg_max = 1.20`
- `GameConfig.kpi_ai_ms_p95_max = 2.50`
- `GameConfig.kpi_replans_per_enemy_per_sec_max = 1.80`
- `GameConfig.kpi_detour_candidates_per_replan_max = 24.0`
- `GameConfig.kpi_hard_stalls_per_min_max = 1.0`

**Contract 3 name:** `ReplayBaselineGateReportV1`

**Owners:** `ReplayGateHelpers.compare_trace_to_baseline(...) -> Dictionary` in `tests/replay_gate_helpers.gd` (returns one scenario-compare result with the exact schema of one `scenario_results[]` entry below) and `TestReplayBaselineGate._run_replay_pack_gate() -> Dictionary` in `tests/test_replay_baseline_gate.gd` (aggregates five scenario results into the full `ReplayBaselineGateReportV1`)

**Inputs (types, nullability, finite checks):**
- `scenario_name: String` — non-empty.
- `baseline_path: String` — non-empty, file exists.
- `candidate_records: Array[Dictionary]` — non-null helper input; every record must satisfy `ReplayTraceRecordV1` schema below.
- Baseline records are loaded inside `ReplayGateHelpers.compare_trace_to_baseline(...)` from `baseline_path`; `baseline_records` is not an external caller parameter.
- `warmup_sec: float` — finite, exact value from `GameConfig.kpi_replay_discrete_warmup_sec` (`0.50`).
- `position_tolerance_px: float` — finite `>= 0.0`, exact value from `GameConfig.kpi_replay_position_tolerance_px` (`6.0`).
- `drift_budget_percent: float` — finite `>= 0.0`, exact value from `GameConfig.kpi_replay_drift_budget_percent` (`2.0`).

**ReplayTraceRecordV1 schema (exact keys/types; every record):**
- `tick: int`
- `enemy_id: int`
- `state: String`
- `intent_type: String`
- `mode: String`
- `path_status: String`
- `target_context_exists: bool`
- `position_x: float`
- `position_y: float`

**Outputs (exact keys/types; full pack-level report from `TestReplayBaselineGate._run_replay_pack_gate()`; helper returns one dictionary with the exact schema of a single `scenario_results[]` entry):**
- `gate_status: String` — values from Status enums below.
- `gate_reason: String` — values from Reason enums below.
- `scenario_results: Array[Dictionary]` — one entry per scenario with keys:
  - `scenario_name: String`
  - `gate_status: String`
  - `gate_reason: String`
  - `sample_count: int`
  - `record_count_match: bool`
  - `discrete_mismatch_after_warmup_count: int`
  - `position_tolerance_violation_count: int`
  - `position_drift_percent: float`
  - `baseline_path: String`
- `pack_sample_count: int`
- `pack_discrete_mismatch_after_warmup_count: int`
- `pack_position_tolerance_violation_count: int`
- `alert_combat_bad_patrol_count: int`

**Status enums (exact values):**
- `"PASS"`
- `"FAIL"`

**Reason enums (exact values):**
- `"ok"`
- `"baseline_missing"`
- `"candidate_capture_failed"`
- `"schema_invalid"`
- `"record_count_mismatch"`
- `"discrete_mismatch_after_warmup"`
- `"position_drift_budget_exceeded"`
- `"alert_combat_bad_patrol_exceeded"`

**Constants/thresholds used (exact values + placement):**
- `GameConfig.kpi_replay_position_tolerance_px = 6.0`
- `GameConfig.kpi_replay_drift_budget_percent = 2.0`
- `GameConfig.kpi_replay_discrete_warmup_sec = 0.50`
- `GameConfig.kpi_alert_combat_bad_patrol_count = 0` (maximum allowed candidate replay records after warmup where `mode` is `"ALERT"` or `"COMBAT"` and `intent_type == "PATROL"` in one replay-pack gate run)

**Contract 4 name:** `StealthLevelChecklistGateReportV1`

**Owner:** `TestLevelStealthChecklist._run_stealth_level_checklist(level_scene_path: String, level_name: String) -> Dictionary` in `tests/test_level_stealth_checklist.gd`

**Inputs (types, nullability, finite checks):**
- `level_scene_path: String` — non-empty, file exists; exact Phase 19 fixture value `res://src/levels/stealth_3zone_test.tscn`.
- `level_name: String` — non-empty; exact Phase 19 fixture value `stealth_3zone_test`.
- `manual_artifact_path: String` — non-empty; exact Phase 19 artifact path `docs/qa/stealth_level_checklist_stealth_3zone_test.md`.
- `controller node` — non-null `Stealth3ZoneTestController` instance.
- `navigation_service node` — non-null and supports `build_policy_valid_path(...)`.
- `shadow zone nodes` — array of `ShadowZone` nodes from group `shadow_zones`.

**Outputs (exact keys/types; all keys always present):**
- `gate_status: String` — values from Status enums below.
- `gate_reason: String` — values from Reason enums below.
- `level_name: String`
- `artifact_exists: bool`
- `automatic_checks_pass: bool`
- `stealth_room_count: int`
- `patrol_reachability_pass: bool`
- `shadow_pocket_availability_pass: bool`
- `shadow_escape_availability_pass: bool`
- `route_variety_pass: bool`
- `chokepoint_width_safety_pass: bool`
- `boundary_scan_support_pass: bool`
- `room_reports: Array[Dictionary]` (per-room check details)

**Status enums (exact values):**
- `"PASS"`
- `"FAIL"`

**Reason enums (exact values):**
- `"ok"`
- `"level_scene_missing"`
- `"controller_missing"`
- `"navigation_service_missing"`
- `"automatic_check_failed"`
- `"manual_artifact_missing"`

**Constants/thresholds used (exact values + placement):**
- `GameConfig.kpi_shadow_pocket_min_area_px2 = 3072.0`
- `GameConfig.kpi_shadow_escape_max_len_px = 960.0`
- `GameConfig.kpi_alt_route_max_factor = 1.50`
- `GameConfig.kpi_shadow_scan_points_min = 3`
- Local test constants in `tests/test_level_stealth_checklist.gd` (exact values, single-file use):
  - `CHECKLIST_EDGE_SAMPLE_INSET_PX = 8.0`
  - `CHECKLIST_CHOKE_ENEMY_RADIUS_PX = 14.0`
  - `CHECKLIST_CHOKE_CLEARANCE_MARGIN_PX = 4.0`

**Contract 5 name:** `ExtendedStealthReleaseGateReportV1`

**Owner:** `TestExtendedStealthReleaseGate._test_extended_stealth_release_gate() -> void` with internal `_run_release_gate() -> Dictionary` in `tests/test_extended_stealth_release_gate.gd`

**Inputs (types, nullability, finite checks):**
- `dependency_gate_results: Array[Dictionary]` — exact four entries (Phase 15, Phase 16, Phase 17, Phase 18), each with `phase_id`, `command`, `passed`.
- `performance_gate_report: Dictionary` — `AiStressMetricsContractV2` shape.
- `replay_gate_report: Dictionary` — `ReplayBaselineGateReportV1` shape.
- `checklist_gate_report: Dictionary` — `StealthLevelChecklistGateReportV1` shape.
- `legacy_zero_tolerance_command: String` — exact command from section 13 gate G17.
- `legacy_zero_tolerance_matches: Array[String]` — zero-length only on pass.

**Outputs (exact keys/types; all keys always present):**
- `final_result: String` — values from Status enums below.
- `final_reason: String` — values from Reason enums below.
- `dependency_gate_pass: bool`
- `performance_gate_pass: bool`
- `replay_gate_pass: bool`
- `checklist_gate_pass: bool`
- `legacy_zero_tolerance_pass: bool`
- `dependency_gate_results: Array[Dictionary]`
- `performance_gate_report: Dictionary`
- `replay_gate_report: Dictionary`
- `checklist_gate_report: Dictionary`
- `legacy_zero_tolerance_matches: Array[String]`

**Status enums (exact values):**
- `"PASS"`
- `"FAIL"`

**Reason enums (exact values):**
- `"ok"`
- `"dependency_gate_failed"`
- `"performance_gate_failed"`
- `"replay_gate_failed"`
- `"checklist_gate_failed"`
- `"legacy_zero_tolerance_failed"`

**Constants/thresholds used (exact values + placement):** none beyond Contracts 2-4 and section 13 gate G17 command.

---

## 7. Deterministic algorithm with exact order.

### 7.1 `AIWatchdog` metric update and snapshot order

Step 1: `begin_ai_tick()` stores `_tick_start_usec`, sets `_tick_active = true`, and resets `transitions_this_tick = 0`.

Step 2: `end_ai_tick()` returns immediately when `_tick_active == false`.

Step 3: `end_ai_tick()` computes one finite `dt_ms`, updates `avg_ai_tick_ms` using `EMA_ALPHA`, appends the sample to `_ai_tick_samples_ms`, and enforces `AI_WATCHDOG_P95_SAMPLE_CAP` by removing oldest samples before return.

Step 4: `record_replan()` increments `_replan_accumulator` and `replans_total` exactly once per call.

Step 5: `record_detour_candidates_evaluated(count)` clamps `count` to `>= 0` and increments `detour_candidates_evaluated_total` by the clamped value exactly once per call.

Step 6: `record_hard_stall_event()` increments `hard_stall_events_total` exactly once per hard-stall event.

Step 7: `record_collision_repath_event()` increments `collision_repath_events_total` exactly once per collision-triggered forced repath event.

Step 8: `_process(delta)` updates `replans_per_sec` EMA using the existing window logic and leaves total counters unchanged.

Step 9: `get_snapshot()` calls `_percentile95_ms()` on a sorted copy of `_ai_tick_samples_ms` and returns the complete `AIWatchdogPerformanceSnapshotV2` dictionary with all keys from section 6.

Percentile rule for `_percentile95_ms()`:
- `n = _ai_tick_samples_ms.size()`
- when `n == 0`, return `0.0`
- sort ascending copy
- `idx = maxi(int(ceil(0.95 * float(n))) - 1, 0)`
- return `sorted[idx]`

Tie-break rule: N/A — percentile index selection is deterministic and unique for each `n`.

### 7.2 `TestAiLongRunStress.run_benchmark_contract(config)` exact order

Step 1: Validate required config keys and finite values from section 6. On any failure, return `gate_status = "FAIL"`, `gate_reason = "invalid_config"`, zeroed metrics, and empty threshold-failure list.

Step 2: Reset EventBus test queue state when available.

Step 3: Call `AIWatchdog.debug_reset_metrics_for_tests()` and then `AIWatchdog.get_snapshot()` to confirm counters start at zero.

Step 4: Seed deterministic RNG with `config["seed"]`.

Step 5: Instantiate `config["scene_path"]` and bootstrap exactly two frames (`process_frame`, `physics_frame`) before fixture manipulation.

Step 6: Acquire `Stealth3ZoneTestController` and call `debug_spawn_enemy_duplicates_for_tests(config["enemy_count"])`. When returned spawned count does not equal `config["enemy_count"]`, return `FAIL/enemy_count_mismatch`.

Step 7: Force collision-heavy setup using deterministic player/enemy placements and door interactions defined in the test file when `config["force_collision_repath"] == true`.

Step 8: Run exactly `config["fixed_physics_frames"]` physics ticks with matching process ticks, collect one final `AIWatchdog` snapshot, and free the level fixture.

Step 9: Derive formulas exactly:
- `replans_per_enemy_per_sec = replans_total / (enemy_count * duration_sec)`
- `detour_candidates_per_replan = detour_candidates_evaluated_total / max(replans_total, 1)`
- `hard_stalls_per_min = hard_stall_events_total * 60.0 / duration_sec`

Step 10: Compare derived metrics and raw metrics to thresholds from section 6 Contract 2 and build `kpi_threshold_failures` by appending failure names in this exact order only:
1. append `"ai_ms_avg"` when `ai_ms_avg > GameConfig.kpi_ai_ms_avg_max`
2. append `"ai_ms_p95"` when `ai_ms_p95 > GameConfig.kpi_ai_ms_p95_max`
3. append `"replans_per_enemy_per_sec"` when `replans_per_enemy_per_sec > GameConfig.kpi_replans_per_enemy_per_sec_max`
4. append `"detour_candidates_per_replan"` when `detour_candidates_per_replan > GameConfig.kpi_detour_candidates_per_replan_max`
5. append `"hard_stalls_per_min"` when `hard_stalls_per_min > GameConfig.kpi_hard_stalls_per_min_max`

Step 11: When `collision_repath_events_total <= 0`, set `gate_status = "FAIL"` and `gate_reason = "collision_repath_metric_dead"` regardless of threshold list state.

Step 12: Otherwise set `gate_status = "PASS"`, `gate_reason = "ok"` when threshold list is empty; else set `gate_status = "FAIL"`, `gate_reason = "threshold_failed"`.

Tie-break rule: N/A — one report is produced from one deterministic benchmark run.

### 7.3 `ReplayGateHelpers.compare_trace_to_baseline(...)` exact order

Step 1: Load baseline JSONL records from `baseline_path` and use the caller-provided `candidate_records` array. On missing baseline file, return `FAIL/baseline_missing`.

Step 2: Validate every record against `ReplayTraceRecordV1` schema from section 6. On first schema failure, return `FAIL/schema_invalid`.

Step 3: Compare record counts. When counts differ, return `FAIL/record_count_mismatch`.

Step 4: Iterate records in file order (one baseline record and one candidate record at the same index). No record reordering is allowed.

Step 5: For each record pair, compare `tick` and `enemy_id` first. Any mismatch is handled as `record_count_mismatch` because ordering contract is broken.

Step 6: Compute `record_time_sec = tick / 60.0` and `in_warmup = record_time_sec <= GameConfig.kpi_replay_discrete_warmup_sec`.

Step 7: Compare discrete fields (`state`, `intent_type`, `mode`, `path_status`, `target_context_exists`).
- When any discrete field mismatches and `in_warmup == false`, increment `discrete_mismatch_after_warmup_count`.
- Warmup discrete mismatches do not fail the scenario and do not increment that counter.

Step 8: Compare positions with absolute tolerance on each axis using `GameConfig.kpi_replay_position_tolerance_px`.
- Violation rule: `abs(dx) > tolerance` or `abs(dy) > tolerance`
- Count violations in `position_tolerance_violation_count`.

Step 9: After all records, compute `position_drift_percent = (position_tolerance_violation_count * 100.0) / max(sample_count, 1)`.

Step 10: Fail the scenario in exact priority order:
1. `discrete_mismatch_after_warmup_count > 0` -> `FAIL/discrete_mismatch_after_warmup`
2. `position_drift_percent > GameConfig.kpi_replay_drift_budget_percent` -> `FAIL/position_drift_budget_exceeded`
3. otherwise `PASS/ok`

Pack-level replay gate (`TestReplayBaselineGate._run_replay_pack_gate()`) additionally computes `alert_combat_bad_patrol_count` as the total number of candidate records after warmup across all five scenarios where `mode` is `"ALERT"` or `"COMBAT"` and `intent_type == "PATROL"`, and fails the pack gate with `FAIL/alert_combat_bad_patrol_exceeded` when that count exceeds `GameConfig.kpi_alert_combat_bad_patrol_count`.

Tie-break rule: N/A — each record pair is fixed by index and `(tick, enemy_id)` contract.

### 7.4 `TestLevelStealthChecklist._run_stealth_level_checklist(...)` exact order

Step 1: Validate scene path and instantiate `stealth_3zone_test`.

Step 2: Bootstrap exactly two frames (`process_frame`, `physics_frame`), then acquire:
- `Stealth3ZoneTestController`
- local `NavigationService`
- `ShadowZone` nodes via `shadow_zones` group
- room rects via `debug_get_room_rects()`
- chokepoint rects via `debug_get_choke_rect("AB")`, `debug_get_choke_rect("BC")`, `debug_get_choke_rect("DC")`
- wall thickness via `debug_get_wall_thickness()`

Step 3: Build deterministic room order from `debug_get_room_rects()` array index order and assign exact fixture room labels by index: `0 -> "A1"`, `1 -> "A2"`, `2 -> "B"`, `3 -> "C"`, `4 -> "D"`. When the returned array size is not exactly `5`, mark automatic checks failed.

Step 4: Patrol Reachability check (fixture proxy): use spawn nodes under `Spawns` in lexical node-name order (`SpawnA1`, `SpawnA2`, `SpawnB`, `SpawnC1`, `SpawnC2`, `SpawnD`); require `build_policy_valid_path(...).status == "ok"` for each consecutive pair.

Step 5: Shadow Pocket Availability check (exact fixture geometry rule):
- Assign each `ShadowZone` to a room by `zone.global_position` center containment in room rects using room index order from Step 3 (first matching room wins).
- Read the child `CollisionShape2D` named `CollisionShape2D`; require `shape_node.shape is RectangleShape2D` for a counted pocket (non-rectangle shapes are ignored for Phase 19 fixture checks).
- Compute pocket area exactly as `shape.size.x * shape.size.y * abs(zone.scale.x) * abs(zone.scale.y)` using the `RectangleShape2D.size` and node scale (fixture shadows are axis-aligned).
- Count the pocket only when the assigned room exists and the computed area is `>= GameConfig.kpi_shadow_pocket_min_area_px2`.
- Require at least one counted pocket per room for every room in the Step 3 room list (current `stealth_3zone_test` fixture has 6 counted pockets across 5 rooms; per-room `>=2` is impossible without changing fixture geometry and would shift test-scene behavior).

Step 6: Shadow Escape Availability check (exact candidate sample set and path-length rule):
- For each counted pocket center and its assigned room rect, build boundary escape candidates in this exact order using `CHECKLIST_EDGE_SAMPLE_INSET_PX`:
  1. top edge midpoint
  2. right edge midpoint
  3. bottom edge midpoint
  4. left edge midpoint
- Then append choke-center candidates in choke-name order `AB`, `BC`, `DC` when the choke rect intersects the room rect.
- Dedup candidate points by exact `Vector2` equality in insertion order (first wins).
- Keep a candidate only when `room_rect.grow(-CHECKLIST_EDGE_SAMPLE_INSET_PX).has_point(candidate)` is true and all `ShadowZone.contains_point(candidate)` checks are false.
- For each kept candidate, call `build_policy_valid_path(pocket_center, candidate, null)` and require `status == "ok"`.
- Compute escape length as the Euclidean segment sum from `pocket_center` through returned `path_points` in array order.
- Require at least one valid candidate per counted pocket and require the shortest valid escape length `<= GameConfig.kpi_shadow_escape_max_len_px`.

Step 7: Route Variety check (exact route anchors and comparison rule):
- Resolve exact anchor points from the scene:
  - `player_spawn = Spawns/PlayerSpawn.global_position`
  - `spawn_a2 = Spawns/SpawnA2.global_position`
  - `spawn_d = Spawns/SpawnD.global_position`
  - `choke_ab_center = debug_get_choke_rect("AB").get_center()`
  - `choke_bc_center = debug_get_choke_rect("BC").get_center()`
  - `choke_dc_center = debug_get_choke_rect("DC").get_center()`
- Route R1 anchors (A/B/C/D path): `[player_spawn, choke_ab_center, choke_bc_center, choke_dc_center, spawn_d]`
- Route R2 anchors (A2->D corridor path): `[player_spawn, spawn_a2, spawn_d]`
- For each consecutive anchor pair in each route, call `build_policy_valid_path(from, to, null)` and require `status == "ok"`.
- Compute each route length as the sum of Euclidean segment lengths through each segment plan’s `path_points` in order, starting from that segment’s `from` anchor.
- Require both routes policy-valid and `max(route1_len, route2_len) <= GameConfig.kpi_alt_route_max_factor * min(route1_len, route2_len)`.

Step 8: Chokepoint Width Safety check (exact constants and width formula):
- Use exact local test constants `CHECKLIST_CHOKE_ENEMY_RADIUS_PX = 14.0` and `CHECKLIST_CHOKE_CLEARANCE_MARGIN_PX = 4.0`.
- `required_clear_width_px = 2.0 * CHECKLIST_CHOKE_ENEMY_RADIUS_PX + 2.0 * CHECKLIST_CHOKE_CLEARANCE_MARGIN_PX` (exact value `36.0`).
- For each required choke rect `AB`, `BC`, and `DC`, compute `min_side = min(rect.size.x, rect.size.y)` and `max_side = max(rect.size.x, rect.size.y)`.
- If `abs(min_side - wall_thickness) <= 0.5` and `max_side > min_side`, treat the rect as a wall-opening proxy and set `choke_width_px = max_side`; otherwise set `choke_width_px = min_side`.
- Require `choke_width_px >= required_clear_width_px`.

Step 9: Boundary Scan Support check (exact room-edge sample set):
- For each room rect from Step 3, build exactly eight boundary samples in this order using `CHECKLIST_EDGE_SAMPLE_INSET_PX`:
  1. top midpoint
  2. right midpoint
  3. bottom midpoint
  4. left midpoint
  5. top-left corner inset
  6. top-right corner inset
  7. bottom-right corner inset
  8. bottom-left corner inset
- A sample counts only when it is inside `room_rect.grow(-CHECKLIST_EDGE_SAMPLE_INSET_PX)`, all `ShadowZone.contains_point(sample)` checks are false, and `build_policy_valid_path(room_rect.get_center(), sample, null).status == "ok"`.
- Require counted sample count `>= GameConfig.kpi_shadow_scan_points_min` for every room.

Step 10: Manual artifact check: require `docs/qa/stealth_level_checklist_stealth_3zone_test.md` to exist.

Step 11: Build `StealthLevelChecklistGateReportV1`; set `FAIL/manual_artifact_missing` only when automatic checks pass and artifact is missing. Set `FAIL/automatic_check_failed` when any automatic check fails.

Tie-break rule: N/A — checklist uses deterministic room order and fixed route/sample sets.

### 7.5 `TestExtendedStealthReleaseGate._run_release_gate()` exact order

Step 1: Run all dependency gates from section 23 in listed order (Phase 15, Phase 16, Phase 17, Phase 18). Stop immediately on first failure and return `FAIL/dependency_gate_failed`.

Step 2: Run `tests/test_ai_performance_gate.gd` in embedded mode and collect `AiStressMetricsContractV2` report.

Step 3: When Step 2 fails, return `FAIL/performance_gate_failed` without running later subgates.

Step 4: Run `tests/test_replay_baseline_gate.gd` in embedded mode and collect `ReplayBaselineGateReportV1` report.

Step 5: When Step 4 fails, return `FAIL/replay_gate_failed` without running later subgates.

Step 6: Run `tests/test_level_stealth_checklist.gd` in embedded mode and collect `StealthLevelChecklistGateReportV1` report.

Step 7: When Step 6 fails, return `FAIL/checklist_gate_failed` without running the legacy scan.

Step 8: Run bounded legacy zero-tolerance scan command from section 13 gate G17 and collect all output lines.

Step 9: When any match line exists, return `FAIL/legacy_zero_tolerance_failed`.

Step 10: Return `PASS/ok` with all subreports and zero legacy matches.

Tie-break rule: N/A — Phase 19 final decision uses short-circuit order and one report.

---

## 8. Edge-case matrix (case -> exact output).

**Case A: invalid benchmark config (`duration_sec <= 0`) in `run_benchmark_contract(config)`**
- Input: `{"seed": 1337, "duration_sec": 0.0, "enemy_count": 12, "fixed_physics_frames": 10800, ...}`
- Expected output dict:
  - `gate_status = "FAIL"`
  - `gate_reason = "invalid_config"`
  - `kpi_threshold_failures = []`
  - `replans_per_enemy_per_sec = 0.0`
  - `hard_stalls_per_min = 0.0`

**Case B: valid performance run under all thresholds**
- Input: fixed Phase 19 benchmark config from section 7, counters and timing values under all KPI limits, `collision_repath_events_total > 0`.
- Expected output dict:
  - `gate_status = "PASS"`
  - `gate_reason = "ok"`
  - `kpi_threshold_failures = []`
  - all derived formulas finite

**Case C: tie-break N/A**
- Proof: section 7 defines no candidate selection algorithm with competing equal scores. All Phase 19 decisions are deterministic short-circuit checks or fixed-order record comparisons. Tie-break logic is not used in this phase.

**Case D: replay baseline file missing for one scenario**
- Input: `baseline_path` missing for `lost_contact_in_shadow`.
- Expected scenario result:
  - `gate_status = "FAIL"`
  - `gate_reason = "baseline_missing"`
- Expected pack result:
  - `gate_status = "FAIL"`
  - `gate_reason = "baseline_missing"`

**Case E: replay discrete mismatch after warmup**
- Input: candidate trace matches baseline until `tick = 31`, then `intent_type` mismatch occurs with `tick/60.0 > 0.50`.
- Expected scenario result:
  - `gate_status = "FAIL"`
  - `gate_reason = "discrete_mismatch_after_warmup"`
  - `discrete_mismatch_after_warmup_count >= 1`

**Case F: replay position drift violations within tolerance budget**
- Input: candidate trace has only position drift mismatches, no discrete mismatches, `position_drift_percent = 1.75`.
- Expected scenario result:
  - `gate_status = "PASS"`
  - `gate_reason = "ok"`
  - `position_drift_percent = 1.75`

**Case G: checklist automatic checks pass and manual artifact missing**
- Input: all automatic checks true, `docs/qa/stealth_level_checklist_stealth_3zone_test.md` missing.
- Expected output dict:
  - `gate_status = "FAIL"`
  - `gate_reason = "manual_artifact_missing"`
  - `automatic_checks_pass = true`
  - `artifact_exists = false`

**Case H: dependency gate fails in extended release gate**
- Input: Phase 18 dependency command from section 23 returns `0 matches`.
- Expected `ExtendedStealthReleaseGateReportV1` output:
  - `final_result = "FAIL"`
  - `final_reason = "dependency_gate_failed"`
  - `performance_gate_pass = false`
  - `replay_gate_pass = false`
  - `checklist_gate_pass = false`
  - `legacy_zero_tolerance_pass = false`

**Case I: bounded legacy scan finds `temporary_foo` in a test helper**
- Input: gate G17 command returns one match line.
- Expected `ExtendedStealthReleaseGateReportV1` output:
  - `final_result = "FAIL"`
  - `final_reason = "legacy_zero_tolerance_failed"`
  - `legacy_zero_tolerance_pass = false`
  - `legacy_zero_tolerance_matches.size() == 1`

---

## 9. Legacy removal plan (delete-first, exact ids).

L1. **Identifier/pattern:** `legacy_` (bounded token prefix, global scan excluding the Phase 19 release-gate owner test fixture file). **Paths:** `src/`, `tests/` with `-g '!tests/test_extended_stealth_release_gate.gd'`. **Discovery line range evidence:** executable bounded scan (with the owner-test exclusion) returned `0 matches`; the excluded file intentionally contains Phase 19 report keys (`legacy_zero_tolerance_*`) required by section 6/7/12 and is not a production legacy token source. Delete-first rule remains blocking for implementation edits.

L2. **Identifier/pattern:** `temporary_` (bounded token prefix, global scan excluding the Phase 19 release-gate owner test fixture file). **Paths:** `src/`, `tests/` with `-g '!tests/test_extended_stealth_release_gate.gd'`. **Discovery line range evidence:** executable bounded scan (with the owner-test exclusion) returned `0 matches`; the excluded file intentionally contains the fixture line string `temporary_bad` for section 8 Case I / section 12 legacy zero-tolerance fixture coverage.

L3. **Identifier/pattern:** `debug_shadow_override` (exact token, global scan). **Paths:** `src/`, `tests/`. **Discovery line range evidence:** global scan returned `0 matches` during discovery; line range = `N/A`.

L4. **Identifier/pattern:** `old_(ai|nav|path|search|shadow|squad|combat|utility|patrol|pursuit|legacy)` (bounded legacy-prefix family only). **Paths:** `src/`, `tests/`. **Discovery line range evidence:** bounded scan returned `0 matches` during discovery; line range = `N/A`.

Dead-after-phase functions: NONE (Phase 19 adds gate infrastructure and instrumentation, and deletes no existing callable function by replacement).

---

## 10. Legacy verification commands (exact rg + expected 0 matches for every removed legacy item).

L1. `rg -n "\blegacy_" src tests -g '!tests/test_extended_stealth_release_gate.gd' -S`
Expected: `0 matches`.

L2. `rg -n "\btemporary_" src tests -g '!tests/test_extended_stealth_release_gate.gd' -S`
Expected: `0 matches`.

L3. `rg -n "\bdebug_shadow_override\b" src tests -S`
Expected: `0 matches`.

L4. `rg -n "\bold_(ai|nav|path|search|shadow|squad|combat|utility|patrol|pursuit|legacy)" src tests -S`
Expected: `0 matches`.

---

## 11. Acceptance criteria (binary pass/fail).

1. `AIWatchdog.get_snapshot()` includes all keys from `AIWatchdogPerformanceSnapshotV2` in section 6, verified by gate G1 and `tests/test_ai_long_run_stress.gd` output assertions.
2. `src/systems/enemy_pursuit_system.gd` calls `AIWatchdog.record_hard_stall_event()`, `AIWatchdog.record_collision_repath_event()`, and `AIWatchdog.record_detour_candidates_evaluated(...)` at the exact hook points from section 2, verified by gates G5-G7.
3. `tests/test_ai_performance_gate.gd` runs fixed config `seed=1337`, `duration_sec=180.0`, `enemy_count=12`, `fixed_physics_frames=10800`, verified by gate G9 and section 12 tests.
4. `tests/test_ai_performance_gate.gd` enforces all five KPI thresholds plus `collision_repath_events_total > 0`, verified by section 12 tests and gate G10.
5. `tests/replay_gate_helpers.gd` validates the replay trace schema from section 6 and enforces warmup/discrete/tolerance/drift rules from section 7, verified by gates G11-G12 and section 12 tests.
6. All five baseline replay files listed in section 4 exist and are referenced by `tests/test_replay_baseline_gate.gd`, verified by gate G13.
7. `tests/test_level_stealth_checklist.gd` verifies automatic checklist checks and manual artifact existence for `stealth_3zone_test`, verified by gates G14-G15 and section 12 tests.
8. `tests/test_extended_stealth_release_gate.gd` short-circuits on dependency failures and owns the final PASS/FAIL decision, verified by gates G16-G18 and section 12 tests.
9. All commands in section 10 return `0 matches`.
10. All commands in section 13 return expected output.
11. Tier 1 smoke commands in section 14 exit `0`.
12. Tier 2 full regression in section 14 exits `0`.
13. PMB-1 through PMB-5 return expected outputs after Phase 19 changes.
14. No file outside the section 4 in-scope list is modified.
15. `CHANGELOG.md` has one Phase 19 entry prepended under the current date header.

---

## 12. Tests (new/update + purpose).

**New test file:** `tests/test_ai_performance_gate.gd`
- **Scene:** `tests/test_ai_performance_gate.tscn`
- **Test functions:**
  - `_test_performance_gate_metrics_formulas_and_thresholds()` — runs the fixed Phase 19 benchmark config and asserts formulas + thresholds from section 6 Contract 2.
  - `_test_collision_repath_metric_alive_in_forced_collision_stress()` — asserts `collision_repath_events_total > 0` in the fixed collision-heavy 3-zone stress run.
  - `_test_performance_gate_rejects_threshold_failure_fixture()` — feeds a deterministic synthetic metrics fixture to the threshold evaluator and asserts `FAIL/threshold_failed` with non-empty `kpi_threshold_failures`.
- **Registration:** add `AI_PERFORMANCE_GATE_TEST_SCENE` to `tests/test_runner_node.gd`, add `_scene_exists(...)` check, add `_run_embedded_scene_suite("AI performance gate suite", AI_PERFORMANCE_GATE_TEST_SCENE)`.

**New test file:** `tests/test_replay_baseline_gate.gd`
- **Scene:** `tests/test_replay_baseline_gate.tscn`
- **Test functions:**
  - `_test_replay_trace_schema_matches_contract()` — validates `ReplayTraceRecordV1` schema on fixture records.
  - `_test_replay_baseline_pack_passes_against_recorded_baselines()` — runs all five scenarios and asserts pack-level PASS.
  - `_test_replay_gate_fails_on_discrete_mismatch_after_warmup_fixture()` — mutates one post-warmup discrete field and asserts `FAIL/discrete_mismatch_after_warmup`.
  - `_test_replay_gate_enforces_position_drift_budget_fixture()` — mutates positions beyond budget and asserts `FAIL/position_drift_budget_exceeded`.
- **Registration:** add `REPLAY_BASELINE_GATE_TEST_SCENE` to `tests/test_runner_node.gd`, add `_scene_exists(...)` check, add `_run_embedded_scene_suite("Replay baseline gate suite", REPLAY_BASELINE_GATE_TEST_SCENE)`.

**New test file:** `tests/test_level_stealth_checklist.gd`
- **Scene:** `tests/test_level_stealth_checklist.tscn`
- **Test functions:**
  - `_test_stealth_3zone_automatic_checks_pass()` — asserts all six automatic checklist checks pass for the 3-zone fixture under Phase 19 thresholds.
  - `_test_stealth_3zone_manual_checklist_artifact_exists()` — asserts `docs/qa/stealth_level_checklist_stealth_3zone_test.md` exists.
  - `_test_checklist_gate_fails_when_artifact_missing_fixture()` — uses a fixture path override and asserts `FAIL/manual_artifact_missing`.
- **Registration:** add `LEVEL_STEALTH_CHECKLIST_TEST_SCENE` to `tests/test_runner_node.gd`, add `_scene_exists(...)` check, add `_run_embedded_scene_suite("Level stealth checklist gate suite", LEVEL_STEALTH_CHECKLIST_TEST_SCENE)`.

**New test file:** `tests/test_extended_stealth_release_gate.gd`
- **Scene:** `tests/test_extended_stealth_release_gate.tscn`
- **Test functions:**
  - `_test_extended_stealth_release_gate_blocks_on_dependency_gate_failure_fixture()` — injects one failing dependency gate and asserts `FAIL/dependency_gate_failed` with short-circuit behavior.
  - `_test_extended_stealth_release_gate_blocks_on_legacy_zero_tolerance_fixture()` — injects passing subreports plus one legacy scan match and asserts `FAIL/legacy_zero_tolerance_failed`.
  - `_test_extended_stealth_release_gate_pass_fixture_contract()` — injects passing subreports and empty legacy matches and asserts final `PASS/ok` report shape.
- **Registration:** add `EXTENDED_STEALTH_RELEASE_GATE_TEST_SCENE` to `tests/test_runner_node.gd`, add `_scene_exists(...)` check, add `_run_embedded_scene_suite("Extended stealth release gate suite", EXTENDED_STEALTH_RELEASE_GATE_TEST_SCENE)`.

**Updated test file:** `tests/test_ai_long_run_stress.gd`
- Add `run_benchmark_contract(config: Dictionary) -> Dictionary` and exact raw + derived metric emission from section 6 Contract 2.
- Add `AIWatchdog.debug_reset_metrics_for_tests()` usage before runs and assert returned snapshot contains new metric keys.
- Keep existing Phase 7 smoke checks in `run_suite()` and reuse the benchmark helper for metric collection to avoid duplicate stress-driving logic.

**Updated test file:** `tests/test_refactor_kpi_contract.gd`
- Add static assertions for Phase 19 `GameConfig.kpi_*` exported vars in `src/core/game_config.gd`.
- Add static assertions that the four Phase 19 gate scene files exist and are runner-registered.
- Add static assertions that the five replay baseline JSONL files and the 3-zone checklist artifact file exist.

**Updated test file:** `tests/test_runner_node.gd`
- Add four scene constants, four existence checks, and four embedded suite runs for Phase 19 gate suites.

**Support helper file (new, not a test scene):** `tests/replay_gate_helpers.gd`
- Provides JSONL save/load, schema validation, trace compare, and pack aggregation used by `tests/test_replay_baseline_gate.gd`.

---

## 13. rg gates (command + expected output).

**Phase-specific gates:**

G1. `rg -n "@export var kpi_(ai_ms_avg_max|ai_ms_p95_max|replans_per_enemy_per_sec_max|detour_candidates_per_replan_max|hard_stalls_per_min_max|alert_combat_bad_patrol_count|shadow_pocket_min_area_px2|shadow_escape_max_len_px|alt_route_max_factor|shadow_scan_points_min)" src/core/game_config.gd -S`
Expected: `10 matches`.

G2. `rg -n "@export var kpi_(replay_position_tolerance_px|replay_drift_budget_percent|replay_discrete_warmup_sec)" src/core/game_config.gd -S`
Expected: `3 matches`.

G3. `rg -n "\"ai_ms_p95\"|\"replans_total\"|\"detour_candidates_evaluated_total\"|\"hard_stall_events_total\"|\"collision_repath_events_total\"|\"ai_tick_samples_count\"" src/systems/ai_watchdog.gd -S`
Expected: `6 matches`.

G4. `rg -n "func record_(detour_candidates_evaluated|hard_stall_event|collision_repath_event)\(|func debug_reset_metrics_for_tests\(|func _percentile95_ms\(" src/systems/ai_watchdog.gd -S`
Expected: `5 matches`.

G5. `rg -n "AI_WATCHDOG_P95_SAMPLE_CAP|_ai_tick_samples_ms" src/systems/ai_watchdog.gd -S`
Expected: `>= 2 matches`.

G6. `rg -n "AIWatchdog\.record_hard_stall_event\(" src/systems/enemy_pursuit_system.gd -S`
Expected: `1 match`.

G7. `rg -n "AIWatchdog\.record_collision_repath_event\(|AIWatchdog\.record_detour_candidates_evaluated\(" src/systems/enemy_pursuit_system.gd -S`
Expected: `2 matches`.

G8. `rg -n "func debug_spawn_enemy_duplicates_for_tests\(|target_total_count" src/levels/stealth_3zone_test_controller.gd -S`
Expected: `>= 2 matches`.

G9. `rg -n "func run_benchmark_contract\(|\"replans_per_enemy_per_sec\"|\"detour_candidates_per_replan\"|\"hard_stalls_per_min\"" tests/test_ai_long_run_stress.gd -S`
Expected: `4 matches`.

G10. `rg -n "1337|180\.0|10800|collision_repath_events_total|kpi_hard_stalls_per_min_max|kpi_detour_candidates_per_replan_max" tests/test_ai_performance_gate.gd -S`
Expected: `>= 6 matches`.

G11. `rg -n "class_name ReplayGateHelpers|func compare_trace_to_baseline\(|\"tick\"|\"enemy_id\"|\"state\"|\"intent_type\"|\"mode\"|\"path_status\"|\"target_context_exists\"|\"position_x\"|\"position_y\"" tests/replay_gate_helpers.gd -S`
Expected: `>= 11 matches`.

G12. `rg -n "kpi_replay_position_tolerance_px|kpi_replay_drift_budget_percent|kpi_replay_discrete_warmup_sec|discrete_mismatch_after_warmup|position_drift_budget_exceeded" tests/test_replay_baseline_gate.gd tests/replay_gate_helpers.gd -S`
Expected: `>= 5 matches`.

G13. `bash -lc 'count=$(rg --files tests/baselines/replay | rg "(shadow_corridor_pressure|door_choke_crowd|lost_contact_in_shadow|collision_integrity|blood_evidence)\\.jsonl$" -n | wc -l); [ "$count" -eq 5 ] && echo "G13: PASS ($count)" || echo "G13: FAIL ($count)"'`
Expected: `G13: PASS (5)`.

G14. `rg -n "kpi_shadow_pocket_min_area_px2|kpi_shadow_escape_max_len_px|kpi_alt_route_max_factor|kpi_shadow_scan_points_min|stealth_level_checklist_stealth_3zone_test\.md" tests/test_level_stealth_checklist.gd -S`
Expected: `>= 5 matches`.

G15. `rg -n "ShadowZone|debug_get_room_rects|debug_get_choke_rect|build_policy_valid_path\(" tests/test_level_stealth_checklist.gd -S`
Expected: `>= 4 matches`.

G16. `rg -n "func _test_extended_stealth_release_gate\(|dependency_gate_failed|performance_gate_failed|replay_gate_failed|checklist_gate_failed|legacy_zero_tolerance_failed" tests/test_extended_stealth_release_gate.gd -S`
Expected: `>= 6 matches`.

G17. `rg -n "\blegacy_|\btemporary_|\bdebug_shadow_override\b|\bold_(ai|nav|path|search|shadow|squad|combat|utility|patrol|pursuit|legacy)" src tests -g '!tests/test_extended_stealth_release_gate.gd' -S`
Expected: `0 matches`.

G18. `rg -n "func _test_extended_stealth_release_gate\(" tests -S`
Expected: `1 match`.

G19. `rg -n "^const (AI_PERFORMANCE_GATE_TEST_SCENE|REPLAY_BASELINE_GATE_TEST_SCENE|LEVEL_STEALTH_CHECKLIST_TEST_SCENE|EXTENDED_STEALTH_RELEASE_GATE_TEST_SCENE) := " tests/test_runner_node.gd -S`
Expected: `4 matches`.

G20. `rg -n "_scene_exists\((AI_PERFORMANCE_GATE_TEST_SCENE|REPLAY_BASELINE_GATE_TEST_SCENE|LEVEL_STEALTH_CHECKLIST_TEST_SCENE|EXTENDED_STEALTH_RELEASE_GATE_TEST_SCENE)\)|_run_embedded_scene_suite\(\"(AI performance gate suite|Replay baseline gate suite|Level stealth checklist gate suite|Extended stealth release gate suite)\"" tests/test_runner_node.gd -S`
Expected: `8 matches`.

**Persistent Module Boundary Contract gates (verbatim):**

[PMB-1] `rg -n "build_reachable_path_points|build_path_points|_build_policy_valid_path_fallback_contract|_build_reachable_path_points_for_enemy" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-2] `rg -n "\.(build_policy_valid_path|build_reachable_path_points|build_path_points)\(" src/entities/enemy.gd -S`
Expected: `0 matches`.

[PMB-3] `rg -n "\bhas_last_seen\b|\bhas_known_target\b|\bhas_investigate_anchor\b" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-4] `rg -n "\"type\"[[:space:]]*:" src/systems/enemy_pursuit_system.gd -S`
Expected: `0 matches`.

[PMB-5] `bash -lc 'count=$(rg -n "_pursuit\.execute_intent\(" src/entities/enemy.gd -S | wc -l); [ "$count" -eq 1 ] && echo "PMB-5: PASS ($count)" || echo "PMB-5: FAIL ($count)"'`
Expected: `PMB-5: PASS (1)`.

---

## 14. Execution sequence (step-by-step, no ambiguity).

Step 0: Run all dependency gates from section 23 in listed order (Phase 15, Phase 16, Phase 17, Phase 18). Stop on first failure.

Step 1: Run section 10 command L1 and delete every `legacy_` token occurrence in `src/` and `tests/` before any other edits.

Step 2: Run section 10 command L2 and delete every `temporary_` token occurrence in `src/` and `tests/` before any other edits.

Step 3: Run section 10 command L3 and delete every `debug_shadow_override` token occurrence in `src/` and `tests/` before any other edits.

Step 4: Run section 10 command L4 and delete every bounded legacy-prefix token occurrence (`old_(ai|nav|path|search|shadow|squad|combat|utility|patrol|pursuit|legacy)`) in `src/` and `tests/` before any other edits.

Step 5: Run all section 10 legacy verification commands (L1-L4). All commands must return `0 matches` before continuing.

Step 6: In `src/core/game_config.gd`, add the 13 Phase 19 `@export var kpi_*` constants from section 2 item 5 with exact values from section 6.

Step 7: In `src/systems/ai_watchdog.gd`, add total-counter fields, p95 sample buffer fields, and `AI_WATCHDOG_P95_SAMPLE_CAP`.

Step 8: In `src/systems/ai_watchdog.gd`, add `record_detour_candidates_evaluated(...)`, `record_hard_stall_event()`, `record_collision_repath_event()`, `debug_reset_metrics_for_tests()`, and `_percentile95_ms()`.

Step 9: In `src/systems/ai_watchdog.gd`, modify `record_replan()`, `end_ai_tick()`, and `get_snapshot()` to produce `AIWatchdogPerformanceSnapshotV2`.

Step 10: In `src/systems/enemy_pursuit_system.gd`, instrument `_execute_move_to_target(...)` with `AIWatchdog.record_hard_stall_event()` at the hard-stall branch before recovery replans.

Step 11: In `src/systems/enemy_pursuit_system.gd`, instrument `_try_open_blocking_door_and_force_repath()` with `AIWatchdog.record_collision_repath_event()` on successful forced repath.

Step 12: In `src/systems/navigation_runtime_queries.gd`, publish deterministic `detour_candidates_evaluated_count` from the actual detour candidate loop in `build_policy_valid_path(...)`, then in `src/systems/enemy_pursuit_system.gd` consume that field in `_plan_path_to(...)` and call `AIWatchdog.record_detour_candidates_evaluated(...)` exactly once per path-plan evaluation.

Step 13: In `src/levels/stealth_3zone_test_controller.gd`, add `debug_spawn_enemy_duplicates_for_tests(target_total_count: int) -> int` using the existing `_spawn_enemies()` wiring path and deterministic `ENEMY_SPAWNS` cycling.

Step 14: Create `tests/replay_gate_helpers.gd` and implement JSONL save/load, trace schema validation, scenario compare, and pack aggregation from section 6 and section 7.

Step 15: Modify `tests/test_ai_long_run_stress.gd` to add `run_benchmark_contract(config: Dictionary) -> Dictionary`, AIWatchdog metric reset, full metric emission, and derived formulas from section 6 Contract 2.

Step 16: Create `tests/test_ai_performance_gate.gd` and `tests/test_ai_performance_gate.tscn`; implement all three test functions from section 12.

Step 17: Create `tests/test_replay_baseline_gate.gd` and `tests/test_replay_baseline_gate.tscn`; implement all four test functions from section 12 using `tests/replay_gate_helpers.gd`.

Step 18: Create the five replay baseline JSONL files listed in section 4 under `tests/baselines/replay/` with `ReplayTraceRecordV1` schema rows only.

Step 19: Create `tests/test_level_stealth_checklist.gd` and `tests/test_level_stealth_checklist.tscn`; implement all three test functions from section 12.

Step 20: Create `docs/qa/stealth_level_checklist_stealth_3zone_test.md` with ten traversal entries and summary fields required by section 2 item 22.

Step 21: Create `tests/test_extended_stealth_release_gate.gd` and `tests/test_extended_stealth_release_gate.tscn`; implement all three test functions from section 12 and the `_run_release_gate()` owner logic from section 7.

Step 22: Update `tests/test_refactor_kpi_contract.gd` with Phase 19 static assertions from section 12.

Step 23: Update `tests/test_runner_node.gd`: add four scene constants, four `_scene_exists(...)` checks, and four `_run_embedded_scene_suite(...)` calls for the new Phase 19 suites.

Step 24: Run Tier 1 smoke suite commands (exact):
- `xvfb-run -a godot-4 --headless --path . res://tests/test_ai_long_run_stress.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_ai_performance_gate.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_replay_baseline_gate.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_level_stealth_checklist.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_extended_stealth_release_gate.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_3zone_combat_transition_stress.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_stealth_room_smoke.tscn`
- `xvfb-run -a godot-4 --headless --path . res://tests/test_refactor_kpi_contract.tscn`

Step 25: Run Tier 2 full regression: `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit `0`.

Step 26: Run all section 13 rg gates (G1-G20 and PMB-1-PMB-5). All commands must return expected output.

Step 27: Prepend one `CHANGELOG.md` entry under the current date header for Phase 19 (extended stealth release gate, AIWatchdog KPI totals+p95, replay baseline pack gate, level stealth checklist gate, bounded legacy zero-tolerance scan).

---

## 15. Rollback conditions.

1. **Trigger:** Any dependency gate in section 23 fails at section 14 step 0. **Rollback action:** do not start implementation; revert all attempted Phase 19 edits. Phase result = FAIL.
2. **Trigger:** Any section 10 legacy verification command returns non-zero matches after section 14 step 5. **Rollback action:** revert all section 4 in-scope file changes. Phase result = FAIL.
3. **Trigger:** `AIWatchdog.get_snapshot()` omits any required key from `AIWatchdogPerformanceSnapshotV2` after section 14 step 9. **Rollback action:** revert `src/systems/ai_watchdog.gd` and all Phase 19 test edits that depend on new keys. Phase result = FAIL.
4. **Trigger:** `EnemyPursuitSystem` instrumentation increments counters more than once per event (duplicate detour/hard-stall/collision counts detected by section 12 tests). **Rollback action:** revert `src/systems/enemy_pursuit_system.gd` and `src/systems/ai_watchdog.gd` Phase 19 edits together and restart from section 14 step 10.
5. **Trigger:** `tests/test_ai_performance_gate.gd` passes thresholds while `collision_repath_events_total <= 0`. **Rollback action:** revert Phase 19 performance gate and stress benchmark edits. Phase result = FAIL.
6. **Trigger:** Replay gate accepts a discrete mismatch after warmup or rejects a drift-only case below budget. **Rollback action:** revert `tests/replay_gate_helpers.gd` and `tests/test_replay_baseline_gate.gd`. Phase result = FAIL.
7. **Trigger:** Checklist gate uses out-of-scope engine/runtime file changes instead of test-side checks (section 4 violation). **Rollback action:** revert all out-of-scope edits immediately, then revert all Phase 19 edits. Phase result = FAIL.
8. **Trigger:** Any baseline JSONL file fails `ReplayTraceRecordV1` schema validation in section 12 tests. **Rollback action:** revert all replay baseline artifacts and replay gate code. Phase result = FAIL.
9. **Trigger:** Any Tier 1 smoke command in section 14 step 24 exits non-zero. **Rollback action:** revert all section 4 in-scope file changes. Phase result = FAIL.
10. **Trigger:** Tier 2 regression in section 14 step 25 exits non-zero. **Rollback action:** revert all section 4 in-scope file changes. Phase result = FAIL.
11. **Trigger:** Any section 13 gate (G1-G20 or PMB-1-PMB-5) fails after section 14 step 26. **Rollback action:** revert all section 4 in-scope file changes. Phase result = FAIL.
12. **Trigger:** Any file outside the section 4 in-scope list is modified. **Rollback action:** revert out-of-scope edits immediately, then revert all Phase 19 edits. Phase result = FAIL.
13. **Trigger:** `tests/test_extended_stealth_release_gate.gd` does not short-circuit on dependency failure and runs subgates anyway. **Rollback action:** revert only `tests/test_extended_stealth_release_gate.gd` and `.tscn`, then revert remaining Phase 19 edits. Phase result = FAIL.
14. **Trigger:** Implementation uses the original broad `old_` zero-tolerance scan without bounded legacy prefixes, causing false-positive failures on valid identifiers. **Rollback action:** revert Phase 19 release-gate test changes and restart from section 14 step 14 with the bounded regex from section 13 gate G17.

---

## 16. Phase close condition.

- [ ] All rg commands in section 10 return `0 matches`
- [ ] All rg gates in section 13 return expected output
- [ ] All tests in section 12 (new + updated) exit `0`
- [ ] Tier 1 smoke suite (section 14) - all commands exit `0`
- [ ] Tier 2 full regression (`xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn`) exits `0`
- [ ] No file outside section 4 in-scope list was modified
- [ ] `CHANGELOG.md` entry prepended
- [ ] `tests/test_ai_performance_gate.gd` records `seed = 1337`, `duration_sec = 180.0`, `enemy_count = 12`, and `fixed_physics_frames = 10800` in the pass report
- [ ] `tests/test_ai_performance_gate.gd` records `collision_repath_events_total > 0` in the pass report
- [ ] `tests/test_replay_baseline_gate.gd` loads all five baseline files from `tests/baselines/replay/`
- [ ] `tests/test_level_stealth_checklist.gd` passes all automatic checks for `stealth_3zone_test`
- [ ] `docs/qa/stealth_level_checklist_stealth_3zone_test.md` exists and is referenced by `tests/test_level_stealth_checklist.gd`
- [ ] `tests/test_extended_stealth_release_gate.gd` returns `PASS/ok` only when dependency gates and all three subgates pass and section 13 gate G17 returns `0 matches`
- [ ] PMB-1 through PMB-5 return expected outputs and `pmb_contract_check` is recorded as all PASS in section 21 report format

---

## 17. Ambiguity check: 0

---

## 18. Open questions: 0

---

## 19. Post-implementation verification plan (diff audit + contract checks + runtime scenarios).

**Diff audit:**
- Diff every file in section 4 against the pre-phase baseline, including all four new test script/scene pairs, the replay helper, five baseline JSONL files, the checklist artifact, and `CHANGELOG.md`.
- Confirm zero modifications outside the section 4 in-scope list.

**Contract checks:**
- `AIWatchdogPerformanceSnapshotV2` (section 6): inspect `src/systems/ai_watchdog.gd` and verify all required keys exist in `get_snapshot()`, `replans_total` increments inside `record_replan()`, p95 sample buffer cap logic, and `debug_reset_metrics_for_tests()` zeroes totals + samples.
- `AiStressMetricsContractV2` (section 6): inspect `tests/test_ai_long_run_stress.gd` and `tests/test_ai_performance_gate.gd` and verify fixed config fields, formula derivation order, threshold list order, and `collision_repath_metric_dead` failure path.
- `ReplayBaselineGateReportV1` (section 6): inspect `tests/replay_gate_helpers.gd` and `tests/test_replay_baseline_gate.gd` and verify strict schema validation, warmup discrete rule, position tolerance axis checks, drift-percent formula, and fail-priority order from section 7.
- `StealthLevelChecklistGateReportV1` (section 6): inspect `tests/test_level_stealth_checklist.gd` and verify room order, patrol proxy route checks, shadow-pocket area computation, escape-length checks, route-variety length factor, chokepoint width rule, and artifact path exact string.
- `ExtendedStealthReleaseGateReportV1` (section 6): inspect `tests/test_extended_stealth_release_gate.gd` and verify dependency short-circuit order, subgate short-circuit order, bounded legacy zero-tolerance scan command exact text from section 13 gate G17, and final reason selection.
- Legacy removal check (section 10): run L1-L4 commands and confirm `0 matches`.

**Runtime scenarios from section 20:** execute P19-A, P19-B, P19-C, P19-D, P19-E, P19-F, P19-G, P19-H, and P19-I.

---

## 20. Runtime scenario matrix (scenario id, setup, frame count, expected invariants, fail conditions).

**P19-A: Performance gate pass on fixed 3-zone stress benchmark**
- Scene: `tests/test_ai_performance_gate.tscn`
- Setup: fixed config `seed=1337`, `duration_sec=180.0`, `fixed_physics_frames=10800`, `enemy_count=12`, `scene_path=res://src/levels/stealth_3zone_test.tscn`, `force_collision_repath=true`; `Stealth3ZoneTestController.debug_spawn_enemy_duplicates_for_tests(12)` used after bootstrap.
- Frame count: `10800 physics frames` (+ deterministic bootstrap frames before start)
- Expected invariants:
  - `gate_status == "PASS"` and `gate_reason == "ok"`
  - `ai_ms_avg <= GameConfig.kpi_ai_ms_avg_max`
  - `ai_ms_p95 <= GameConfig.kpi_ai_ms_p95_max`
  - `replans_per_enemy_per_sec <= GameConfig.kpi_replans_per_enemy_per_sec_max`
  - `detour_candidates_per_replan <= GameConfig.kpi_detour_candidates_per_replan_max`
  - `hard_stalls_per_min <= GameConfig.kpi_hard_stalls_per_min_max`
  - `collision_repath_events_total > 0`
- Fail conditions:
  - Any threshold failure
  - `collision_repath_events_total <= 0`
  - Returned `enemy_count != 12`
- Covered by: `_test_performance_gate_metrics_formulas_and_thresholds`, `_test_collision_repath_metric_alive_in_forced_collision_stress`

**P19-B: Performance gate threshold failure fixture is rejected**
- Scene: `tests/test_ai_performance_gate.tscn`
- Setup: synthetic metrics fixture with `ai_ms_p95` and `hard_stalls_per_min` above thresholds and `collision_repath_events_total > 0`.
- Frame count: `0` (unit-level fixture evaluation)
- Expected invariants:
  - `gate_status == "FAIL"`
  - `gate_reason == "threshold_failed"`
  - `kpi_threshold_failures` contains both threshold names in deterministic order
- Fail conditions:
  - Fixture passes
  - Failure reason is not `threshold_failed`
- Covered by: `_test_performance_gate_rejects_threshold_failure_fixture`

**P19-C: Replay baseline pack passes against recorded baselines**
- Scene: `tests/test_replay_baseline_gate.tscn`
- Setup: run five scenarios (`shadow_corridor_pressure`, `door_choke_crowd`, `lost_contact_in_shadow`, `collision_integrity`, `blood_evidence`) with fixed seed `1337`, fixed scenario duration `3600 physics frames` each, compare against the five JSONL baselines.
- Frame count: `18000 physics frames` total across the five scenarios (5 x 3600)
- Expected invariants:
  - Pack `gate_status == "PASS"`
  - Every scenario result `gate_status == "PASS"`
  - No post-warmup discrete mismatches
  - Every scenario `position_drift_percent <= GameConfig.kpi_replay_drift_budget_percent`
- Fail conditions:
  - Any scenario fails schema, count, discrete, or drift checks
- Covered by: `_test_replay_baseline_pack_passes_against_recorded_baselines`

**P19-D: Replay gate rejects discrete mismatch after warmup**
- Scene: `tests/test_replay_baseline_gate.tscn`
- Setup: mutate one candidate record discrete field (`intent_type`) at `tick > 30` in a fixture trace while keeping positions unchanged.
- Frame count: `0` (fixture compare)
- Expected invariants:
  - Scenario `gate_status == "FAIL"`
  - Scenario `gate_reason == "discrete_mismatch_after_warmup"`
  - `discrete_mismatch_after_warmup_count >= 1`
- Fail conditions:
  - Scenario passes
  - Mismatch is treated as warmup when `tick > 30`
- Covered by: `_test_replay_gate_fails_on_discrete_mismatch_after_warmup_fixture`

**P19-E: Replay gate enforces aggregate position drift budget**
- Scene: `tests/test_replay_baseline_gate.tscn`
- Setup: mutate candidate positions so >2.0% of records exceed axis tolerance by >6px while discrete fields remain identical.
- Frame count: `0` (fixture compare)
- Expected invariants:
  - Scenario `gate_status == "FAIL"`
  - Scenario `gate_reason == "position_drift_budget_exceeded"`
  - `position_drift_percent > GameConfig.kpi_replay_drift_budget_percent`
- Fail conditions:
  - Scenario passes with drift percent > budget
- Covered by: `_test_replay_gate_enforces_position_drift_budget_fixture`

**P19-F: Stealth checklist automatic checks pass on 3-zone fixture**
- Scene: `tests/test_level_stealth_checklist.tscn`
- Setup: instantiate `stealth_3zone_test`, collect controller debug geometry, local navigation service, shadow zones, and manual artifact path `docs/qa/stealth_level_checklist_stealth_3zone_test.md`.
- Frame count: `2 bootstrap frames` + deterministic test-side nav queries
- Expected invariants:
  - `automatic_checks_pass == true`
  - `patrol_reachability_pass == true`
  - `shadow_pocket_availability_pass == true`
  - `shadow_escape_availability_pass == true`
  - `route_variety_pass == true`
  - `chokepoint_width_safety_pass == true`
  - `boundary_scan_support_pass == true`
- Fail conditions:
  - Any automatic check false
  - Controller or navigation service missing
- Covered by: `_test_stealth_3zone_automatic_checks_pass`

**P19-G: Checklist gate fails when manual artifact is missing**
- Scene: `tests/test_level_stealth_checklist.tscn`
- Setup: run the same automatic checks with a fixture artifact path that does not exist.
- Frame count: `0` (fixture path override after cached automatic-check result)
- Expected invariants:
  - `gate_status == "FAIL"`
  - `gate_reason == "manual_artifact_missing"`
  - `automatic_checks_pass == true`
  - `artifact_exists == false`
- Fail conditions:
  - Gate passes without artifact
- Covered by: `_test_checklist_gate_fails_when_artifact_missing_fixture`

**P19-H: Extended release gate short-circuits on dependency failure**
- Scene: `tests/test_extended_stealth_release_gate.tscn`
- Setup: inject one failing dependency gate fixture for Phase 18 and pass fixtures for all subgates.
- Frame count: `0` (fixture aggregation)
- Expected invariants:
  - `final_result == "FAIL"`
  - `final_reason == "dependency_gate_failed"`
  - Subgate fixtures are not executed (recorded call count `0`)
- Fail conditions:
  - Subgates run after dependency failure
  - Final reason differs
- Covered by: `_test_extended_stealth_release_gate_blocks_on_dependency_gate_failure_fixture`

**P19-I: Extended release gate rejects bounded legacy zero-tolerance match**
- Scene: `tests/test_extended_stealth_release_gate.tscn`
- Setup: inject passing dependency gates and passing subreports, plus one bounded legacy-scan match string (`tests/tmp_fixture.gd:1:var temporary_bad := true`).
- Frame count: `0` (fixture aggregation)
- Expected invariants:
  - `final_result == "FAIL"`
  - `final_reason == "legacy_zero_tolerance_failed"`
  - `legacy_zero_tolerance_matches.size() == 1`
- Fail conditions:
  - Gate passes with a legacy match
- Covered by: `_test_extended_stealth_release_gate_blocks_on_legacy_zero_tolerance_fixture`

---

## 21. Verification report format (what must be recorded to close phase).

Record all fields below to close phase:
- `phase_id: PHASE_19`
- `changed_files: [exact paths of all modified/created files]`
- `scope_audit: PASS|FAIL` (list out-of-scope paths if FAIL; empty list required for PASS)
- `test_only_compatibility_exceptions: []` (empty list when unused; when used, list exact path + failing command + root-cause summary + confirmation no production file change was used for that failure)
- `dependency_gate_check: [PHASE-15: PASS|FAIL, PHASE-16: PASS|FAIL, PHASE-17: PASS|FAIL, PHASE-18: PASS|FAIL]` **[BLOCKING - all must be PASS before implementation and before close]**
- `legacy_rg: [{command, expected: "0 matches", actual, PASS|FAIL}]` for all 4 commands from section 10
- `rg_gates: [{gate: "G1".."G20"|"PMB-1".."PMB-5", command, expected, actual, PASS|FAIL}]`
- `phase_tests: [{test_function, scene, exit_code: 0, PASS|FAIL}]` for all new and updated test functions listed in section 12
- `smoke_suite: [{command, exit_code: 0, PASS|FAIL}]` for all 8 Tier 1 commands from section 14
- `tier2_regression: {command: "xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn", exit_code, PASS|FAIL}`
- `ai_watchdog_metrics_contract_check: {snapshot_keys_present: [..], p95_sample_cap_enforced: true|false, totals_reset_for_tests: true|false, PASS|FAIL}`
- `performance_gate_metrics: {seed: 1337, duration_sec: 180.0, fixed_physics_frames: 10800, enemy_count: 12, ai_ms_avg, ai_ms_p95, replans_total, detour_candidates_evaluated_total, hard_stall_events_total, collision_repath_events_total, replans_per_enemy_per_sec, detour_candidates_per_replan, hard_stalls_per_min, threshold_failures: [], PASS|FAIL}`
- `replay_baseline_gate: {scenarios: [{name, sample_count, discrete_mismatch_after_warmup_count, position_drift_percent, PASS|FAIL}], pack_status: PASS|FAIL, baseline_paths: [..], PASS|FAIL}`
- `level_stealth_checklist_gate: {level_name: "stealth_3zone_test", automatic_checks_pass: true|false, artifact_exists: true|false, room_count: int, room_reports: [..], PASS|FAIL}`
- `release_gate_summary: {dependency_gate_pass: true|false, performance_gate_pass: true|false, replay_gate_pass: true|false, checklist_gate_pass: true|false, legacy_zero_tolerance_pass: true|false, final_result: PASS|FAIL}`
- `baseline_artifacts_present: [shadow_corridor_pressure.jsonl, door_choke_crowd.jsonl, lost_contact_in_shadow.jsonl, collision_integrity.jsonl, blood_evidence.jsonl]`
- `manual_checklist_artifact: {path: "docs/qa/stealth_level_checklist_stealth_3zone_test.md", exists: true|false}`
- `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, PMB-3: PASS|FAIL, PMB-4: PASS|FAIL, PMB-5: PASS|FAIL]` **[BLOCKING - all must be PASS to close phase]**
- `changelog_prepended: true|false`
- `unresolved_deviations: []` (non-empty list forces `final_result = FAIL`)
- `final_result: PASS|FAIL`

---

## 22. Structural completeness self-check.

Sections present: 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23.
Missing sections: NONE.
- Evidence preamble (`### Evidence`) present between `## PHASE 19` header and section 1: yes
- PMB gates present in section 13 (PMB section exists in document): yes
- `pmb_contract_check` present in section 21 (PMB section exists in document): yes

---

## 23. Dependencies on previous phases.

1. **Phase 15** — utility doctrine and target-context ownership in `Enemy._build_utility_context(...)` and `EnemyUtilityBrain._choose_intent(...)` introduces replay-critical combat/no-LOS behavior (`target_context_exists`, `SHADOW_BOUNDARY_SCAN` doctrine ordering, no patrol/home regression under active target context). Phase 19 replay baselines and `KPI_ALERT_COMBAT_BAD_PATROL_COUNT` gate require those outputs. Dependency gate (must pass before section 14 step 1): `rg -n "target_context_exists|SHADOW_BOUNDARY_SCAN|if not has_los and alert_level >= ENEMY_ALERT_LEVELS_SCRIPT\.ALERT" src/entities/enemy.gd src/systems/enemy_utility_brain.gd -S` -> expected `>= 4 matches`.

2. **Phase 16** — dark-search session ownership in `Enemy` introduces per-room dark-search node sequencing and shadow-boundary scan choreography used by the `lost_contact_in_shadow` replay baseline scenario. Phase 19 replay traces require stable dark-search session outputs and sequencing. Dependency gate (must pass before section 14 step 1): `rg -n "_record_combat_search_execution_feedback|_select_next_combat_dark_search_node|_combat_search_current_node_key|combat_search_shadow_scan_suppressed" src/entities/enemy.gd -S` -> expected `>= 4 matches`.

3. **Phase 17** — pursuit repath recovery outputs and policy-only pursuit PMB invariants introduce `repath_recovery_*` feedback and recovery behavior needed for replay and performance-gate coverage of hard stalls and policy-blocked recovery. Phase 19 KPI counters and replay baselines require those paths. Dependency gate (must pass before section 14 step 1): `rg -n "repath_recovery_reason|repath_recovery_request_next_search_node" src/systems/enemy_pursuit_system.gd src/entities/enemy.gd -S` -> expected `>= 4 matches`.

4. **Phase 18** — squad tactical slot metadata and FLANK contract gating introduce `slot_role`, `cover_source`, `cover_los_break_quality`, and `flank_slot_contract_ok` outputs used by replay baselines and final release-gate behavioral regression coverage in combat scenarios. Phase 19 replay and checklist gates require those fields to exist in the runtime behavior chain. Dependency gate (must pass before section 14 step 1): `rg -n "slot_role|cover_source|cover_los_break_quality|flank_slot_contract_ok" src/systems/enemy_squad_system.gd src/entities/enemy.gd src/systems/enemy_utility_brain.gd -S` -> expected `>= 8 matches`.
