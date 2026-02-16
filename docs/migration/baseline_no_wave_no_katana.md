# Baseline: Legacy Runtime Cleanup

Date (UTC): 2026-02-15
Project root: `/root/arena-shooter`

## Scope

This snapshot captures the current baseline after cleanup of legacy close-combat traces in runtime/UI and active documentation.

## Commands Executed

1. Legacy token control scan

```bash
rg -n --hidden -S '<legacy_tokens_regex>' src scenes tests project.godot README.md docs level_mvp_decomposition_contract.md
```

2. HUD controller suite

```bash
/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_level_hud_controller.tscn
```

3. Full test runner

```bash
/snap/godot-4/current/godot-4 --headless --path . --scene res://tests/test_runner.tscn
```

## Results

- Legacy token control scan: `0` matches in the control scope.
- `test_level_hud_controller`: `8/8` passed.
- `test_runner`: `101/101` passed.

## Baseline Decision Gate

Current baseline is healthy and accepted as a reference point for next migration iterations.
