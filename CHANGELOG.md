# Arena Shooter Changelog

## 2026-02-11

### Door uniformity + central adjacency + walkable grass
- Changed: procedural doors now use a uniform opening size from config (`door_opening_uniform`), with no relaxed smaller-door fallback in composition/connectivity repair.
- Added: hub-adjacency enforcement pass (`_enforce_hub_adjacent_doors`) so central rooms connect to feasible adjacent rooms under existing caps/checks.
- Changed: tighter door overlap spacing to reduce narrow/stacked pseudo-entries near neighboring doors.
- Changed: extra pseudo-closet validation for non-corridor geometry (`min<128 && aspect>2.5` invalid; multi-rect closet-like fragments invalid).
- Added: floor rendering in `level_mvp` now paints grass only over walkable room rects; full-arena floor sprite is hidden when procedural layout is valid.
- Updated tests:
  - `tests/test_layout_stats.gd` now logs/fails on `central_missing` and non-uniform door variants.
- Result:
  - `test_layout_stats`: PASS (`central_missing=0`, `door_variants=1`, `gut=0`, `bad_edge=0`).
  - `test_hotline_similarity`: PASS (`95.25/100`).
  - `test_layout_visual_regression`: PASS.
- Files: `src/systems/procedural_layout.gd`, `src/core/game_config.gd`, `src/levels/level_mvp.gd`, `tests/test_layout_stats.gd`

## 2026-02-10

### Closet access + anti-floating-wall fix
- Changed: disabled interior blocker generation that produced random "wall in the middle of room" artifacts.
- Added: closet classifier helper and strict closet door cap (`max_doors=1`).
- Added: validation rule for closets: allowed count `0..2`, and every closet must have exactly one entrance.
- Changed: dead-end validation excludes closets (they are validated separately by one-entrance rule).
- Changed: walkability check now uses wall clearance radius and tighter unreachable budget (`<=1`) to catch narrow fake passages.
- Updated tests:
  - `tests/test_layout_stats.gd` logs and fails on closets with invalid entrance count.
  - `tests/test_layout_visual_regression.gd` aligns blocker metric with new optional blocker policy and tighter unreachable threshold.
- Result:
  - `test_layout_stats`: PASS (50/50 valid, `closet_bad_entries=0`, `gut=0`, `bad_edge=0`)
  - `test_layout_visual_regression`: PASS (`walkability_failures=0`)
  - `test_hotline_similarity`: PASS (`95.25/100`)
- Files: `src/systems/procedural_layout.gd`, `tests/test_layout_stats.gd`, `tests/test_layout_visual_regression.gd`

### Walkability + route rhythm hardening (latest)
- Added: flood-fill walkability validation to reject internal unreachable pockets/void-like leftovers inside playable silhouette.
- Added: main path rhythm validation (minimum turns + max straight run cap) to reduce long boring "door-in-line" routes.
- Added: bend-aware door scoring in both BSP door placement and connectivity repair.
- Added: regression checks in `tests/test_layout_visual_regression.gd` for linear path failures and unreachable walk cells.
- Result: `test_hotline_similarity` reached **95.50/100**; visual regression shows `walkability_failures=0`, `linear_path_failures=0`.
- Files: `src/systems/procedural_layout.gd`, `tests/test_layout_visual_regression.gd`

### Hotline similarity tuning (brief)
- Added: T/U room reservation + mode-sticky retries in procedural layout generation.
- Added: Feasibility-aware composition mode pick (choose only feasible HALL/SPINE/RING/DUAL_HUB for current leaf graph).
- Added: Dedicated benchmark test `tests/test_hotline_similarity.gd` (+ `.tscn`) with target score 95/100.
- Result: similarity score improved from 69.25 to 92.75; hard geometry constraints remain clean (`gut=0`, `bad_edge=0`).

## 2026-02-10

### 14:00 MSK - HM-Style Layout Improvements Plan (Ready for implementation)
- **Added**: Comprehensive plan for 90-95% Hotline Miami similarity
- **Plan**: PLAN_HM_LAYOUT_IMPROVEMENTS.md
- **Phase 1**: Void interior holes fix, L-shaped corridors (20%), room count 9-15
- **Phase 1.5**: Thin geometry removal (128px strict), hub degree ≤3, CENTRAL_SPINE 40%, secondary loops, perimeter notches (35%)
- **Phase 2**: MAX_ASPECT 7.0, narrow_room_max 3, L-rooms 4 max (20% chance)
- **Phase 3**: Voids 2-5, BSP split variance 0.20-0.80
- **Phase 3.5**: Dead-end rooms on perimeter (10-20%), corner doors (30%), double doors (12%), extreme room sizes
- **Phase 4 (optional)**: T/U-shaped rooms
- **Key decisions**: Edge corridors remain, dead-ends only on perimeter, voids min 2, no narrow corridor variance
- **Files**: Plan created, implementation pending

## 2026-02-09

### 02:00 MSK - Layout diversity: all 4 composition modes + 9 unique layouts
- **Fixed**: HALL composition always succeeds (hub is structural label, not strict degree requirement)
- **Fixed**: Corridor degree check allows deg=1 for void-adjacent corridors
- **Fixed**: Entry gate no longer required for validation (cosmetic; player spawns inside)
- **Result**: 30/30 valid, 9 unique layouts, modes: SPINE 50%, HALL 20%, RING 20%, DUAL_HUB 10%
- **Files**: procedural_layout.gd

### 01:38 MSK - Layout generation tuning: 0% → 100% valid layouts
- **Fixed**: RING/DUAL_HUB fallback modes not updating _layout_mode → composition always failed
- **Fixed**: corridor_max_aspect 10→30 (corridors spanning arena height are by design)
- **Fixed**: rooms_count_min 7→5 (BSP with anti-cross often produces 5-6 rooms)
- **Fixed**: Void constraints relaxed (center dist 0.25→0.15, target 2..4→1..3, minimum 2→1)
- **Fixed**: Validation relaxed (avg_degree cap 2.5→2.8, high_degree_count 2→3, form diversity thresholds, corridor deg: internal≥2/perimeter≥1, hub deg≥2)
- **Fixed**: Room identity threshold corridor_w_min*1.2→1.0
- **Result**: 30/30 seeds valid, 90% voids≥2, modes: DUAL_HUB 40%, RING 40%, SPINE 20%
- **Files**: procedural_layout.gd, game_config.gd

### 23:45 MSK - Hotline Miami composition-first layout overhaul (Parts 1-9)
- **Added**: Anti-BSP-cross rule (cross_split_max_frac=0.72, center-avoid ±8%)
- **Added**: Composition enforcement (_enforce_composition) — forced hub/spine/ring/dual-hub connections
- **Added**: Protected doors system — composition-critical doors cannot be removed by _enforce_max_doors
- **Added**: Room identity check — rejects narrow pseudo-corridor rooms (aspect>2.7 limit=1)
- **Added**: Corridor constraints — degree>=2, area cap, aspect ratio cap (10:1)
- **Added**: _merge_collinear_segments for perimeter wall dedup
- **Added**: _arena_is_too_tight validation check
- **Added**: _validate_structure() — mode-specific composition verification
- **Added**: BFS helpers (_bfs_connected, _bfs_distance)
- **Changed**: Void system strengthened — always attempt voids, target 2..4, center distance check, L-cut silhouette logic
- **Changed**: BSP Phase 2 — split range widened to 0.25-0.75, anti-cross line length cap
- **Changed**: Up to 2 doors per BSP split (Part 7 multi-door)
- **Changed**: _ensure_connectivity now recomputes BFS after each door addition
- **Changed**: Validation extended — require >=2 voids, void area>=8%, form diversity, structure check
- **Changed**: Retry limit 10→30, avg_degree cap 2.3→2.5
- **Added**: F4 key regenerates layout instantly
- **Added**: Enhanced debug overlay — room degree labels, mode/hubs/voids/avg_deg/ring info
- **Added**: GameConfig params: cross_split_max_frac, void_area_min_frac, narrow_room_max, corridor_max_aspect, composition_enabled
- **Files**: procedural_layout.gd, level_mvp.gd, game_config.gd

### 22:35 MSK - Arena scaling & room/void tuning
- **Changed**: rooms_count_min 6→7, rooms_count_max 9→12
- **Changed**: Voids now spawn with 50% probability (was 100%), max 2 (was 2-4)
- **Changed**: Validation no longer requires voids (allows no-void layouts)
- **Changed**: Arena sizes ×1.5 (SQUARE 2100-2700, LANDSCAPE/PORTRAIT base 1650-2100)
- **Files**: game_config.gd, procedural_layout.gd, level_mvp.gd

### 23:30 MSK - L-shaped rooms, visible voids, entry gate, perimeter corridor fix
- **Added**: L-shaped rooms (_apply_l_rooms) — corner notch cuts creating Г-shaped walkable space with internal walls
- **Changed**: VOID cutouts prefer corner rooms and larger area (DESC), with adjacency clustering for visible silhouette
- **Added**: Top entry gate — opening on top perimeter wall near player spawn
- **Added**: Validation: void area >= 8% of arena, entry gate must exist
- **Changed**: _rooms_touch / _touches_arena_perimeter now handle multi-rect rooms
- **Added**: _room_bounding_box, _room_total_area, _count_perimeter_sides utility functions
- **Added**: Notch wall segments in _build_walls for L-room collision
- **Changed**: Debug draw shows L-room notches (dark gray), entry gate (cyan), updated labels
- **Files**: src/systems/procedural_layout.gd

### 22:00 MSK - Hotline-style procedural layout upgrade (BSP extension)
- **Changed**: Interior corridor triple-split (room|corridor|room) replaces edge strip corridors
- **Added**: VOID cutouts — 1-3 perimeter BSP leaves marked as outside for irregular silhouette
- **Added**: Aspect ratio guard (max 1:5) on BSP splits prevents noodle corridors
- **Changed**: VOID-aware wall building — perimeter walls only where SOLID rooms touch arena edge
- **Changed**: Validation extended — max 1 perimeter corridor, hub degree >= 2, solid-only connectivity
- **Changed**: All subsystems (doors, loops, connectivity, spawn) skip VOID rooms
- **Added**: Uses GameConfig corridor_w_min/corridor_w_max for corridor width (was hardcoded 96px)
- **Files**: src/systems/procedural_layout.gd

### 18:30 MSK - Hub/Spine topology + arena presets
- **Added**: `ArenaPreset` enum (SQUARE/LANDSCAPE/PORTRAIT) + `_random_arena_rect()` in `level_mvp.gd`
- **Added**: `LayoutMode` enum (CENTRAL_HALL/CENTRAL_SPINE/CENTRAL_RING/CENTRAL_LIKE_HUB) in `procedural_layout.gd`
- **Added**: Topology role tagging: hub, spine, ring, dual-hub — no geometry changes, only door priority
- **Added**: Edge corridor suppression — perimeter corridors (>50% long side on boundary) deprioritized
- **Added**: `_door_pair_priority()` — topology-aware door pair scoring (hub>ring>big>interior>perimeter)
- **Added**: `_max_doors_for_room()` — hub rooms get 3-5 max doors, ring 3, others 2
- **Added**: `_build_leaf_adjacency()`, `_rooms_touch()` — geometric adjacency graph for topology detection
- **Added**: Ring cycle detection via DFS (`_find_short_cycle`, `_dfs_cycle`)
- **Added**: Perimeter corridor chain validation (`_has_long_perimeter_corridor_chain`, max 2)
- **Changed**: Validation relaxed: avg_degree ≤ 2.3 (was 2.2), high_degree_count ≤ 2 (was 1)
- **Changed**: Player spawn prefers hub/spine-adjacent non-corridor rooms
- **Changed**: Debug draw shows hub rooms (red), ring rooms (orange), mode label
- **Changed**: `regenerate_layout()` now randomizes arena shape on each regeneration
- **Files**: `src/systems/procedural_layout.gd`, `src/levels/level_mvp.gd`

### 16:30 MSK - Hotline BSP: space-filling + corridor-leaves + split-line walls + cut doors
- **Changed**: Complete rewrite of `procedural_layout.gd` BSP generation
- **Added**: Space-filling BSP — rooms ARE leaves, no shrink/padding gaps, NO voids
- **Added**: Corridor leaves as real thin strips (width ~96px, 1-2 forced, 3 if rooms>=9)
- **Added**: `_leaves`, `_split_segs`, `_wall_segs` data arrays for split-line architecture
- **Changed**: Walls built from BSP split lines + arena perimeter (NOT grid boundary scan)
- **Changed**: Doors placed centered on split walls with jitter; cut as openings in wall segments
- **Changed**: Each BSP split generates exactly one wall segment — no duplicates
- **Changed**: Player spawn in north-central NON-corridor room (largest among top 3 candidates)
- **Removed**: Grid-based wall collection (`_collect_wall_segments`, `_build_grid`, `_is_walkable` grid)
- **Removed**: Old corridor connector rects (`_create_corridors`), L-room carving, room shrink by padding
- **Removed**: Gap/threshold door geometry (`_try_door`, `_door_rect`, `_horiz_door`, `_vert_door`)
- **Changed**: Debug draw: corridor leaves yellow, normal rooms green; corridor_leaves count in stats
- **Files**: `src/systems/procedural_layout.gd`

## 2026-02-08

### 23:50 MSK - Hotline Miami-style room geometry/topology patch
- **Changed**: procedural_layout.gd - Hotline-style constraints on BSP rooms
  - Room aspect ratio clamping [0.65..1.75], min 220x200, max 520x420
  - 2 largest BSP leaves inflated to big_room_min (360x280)
  - L-room constraints: leg_min=160, cut_max_frac=0.40, chance=0.12
  - Doors centered on walls with ±20% jitter (not random placement)
  - Door spacing check: reject doors within 48px on same wall
  - max_doors_per_room=2, extra_loops_max=1
  - Corridors: 1..2 logical (3 only if rooms>=9), area cap 25%
  - Emergency connectivity: max 2 rects per emergency corridor
  - Validation: avg_degree<=2.2, max 1 room with degree>3, big rooms check
  - Grid cell_size 8.0 (was 20.0), wall overlap symmetric ±2px
  - Safe player spawn: test_move collision check with spiral fallback
  - Debug stats: big_rooms_count, avg_degree, logical_corridors_count
- **Changed**: game_config.gd - 8 new Hotline tunables + updated defaults
  - New: big_rooms_target, big_room_min_w/h, l_leg_min, l_cut_max_frac, max_doors_per_room, extra_loops_max, corridor_area_cap
  - Updated defaults: door 96-128, corner_min 48, rooms_count_max 9, corridor_len_min 320
- **Files**: src/systems/procedural_layout.gd, src/core/game_config.gd

### 21:30 MSK - Procedural layout: BSP rooms, corridors, doors, grid walls
- **Added**: `src/systems/procedural_layout.gd` — BSP room generator (6-10 rooms, 1-3 corridors, grid occupancy walls, L-rooms, connectivity validation, 10-attempt retry)
- **Added**: 30+ new GameConfig fields in Procedural Layout section (rooms, corridors, doors, walls, debug toggles)
- **Changed**: `level_mvp.gd` — LayoutWalls/LayoutDebug containers, generation call after ArenaBoundary, wave_manager guarded by `waves_enabled`, layout debug overlay, `regenerate_layout()` method
- **Files**: `src/core/game_config.gd`, `src/systems/procedural_layout.gd`, `src/levels/level_mvp.gd`

### 20:45 MSK - Footprint shader tint (alpha-based coloring)
- **Added**: `shaders/footprint_tint.gdshader` — tints by texture alpha, ignores RGB
- **Changed**: Each pooled Sprite2D gets own ShaderMaterial with `tint_color` uniform
- **Changed**: `_spawn_footprint` sets `tint_color` via shader param (was `sprite.modulate`)
- **Changed**: `_age_footprints` fade uses `mat.set_shader_parameter("tint_color", ...)` (was `modulate.a`)
- **Files**: `shaders/footprint_tint.gdshader`, `src/systems/footprint_system.gd`

### 20:25 MSK - Footprints: RED on blood/corpse, no black prints
- **Changed**: Footprints on blood/corpse are now RED (was black), reload charges on contact
- **Changed**: Fading formula uses `charges/maxp` (was `(charges-1)/(maxp-1)`)
- **Files**: `src/systems/footprint_system.gd`

### 20:15 MSK - Fix footprint logic: no prints on grass, corpse detection fix
- **Fixed**: `has_corpse_at()` counted BakedCorpses Node2D container as corpse → now checks only `_corpses` array + baked Sprite2D children
- **Changed**: No footprints on clean grass (only on blood/corpse or with blood charges)
- **Changed**: `_spawn_footprint` "else" branch returns early as safeguard (unreachable via guard in update)
- **Files**: `src/systems/vfx_system.gd`, `src/systems/footprint_system.gd`

### 17:24 MSK - Fix coordinate space: global_position for player_pos + VFX detection
- **Fixed**: `player.gd:72` — `RuntimeState.player_pos` now uses `global_position` instead of `position`
- **Fixed**: `melee_system.gd:183` — same fix for dash movement update
- **Fixed**: `vfx_system.gd` — `has_blood_at()` / `has_corpse_at()` use `child.global_position` (removed `to_local`)
- **Changed**: `footprint_system.gd` — rotation back to `move_dir.angle()` (removed facing_dir/aim_dir usage)
- **Files**: `src/entities/player.gd`, `src/systems/melee_system.gd`, `src/systems/vfx_system.gd`, `src/systems/footprint_system.gd`

### 16:38 MSK - Fix VFX blood/corpse detection coordinate space
- **Fixed**: `has_blood_at()` / `has_corpse_at()` now convert incoming world pos to container local space via `to_local()` before comparing with `child.position`
- **Files**: `src/systems/vfx_system.gd`

### 16:16 MSK - Footprint: detect blood/corpse at stamp_pos + debug flags
- **Changed**: Blood/corpse detection now at stamp contact point (`stamp_pos = player_pos - move_dir * rear_offset`) instead of player center
- **Changed**: `_spawn_footprint` simplified to `(stamp_pos, facing_dir, on_blood, on_corpse)` — position precomputed in update()
- **Added**: `last_on_blood` / `last_on_corpse` debug fields on FootprintSystem
- **Changed**: F3 overlay shows live `blood=0/1 corpse=0/1 charges=N` for debugging
- **Files**: `src/systems/footprint_system.gd`, `src/levels/level_mvp.gd`

### 16:01 MSK - Footprint direction: use player_aim_dir for rotation
- **Changed**: Footprint rotation now uses `RuntimeState.player_aim_dir` instead of move_dir
- **Changed**: Position still placed behind player along move_dir (rear offset)
- **Changed**: Backward walk now correctly shows toe facing where player looks
- **Files**: `src/systems/footprint_system.gd`

### 15:36 MSK - Footprint color states: blood vs corpse + rotation debug
- **Added**: `has_blood_at()` and `has_corpse_at()` to VFXSystem (split from combined method)
- **Changed**: Footprint color logic: NORMAL (dusty grey-brown) on clean floor, BLACK on blood/corpse, BLOODY red when walking off blood with charge decay
- **Changed**: Blood charges only reload when stepping on blood (not corpse alone); on-blood/corpse does NOT consume charges
- **Changed**: F3 debug overlay now shows `rot:` value for footprint_rotation_offset_deg
- **Files**: `src/systems/footprint_system.gd`, `src/systems/vfx_system.gd`, `src/levels/level_mvp.gd`

### 15:21 MSK - Footprint density fix: paired-step stamp + distance accumulator
- **Changed**: Removed left/right alternation — PNG contains both feet as paired stamp
- **Changed**: Replaced distance-to-last-spawn with `_distance_accum` for stable spacing
- **Changed**: Removed `_next_is_left`, `flip_h`, separation/perp logic entirely
- **Changed**: GameConfig defaults: step_distance 22→40, scale 1.2→0.65, alpha 0.6→0.35, vel_threshold 10→35, jitter 2→1, rear_offset 14→12
- **Changed**: Normal footprint color from black to dusty grey-brown (0.18,0.16,0.14); on-blood stays black (0.08)
- **Changed**: Debug overlay now shows: FP count, spawned total, blood charges, step distance
- **Files**: `src/systems/footprint_system.gd`, `src/core/game_config.gd`, `src/levels/level_mvp.gd`

### 14:48 MSK - Footprint system: PNG texture + rotation + bloody boots
- **Changed**: Replaced procedural boot tread generation with preloaded `boot_print_cc0.png`
- **Changed**: Removed `MaterialState` enum and all 6 cached textures; single PNG with `flip_h` for left/right
- **Added**: `footprint_rotation_offset_deg` (90.0) in GameConfig — toe faces movement direction
- **Added**: Bloody boots decay: stepping on blood gives 8 charges, off-blood prints fade red→invisible
- **Changed**: Fade uses per-footprint `base_alpha` stored at spawn (2s fade window instead of 3s)
- **Added**: Strict no-move guard — `delta_pos < 0.001` prevents spawning when only aiming
- **Added**: Debug getters `get_spawned_total()` / `get_blood_charges()`
- **Files**: `src/systems/footprint_system.gd`, `src/core/game_config.gd`

## 2026-02-07

### 22:26 MSK - Visual Integration Pass STEP 3: Entity Sprites

#### Player Sprite — Kenney Hitman (CC0)
- **Changed**: Player sprite from green circle placeholder to Kenney "Hitman 1" with gun
- **Source**: Kenney Top-down Shooter pack (CC0 1.0), via OpenGameArt mirror
- **Visual**: Dark-clothed figure with sunglasses (eyewear), holding pistol, top-down view
- **Size**: 49x43 native (larger than 16px collision radius = sprite extends beyond hitbox, standard)
- **Processing**: Darkened (-modulate 85,95) for grittier look
- **Files**: `assets/sprites/player/player_idle_0001.png`, `scenes/levels/level_mvp.tscn`

#### Enemy Sprite — Kenney Zombie (CC0)
- **Changed**: Enemy sprite from red circle placeholder to Kenney "Zombie 1" holding pose
- **Source**: Kenney Top-down Shooter pack (CC0 1.0)
- **Visual**: Green-skinned shambling monster, top-down view
- **Size**: 35x43 native (fits 12.8px collision radius well)
- **Processing**: Darkened + saturated (-modulate 80,110) for grittier look
- **Files**: `assets/sprites/enemy/enemy_zombie_0001.png`, `scenes/entities/enemy.tscn`

#### Boss Sprite — Procedural Robot (288x288)
- **Changed**: Boss sprite from large red circle placeholder to high-res procedural mechanical boss
- **Visual**: Dark metallic body, glowing red eyes, armor plates, side modules, industrial aesthetic
- **Size**: 288x288 (matches 144px collision radius exactly)
- **Created**: Procedural via ImageMagick (robot aesthetic inspired by Kenney Robot 1)
- **Files**: `assets/sprites/boss/boss_0001.png`, `scenes/entities/boss.tscn`

#### Texture Filtering Update
- **Changed**: All entity sprites texture_filter from 0 (NEAREST) to 1 (LINEAR)
- **Reason**: Kenney sprites are vector-style, LINEAR smoothing looks better at zoom 2x
- **Files**: `scenes/levels/level_mvp.tscn`, `scenes/entities/enemy.tscn`, `scenes/entities/boss.tscn`

#### Attribution
- **Added**: Kenney Top-down Shooter pack credits in README attribution table
- **Files**: `README.md`

### 21:28 MSK - Visual Integration Pass STEP 2: Footprints

#### Boot Tread Texture — 2x Resolution
- **Changed**: Boot tread texture from 8x14 to 16x28 pixels (2x resolution for readability)
- **Changed**: Texture now uses NEAREST filtering for crisp pixel look at zoom
- **Changed**: Default scale from 0.9 to 1.2, alpha from 0.45 to 0.6 (more visible)
- **Changed**: Tread pattern: wider heel/toe bars, distinct arch gap, grit variation per pixel

#### Footprint Material States (Normal/Bloody/Black)
- **Added**: 3-state material system: NORMAL (dusty grey) → BLOODY (crimson) → BLACK (dark residue)
- **Added**: VFX system wired to FootprintSystem (was passed but ignored as `_vfx`)
- **Added**: Blood/corpse proximity detection via `vfx_system.has_blood_or_corpse_at()`
- **Added**: Separate textures per material state (6 total: L/R x 3 states)
- **Added**: GameConfig tunables: `footprint_bloody_steps` (8), `footprint_black_steps` (4), `footprint_blood_detect_radius` (25px)
- **Files**: `src/systems/footprint_system.gd`, `src/core/game_config.gd`

#### F3 Debug Overlay — Footprint + Atmosphere Counters
- **Added**: Footprint material state display in debug overlay (e.g. "FP: 12 [BLOODY(5)]")
- **Added**: Floor texture path, atmosphere particle count, floor decal count in new FloorLabel
- **Added**: `get_particle_count()` and `get_decal_count()` to AtmosphereSystem
- **Changed**: Debug overlay width from 280 to 400px, height from 100 to 120px
- **Files**: `src/levels/level_mvp.gd`, `src/systems/atmosphere_system.gd`

#### Tests
- Unit tests: 79/79 passed
- Level smoke: 4/4 passed

### 21:15 MSK - Visual Integration Pass STEP 1: Floor + Z-Index Fix

#### Arena Floor — CC0 Dirt+Grass Texture
- **Added**: Downloaded CC0 seamless dirt+grass texture from ambientCG (Ground037)
- **Added**: `assets/textures/floor/dirt_grass_01.png` (256x256, darkened for gritty look)
- **Changed**: FloorSprite texture from `floor_0001.png` to `dirt_grass_01.png`
- **Changed**: FloorSprite texture_filter from 0 (nearest/pixel) to 1 (linear/natural)
- **Changed**: FloorSprite scale from (100,100) to (0.15625,0.15625), region from 3200x3200 to 12800x12800
- **Result**: 50x50 seamless tiles, 40 world px per tile (~80 screen px at zoom 2x), 2000px total coverage
- **Files**: `scenes/levels/level_mvp.tscn`, `assets/textures/floor/dirt_grass_01.png`

#### Z-Index Layering Fix (ROOT CAUSE OF INVISIBLE FEATURES)
- **Fixed**: Floor node z_index set to -20 (was 0, default)
- **Root cause**: All visual polish systems used negative z_index but Floor was at 0, so footprints (-5), floor decals (-9), shadows (-2), floor overlay (-8) all rendered BEHIND the floor
- **Fixed**: Atmosphere floor decal per-sprite z_index removed (was -10, compounding with container's -9 to give -19)
- **Changed**: Floor decal alpha increased from 0.15 to 0.35, modulate from 0.3 to 0.5 for visibility
- **Files**: `scenes/levels/level_mvp.tscn`, `src/systems/atmosphere_system.gd`

#### New z_index layering order (bottom to top):
| Layer | z_index | Description |
|-------|---------|-------------|
| Floor | -20 | Dirt+grass ground texture |
| Floor decals | -9 | Atmosphere crack/dirt marks |
| Floor overlay | -8 | Dark readability overlay |
| Footprints | -5 | Boot tread prints |
| Shadows | -2 | Entity shadows + highlight |
| Arena boundary | -1 | Arena edge visual |
| Entities/Blood/Corpses | 0 | Gameplay entities |
| Melee arcs | 10 | Slash visual effects |
| Atmosphere particles | 20 | Dust motes |

#### Attribution
- **Added**: Asset Attribution table in README.md
- **Source**: ambientCG Ground037, CC0 1.0 Public Domain

### 15:33 MSK - Visual Polish Pass (Patch 0.2 Pre-Phase 2)

#### Footprint System — Complete Rewrite
- **Changed**: FootprintSystem fully rewritten per canon spec
- **Added**: Industrial caterpillar/winter boot tread procedural textures (8x14 px)
- **Added**: Left/right foot alternation with mirrored textures
- **Added**: Proper movement-aligned positioning (rear_offset, separation, perpendicular)
- **Added**: Velocity threshold gate (no spawn when stationary)
- **Added**: 20-second lifetime with 2-second fade-out
- **Added**: Pooled sprite nodes (100 pre-allocated, configurable)
- **Added**: Rotation jitter (2 deg) for natural feel
- **Added**: All footprint tunables in GameConfig (step_distance, rear_offset, separation, scale, alpha, lifetime, velocity_threshold, max_count)

#### Melee Arc Visuals — New System
- **Added**: MeleeArcSystem — visual slash arcs during ACTIVE melee window
- **Added**: Light slash arc: 26 px radius, 80° arc, 2 px thickness, 0.08s duration
- **Added**: Heavy slash arc: 30 px radius, 110° arc, 3 px thickness, 0.12s duration
- **Added**: Dash trail: 20–28 px streaks with 3 afterimages, alpha falloff
- **Added**: Pooled Line2D nodes (8 arcs + 6 trails), auto-cleanup after duration
- **Added**: All melee arc tunables in GameConfig

#### Shadow + Highlight Layering — New System
- **Added**: ShadowSystem — entity shadows + player highlight ring
- **Added**: Player shadow: radius * 1.2, alpha 0.25, slight offset for depth
- **Added**: Enemy shadows: radius * 1.1, alpha 0.18
- **Added**: Boss shadow: larger radius, same alpha
- **Added**: Player highlight ring: radius + 2px, thickness 2px, blue glow alpha 0.5
- **Added**: Renders below entities via z_index -2

#### Combat Feedback — New System
- **Added**: CombatFeedbackSystem — hit/kill/damage visual overlays
- **Added**: Directional damage arc: red screen overlay, 0.12s fade on player_damaged
- **Added**: Kill edge pulse: white screen flash, alpha 0.15, 0.1s on enemy_killed
- **Changed**: Enemy hit flash: white flash 0.06s (was red 0.1s) for better readability
- **Changed**: Enemy kill pop: scale 1.0 → 1.2 → 0 with configurable duration (was 1.0 → 1.5)
- **Added**: Pooled ColorRect overlays (4 arcs + 4 pulses)

#### Blood & Corpse Visual Lifecycle
- **Added**: Blood aging — gradual darkening (darken_rate 0.01/s) + desaturation (0.005/s)
- **Added**: Blood decal count clamping (max 500, oldest removed first)
- **Added**: Corpse settle animation — small rotation + slide on spawn (0.3s ease-out)
- **Added**: VFXSystem.update_aging() called per frame for blood decay

#### Arena Floor & Atmosphere — New System
- **Added**: AtmosphereSystem — ambient dust particles + floor decals
- **Added**: Sparse floor decals (12 procedural dirt/crack marks, alpha 0.15)
- **Added**: Ambient dust particles: slow drift, alpha 0.05–0.15, lifetime 3–6s, bell-curve fade
- **Added**: Dark floor overlay (Sprite2D world-space, alpha 0.15) for combat readability
- **Added**: Soft vignette overlay on HUD layer

#### HUD / UI Polish
- **Added**: F3 debug overlay toggle (FPS, entity counts, blood/corpse/footprint stats)
- **Added**: HP label emphasized in red
- **Added**: Wave label in warm yellow
- **Added**: Boss HP in orange
- **Added**: Weapon/mode display in blue
- **Added**: Secondary labels dimmed (grey, alpha 0.8)
- **Added**: Hidden Momentum placeholder label (visible=false, ready for Phase 2)
- **Added**: Compact weapon display format
- **Added**: `debug_toggle` input action (F3 key) in project.godot

#### Menu Micro Polish
- **Changed**: Main menu buttons have hover fade animation (0.85 → 1.0 alpha, 0.15s)
- **Added**: Subtle animated background (pulsing color, 3s sine loop)

#### Architecture & Performance
- **Added**: 40+ new GameConfig tunables in "Visual Polish" section with reset_to_defaults
- **Added**: 4 new system classes: MeleeArcSystem, ShadowSystem, CombatFeedbackSystem, AtmosphereSystem
- **Changed**: LevelMVP creates and updates all 4 new visual systems
- **Changed**: All visual systems use pooled nodes (no per-frame allocation)
- **Changed**: All visual effects are headless-test safe (no crashes in --headless mode)
- **Added**: 17 new unit tests (Sections 17-19): GameConfig defaults, system classes, reset_to_defaults

#### Test Results
- Unit tests: 79/79 passing (was 62)
- Level smoke tests: 4/4 passing
- Melee smoke tests: 7/7 passing
- **Total: 90/90 tests passing**

#### New Files
- `src/systems/melee_arc_system.gd` — Katana slash visual arcs
- `src/systems/shadow_system.gd` — Entity shadows + player highlight ring
- `src/systems/combat_feedback_system.gd` — Hit/kill/damage screen overlays
- `src/systems/atmosphere_system.gd` — Ambient particles + floor decals

#### Modified Files
- `src/core/game_config.gd` — 40+ visual polish tunables + reset_to_defaults
- `src/systems/footprint_system.gd` — Complete rewrite (pooled, movement-aligned, boot tread)
- `src/systems/vfx_system.gd` — Blood aging, corpse settle, decal clamping, update_aging()
- `src/entities/enemy.gd` — White flash 0.06s, kill pop 1.0→1.2→0
- `src/levels/level_mvp.gd` — 4 new systems, F3 debug overlay, HUD styling, vignette, floor overlay
- `src/ui/main_menu.gd` — Button hover animations, background pulse
- `scenes/levels/level_mvp.tscn` — Updated debug hints with F3
- `project.godot` — `debug_toggle` input action (F3)
- `tests/test_runner_node.gd` — 17 new visual polish tests

### 02:57 MSK - PATCH 0.2 Phase 1: Katana Core + Feel
- **Added**: MeleeSystem — full katana state machine (IDLE → WINDUP → ACTIVE → RECOVERY / DASHING)
- **Added**: 3 katana moves: Light Slash (LMB), Heavy Slash (RMB), Dash Slash (Space)
- **Added**: Katana Mode toggle (Q key) — switches between GUN and KATANA modes
- **Added**: All katana tunables in GameConfig (30+ parameters: damage, arc, range, knockback, stagger, hitstop per move)
- **Added**: Input buffer system (0.12s) for responsive move queuing
- **Added**: Hitstop on melee hit (Engine.time_scale brief freeze, safe restore)
- **Added**: Knockback + stagger system on enemies (blocks movement, decays over time)
- **Added**: Dash slash with i-frames (invulnerability window during dash center)
- **Added**: `RuntimeState.katana_mode`, `is_player_invulnerable`, `invuln_timer`
- **Added**: EventBus signals: `katana_mode_changed`, `melee_hit`
- **Added**: InputMap actions: `katana_toggle` (Q), `katana_light` (LMB), `katana_heavy` (RMB), `katana_dash` (Space)
- **Added**: `enemy.apply_damage()`, `enemy.apply_stagger()`, `enemy.apply_knockback()` methods
- **Added**: `boss.apply_damage()` (delegates to take_damage), stagger/knockback immune
- **Added**: Invulnerability guard in CombatSystem and Boss damage pipelines
- **Added**: HUD displays "Mode: GUN / KATANA" with weapon info or slash state
- **Added**: VFX hook — melee hits emit `blood_spawned` + `melee_hit` events
- **Added**: Headless smoke test `test_melee_smoke.tscn` — 7 tests (toggle, slash damage, dash movement)
- **Changed**: Player blocks shooting/weapon switching when katana mode ON
- **Changed**: level_mvp.gd creates and updates MeleeSystem
- **Files**: `src/systems/melee_system.gd` (new), `src/core/game_config.gd`, `src/core/runtime_state.gd`, `src/systems/event_bus.gd`, `src/entities/enemy.gd`, `src/entities/boss.gd`, `src/entities/player.gd`, `src/systems/combat_system.gd`, `src/levels/level_mvp.gd`, `scenes/levels/level_mvp.tscn`, `project.godot`, `tests/test_melee_smoke.gd` (new), `tests/test_melee_smoke.tscn` (new)

## 2026-02-06

### 19:00 MSK - Phase 4: Sound Effects System
- **Added**: SFXSystem — audio player pool (12 channels) with EventBus integration
- **Added**: 14 procedurally generated SFX files via sox (WAV, 44100 Hz, mono):
  - Weapon shots: `pistol_shot`, `auto_shot`, `shotgun_shot`, `plasma_shot`, `rocket_shot`, `chain_lightning`
  - Explosions: `rocket_explosion`
  - Combat: `enemy_death`, `player_hit`, `player_death`
  - UI/events: `weapon_switch`, `wave_start`, `boss_spawn`, `boss_death`
- **Added**: Per-weapon shot sounds via `WEAPON_SFX` mapping
- **Added**: Volume control reads from `GameConfig.sfx_volume` (existing slider in Settings)
- **Files**: `src/systems/sfx_system.gd` (new), `src/app_root.gd`, `assets/audio/sfx/*.wav` (14 files)

### 18:30 MSK - Phase 3: Arena Combat Polish + Full Weapon System

#### PART A — Arena Combat Polish
- **Added**: Camera shake on rocket explosion (A1) — small amplitude, short duration, purely visual
- **Added**: "WAVE X" overlay on wave start (A2) — fade-in/out animation + subtle screen flash
- **Added**: Enemy spawn visual cue (A3) — scale-in animation with white flash
- **Added**: Enemy death feedback (A4) — white flash + scale burst before cleanup
- **Added**: Arena boundary visualization (A5) — darkened border strips beyond play area

#### PART B — Full Weapon System
- **Added**: AbilitySystem — weapon registry with 6 weapons, reads stats from GameConfig (B1)
  - Pistol: single bullet, 180 RPM
  - Automatic: rapid bullet fire, 150 RPM
  - Shotgun: 5-pellet spread, 60 RPM
  - Plasma: slow heavy projectile, 120 RPM
  - Rocket Launcher: explosive + AoE damage on hit/TTL, 30 RPM
  - Chain Lightning: hitscan chaining up to 5 targets, 120 RPM
- **Added**: Weapon switching (B2) — mouse wheel cycle + keys 1-6 direct select
- **Added**: HUD weapon display (B3) — shows current weapon name and slot number
- **Added**: Rocket AoE explosion — damages all enemies/bosses in 7-tile radius
- **Added**: Chain lightning VFX — jagged line arcs between targets

#### Architecture
- **Added**: `GameConfig.weapon_stats` — canonical weapon parameters (no hardcoded stats)
- **Changed**: `ProjectileSystem.WEAPON_STATS` reads from GameConfig on init
- **Added**: 3 new EventBus signals: `weapon_changed`, `rocket_exploded`, `chain_lightning_hit`
- **Added**: 8 input actions: `weapon_next/prev`, `weapon_1` through `weapon_6`

#### New Files
- `src/systems/ability_system.gd` — weapon registry + activation + chain lightning hitscan
- `src/systems/camera_shake.gd` — camera shake utility
- `src/ui/wave_overlay.gd` — wave start announcement overlay
- `src/systems/arena_boundary.gd` — visual arena edge

#### Modified Files
- `src/systems/event_bus.gd` — 3 new signals + emit methods + dispatch cases
- `src/core/game_config.gd` — weapon_stats dict + shake params
- `src/entities/projectile.gd` — rocket AoE explosion
- `src/systems/projectile_system.gd` — reads from GameConfig
- `src/entities/enemy.gd` — spawn animation + death feedback
- `src/entities/player.gd` — AbilitySystem delegation + weapon switching
- `src/systems/vfx_system.gd` — chain lightning arc visuals
- `src/levels/level_mvp.gd` — all systems wired, HUD weapon display
- `scenes/levels/level_mvp.tscn` — WeaponLabel + updated debug hints
- `project.godot` — 8 new input actions

### 13:47 MSK - Reliability & Smoke Tests
- **Fixed**: AppRoot now calls `_pause_level()` before showing UI on GAME_OVER and LEVEL_COMPLETE (guarantees gameplay stop even if nodes skip `is_frozen` check)
- **Fixed**: EventBus `_compare_events` uses bracket access `a["priority"]` instead of dot notation (stable Dictionary key access)
- **Added**: WaveManager subscribes to `state_changed` — disables `_spawning_active` on MAIN_MENU/GAME_OVER/LEVEL_COMPLETE (prevents zombie spawns in dead level)
- **Added**: Headless smoke test (`test_level_smoke.tscn`) — start-delay guard, enemy spawning, boss_killed→LEVEL_COMPLETE (4/4 passing)
- **Removed**: Unused `_is_paused` variable from `level_mvp.gd` (single source of truth: `RuntimeState.is_frozen`)
- **Files**: `src/app_root.gd`, `src/systems/event_bus.gd`, `src/systems/wave_manager.gd`, `src/levels/level_mvp.gd`, `tests/test_level_smoke.gd`, `tests/test_level_smoke.tscn`, `README.md`

## 2026-02-05

### 19:40 MSK - Boss Bug Fix
- **Fixed**: AoE attack now centers on BOSS position instead of player position
- **Fixed**: AoE damage only applies when player is within 8-tile radius
- **Fixed**: Boss spawns >= 10 tiles away from player
- **Added**: `BOSS_MIN_SPAWN_DISTANCE_TILES` constant (10.0)
- **Added**: `Boss.get_safe_spawn_position()` static helper
- **Files**: `src/entities/boss.gd`, `src/systems/wave_manager.gd`

### 19:30 MSK - Typing Warnings Fix
- **Fixed**: `footprint_system.gd:80` - explicit cast for `pop_front()`
- **Fixed**: `footprint_system.gd:128` - explicit float type for `absf()`
- **Files**: `src/systems/footprint_system.gd`

### 19:20 MSK - SFX Volume Slider
- **Added**: `sfx_volume` parameter in GameConfig
- **Added**: SFX Volume slider in Settings menu
- **Files**: `src/core/game_config.gd`, `src/ui/settings_menu.gd`, `scenes/ui/settings_menu.tscn`

### 19:00 MSK - Test Infrastructure
- **Added**: Scene-based test runner (`test_runner.tscn`, `test_runner_node.gd`)
- **Result**: 62/62 tests passing
- **Files**: `tests/test_runner.tscn`, `tests/test_runner_node.gd`

### 18:30 MSK - Initial Commit v0.01
- **Added**: Initial project structure
- **Pushed**: https://github.com/Alex-cat-ui/arena-shooter
- **Files**: all project files
