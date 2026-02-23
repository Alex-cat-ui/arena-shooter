# Stealth Features Execution Plan

**All phases execute AFTER `ai_nav_refactor_execution_v2.md` is complete.**

---

## Dependency Order

```
SF-0: SP-1 Noise Foundation + NoiseRingVisual
├── SF-1: SN-1 Sprint Speed + Sprint Noise
├── SF-2: SK-1 Stealth Kill  ← depends on SF-3
├── SF-3: BD-1 Death Marker (CorpseMarker)
│   └── SF-4: BD-2 Missing Contact
├── SF-5: DT-1 Distraction Throwables
├── SF-6: FA-1 Flashlight Watcher Archetype
└── SF-7: LM-1 Light Fixtures + Switches
SF-8: AI-1..AI-6 + FEAR-1..4
SF-9B: MH-1 Door Stacking
SF-9A: 8B Cross-Room Patrol  ← benefits from SF-9B if present
```

SK-1 (SF-2) depends on BD-1 (SF-3): stealth kill spawns CorpseMarker.
Execution order: SF-0 → SF-1 → SF-3 → SF-2 → SF-4 → SF-5 → SF-6 → SF-7 → SF-8 → SF-9B → SF-9A.

---

## SF-0 / SP-1: Noise System Foundation + Noise Ring Visual

### Goal
Replace current room-only shot propagation with unified noise event bus (AND-model pixel radius filter)
and add in-world expanding ring visualization for every noise event.

### What Exists Now
- `NavigationService._on_player_shot()` propagates `player_shot` signal inline to same/adjacent rooms (binary, no radius filter).
- `enemy.on_heard_shot()` receives shot event.
- No visual feedback for noise.

### What Changes

**`src/core/event_bus.gd`** — add:
```gdscript
signal noise_event(pos: Vector2, radius: float, type: String)

func emit_noise(pos: Vector2, radius: float, type: String) -> void:
    noise_event.emit(pos, radius, type)

func emit_noise_room_wide(pos: Vector2, type: String) -> void:
    noise_event.emit(pos, -1.0, type)   # radius = -1.0 = room-wide flag
```

**`src/systems/navigation_service.gd`** — replace `_on_player_shot()` body:
```gdscript
func _on_player_shot(weapon: String, position: Vector2) -> void:
    if "shotgun" in weapon:
        EventBus.emit_noise(position, GameConfig.noise_radius_shotgun, "gunshot_shotgun")
    else:
        EventBus.emit_noise(position, GameConfig.noise_radius_pistol, "gunshot_pistol")
```
Connect `EventBus.noise_event` → `_on_noise_event(pos: Vector2, radius: float, type: String)`.

`_on_noise_event` AND-filter logic:
```gdscript
func _on_noise_event(pos: Vector2, radius: float, type: String) -> void:
    var noise_room := room_id_at_point(pos)
    for enemy in _get_all_enemies():
        var enemy_room := room_id_at_point(enemy.global_position)
        if radius == -1.0:  # room-wide: same room only
            if enemy_room != noise_room:
                continue
        else:
            if not is_same_or_adjacent_room(noise_room, enemy_room):
                continue
            if enemy.global_position.distance_to(pos) > radius:
                continue
        enemy.on_noise_event(pos, type)
```

**`src/entities/enemy.gd`** — add:
```gdscript
func on_noise_event(noise_pos: Vector2, noise_type: String) -> void
```
Delete: `on_heard_shot()` — dead after this phase.

Dispatch logic in `on_noise_event`:
- type in `{"gunshot_pistol", "gunshot_shotgun"}`: → ALERT + `investigate_anchor = noise_pos`
- type in `{"body_fall", "fixture_break", "distraction", "missing_contact"}`: → SUSPICIOUS + `investigate_anchor = noise_pos`
- type == `"lights_out"`: → SUSPICIOUS + `investigate_anchor = noise_pos` (= switch position passed as pos)
- type == `"sprint_footstep"`: `_sprint_suspicion_accumulator += GameConfig.sprint_footstep_suspicion_rate * delta` (held each frame while event is active within radius, not one-shot)

### Noise Types — Complete Table

| type | radius (px) | enemy reaction |
|------|-------------|----------------|
| `gunshot_pistol` | 220 | ALERT + investigate_anchor = noise_pos |
| `gunshot_shotgun` | 300 | ALERT + investigate_anchor = noise_pos |
| `body_fall` | 80 | SUSPICIOUS + investigate_anchor = noise_pos |
| `fixture_break` | 120 | SUSPICIOUS + investigate_anchor = noise_pos |
| `distraction` | 280 | SUSPICIOUS + investigate_anchor = noise_pos |
| `sprint_footstep` | 60 | suspicion += sprint_footstep_suspicion_rate/s, not instant ALERT |
| `missing_contact` | 80 | SUSPICIOUS + investigate_anchor = noise_pos |
| `lights_out` | room-wide (-1) | SUSPICIOUS + investigate_anchor = noise_pos (switch pos) |

`sprint_footstep` does NOT trigger instant state change. Suspicion accumulates per second while enemy remains within 60px of noise_pos. If suspicion threshold reached → normal state transition.

### AND-Model Definition
Enemy hears noise event IF:
1. `is_same_or_adjacent_room(noise_room, enemy_room)` == true
2. AND `enemy.global_position.distance_to(noise_pos) <= noise_radius`

Exception: `radius == -1.0` (room-wide) → only condition 1, condition 2 ignored.

### Noise Ring Visual System
New file: `src/systems/noise_ring_system.gd`, extends Node2D.
Added as child of World scene root. Subscribes to `EventBus.noise_event`.
Uses pooled Line2D nodes (same pattern as MeleeArcSystem).

On `noise_event(pos, radius, type)`:
- Spawn ring at `pos`, starting `current_radius = 0.0`
- Each frame: `current_radius += (display_radius / noise_ring_expand_duration) * delta`
- Line2D redrawn as circle (64 points) at `current_radius`
- Alpha fades from initial to 0.0 over `noise_ring_expand_duration`
- When `current_radius >= display_radius`: return node to pool

`display_radius` for `lights_out` (radius=-1.0) = 160.0 (visual approximation only, not gameplay).

Ring parameters by type:

| type | color | width_px | ring_count | ring_delay_s |
|------|-------|----------|------------|-------------|
| `sprint_footstep` | Color(1.0, 0.55, 0.0, 0.7) | 1.5 | 1 | 0.0 |
| `gunshot_pistol` | Color(0.95, 0.15, 0.1, 0.9) | 2.5 | 3 | 0.05 |
| `gunshot_shotgun` | Color(0.7, 0.05, 0.05, 0.9) | 3.0 | 3 | 0.05 |
| `distraction` | Color(1.0, 0.9, 0.0, 0.8) | 2.0 | 1 | 0.0 |
| `body_fall` | Color(0.65, 0.65, 0.65, 0.6) | 1.5 | 1 | 0.0 |
| `fixture_break` | Color(1.0, 1.0, 0.8, 0.8) | 2.0 | 1 | 0.0 |
| `missing_contact` | Color(0.6, 0.6, 1.0, 0.6) | 1.5 | 1 | 0.0 |
| `lights_out` | Color(0.3, 0.5, 1.0, 0.7) | 2.0 | 1 | 0.0 |

Multi-ring (ring_count > 1): rings 2 and 3 are spawned with delay `(i-1) * ring_delay_s` after ring 1.
NoiseRingSystem is purely visual. It does NOT affect gameplay, AI, or any game state.

### GameConfig Constants
```gdscript
noise_radius_pistol: float = 220.0
noise_radius_shotgun: float = 300.0
noise_radius_body_fall: float = 80.0
noise_radius_fixture_break: float = 120.0
noise_radius_distraction: float = 280.0
noise_radius_sprint_footstep: float = 60.0
noise_radius_missing_contact: float = 80.0
sprint_footstep_suspicion_rate: float = 0.15   # per second
noise_ring_expand_duration: float = 0.4
noise_ring_gunshot_count: int = 3
noise_ring_gunshot_delay: float = 0.05
```

### Legacy to Delete
- `enemy.on_heard_shot()` in `src/entities/enemy.gd` — delete (replaced by `on_noise_event`)
- Inline shot-to-enemy propagation loop in `NavigationService._on_player_shot()` — replace with `emit_noise` call
- Any `EventBus.player_shot` connection in NavigationService used for enemy propagation — disconnect

### Tests
`tests/test_noise_system_sp1.gd`:
- `test_and_model_radius_filter_blocks_far_enemy` — enemy outside radius does not receive event
- `test_and_model_room_filter_blocks_nonadjacent` — non-adjacent room enemy does not receive event
- `test_room_wide_reaches_all_same_room` — lights_out (radius=-1) reaches all enemies in same room only
- `test_gunshot_triggers_alert` — gunshot_pistol → ALERT
- `test_distraction_triggers_suspicious` — distraction → SUSPICIOUS
- `test_sprint_footstep_accumulates_suspicion` — sprint_footstep increments suspicion, not instant state

### Out of Scope
- Wall occlusion (no ray-cast against geometry for noise)
- Multi-hop propagation (noise does not re-emit from receivers)
- Noise from enemy weapons

---

## SF-1 / SN-1: Sprint Speed + Sprint Noise

### Goal
Slow all movement by 1.5x. Sprint (shift) restores original player speed. Sprint emits noise.

### Current Speed Values (pre-SN-1)
- `player_speed_tiles = 10.0` (game_config.gd)
- Zombie: `speed_tiles = 2.0`, Fast: `4.0`, Tank: `1.5`, Swarm: `3.0` (enemy.gd, from stats)
- `PATROL_SPEED_SCALE = 0.82` (enemy_patrol_system.gd)

### Speed Design — Variant A (patrol = nerfed, alert/combat = original pre-nerf)

| Entity | Walk / Patrol | Alert / Combat |
|--------|--------------|----------------|
| Player | **6.7 tiles/sec** (new constant) | **10.0 tiles/sec** (shift key, existing) |
| Zombie | patrol: **1.09** | **2.0** (original) |
| Fast | patrol: **2.19** | **4.0** (original) |
| Tank | patrol: **0.82** | **1.5** (original) |
| Swarm | patrol: **1.64** | **3.0** (original) |

Patrol speed formula: `speed_tiles * (1.0 / GameConfig.enemy_patrol_speed_divisor) * PATROL_SPEED_SCALE`
= `speed_tiles * 0.667 * 0.82`

Alert/combat speed: `speed_tiles` (original, divisor NOT applied).
Suspicious state: uses patrol speed (same as CALM).

Rationale: player walk (6.7) > all enemy patrol speeds → stealth viable.
Enemy alert/combat speed < player sprint (10.0) → player can always escape.
Enemy alert/combat speed mixed vs player walk → creates tactical tension.

### What Changes

**`src/core/game_config.gd`**:
```gdscript
player_walk_speed_tiles: float = 6.7    # new constant; was implicitly = player_speed_tiles
enemy_patrol_speed_divisor: float = 1.5  # new constant
# player_speed_tiles = 10.0 remains (= sprint speed)
```

**`src/entities/player.gd`** (or player input handler):
- Default movement speed: `GameConfig.player_walk_speed_tiles` (6.7)
- When `Input.is_action_pressed("sprint")`: speed = `GameConfig.player_speed_tiles` (10.0)
- Sprint noise: timer `_sprint_noise_timer`; while sprinting, every `sprint_noise_interval` (0.3s):
  ```gdscript
  EventBus.emit_noise(global_position, GameConfig.noise_radius_sprint_footstep, "sprint_footstep")
  ```
- Walk: no noise emission.

**`src/systems/enemy_patrol_system.gd`**:
```gdscript
var patrol_speed: float = speed_tiles * (1.0 / GameConfig.enemy_patrol_speed_divisor) * PATROL_SPEED_SCALE
```

**`src/entities/enemy.gd`** or `src/systems/enemy_pursuit_system.gd`**:
- ALERT/COMBAT: speed = `speed_tiles` (no divisor)
- CALM/SUSPICIOUS (patrol): speed = patrol formula above

### Sprint Noise Reaction Detail
`sprint_footstep` is processed in `enemy.on_noise_event()`:
- enemy.awareness == CALM: `_sprint_suspicion += GameConfig.sprint_footstep_suspicion_rate * delta` while within 60px
- enemy.awareness == SUSPICIOUS: same accumulation but × 2.0 multiplier
- enemy.awareness == ALERT/COMBAT: event ignored (already aware)

Sprint_footstep events fire every 0.3s. Enemy continuously checks proximity each physics frame.
`_sprint_suspicion` feeds into normal suspicion threshold → normal state transition if threshold reached.

### GameConfig Constants
```gdscript
player_walk_speed_tiles: float = 6.7
enemy_patrol_speed_divisor: float = 1.5
sprint_noise_interval: float = 0.3
# noise_radius_sprint_footstep defined in SP-1
```

### Tests
`tests/test_sprint_noise_sn1.gd`:
- `test_player_walk_uses_walk_speed` — default speed = 6.7
- `test_player_sprint_uses_sprint_speed` — shift held = 10.0
- `test_enemy_patrol_speed_divided` — zombie patrol speed ≈ 1.09
- `test_enemy_alert_speed_original` — zombie alert speed = 2.0 (no divisor)
- `test_sprint_emits_noise_every_interval` — noise emitted each 0.3s while sprinting
- `test_walk_no_noise_emission` — walking emits no noise_event

### Out of Scope
- Enemy footstep noise
- Crouch mechanic
- Audio for footsteps (AI detection only)

---

## SF-3 / BD-1: Death Marker (CorpseMarker)

*(SF-3 before SF-2: SK-1 depends on CorpseMarker)*

### Goal
Enemy deaths leave discoverable evidence without full body FSM.

### New Node
`src/systems/stealth/corpse_marker.gd`, extends Area2D.
```gdscript
var ttl: float                   # set on _ready: randf_range(60.0, 120.0)
var radius: float = 80.0
var kill_type: String = "normal" # "normal" | "stealth_kill"
```
Collision: CircleShape2D radius=80.0, `monitoring = true`, `monitorable = false`.
Added to group `"corpse_markers"` on `_ready()`.

### Spawn
In `enemy.die(kill_type: String = "normal")`:
```gdscript
var marker := CorpseMarker.new()
marker.kill_type = kill_type
marker.global_position = global_position
get_tree().current_scene.add_child(marker)
```

### On Spawn
- `kill_type == "normal"`: `EventBus.emit_noise(global_position, GameConfig.noise_radius_body_fall, "body_fall")`
- `kill_type == "stealth_kill"`: no noise emission

### Discovery
Triggered when patrolling enemy enters CorpseMarker Area2D (`body_entered` signal):
1. If enemy.awareness == ALERT or COMBAT: ignore (already knows about threat)
2. Otherwise: `enemy.on_noise_event(marker.global_position, "body_fall")`
3. Chain reaction: `EventBus.emit_noise(marker.global_position, GameConfig.corpse_marker_chain_radius, "body_fall")`

Chain reaction allows nearby enemies to also react without having to enter the marker zone.

### Cleanup
- `_process(delta)`: `ttl -= delta; if ttl <= 0: queue_free()`
- All enemies dead in scene: all markers `queue_free()` immediately

### GameConfig Constants
```gdscript
corpse_marker_ttl_min: float = 60.0
corpse_marker_ttl_max: float = 120.0
corpse_marker_radius: float = 80.0
corpse_marker_chain_radius: float = 120.0
```

### Tests
`tests/test_corpse_marker_bd1.gd`:
- `test_normal_kill_emits_body_fall_noise`
- `test_stealth_kill_no_noise_on_spawn`
- `test_discovery_triggers_suspicious`
- `test_chain_reaction_on_discovery`
- `test_ttl_expires_queue_free`
- `test_alert_enemy_ignores_discovery`

### Out of Scope
- Body dragging
- Radio call to HQ
- Corpse sprite (handled by CombatFeedbackSystem, separate)

---

## SF-2 / SK-1: Stealth Kill

### Goal
Instant silent kill from behind. Core reward mechanic for stealth play.

### E Key Priority Order
1. **SK-1** — all conditions true → execute stealth kill
2. **LM-1 switch** — LightSwitch within `light_switch_interact_range` (64px) → `switch.toggle()`
3. **Door** — existing door interaction logic

Priority 1 is checked first. If conditions not met, check priority 2, then 3.

### Conditions (all must be simultaneously true)
1. `player.global_position.distance_to(enemy.global_position) <= GameConfig.sk1_range` (80.0px)
2. Player in 60° cone behind enemy:
   - `facing_dir = enemy.velocity.normalized()` if `enemy.velocity.length() > 0.1`, else `enemy._last_facing_dir`
   - `behind_angle = atan2(-facing_dir.y, -facing_dir.x)`
   - `angle_to_player = atan2(player_pos.y - enemy_pos.y, player_pos.x - enemy_pos.x)`
   - `diff = abs(wrapf(angle_to_player - behind_angle, -PI, PI))`
   - Condition: `diff <= deg_to_rad(GameConfig.sk1_cone_half_angle_deg)` (30.0°)
3. `enemy.can_see_player() == false` (works in any awareness state)

All three conditions must be true. Failure of any one = no stealth kill.

### UI Hint
While all conditions true: `enemy.modulate = Color(1.3, 0.3, 0.3, 1.0)` (red tint, visible cue).
Modulate resets to `Color(1, 1, 1, 1)` immediately when any condition fails.
No text prompt.

### On E Press (all conditions true)
1. `enemy.die("stealth_kill")` — CorpseMarker spawns without noise (BD-1 contract)
2. No `emit_noise` call (0px radius = silent)
3. `enemy.set_physics_process(false)` for `GameConfig.sk1_freeze_duration` (0.25s) — animation placeholder
4. Player input locked for `GameConfig.sk1_input_lock_duration` (0.25s)

### Approach Suspicion (pre-kill zone)
While player is within `sk1_approach_range` (120px) AND in 60° behind cone AND NOT within kill range (80px):
- `enemy.awareness_system.add_suspicion(GameConfig.sk1_approach_suspicion_rate * delta)` (0.08/s)
- Uses existing suspicion ring visual (no new visual needed)
- Enemy may turn and detect player if suspicion reaches threshold before kill

### GameConfig Constants
```gdscript
sk1_range: float = 80.0
sk1_cone_half_angle_deg: float = 30.0
sk1_approach_range: float = 120.0
sk1_approach_suspicion_rate: float = 0.08
sk1_freeze_duration: float = 0.25
sk1_input_lock_duration: float = 0.25
```

### Tests
`tests/test_stealth_kill_sk1.gd`:
- `test_sk1_all_conditions_executes_kill`
- `test_sk1_out_of_range_no_kill`
- `test_sk1_wrong_angle_no_kill`
- `test_sk1_enemy_sees_player_no_kill`
- `test_sk1_spawns_corpsemarker_silent`
- `test_sk1_approach_zone_accumulates_suspicion`
- `test_sk1_priority_over_switch` — SK-1 executes before LightSwitch when both available

### Out of Scope
- Carry body
- Special kill animation assets (placeholder freeze only in this phase)

---

## SF-4 / BD-2: Missing Contact

### Goal
Simulate "where is colleague?" AI reaction when a patrol post becomes empty.
No radio. No explicit communication. Pure behavior simulation.

### Mechanism
On enemy death: `NavigationService` registers `DeadPost`:
```gdscript
var dead_posts: Array = []  # Array of Dictionary

# On enemy.die():
dead_posts.append({
    "pos": enemy.home_pos,       # Vector2: the enemy's patrol home position
    "room_id": enemy.home_room_id,
    "timer": randf_range(GameConfig.missing_contact_delay_min, GameConfig.missing_contact_delay_max)
})
```

Each `_physics_process(delta)` in NavigationService:
```gdscript
for i in range(dead_posts.size() - 1, -1, -1):
    dead_posts[i]["timer"] -= delta
    if float(dead_posts[i]["timer"]) <= 0.0:
        EventBus.emit_noise(
            dead_posts[i]["pos"],
            GameConfig.noise_radius_missing_contact,
            "missing_contact"
        )
        dead_posts.remove_at(i)
```

### Enemy Reaction to `missing_contact`
Handled entirely by `on_noise_event` (SP-1):
- CALM → SUSPICIOUS + `investigate_anchor = noise_pos`
- SUSPICIOUS/ALERT: update `investigate_anchor = noise_pos` only if `enemy.global_position.distance_to(noise_pos) < enemy.global_position.distance_to(current_investigate_anchor)`

### Visual
Uses existing `enemy_alert_marker_presenter.gd`:
SUSPICIOUS state → "?" icon appears automatically. No additional visual assets or code required.
The effect from the player's perspective: a patrolling enemy in another area unexpectedly changes course toward where a colleague died. The "?" icon communicates "something is wrong."

### GameConfig Constants
```gdscript
missing_contact_delay_min: float = 15.0
missing_contact_delay_max: float = 30.0
# noise_radius_missing_contact defined in SP-1
```

### Tests
`tests/test_missing_contact_bd2.gd`:
- `test_dead_post_registered_on_enemy_death`
- `test_timer_fires_noise_event_at_pos`
- `test_noise_event_triggers_suspicious`
- `test_post_removed_after_fire`
- `test_no_reaction_if_enemy_already_alert`

### Out of Scope
- Radio calls or explicit communication animation
- Patrol counting rewrite
- Chain "all enemies alert" reaction from missing_contact

---

## SF-5 / DT-1: Distraction Throwables

### Goal
Player throws items to create distraction noise at a targeted position.
Worms 2-style power meter: hold key to charge distance, release to throw.

### Items
Types: Bottle, Stone. Cosmetically different sprites, mechanically identical.
Level placement: 1–3 items per level, random room positions (by level generator — separate phase).
Max carried: `throwable_max_carried` = 3.
HUD: item count displayed bottom-right, adjacent to ammo counter.

### Pickup
Trigger: player within `throwable_pick_range` (48px) of item AND (auto-enter OR E key press).
E key priority: pickup is lower priority than SK-1 and LightSwitch — checked after those.
On pickup: `inventory_count += 1` (max 3). Item node `queue_free()`.

### Throwing — Worms 2 Power Meter

**Input action**: `throw_item` (F key, new action).

**Charging** (while F held):
```gdscript
var _throw_charge: float = 0.0      # 0.0 = min, 1.0 = max
var _throw_direction: Vector2       # player → cursor, normalized, updated each frame

# In _process(delta) while Input.is_action_pressed("throw_item"):
_throw_charge = min(_throw_charge + delta / GameConfig.throwable_max_charge_time, 1.0)
_throw_direction = (get_global_mouse_position() - global_position).normalized()
```

**On F release** (if `_throw_charge > 0` and `inventory_count > 0`):
```gdscript
var distance: float = _throw_charge * GameConfig.throwable_max_range
var landing_pos: Vector2 = global_position + _throw_direction * distance
# No further clamping needed: _throw_charge ∈ [0, 1], distance ∈ [0, throwable_max_range]
_spawn_throwable(global_position, landing_pos)
inventory_count -= 1
_throw_charge = 0.0
```

If `inventory_count == 0`: F key does nothing. `ThrowMeterUI` does not appear.

### Power Bar UI — `ThrowMeterUI`

New node: `src/ui/throw_meter_ui.gd`, extends Node2D. Added as child of player.

**Position**: `player.global_position + Vector2(0.0, 26.0)` (26px below player center, world-space).

**Bar spec**:
- Total size: 50px wide × 5px tall
- Border: 1px, `Color(0.1, 0.1, 0.1, 0.9)`
- Fill direction: left to right
- Color by charge fraction:
  - `charge < 0.5`: `Color(0.2, 0.8, 0.2, 0.9)` (green)
  - `0.5 ≤ charge < 0.8`: `Color(0.9, 0.7, 0.1, 0.9)` (yellow)
  - `charge ≥ 0.8`: `Color(0.9, 0.2, 0.1, 0.9)` (red)
- Appears when `_throw_charge > 0`, disappears immediately on release

**Trajectory arc** (while charging):
- Line2D with 8 points, from `player_pos` to `landing_pos`
- Arc peak height: `max(20.0, distance * GameConfig.throwable_arc_height_factor)` (parabolic, upward in screen)
- Point `i` of 8: `t = i / 7.0`, pos = `lerp(start, end, t) + Vector2(0.0, -sin(t * PI) * arc_peak)`
- Color: `Color(1.0, 1.0, 1.0, 0.5)` (translucent white)
- Updates every frame while charging

**Landing indicator** (at `landing_pos`):
- Circle (drawn via `draw_arc`): radius 16px
- Color: `Color(1.0, 1.0, 0.5, 0.7)` (translucent yellow)
- Pulses: `scale = 1.0 + 0.1 * sin(Time.get_ticks_msec() * 0.006)` (oscillates 0.9→1.1 at ~1Hz)

### ThrowableItem Node
New file: `src/systems/stealth/throwable_item.gd`, extends Area2D.
```gdscript
var start_pos: Vector2
var end_pos: Vector2
var arc_peak: float
var _elapsed: float = 0.0
```
`_physics_process(delta)`:
```gdscript
_elapsed += delta
var t: float = _elapsed / GameConfig.throwable_flight_duration
var base_pos: Vector2 = start_pos.lerp(end_pos, t)
var arc_offset: float = -sin(t * PI) * arc_peak
global_position = base_pos + Vector2(0.0, arc_offset)
if _elapsed >= GameConfig.throwable_flight_duration:
    EventBus.emit_noise(end_pos, GameConfig.noise_radius_distraction, "distraction")
    queue_free()
```

### Enemy Reaction to `distraction`
Handled via `on_noise_event`:

| State | Reaction |
|-------|---------|
| CALM | → SUSPICIOUS + `investigate_anchor = noise_pos` |
| SUSPICIOUS | update `investigate_anchor = noise_pos` |
| ALERT | update `investigate_anchor = noise_pos` IF `not can_see_player()` at that moment |
| COMBAT | ignored |

Enemy arrives at `investigate_anchor`: LOOK sweep for `randf_range(throwable_investigate_duration_min, throwable_investigate_duration_max)` seconds, then returns to patrol post.

### GameConfig Constants
```gdscript
throwable_max_range: float = 280.0
throwable_flight_duration: float = 0.4
throwable_max_charge_time: float = 1.0
throwable_max_carried: int = 3
throwable_pick_range: float = 48.0
throwable_investigate_duration_min: float = 3.0
throwable_investigate_duration_max: float = 5.0
throwable_arc_height_factor: float = 0.3
```

### Tests
`tests/test_throwable_dt1.gd`:
- `test_pickup_adds_to_inventory`
- `test_throw_emits_distraction_at_landing_pos`
- `test_max_range_respected_at_full_charge`
- `test_zero_charge_minimal_distance`
- `test_distraction_triggers_suspicious`
- `test_empty_inventory_no_throw`
- `test_power_bar_appears_on_charge_start`

### Out of Scope
- Damage from throw
- Explosive throwables
- Replenishment between levels (items are per-level only)

---

## SF-6 / FA-1: Flashlight Watcher Archetype

### Goal
Enemy type with always-on flashlight. Neutralizes shadow-hiding strategy.

### Implementation
NOT a separate GDScript class. Config flag set on enemy initialization via spawn config dict.
Enemy type key used by level generator: `"watcher"`.

### Watcher-Specific Fields (set on spawn via config dict)
```gdscript
always_flashlight: bool = true
min_awareness_state: int = EnemyAlertLevels.SUSPICIOUS   # awareness floor
patrol_speed_multiplier: float = 0.8       # applied on top of patrol speed
flashlight_cone_angle_deg: float = 70.0    # vs standard 45°
```

### Behavioral Differences vs Standard Enemy

1. **Flashlight**: `_shadow_check_flashlight_override = true` always (forced on, ignores awareness state).
2. **Awareness floor**: attempt to transition to CALM → stays SUSPICIOUS instead. Watcher is always at least SUSPICIOUS.
3. **Shadow zones**: do not hide player from Watcher (flashlight illuminates cone, ignores `shadow_mul = 0`).
4. **Speed**: `patrol_speed *= patrol_speed_multiplier` (0.8 × normal patrol speed = slower but more thorough).
5. **Detection angle**: uses `flashlight_cone_angle_deg = 70.0` instead of standard 45°.

### Integration
Watcher counts as 1 enemy from room budget (replaces one standard enemy, not added extra).
Explicit placement: `{"type": "watcher", "room_id": N}` in room spawn config.
Recommended: 0–1 Watcher per level, placed in key rooms only.

Spawn system reads config dict → if `config.get("always_flashlight", false)`: apply watcher fields above.

### Tests
`tests/test_watcher_fa1.gd`:
- `test_watcher_flashlight_always_on_regardless_of_state`
- `test_watcher_awareness_floor_stays_suspicious`
- `test_watcher_detects_player_in_shadow_zone`
- `test_watcher_wider_cone_detects_angled_player`
- `test_watcher_speed_reduced_vs_standard`

### Out of Scope
- Watcher as boss or miniboss
- Unique patrol routes for Watcher
- Watcher-specific team coordination

---

## SF-7 / LM-1: Light Fixtures + Switches

### Goal
Toggleable and destructible light sources control shadow zone activation.
Riddick-inspired tactical darkness. Test level integration only (generator integration = separate phase).

### New Nodes

#### `LightFixture` — `src/systems/stealth/light_fixture.gd`, extends Node2D
```gdscript
var light_on: bool = true
@export var linked_shadow_zone_path: NodePath   # path to child ShadowZone
@export var breakable: bool = true
@export var sprite_on: Texture2D
@export var sprite_off: Texture2D
@onready var _point_light: PointLight2D = $PointLight2D
@onready var _shadow_zone: ShadowZone = get_node(linked_shadow_zone_path)

func set_light(on: bool) -> void:
    light_on = on
    _point_light.enabled = on
    _shadow_zone.monitoring = not on
    $Sprite2D.texture = sprite_on if on else sprite_off
```
PointLight2D child: `energy = 1.2`, `range = 256.0`, `color = Color(1.0, 0.95, 0.8)` (warm white).

#### `LightSwitch` — `src/systems/stealth/light_switch.gd`, extends Node2D
```gdscript
@export var interact_range: float = 64.0
@export var linked_fixtures: Array[NodePath]
var is_on: bool = true

func toggle() -> void:
    is_on = not is_on
    for fp in linked_fixtures:
        var fixture := get_node(fp) as LightFixture
        if fixture:
            fixture.set_light(is_on)
    if not is_on:
        EventBus.emit_noise_room_wide(global_position, "lights_out")
    # Turning back ON: silent (no noise emission)
```

### Visual Implementation

**Scene ambient setup (one CanvasModulate per scene)**:
```gdscript
CanvasModulate.color = Color(0.3, 0.3, 0.35)  # dim ambient, slightly blue
```
This darkens the entire scene. LightFixture's PointLight2D adds warm brightness locally.

**Per LightFixture**:
- Light ON: `PointLight2D.enabled = true` → warm circular glow on floor around fixture → room looks normally lit
- Light OFF: `PointLight2D.enabled = false` → room falls to ambient (30% brightness, cool blue)

**Player visual in darkness (Mark of Ninja style)**:
- Player has `PointLight2D` child: `energy = 0.15`, `range = 70.0`, `color = Color(1.0, 1.0, 1.0)` — player always sees themselves; AI ignores this light (visual only)
- Player enters ShadowZone: `player.modulate = Color(0.5, 0.55, 0.7, 1.0)` (blue-grey tint) + outline shader activates (2px white outline)
- Player exits ShadowZone: `player.modulate = Color(1.0, 1.0, 1.0, 1.0)`, outline off

**Enemy in ShadowZone**:
- `enemy.modulate = Color(0.6, 0.6, 0.65, 1.0)` (dimmer but readable)
- No outline shader on enemies

**Test level**: LightFixture and LightSwitch placed manually as scene nodes. CanvasModulate is one global node per scene.

### Shooting a Fixture (`breakable = true`)

Bullet collides with LightFixture CollisionShape2D:
1. `fixture.set_light(false)` (fixture permanently off after being shot)
2. `EventBus.emit_noise(fixture.global_position, GameConfig.noise_radius_fixture_break, "fixture_break")`
3. `fixture.breakable = false` (prevents second collision handling)

Broken fixture cannot be re-enabled by any means (switch remains but fixture ignores toggle).
`sprite_off` shows broken lamp texture.

### Enemy Reactions — Complete Case Matrix

**Case 1: Player uses switch, enemies in SAME room**
→ `emit_noise_room_wide(switch_pos, "lights_out")` fires.
→ All same-room enemies receive `on_noise_event(switch_pos, "lights_out")`.
→ Each: SUSPICIOUS + `investigate_anchor = switch_pos`.
→ Enemy walks to switch. No player found → `switch.toggle()` (re-enables) → LOOK sweep `randf_range(5.0, 8.0)` s → CALM.

**Case 2: Player uses switch, enemies in OTHER rooms**
→ `emit_noise_room_wide` = same room only. Enemies in other rooms receive nothing.
→ They have zero knowledge of the light change.
→ They ONLY react when physically entering the dark room (Case 3).

**Case 3: Enemy enters dark room during patrol (any room transition)**
At waypoint arrival: check `navigation_service.room_has_active_shadow_zones(new_room_id)`.
If `true` AND `enemy.awareness == CALM`:
- → SUSPICIOUS "dark_room"
- `investigate_anchor = nearest_switch_pos_in_room`
- Enemy walks to switch → toggles back on → LOOK sweep → CALM

**Case 4: No enemies patrol the dark room**
Light stays off for the remainder of the level. No automatic restoration.
This is correct designed behavior — unpatrolled areas remain dark.

**Case 5: Player shoots fixture, enemy in adjacent room**
→ `fixture_break` noise at `noise_radius_fixture_break` (120px), AND-model applies.
→ Enemy in adjacent room within 120px AND same/adjacent room → SUSPICIOUS → `investigate_anchor = fixture_pos`.
→ If enemy enters the now-dark room: Case 3 applies (waypoint check, goes to switch).
→ Switch still works (switch was not broken, only fixture was).

**Enemy re-enable protocol (reaching switch)**:
1. `switch.is_on == true` already (someone else re-enabled first): skip toggle, LOOK sweep 3s → CALM.
2. `switch.is_on == false`: `switch.toggle()` (re-enables lights) → LOOK sweep `randf_range(5.0, 8.0)` s → CALM.
3. Player spotted during approach to switch: → ALERT (normal detection flow, abandons switch goal).

**Watcher (FA-1) in dark room**: Watcher's always-on flashlight is unaffected by room darkness. Watcher does not react to "dark_room" condition (no SUSPICIOUS trigger). Standard enemies entering the same room still react normally.

### NavigationService New Method
```gdscript
func room_has_active_shadow_zones(room_id: int) -> bool
```
Returns `true` if any ShadowZone with `monitoring = true` has its global_position within the bounds of `room_id`.
ShadowZones register themselves with NavigationService via `NavigationService.register_shadow_zone(self)` on `_ready()`.

### GameConfig Constants
```gdscript
light_switch_interact_range: float = 64.0
light_enemy_investigate_duration_min: float = 5.0
light_enemy_investigate_duration_max: float = 8.0
light_enemy_relight_look_duration_min: float = 3.0
light_enemy_relight_look_duration_max: float = 5.0
# noise_radius_fixture_break defined in SP-1
```

### Tests
`tests/test_light_fixtures_lm1.gd`:
- `test_toggle_off_activates_shadow_zone`
- `test_toggle_on_deactivates_shadow_zone`
- `test_toggle_off_emits_noise_room_wide`
- `test_toggle_on_no_noise`
- `test_lights_out_noise_same_room_only`
- `test_enemy_enters_dark_room_goes_suspicious`
- `test_enemy_reenables_switch_returns_calm`
- `test_shoot_fixture_emits_fixture_break`
- `test_broken_fixture_cannot_reenable_via_switch`
- `test_watcher_not_affected_by_dark_room`

### Out of Scope
- Fusebox (whole-wing shutoff) — LM-2, optional future phase
- Pitch-black rooms: ambient is always ≥ 30% brightness for readability
- Torch-carrying enemies restoring light while moving
- Cross-room dark room discovery via normal patrol: only via noise events until SF-9A (8B) is implemented
- Generator integration: test level only in this phase

---

## SF-8: AI Improvements (AI-1..6 + FEAR-1..4)

All features are additive — extend existing state machines without replacing them.
Primary files: `enemy_awareness_system.gd`, `enemy_perception_system.gd`, `enemy_patrol_system.gd`, `enemy_pursuit_system.gd`.
Tests: `tests/test_ai_improvements.gd` (AI-1..6), `tests/test_fear_behaviors.gd` (FEAR-1..4).

---

### AI-1: Recognition Delay

**Goal**: 0.15–0.3s warmup before suspicion starts building. Enemy "looks twice."

**What exists**: suspicion accumulates immediately when player enters LOS in `process_confirm()`.

**Change** in `enemy_awareness_system.gd`:
```gdscript
var recognition_delay: float = 0.0   # set on spawn: randf_range(0.15, 0.30)
var _recognition_timer: float = 0.0
```
In `process_confirm()`, at start of `valid_contact == true` branch:
```gdscript
if _recognition_timer < recognition_delay:
    _recognition_timer += delta
    return  # do not accumulate suspicion yet
```
Reset `_recognition_timer = 0.0` when `_los_lost_time > grace_window` (LOS truly lost).

**GameConfig**: `ai_recognition_delay_min: float = 0.15`, `ai_recognition_delay_max: float = 0.30`

**Tests**: `test_ai1_recognition_delay_prevents_instant_suspicion`

---

### AI-2: Share Search Anchors

**Goal**: ALERT enemy broadcasts last_seen_pos to nearby enemies.

**What exists**: no cross-enemy communication on alert entry.

**Change** in `src/core/event_bus.gd`:
```gdscript
signal alert_anchor_broadcast(from_pos: Vector2, anchor_pos: Vector2)
```
In `enemy_awareness_system.gd`, on ALERT state entry:
```gdscript
EventBus.alert_anchor_broadcast.emit(owner.global_position, _last_seen_pos)
```
`NavigationService` listens to `alert_anchor_broadcast`:
```gdscript
func _on_alert_anchor_broadcast(from_pos: Vector2, anchor_pos: Vector2) -> void:
    var from_room := room_id_at_point(from_pos)
    for enemy in _get_all_enemies():
        if enemy.global_position.distance_to(from_pos) > GameConfig.ai2_broadcast_radius:
            continue
        if not is_same_or_adjacent_room(from_room, room_id_at_point(enemy.global_position)):
            continue
        if enemy.awareness_state == EnemyAlertLevels.COMBAT:
            continue
        enemy.set_investigate_anchor(anchor_pos)
```

**GameConfig**: `ai2_broadcast_radius: float = 300.0`

**Tests**: `test_ai2_nearby_enemy_receives_anchor`, `test_ai2_far_enemy_ignored`, `test_ai2_combat_enemy_ignored`

---

### AI-3: Interrupt Reaction

**Goal**: Enemy at waypoint does LOOK sweep if CorpseMarker or blood decal nearby.

**What exists**: enemy idles at waypoint without checking environment.

**Change** in `enemy_patrol_system.gd`, called at waypoint idle start:
```gdscript
func _check_nearby_evidence() -> bool:
    for marker in get_tree().get_nodes_in_group("corpse_markers"):
        if owner.global_position.distance_to(marker.global_position) <= GameConfig.ai3_evidence_radius:
            return true
    for decal in get_tree().get_nodes_in_group("blood_decals"):
        if owner.global_position.distance_to(decal.global_position) <= GameConfig.ai3_evidence_radius:
            return true
    return false
```
If `_check_nearby_evidence()` returns true: insert 2.0s LOOK sweep (rotate +45°, hold 0.5s, rotate -45°, hold 0.5s, return forward) before normal idle resume.
Blood decals must be in group `"blood_decals"` (verify with CombatFeedbackSystem; add to group if not present).
CorpseMarkers are in group `"corpse_markers"` (added in BD-1).

**GameConfig**: `ai3_evidence_radius: float = 80.0`

**Tests**: `test_ai3_corpsemarker_triggers_look_sweep`, `test_ai3_blood_decal_triggers_look_sweep`, `test_ai3_no_evidence_no_sweep`

---

### AI-4: Coordinated Search Formation

**Goal**: Squad in ALERT assigns different anchor points instead of all converging on same point.

**What exists**: squad roles for patrol assignment; no ALERT-state coordination.

**Change**: extend squad role system (file TBD from squad system inspection) to ALERT state.
When squad (2+ enemies sharing home_room_id) all enter ALERT:
- Squad leader: `investigate_anchor = _last_seen_pos`
- Flanker 1: `investigate_anchor = _last_seen_pos + perp * GameConfig.ai4_search_spread_px`
- Flanker 2: `investigate_anchor = _last_seen_pos - perp * GameConfig.ai4_search_spread_px`

Where `perp` = perpendicular to `(_last_seen_pos - enemy.global_position).normalized()`, clamped to room bounds.

**GameConfig**: `ai4_search_spread_px: float = 80.0`

**Tests**: `test_ai4_squad_assigns_different_anchors`, `test_ai4_single_enemy_no_spread`

---

### AI-5: Combat→ALERT Memory

**Goal**: Use position-at-LOS-loss as investigate anchor, not stale `_last_seen_pos`.

**What exists**: COMBAT→ALERT transition uses `_last_seen_pos` which may be outdated.

**Change** in `enemy_awareness_system.gd`:
```gdscript
var _los_loss_position: Vector2 = Vector2.ZERO
var _was_valid_contact: bool = false
```
In `process_confirm()`:
```gdscript
if _was_valid_contact and not valid_contact:
    _los_loss_position = _last_known_player_pos  # capture at moment of loss
_was_valid_contact = valid_contact
```
At COMBAT→ALERT transition: `investigate_anchor = _los_loss_position` (not `_last_seen_pos`).

**Tests**: `test_ai5_los_loss_position_used_as_anchor`, `test_ai5_stale_last_seen_not_used`

---

### AI-6: Peripheral Suspicion

**Goal**: Outside 120° FOV, within 150px → suspicion += 0.05/s without LOS required.

**What exists**: suspicion only from direct FOV + LOS check.

**Change** in `enemy_perception_system.gd`, add to `_process(delta)`:
```gdscript
func _check_peripheral_suspicion(player_pos: Vector2, delta: float) -> void:
    var dist := owner.global_position.distance_to(player_pos)
    if dist > GameConfig.ai6_peripheral_radius:   # 150.0
        return
    var to_player: Vector2 = (player_pos - owner.global_position).normalized()
    var dot: float = _facing_dir.dot(to_player)
    var fov_cos: float = cos(deg_to_rad(GameConfig.perception_fov_deg * 0.5))
    if dot >= fov_cos:
        return  # inside main FOV: handled by normal perception, skip peripheral
    _awareness_system.add_suspicion(GameConfig.ai6_peripheral_suspicion_rate * delta)
```
`add_suspicion(amount: float)` in `enemy_awareness_system.gd`: `_suspicion = min(_suspicion + amount, 1.0)`.

**GameConfig**: `ai6_peripheral_radius: float = 150.0`, `ai6_peripheral_suspicion_rate: float = 0.05`

**Tests**: `test_ai6_outside_fov_accumulates_suspicion`, `test_ai6_inside_fov_no_peripheral`, `test_ai6_beyond_radius_no_effect`

---

### FEAR-1: Suppression

**Goal**: 3+ hits in 1.5s → enemy stays in cover (suppressed), does not advance.

**Change** in `enemy_awareness_system.gd`:
```gdscript
var _suppression_hits: int = 0
var _suppression_window_timer: float = 0.0
var _suppression_active: bool = false
var _suppression_timer: float = 0.0

func register_hit_from_player() -> void:
    if _suppression_window_timer <= 0.0:
        _suppression_hits = 0
    _suppression_window_timer = GameConfig.fear1_suppression_window
    _suppression_hits += 1
    if _suppression_hits >= GameConfig.fear1_suppression_hit_count:
        _suppression_active = true
        _suppression_timer = randf_range(GameConfig.fear1_suppression_duration_min,
                                         GameConfig.fear1_suppression_duration_max)
        _suppression_hits = 0

func is_suppressed() -> bool:
    return _suppression_active
```
`register_hit_from_player()` called from bullet impact handler (in `enemy.gd` or damage system).
In `_process(delta)`: `_suppression_window_timer -= delta; _suppression_timer -= delta; if _suppression_timer <= 0: _suppression_active = false`.

In `enemy_pursuit_system.gd` COMBAT movement:
```gdscript
if _awareness.is_suppressed():
    return  # stay in cover, do not advance position
```

**GameConfig**:
```gdscript
fear1_suppression_hit_count: int = 3
fear1_suppression_window: float = 1.5
fear1_suppression_duration_min: float = 2.0
fear1_suppression_duration_max: float = 4.0
```

**Tests**: `test_fear1_suppression_activates_after_hits`, `test_fear1_suppressed_enemy_does_not_advance`, `test_fear1_expires_after_duration`

---

### FEAR-2: Last Man Panic

**Goal**: Last survivor in room enters panic: chaotic movement + faster fire + escape attempt.

**Change** in `src/core/event_bus.gd`:
```gdscript
signal enemy_died_in_room(room_id: int)
```
In `enemy.die()`: `EventBus.enemy_died_in_room.emit(home_room_id)`.

Each living enemy listens to `enemy_died_in_room`:
```gdscript
func _on_enemy_died_in_room(room_id: int) -> void:
    if room_id != home_room_id: return
    if _count_living_enemies_in_room(home_room_id) > 1: return
    # Self is last one alive in this room
    _panic_active = true
    _panic_timer = GameConfig.fear2_panic_duration
    _panic_direction_timer = 0.0
```

While `_panic_active` in COMBAT/ALERT:
- Change random move direction every `fear2_direction_change_interval` (0.5s)
- Fire rate × `fear2_fire_rate_multiplier` (1.5)
- Move toward nearest room exit door
- On `_panic_timer <= 0`: panic ends → resume normal ALERT behavior

**GameConfig**:
```gdscript
fear2_panic_duration: float = 8.0
fear2_fire_rate_multiplier: float = 1.5
fear2_direction_change_interval: float = 0.5
```

**Tests**: `test_fear2_last_man_triggers_panic`, `test_fear2_not_last_man_no_panic`, `test_fear2_panic_expires`

---

### FEAR-3: Flanking via Alternate Path

**Goal**: Enemy in ALERT: 25% chance every 4s to route through adjacent room.

**Change** in `enemy_pursuit_system.gd`, in ALERT state:
```gdscript
var _flank_timer: float = GameConfig.fear3_flank_check_interval   # 4.0s

# In _physics_process(delta) while ALERT:
_flank_timer -= delta
if _flank_timer <= 0.0:
    _flank_timer = GameConfig.fear3_flank_check_interval
    if randf() < GameConfig.fear3_flank_chance:   # 0.25
        var adj := navigation_service.get_adjacent_room_ids(home_room_id)
        if not adj.is_empty():
            var flank_room_id: int = adj[randi() % adj.size()]
            var intermediate: Vector2 = navigation_service.get_room_center(flank_room_id)
            nav_agent.target_position = intermediate  # go through adjacent room
            # After reaching intermediate, normal pursuit resumes
```

**GameConfig**:
```gdscript
fear3_flank_check_interval: float = 4.0
fear3_flank_chance: float = 0.25
```

**Tests**: `test_fear3_flank_triggers_at_correct_probability`, `test_fear3_routes_through_adjacent_room`

---

### FEAR-4: Reactive Position Change

**Goal**: Player stationary 3s → squad changes cover angles.

**Change** in `enemy_pursuit_system.gd` or squad coordinator:
```gdscript
var _player_still_timer: float = 0.0
var _player_last_pos: Vector2 = Vector2.ZERO
```
Each frame in COMBAT:
```gdscript
if player.global_position.distance_to(_player_last_pos) < GameConfig.fear4_player_still_threshold:
    _player_still_timer += delta
    if _player_still_timer >= GameConfig.fear4_player_still_duration:
        EventBus.player_stationary.emit(player.global_position)
        _player_still_timer = 0.0
else:
    _player_still_timer = 0.0
    _player_last_pos = player.global_position
```
Add `signal player_stationary(player_pos: Vector2)` to EventBus.
Squad coordinator listens: on `player_stationary`, squad members in same/adjacent room move to new cover positions (perpendicular offset from current position relative to player).

**GameConfig**:
```gdscript
fear4_player_still_duration: float = 3.0
fear4_player_still_threshold: float = 20.0
```

**Tests**: `test_fear4_squad_repositions_after_stillness`, `test_fear4_moving_player_resets_timer`

---

## SF-9B / MH-1: Door Stacking

### Goal
Enemy pauses at doorway and performs LOOK sweep before entering a room. Simulates Manhunt-style "door clearing."

### What Exists
Enemies auto-open doors via `try_enemy_open_nearest()` in `enemy_pursuit_system.gd` (~line 817) when blocked at 30px from door. No pre-entry check or pause. Player opens doors via E key (`interact_toggle()`, 20px range).

### What Changes
In `enemy_patrol_system.gd`, when computing the next waypoint path:

Detect doorway crossing: if `navigation_service.room_id_at_point(next_waypoint)` ≠ current room → enemy is about to cross a doorway.

At distance `mh1_door_sweep_distance` (64px) from the door center:
1. Stop movement
2. Execute LOOK sweep sequence:
   - Rotate sprite +`mh1_door_sweep_angle_deg` (45°) over `mh1_door_sweep_side_duration` (0.5s)
   - Hold 0.25s
   - Rotate −`mh1_door_sweep_angle_deg` × 2 (−45° from original) over `mh1_door_sweep_side_duration` (0.5s)
   - Hold 0.25s
   - Return to forward direction
3. Continue navigation toward door → existing `try_enemy_open_nearest()` handles door open at 30px

Total sweep duration: `randf_range(mh1_sweep_duration_min, mh1_sweep_duration_max)` (1.0–2.0s).

**Door state does not change sweep behavior.** Sweep happens at doorway regardless of whether door is closed or open. If closed: sweep → approach → auto-open → enter. If open: sweep → walk through.

**Sweep interruption**: if enemy receives noise_event or player spotted during sweep → immediately abort sweep, enter SUSPICIOUS/ALERT state.

### GameConfig Constants
```gdscript
mh1_door_sweep_distance: float = 64.0
mh1_door_sweep_angle_deg: float = 45.0
mh1_door_sweep_side_duration: float = 0.5
mh1_sweep_duration_min: float = 1.0
mh1_sweep_duration_max: float = 2.0
```

### Tests
`tests/test_door_stacking_mh1.gd`:
- `test_enemy_stops_at_doorway_distance`
- `test_look_sweep_rotates_correct_angles`
- `test_sweep_completes_then_enters`
- `test_alert_during_sweep_aborts_it`
- `test_open_door_also_triggers_sweep`

### Out of Scope
- Player door clearing behavior
- Sweep angle based on room geometry (always fixed ±45°)
- Sweep for non-door nav mesh crossings

---

## SF-9A / 8B: Cross-Room Patrol

### Goal
20% chance per patrol cycle: enemy probes into adjacent room (25% depth), then returns.
Increases patrol unpredictability without permanently reassigning enemies.

### Dependencies
- NavigationService (nav refactor): `get_adjacent_room_ids()`, `get_door_between()`, `get_room_center()` must exist.
- SF-9B (MH-1): if MH-1 is implemented, door sweep fires automatically when enemy crosses the doorway. If MH-1 not yet implemented, enemy navigates through door without sweep.

### Trigger Conditions (all must be true simultaneously)
1. `enemy.awareness_state == EnemyAlertLevels.CALM`
2. Enemy just completed a full patrol cycle (returned to first waypoint in home_room)
3. `navigation_service.get_adjacent_room_ids(home_room_id).size() > 0`
4. `randf() < GameConfig.cross_room_patrol_chance` (0.20)
5. `_cross_room_active == false` (not currently executing a probe)

### Probe Waypoint Computation
```gdscript
func _compute_probe_waypoint(from_id: int, to_id: int) -> Vector2:
    var door_rect: Rect2 = navigation_service.get_door_between(from_id, to_id)
    var door_center: Vector2 = door_rect.get_center()
    var room_center: Vector2 = navigation_service.get_room_center(to_id)
    return door_center + (room_center - door_center) * GameConfig.cross_room_patrol_depth
```

Adjacent room selection: `adj_rooms[randi() % adj_rooms.size()]` (uniform random).

Validity check before committing to probe:
```gdscript
var map_rid: RID = navigation_service.get_navigation_map_rid()
var test_path: PackedVector2Array = NavigationServer2D.map_get_path(map_rid, owner.global_position, probe_wp, true)
if test_path.is_empty():
    return  # fallback: skip probe this cycle, start normal patrol
```

### Patrol Route During Probe
```
[home_room waypoint N]
    → [doorway threshold 64px — MH-1 sweep if enabled]
    → [probe_waypoint]
    → [home_room waypoint 0]
```
After reaching `probe_waypoint`: next target = first waypoint in home_room_id.
`home_room_id` does NOT change. Enemy is a visitor in the adjacent room.

### State During Probe

| Parameter | Value |
|-----------|-------|
| `home_room_id` | unchanged |
| awareness | CALM (PATROL) |
| speed | patrol speed (nerfed, same as normal patrol) |
| LM-1 waypoint check | executes at probe_waypoint (discovers darkness if present) |
| AI-3 evidence check | executes at probe_waypoint |
| BD-1 CorpseMarker discovery | triggers if CorpseMarker within 80px |

### Probe Interruption
If during probe:
- Noise event received → `on_noise_event` → SUSPICIOUS/ALERT: abort probe (`_cross_room_active = false`), handle event normally
- Player spotted → ALERT: abort probe, normal combat flow
- Probe waypoint becomes unreachable mid-navigation: abort, resume home patrol

### Probe Completion
After reaching probe_waypoint: `_cross_room_active = false`. Enemy navigates back to `home_room waypoint 0`.

### GameConfig Constants
```gdscript
cross_room_patrol_chance: float = 0.20
cross_room_patrol_depth: float = 0.25
```

### Edge Cases

| Situation | Behavior |
|-----------|---------|
| No adjacent rooms | `get_adjacent_room_ids().is_empty()` → condition 3 fails → probe never triggers |
| Single adjacent room | 8B always probes the same room when triggered. Acceptable |
| Two enemies probe same room simultaneously | Independent rolls, no coordination. Both proceed |
| Watcher (FA-1) | Can also probe. No special handling |
| Probe waypoint unreachable | Validity check fails → skip probe this cycle, normal patrol |
| ALERT during probe | Abort probe, pursue/search normally |

### Tests
`tests/test_cross_room_patrol_8b.gd`:
- `test_probe_triggers_at_correct_probability` — statistical: 100 cycles, expect 15–25% probes
- `test_probe_waypoint_at_25_percent_depth` — waypoint is at 25% of door→room_center vector
- `test_probe_skipped_when_unreachable` — empty path → no probe, normal patrol
- `test_home_room_unchanged_during_probe`
- `test_alert_during_probe_aborts_it`
- `test_no_adjacent_rooms_never_probes`
- `test_probe_returns_to_home_after_waypoint`

### Out of Scope
- Deep penetration (> 25% room depth)
- `home_room_id` reassignment
- Chained probes (from adjacent room into a third room)
- 8B in ALERT/COMBAT states
- Coordination between multiple probing enemies

---

*Document created: 2026-02-21.*
*Updated: 2026-02-21 — full revision: exact speed values, visual specs (noise rings, power bar, Light2D), all 5 LM-1 cases, SF-8 (AI-1..6, FEAR-1..4) with file targets, SF-9A/8B full spec, SF-9B/MH-1 with door mechanics, all open questions resolved.*
