# Stealth Combat Contract

Date: 2026-02-16
Scope: stealth/combat test room (`src/levels/stealth_test_config.gd`)

## Room State Formula

Priority rule for room state:

```text
effective_state = COMBAT if latch_count > 0 else transient_state
```

- `transient_state`: `CALM | SUSPICIOUS | ALERT` (TTL decay).
- `combat_latch`: set of latched enemies in the room.
- Formula above is mandatory and has strict priority over transient state.

## Aggro Event Matrix

- Hard sources (enter `combat_latch`):
  - visual confirm
  - direct damage
- Soft sources (do not enter `combat_latch`):
  - noise
  - body discovery
  - propagation

## Phase 1 Config Parameters

Required config values (source of truth: `StealthTestConfig.VALUES`):

```gdscript
"combat_last_seen_grace_sec": 1.5
"combat_room_migration_hysteresis_sec": 0.2
"combat_search_radius_px": 160
"combat_repath_interval_no_los_sec": 0.2
"combat_stuck_window_sec": 1.0
"combat_stuck_min_progress_px": 8
"combat_detour_offsets": [120, 180, 240]
"flashlight_active_in_alert": true
"flashlight_active_in_combat": true
"flashlight_bonus_in_alert": true
"flashlight_bonus_in_combat": true
"enemy_weapons_enabled_on_start": true
```
