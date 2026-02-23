# Phase Spec Writing Template (v2)
# For: ai_nav_refactor_execution_v2.md phases

You are writing an execution spec for exactly [PHASE_N] from file ai_nav_refactor_execution.md.
Output must be unambiguous and fully testable. Output in file ai_nav_refactor_execution_v2.md at the
end of the file; existing text must remain unchanged.

─────────────────────────────────────────────
HARD RULES
─────────────────────────────────────────────
1. Write fully in English prose. No transliteration.
2. Do not use vague wording: forbidden words are "may", "can", "should",
   "usually", "typically", "if needed", "generally", "often", "sometimes".
   Every statement is either always true or always false for this phase.
3. Every rule must be verifiable by command, test, or formula.
4. Legacy must be deleted before new logic in this phase. Dead code after this phase also must be deleted.
5. Temporary old/new coexistence is forbidden.
6. If any PHASE INPUT field is missing or contains a placeholder, ask clarifying
   questions and stop. Do not write the spec until all PHASE INPUT fields are filled.
7. Every cross-reference within this spec must use the exact format "section N"
   where N is a section number of THIS phase (1–23). A reference to another
   phase's section must use "Phase X, section N". A bare "section N" that
   resolves to a different phase's content is forbidden. Before writing any
   cross-reference, verify the target section exists and contains the content
   type being referenced (e.g. "section 12" must actually contain test names).
8. For every invariant in section 2 OR section 3 that uses the words
   "from previous phase", "retained", "remains unchanged", or "preserved",
   the specific phase that introduced that behavior MUST appear by id in
   section 23. A dependency listed only implicitly through another dependency
   is forbidden.
9. (PMB contract inheritance) If the target execution document contains a
   `## Persistent Module Boundary Contract` section, then the generated phase
   spec MUST:
     a) Include all PMB commands verbatim in section 13 (rg gates) with their
        exact expected outputs, labeled `[PMB-N] <command>` → expected: 0 matches.
     b) Include `pmb_contract_check: [PMB-1: PASS|FAIL, ...]` in section 21
        (Verification report), marked as blocking (all must be PASS to close phase).
   Failure to include either = structural completeness self-check (section 22)
   MUST report FAIL for "PMB gates present" and "pmb_contract_check present".
10. (GDScript type safety) All GDScript code in this phase must follow:
     a) Dictionary value access returns Variant. Arithmetic requires explicit cast:
        `float(dict["key"])` or `int(dict["key"])`. Using `:=` with Dictionary
        arithmetic is forbidden.
     b) `Vector2.is_equal_approx(other)` accepts exactly one argument. Custom
        epsilon: `abs(a.x - b.x) < eps and abs(a.y - b.y) < eps`.
     c) Any function whose name does not start with `_` is public. All public
        function return types and parameter types must be declared explicitly.
        Untyped `var` for public function return values is forbidden.
     d) `NavigationServer2D.map_get_path(rid, from, to, optimize)` returns
        `PackedVector2Array`. Empty array = no path, not an error.
     e) `NavigationAgent2D.get_next_path_position()` is valid only after
        `target_position` is set and at least one physics frame has passed.
11. (No partial implementation) If the implementation cannot be completed within
    this phase scope, roll back all changes to the state before this phase began.
    Partial state = phase FAILED.
12. (Project infrastructure) Engine: Godot 4.6, GDScript.
    Headless runner: `xvfb-run -a godot-4 --headless --path . res://tests/<scene>.tscn`
    Constants: new constants go into `src/core/game_config.gd` as exported vars
    unless file-local (used in exactly one function) — those use `const` at file scope.
    Tests: every new test file MUST be registered in `tests/test_runner_node.gd`
    in `_get_test_suites()`. Unregistered test = phase cannot close.
    CHANGELOG: after implementation, prepend one entry to `CHANGELOG.md` under
    the current date header. Do not read the full file — prepend only.
13. (Test-only compatibility exception) If a listed phase test / Tier 1 smoke /
    Tier 2 regression fails and root cause is proven to be test-side only
    (stale assertion, stale fake/stub API, deleted legacy private call, or test
    fixture incompatibility), the implementation may patch additional files
    under `tests/` (and `tests/test_runner_node.gd` only when wiring is needed)
    outside section 4 scope to restore compatibility. This exception is valid
    only when:
    a) no production file outside section 4 is changed to resolve that failure,
    b) the patch is minimal and does not require future-phase production logic,
    c) the failing test is re-run and passes after the patch,
    d) the phase verification report records every such file in
       `test_only_compatibility_exceptions` with path + failing command +
       root-cause summary + confirmation that no production file change was used.

─────────────────────────────────────────────
PROJECT DISCOVERY (MANDATORY BEFORE WRITING THE PHASE SPEC)
─────────────────────────────────────────────
1. Before writing the phase spec, inspect the real project code for all impacted
   systems/files.
2. Build the impacted file list by running rg for each identifier listed in
   PHASE INPUT items 17 (legacy to delete) and 8 (contracts to change).
   Then read each matched file in full.
3. For each impacted system, identify exact owner functions, callers, and state
   transitions (call graph + data flow).
4. Include an evidence section in the output as a preamble between the
   `## PHASE [ID]` header and section 1. Label it `### Evidence`. Contents:
   - "Inspected files" (exact paths)
   - "Inspected functions/methods" (exact identifiers)
   - "Search commands used" (exact commands)
5. Do not propose changes for any file/system that was not inspected.
6. If any required file is missing or unclear, stop and output open questions
   instead of assumptions.
7. Any assumption without code evidence is forbidden.

─────────────────────────────────────────────
PHASE INPUT (FILL ALL — no field may be left as placeholder)
─────────────────────────────────────────────
 1. Phase id: [PHASE_ID]
 2. Phase title: [PHASE_TITLE]
 3. Goal (one sentence): [GOAL]
 4. In-scope files (exact paths): [LIST]
 5. Out-of-scope files (exact paths, at least 3): [LIST]
 6. Current behavior ("what now"): must be expressed as a failing test name,
    an rg command with non-zero output, or a measurable metric. Not prose. [TEXT]
 7. Target behavior ("what after"): must be expressed as a passing test name,
    an rg command with zero output, or a measurable metric. Not prose. [TEXT]
 8. Contracts to introduce/change: [LIST]
 9. Contract name: [NAME]  (write "N/A — no new contracts" if phase only removes legacy)
10. Inputs (types, nullability, finite checks): [TEXT]  (N/A if item 9 = N/A)
11. Outputs (exact keys/types/enums): [TEXT]  (N/A if item 9 = N/A)
12. Status enums: [LIST]  (N/A if item 9 = N/A)
13. Reason enums: [LIST]  (N/A if item 9 = N/A)
14. Deterministic order and tie-break rules: [TEXT]
15. Constants/thresholds/eps (exact values + placement: GameConfig or local): [TEXT]
16. Forbidden patterns (identifiers/branches): [LIST]
17. Legacy to delete first (exact ids/functions/consts + file path each): [LIST]
    Also list any function that will become unreachable (dead) as a result of
    this phase's new logic. Dead-after-phase = must be deleted in this phase.
18. Migration notes (rename/move, if any): [TEXT]
19. New tests (exact filenames): [LIST]
20. Tests to update (exact filenames): [LIST]
21. Tier 1 smoke suite commands (exact, xvfb-run prefix, one per line): [LIST]
    Note: Tier 2 full regression `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn`
    is always mandatory and does not need to be listed here.
22. rg gates (exact command + expected result): [LIST]
23. Rollback trigger conditions: [LIST]
24. Dependencies on previous phases (phase id + exact behavior inherited): [LIST]
25. Non-goals in this phase: [LIST]
26. Runtime scenarios (exact test scene/seed/frame count/setup/expected outcome): [LIST]

─────────────────────────────────────────────
LEGACY REMOVAL VERIFICATION (MANDATORY)
─────────────────────────────────────────────
1. Provide exact rg command for each legacy identifier/function/constant from
   PHASE INPUT item 17. Each rg command must search the full `src/` directory
   (not a single file) unless the identifier is guaranteed file-unique by
   PROJECT DISCOVERY evidence — in that case state the evidence explicitly.
2. Expected result for each command: 0 matches.
3. Phase cannot close until all legacy verification commands return 0 matches.
4. Any non-zero match count => phase FAILED.
5. No allowlist. No temporary compatibility branches.
6. Legacy removal commands are section 10 of the output. They are separate from
   section 13 (rg gates). Section 10 must list every legacy id with its own
   rg command. A batch command covering multiple ids is forbidden.

─────────────────────────────────────────────
REQUIRED OUTPUT FORMAT (STRICT)
─────────────────────────────────────────────
The spec for this phase MUST begin with:
  ## PHASE [ID]
  Phase id: [PHASE_ID].
immediately before section 1. A phase without a "## PHASE" markdown level-2
header is malformed and cannot be executed.

 1. What now. Must include: at least one rg command or test name that demonstrates
    the current broken/incomplete state. Prose alone is forbidden.
 2. What changes. Format: numbered list of specific changes. Each item names the
    exact function and file being modified. Prose summary alone is forbidden.
 3. What will be after. Each item must be verifiable: name the rg gate from
    section 13 or the test from section 12 that proves it. Unverifiable items
    are forbidden.
 4. Scope and non-scope (exact files). Must include:
    - In-scope file list (paths) = allowed file-change boundary.
      Any change outside this list = phase FAILED regardless of test results,
      except Hard Rule 13 test-only compatibility exception files.
    - Out-of-scope file list (paths, at least 3).
 5. Single-owner authority for this phase. Must name:
    - The exact file that owns the primary decision/behavior introduced in this phase.
    - The exact function within that file that is the sole decision point.
    - A statement that no other file duplicates this decision (verifiable via
      an rg gate in section 13).
 6. Full input/output contract. Must include for each contract:
    - Contract name
    - All input fields with type, nullability, and finite-check rule
    - All output fields with exact key name, type, and valid values
    - All status enums with exact string values
    - All reason enums with exact string values
    - Constants/thresholds used (name, value, placement)
 7. Deterministic algorithm with exact order. Must specify:
    - Exact function call order
    - Tie-break rules when two candidates are equal. If N ≤ 1 candidates
      are guaranteed by design, state this explicitly instead of tie-break rules.
    - Exact behavior when input is empty/null/invalid
 8. Edge-case matrix (case → exact output). Minimum 4 cases, mandatory types:
    - Case A: empty or null input → expected output dict + status
    - Case B: single valid input, no ambiguity → expected output dict + status
    - Case C: tie-break triggered (two equal candidates) → expected output dict + status.
      If section 7 proves N ≤ 1 candidates is guaranteed by design, replace Case C with
      an explicit "tie-break N/A" statement citing the section 7 proof.
    - Case D: all inputs invalid/blocked → expected output dict + status
    Additional cases for each distinct code path beyond the above.
 9. Legacy removal plan (delete-first, exact ids). One entry per legacy item.
    Each entry must state: identifier, file path, and approximate line range
    confirmed by PROJECT DISCOVERY.
10. Legacy verification commands (exact rg + expected 0 matches for every
    removed legacy item). One rg command per legacy item. No batching.
    Each command searches `src/` unless PROJECT DISCOVERY proves file-uniqueness.
11. Acceptance criteria (binary pass/fail). Each criterion must be a boolean
    statement answerable by running a command or reading a test result.
    Human judgment is forbidden as a criterion.
12. Tests (new/update + purpose). For each new test file:
    - Exact filename
    - Exact test function names
    - What each test asserts (one-line description)
    - Registration: confirm file is added to `tests/test_runner_node.gd`.
    For each updated test file:
    - Exact filename
    - What changes and why (which legacy call is removed/replaced).
13. rg gates (command + expected output).
    Phase-specific gates first, then PMB gates.
    If a `## Persistent Module Boundary Contract` exists in the enclosing document:
      append all PMB-N commands labeled `[PMB-N] <command>` → expected: 0 matches.
    Each gate must specify exact rg command with all flags and expected output.
14. Execution sequence (step-by-step, no ambiguity). Must include in this order:
    - Step N: delete each legacy item from section 9 (one step per item)
    - Step N: implement new logic (one step per function/block, name exact target)
    - Step N: add/update tests and register each in `tests/test_runner_node.gd`
    - Step N: run Tier 1 smoke suite (exact commands from PHASE INPUT item 21)
    - Step N: run Tier 2 full regression:
      `xvfb-run -a godot-4 --headless --path . res://tests/test_runner.tscn` — must exit 0
    - Step N (conditional): if a listed test fails and Hard Rule 13 conditions
      are all satisfied, apply minimal test-only compatibility patch, rerun the
      failed command, and record the exception for section 21 report
    - Step N: run all rg gates from section 13 — all must return expected output
    - Step N: prepend CHANGELOG entry
    "Implement X" alone as a step is forbidden — each step names exact function/file/block.
15. Rollback conditions. For each condition: exact trigger + exact rollback action.
16. Phase close condition. Binary checklist. All items must be true simultaneously:
    - [ ] All rg commands in section 10 return 0 matches
    - [ ] All rg gates in section 13 return expected output
    - [ ] All tests in section 12 (new + updated) exit 0
    - [ ] Tier 1 smoke suite (PHASE INPUT item 21) — all commands exit 0
    - [ ] Tier 2 full regression (`test_runner.tscn`) exits 0
    - [ ] No file outside section 4 in-scope list was modified, except
          Hard Rule 13 test-only compatibility exception files
    - [ ] CHANGELOG entry prepended
    Additional phase-specific criteria may be added after these mandatory items.
17. Ambiguity self-check line: Ambiguity check: 0
18. Open questions line: Open questions: 0
19. Post-implementation verification plan (diff audit + contract checks +
    runtime scenarios). Must name: which files to diff, which contracts to
    check, and which runtime scenarios from section 20 to execute.
20. Runtime scenario matrix (scenario id, setup, frame count, expected invariants,
    fail conditions). Each scenario must be executable headless via:
    `xvfb-run -a godot-4 --headless --path . res://tests/<scene>.tscn`
    If no dedicated test scene exists for a scenario, state which existing scene
    covers it and which assertions prove the invariant.
21. Verification report format (what must be recorded to close phase). Must
    include field:
    `pmb_contract_check: [PMB-1: PASS|FAIL, PMB-2: PASS|FAIL, ...]`
    marked as blocking if PMB section exists in the document.
    Also include:
    `test_only_compatibility_exceptions: []` (empty list when unused; each
    entry records exact path + failing command + root-cause summary + "no prod
    file change used" confirmation).
22. Structural completeness self-check:
    "Sections present: [comma-separated list of section numbers 1–23].
    Missing sections: [list or NONE]."
    A spec with any section from 1–23 missing cannot close.
    - Evidence preamble (### Evidence) present between ## PHASE header and section 1: yes / NO → FAIL
    - PMB gates present in section 13 (if PMB section exists in document): yes / NO → FAIL
    - pmb_contract_check present in section 21 (if PMB section exists in document): yes / NO → FAIL
23. Dependencies on previous phases. For each dependency:
    - Phase id that introduced the behavior
    - Exact behavior being inherited (function name or invariant text)
    - Why this phase requires it
