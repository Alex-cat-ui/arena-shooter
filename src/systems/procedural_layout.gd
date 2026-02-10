## procedural_layout.gd
## ProceduralLayout – Hotline-style BSP room generator (composition-first).
## CANON: Space-filling BSP leaves. Corridor leaves are thin strips (real rooms).
## CANON: Walls from BSP split lines + perimeter. Doors cut into split walls.
## CANON: BSP-tree doors (no all-pairs scan), MAX_DOORS_PER_ROOM from config (default 2), 0..1 extra loops.
## CANON: Composition enforcement – hub/spine/ring/dual-hub forced connections + protected doors.
class_name ProceduralLayout
extends RefCounted

## Layout output data
var rooms: Array = []           # [{id:int, rects:[Rect2], center:Vector2, is_corridor:bool}]
var corridors: Array = []       # [Rect2] -- corridor leaf rects (debug/UI only)
var void_rects: Array = []      # [Rect2] -- VOID leaf rects (exterior cutouts)
var doors: Array = []           # [Rect2]
var player_room_id: int = -1
var player_spawn_pos: Vector2 = Vector2.ZERO
var layout_seed: int = 0
var valid: bool = false

## Debug stats
var max_doors_stat: int = 0
var extra_loops: int = 0
var isolated_fixed: int = 0
var big_rooms_count: int = 0
var avg_degree: float = 0.0

## Internal
var _arena: Rect2
var _cell_size: float = 8.0

## BSP tree and data
var _bsp_root: Dictionary = {}
var _leaves: Array = []          # leaf dicts with rect, leaf_id, is_corridor
var _split_segs: Array = []      # [{type:"V"/"H", pos:float, t0:float, t1:float, left_ids:Array, right_ids:Array}]
var _wall_segs: Array = []       # final wall segments after cutting doors

## Door tracking
var _door_adj: Dictionary = {}   # room_id -> Array[int] connected via doors
var _door_map: Array = []        # [{a:int, b:int, rect:Rect2}]
var _logical_corr_count: int = 0
var _big_leaf_set: Array = []

## Topology
enum LayoutMode { CENTRAL_HALL, CENTRAL_SPINE, CENTRAL_RING, CENTRAL_LIKE_HUB }
var _layout_mode: int = 0
var _hub_ids: Array = []
var _ring_ids: Array = []
var _low_priority_ids: Array = []
var _void_ids: Array = []
var _leaf_adj: Dictionary = {}
var layout_mode_name: String = ""
const COMPLEX_SHAPES_CHANCE := 0.15
var _l_room_ids: Array = []
var _l_room_notches: Array = []  # [{room_id:int, notch_rect:Rect2, corner:String}]
var _perimeter_notches: Array = []  # [{room_id:int, notch_rect:Rect2, side:String}]
var _t_u_room_ids: Array = []
var _complex_shape_wall_segs: Array = []
var _entry_gate: Rect2 = Rect2()

## Composition enforcement (Part 4)
var _protected_doors: Array = []  # [{a:int, b:int}] normalized (a<b)
var _composition_ok: bool = true


## ============================================================================
## PUBLIC API
## ============================================================================

static func generate_and_build(arena_rect: Rect2, p_seed: int, walls_node: Node2D, debug_node: Node2D, player_node: Node2D) -> ProceduralLayout:
	var layout := ProceduralLayout.new()
	layout._arena = arena_rect

	var current_seed := p_seed
	for attempt in range(30):
		seed(current_seed)
		layout.layout_seed = current_seed
		layout._generate()
		if layout._validate():
			layout.valid = true
			break
		current_seed += 1
		layout.rooms.clear()
		layout.corridors.clear()
		layout.doors.clear()
		layout._door_adj.clear()
		layout._door_map.clear()
		layout._logical_corr_count = 0
		layout._big_leaf_set.clear()
		layout._leaves.clear()
		layout._split_segs.clear()
		layout._wall_segs.clear()
		layout._hub_ids.clear()
		layout._ring_ids.clear()
		layout._low_priority_ids.clear()
		layout._void_ids.clear()
		layout.void_rects.clear()
		layout._leaf_adj.clear()
		layout._l_room_ids.clear()
		layout._l_room_notches.clear()
		layout._perimeter_notches.clear()
		layout._t_u_room_ids.clear()
		layout._complex_shape_wall_segs.clear()
		layout._entry_gate = Rect2()
		layout._protected_doors.clear()
		layout._composition_ok = true

	if layout.valid:
		layout._build_walls(walls_node)
		layout._place_player(player_node)
		if GameConfig and GameConfig.layout_debug_draw:
			layout._build_debug(debug_node)
		var void_area_pct := 0.0
		var arena_area := layout._arena.get_area()
		for vr: Rect2 in layout.void_rects:
			void_area_pct += vr.get_area()
		void_area_pct = void_area_pct / maxf(arena_area, 1.0) * 100.0
		print("[ProceduralLayout] OK seed=%d arena=%.0fx%.0f rooms=%d corridors=%d doors=%d big=%d avg_deg=%.1f max_doors=%d loops=%d isolated=%d corr_leaves=%d mode=%s hubs=%d voids=%d void%%=%.1f l_rooms=%d gate=%s" % [
			layout.layout_seed, layout._arena.size.x, layout._arena.size.y,
			layout.rooms.size(), layout.corridors.size(),
			layout.doors.size(), layout.big_rooms_count,
			layout.avg_degree, layout.max_doors_stat, layout.extra_loops, layout.isolated_fixed,
			layout._logical_corr_count, layout.layout_mode_name, layout._hub_ids.size(),
			layout._void_ids.size(), void_area_pct, layout._l_room_ids.size(),
			str(layout._entry_gate != Rect2())])
	else:
		push_warning("[ProceduralLayout] FAILED after 30 attempts")

	return layout


## ============================================================================
## GENERATION
## ============================================================================

func _generate() -> void:
	rooms.clear()
	corridors.clear()
	doors.clear()
	_door_adj.clear()
	_door_map.clear()
	_leaves.clear()
	_split_segs.clear()
	_wall_segs.clear()
	_logical_corr_count = 0
	_big_leaf_set.clear()
	_hub_ids.clear()
	_ring_ids.clear()
	_low_priority_ids.clear()
	_void_ids.clear()
	void_rects.clear()
	_leaf_adj.clear()
	_l_room_ids.clear()
	_l_room_notches.clear()
	_perimeter_notches.clear()
	_t_u_room_ids.clear()
	_complex_shape_wall_segs.clear()
	_entry_gate = Rect2()
	_protected_doors.clear()
	_composition_ok = true
	_layout_mode = 0
	layout_mode_name = ""
	extra_loops = 0
	isolated_fixed = 0
	big_rooms_count = 0
	avg_degree = 0.0

	var target := randi_range(
		GameConfig.rooms_count_min if GameConfig else 6,
		GameConfig.rooms_count_max if GameConfig else 9)

	# 1) BSP split with forced corridor leaves (Part 2: anti-cross)
	_bsp_root = _bsp_split_with_corridors(target)

	# 2) Collect leaves and assign IDs
	var leaf_nodes: Array = []
	_collect_leaves_dfs(_bsp_root, leaf_nodes)
	_leaves = leaf_nodes
	for i in range(_leaves.size()):
		_leaves[i]["leaf_id"] = i

	# 3) Identify largest non-corridor leaves
	var non_corr_rects: Array = []
	for lf in _leaves:
		non_corr_rects.append(lf["rect"] as Rect2)
	var big_target: int = GameConfig.big_rooms_target if GameConfig else 2
	_big_leaf_set = _find_largest_leaves(non_corr_rects, big_target)

	# 4) Create rooms from leaves (space-filling, no shrink)
	_create_rooms_from_leaves()

	# 4.3) Room identity check (Part 6) — bad rooms → early return → validate fails
	if not _check_room_identity():
		_composition_ok = false
		return

	# 4.5) Build leaf adjacency + assign topology roles
	_build_leaf_adjacency()
	_assign_topology_roles()

	# 4.7) Assign VOID cutouts (Hotline silhouette — strengthened Part 5)
	_assign_void_cutouts()

	# 4.75) Perimeter notches (real silhouette cuts)
	_apply_perimeter_notches()

	# 4.8) Apply L-shaped rooms (internal notch cuts)
	_apply_l_rooms()

	# 4.9) Apply T/U complex room shapes
	_apply_t_u_shapes()

	# 5) Collect split segments from BSP tree
	_collect_split_segments(_bsp_root)

	# 6) Init door adjacency
	for i in range(rooms.size()):
		_door_adj[i] = []

	# 7) BSP-tree doors (spanning tree) — Part 7: up to 2 doors per split
	_create_doors_bsp(_bsp_root)

	# 7.5) Composition enforcement (Part 4) — forced doors + protected set
	if GameConfig and GameConfig.composition_enabled:
		if not _enforce_composition():
			_composition_ok = false
			return

	# 8) Optional extra loops (0..1)
	var el_max: int = mini(GameConfig.extra_loops_max if GameConfig else 1, 1)
	_add_extra_loops(randi_range(0, el_max))

	# 9) Enforce max doors per room (Part 4: skip protected doors)
	_enforce_max_doors()

	# 10) Ensure full connectivity (Part 7: BFS recompute after each door)
	if not _ensure_connectivity():
		_composition_ok = false
		return

	# 11) Player room
	_find_player_room()

	# 12) Entry gate on top perimeter
	_compute_entry_gate()

	# Compute debug stats (skip VOID)
	var md := 0
	var total_degree := 0.0
	var solid_count_stat := 0
	for i in range(rooms.size()):
		if i in _void_ids:
			continue
		solid_count_stat += 1
		var deg := 0
		if _door_adj.has(i):
			deg = (_door_adj[i] as Array).size()
		md = maxi(md, deg)
		total_degree += float(deg)
	max_doors_stat = md
	avg_degree = total_degree / maxf(float(solid_count_stat), 1.0)

	# Count big rooms (skip VOID) - use bounding box of all rects
	var big_w: float = GameConfig.big_room_min_w if GameConfig else 360.0
	var big_h: float = GameConfig.big_room_min_h if GameConfig else 280.0
	big_rooms_count = 0
	for room in rooms:
		if room.get("is_void", false) == true:
			continue
		var bbox := _room_bounding_box(int(room["id"]))
		if bbox.size.x >= big_w or bbox.size.y >= big_h:
			big_rooms_count += 1


func _find_largest_leaves(leaf_rects: Array, count: int) -> Array:
	var indexed: Array = []
	for i in range(leaf_rects.size()):
		indexed.append({"idx": i, "area": (leaf_rects[i] as Rect2).get_area()})
	indexed.sort_custom(func(a, b): return float(a["area"]) > float(b["area"]))
	var result: Array = []
	for i in range(mini(count, indexed.size())):
		result.append(int(indexed[i]["idx"]))
	return result


## ============================================================================
## BSP TREE WITH CORRIDOR LEAVES (Part 2: anti-cross + center-avoid)
## ============================================================================

func _bsp_split_with_corridors(target_count: int) -> Dictionary:
	var min_leaf_w: float = GameConfig.room_min_w if GameConfig else 220.0
	var min_leaf_h: float = GameConfig.room_min_h if GameConfig else 200.0
	var corr_w_min_val: float = GameConfig.corridor_w_min if GameConfig else 80.0
	var corr_w_max_val: float = GameConfig.corridor_w_max if GameConfig else 110.0
	var corridor_len_min_val: float = GameConfig.corridor_len_min if GameConfig else 320.0
	var MAX_ASPECT := 5.0
	var cross_max_frac: float = GameConfig.cross_split_max_frac if GameConfig else 0.72
	var arena_major := maxf(_arena.size.x, _arena.size.y)
	var center_avoid := 0.08

	var root := {"rect": _arena, "left": null, "right": null, "leaf_id": -1, "is_corridor": false}
	var all_nodes: Array = [root]

	# Determine how many corridor leaves to force
	var corr_max := 2
	if target_count >= 9:
		corr_max = 3
	var K := randi_range(1, corr_max)
	var perimeter_corr_placed := 0

	# --- Phase 1: Force K corridor leaves (prefer interior triple-split) ---
	for _k in range(K):
		# --- Try interior triple split: room | corridor | room ---
		var best_triple = null
		var best_triple_area := 0.0
		for n in all_nodes:
			if n["left"] != null:
				continue
			if n["is_corridor"] == true:
				continue
			var lf: Rect2 = n["rect"]
			var can_v := lf.size.x >= min_leaf_w + corr_w_min_val + min_leaf_w and lf.size.y >= corridor_len_min_val
			var can_h := lf.size.y >= min_leaf_h + corr_w_min_val + min_leaf_h and lf.size.x >= corridor_len_min_val
			if (can_v or can_h) and lf.get_area() > best_triple_area:
				best_triple_area = lf.get_area()
				best_triple = n

		if best_triple != null:
			var lf: Rect2 = best_triple["rect"]
			var can_v := lf.size.x >= min_leaf_w + corr_w_min_val + min_leaf_w and lf.size.y >= corridor_len_min_val
			var can_h := lf.size.y >= min_leaf_h + corr_w_min_val + min_leaf_h and lf.size.x >= corridor_len_min_val
			var do_vert: bool
			if can_v and can_h:
				do_vert = randf() > 0.5
			elif can_v:
				do_vert = true
			else:
				do_vert = false

			if do_vert:
				var max_sw := lf.size.x - min_leaf_w * 2.0
				var sw := clampf(randf_range(corr_w_min_val, corr_w_max_val), corr_w_min_val, max_sw)
				var cx := randf_range(lf.position.x + min_leaf_w, lf.end.x - min_leaf_w - sw)
				var left_room := {"rect": Rect2(lf.position, Vector2(cx - lf.position.x, lf.size.y)), "left": null, "right": null, "leaf_id": -1, "is_corridor": false}
				var corr_rect := Rect2(Vector2(cx, lf.position.y), Vector2(sw, lf.size.y))
				var corridor_node := {"rect": corr_rect, "left": null, "right": null, "leaf_id": -1, "is_corridor": true}
				var right_room := {"rect": Rect2(Vector2(cx + sw, lf.position.y), Vector2(lf.end.x - cx - sw, lf.size.y)), "left": null, "right": null, "leaf_id": -1, "is_corridor": false}
				var chunk_rect := Rect2(Vector2(cx, lf.position.y), Vector2(lf.end.x - cx, lf.size.y))
				var intermediate := {"rect": chunk_rect, "left": corridor_node, "right": right_room, "leaf_id": -1, "is_corridor": false}
				best_triple["left"] = left_room
				best_triple["right"] = intermediate
				all_nodes.append(left_room)
				all_nodes.append(intermediate)
				all_nodes.append(corridor_node)
				all_nodes.append(right_room)
			else:
				var max_sw := lf.size.y - min_leaf_h * 2.0
				var sw := clampf(randf_range(corr_w_min_val, corr_w_max_val), corr_w_min_val, max_sw)
				var cy := randf_range(lf.position.y + min_leaf_h, lf.end.y - min_leaf_h - sw)
				var top_room := {"rect": Rect2(lf.position, Vector2(lf.size.x, cy - lf.position.y)), "left": null, "right": null, "leaf_id": -1, "is_corridor": false}
				var corr_rect := Rect2(Vector2(lf.position.x, cy), Vector2(lf.size.x, sw))
				var corridor_node := {"rect": corr_rect, "left": null, "right": null, "leaf_id": -1, "is_corridor": true}
				var bottom_room := {"rect": Rect2(Vector2(lf.position.x, cy + sw), Vector2(lf.size.x, lf.end.y - cy - sw)), "left": null, "right": null, "leaf_id": -1, "is_corridor": false}
				var chunk_rect := Rect2(Vector2(lf.position.x, cy), Vector2(lf.size.x, lf.end.y - cy))
				var intermediate := {"rect": chunk_rect, "left": corridor_node, "right": bottom_room, "leaf_id": -1, "is_corridor": false}
				top_room["left"] = null
				best_triple["left"] = top_room
				best_triple["right"] = intermediate
				all_nodes.append(top_room)
				all_nodes.append(intermediate)
				all_nodes.append(corridor_node)
				all_nodes.append(bottom_room)
			_logical_corr_count += 1
			continue

		# --- Fallback: edge corridor (max 1 perimeter corridor) ---
		if perimeter_corr_placed >= 1:
			continue
		var best = null
		var best_area := 0.0
		for n in all_nodes:
			if n["left"] != null:
				continue
			if n["is_corridor"] == true:
				continue
			var lf: Rect2 = n["rect"]
			var can_v := lf.size.x >= corr_w_min_val + min_leaf_w and lf.size.y >= corridor_len_min_val
			var can_h := lf.size.y >= corr_w_min_val + min_leaf_h and lf.size.x >= corridor_len_min_val
			if (can_v or can_h) and lf.get_area() > best_area:
				best_area = lf.get_area()
				best = n
		if best == null:
			continue

		var lf2: Rect2 = best["rect"]
		var can_v2 := lf2.size.x >= corr_w_min_val + min_leaf_w and lf2.size.y >= corridor_len_min_val
		var can_h2 := lf2.size.y >= corr_w_min_val + min_leaf_h and lf2.size.x >= corridor_len_min_val
		var do_vert2: bool
		if can_v2 and can_h2:
			do_vert2 = randf() > 0.5
		elif can_v2:
			do_vert2 = true
		else:
			do_vert2 = false

		if do_vert2:
			var max_sw := lf2.size.x - min_leaf_w
			var sw := clampf(randf_range(corr_w_min_val, corr_w_max_val), corr_w_min_val, max_sw)
			var on_right := randf() > 0.5
			if on_right:
				var sx := lf2.end.x - sw
				best["left"] = {"rect": Rect2(lf2.position, Vector2(sx - lf2.position.x, lf2.size.y)), "left": null, "right": null, "leaf_id": -1, "is_corridor": false}
				best["right"] = {"rect": Rect2(Vector2(sx, lf2.position.y), Vector2(sw, lf2.size.y)), "left": null, "right": null, "leaf_id": -1, "is_corridor": true}
			else:
				best["left"] = {"rect": Rect2(lf2.position, Vector2(sw, lf2.size.y)), "left": null, "right": null, "leaf_id": -1, "is_corridor": true}
				best["right"] = {"rect": Rect2(Vector2(lf2.position.x + sw, lf2.position.y), Vector2(lf2.size.x - sw, lf2.size.y)), "left": null, "right": null, "leaf_id": -1, "is_corridor": false}
		else:
			var max_sw := lf2.size.y - min_leaf_h
			var sw := clampf(randf_range(corr_w_min_val, corr_w_max_val), corr_w_min_val, max_sw)
			var on_bottom := randf() > 0.5
			if on_bottom:
				var sy := lf2.end.y - sw
				best["left"] = {"rect": Rect2(lf2.position, Vector2(lf2.size.x, sy - lf2.position.y)), "left": null, "right": null, "leaf_id": -1, "is_corridor": false}
				best["right"] = {"rect": Rect2(Vector2(lf2.position.x, sy), Vector2(lf2.size.x, sw)), "left": null, "right": null, "leaf_id": -1, "is_corridor": true}
			else:
				best["left"] = {"rect": Rect2(lf2.position, Vector2(lf2.size.x, sw)), "left": null, "right": null, "leaf_id": -1, "is_corridor": true}
				best["right"] = {"rect": Rect2(Vector2(lf2.position.x, lf2.position.y + sw), Vector2(lf2.size.x, lf2.size.y - sw)), "left": null, "right": null, "leaf_id": -1, "is_corridor": false}

		all_nodes.append(best["left"])
		all_nodes.append(best["right"])
		_logical_corr_count += 1
		perimeter_corr_placed += 1

	# --- Phase 2: Normal BSP splitting until leaf_count >= target_count ---
	# Part 2: anti-cross (long split ban) + center-avoid
	var arena_cx := _arena.position.x + _arena.size.x * 0.5
	var arena_cy := _arena.position.y + _arena.size.y * 0.5

	while true:
		var leaf_count := 0
		for n in all_nodes:
			if n["left"] == null:
				leaf_count += 1
		if leaf_count >= target_count:
			break

		var best = null
		var best_area := 0.0
		for n in all_nodes:
			if n["left"] != null:
				continue
			if n["is_corridor"] == true:
				continue
			var lf: Rect2 = n["rect"]
			var can_any := lf.size.x >= min_leaf_w * 2 or lf.size.y >= min_leaf_h * 2
			if can_any and lf.get_area() > best_area:
				best_area = lf.get_area()
				best = n
		if best == null:
			break

		var lf: Rect2 = best["rect"]
		var can_v := lf.size.x >= min_leaf_w * 2
		var can_h := lf.size.y >= min_leaf_h * 2

		# Build orientation list: preferred first, then fallback
		var orientations: Array = []
		if can_h and can_v:
			var prefer_horiz: bool = lf.size.y >= lf.size.x if absf(lf.size.y - lf.size.x) > 40.0 else randf() > 0.5
			if prefer_horiz:
				orientations = [true, false]
			else:
				orientations = [false, true]
		elif can_h:
			orientations = [true]
		else:
			orientations = [false]

		var split_ok := false
		for horiz in orientations:
			if horiz:
				# Part 2: horizontal split creates line of length lf.size.x
				var line_len := lf.size.x
				if line_len > arena_major * cross_max_frac:
					continue  # Too long — would create cross

				# Try split position with center-avoid
				var sy := 0.0
				var valid_pos := false
				for _try in range(5):
					sy = lf.position.y + lf.size.y * randf_range(0.25, 0.75)
					# Center-avoid: if arena center Y is within leaf range
					if arena_cy >= lf.position.y and arena_cy <= lf.end.y:
						if absf(sy - arena_cy) < _arena.size.y * center_avoid:
							continue  # Too close to arena center
					valid_pos = true
					break
				if not valid_pos:
					sy = lf.position.y + lf.size.y * randf_range(0.35, 0.65)

				var top_h := sy - lf.position.y
				var bot_h := lf.end.y - sy
				var top_ar := maxf(lf.size.x, top_h) / maxf(minf(lf.size.x, top_h), 1.0)
				var bot_ar := maxf(lf.size.x, bot_h) / maxf(minf(lf.size.x, bot_h), 1.0)
				if top_ar > MAX_ASPECT or bot_ar > MAX_ASPECT:
					continue
				best["left"] = {"rect": Rect2(lf.position, Vector2(lf.size.x, top_h)), "left": null, "right": null, "leaf_id": -1, "is_corridor": false}
				best["right"] = {"rect": Rect2(Vector2(lf.position.x, sy), Vector2(lf.size.x, bot_h)), "left": null, "right": null, "leaf_id": -1, "is_corridor": false}
				split_ok = true
				break
			else:
				# Part 2: vertical split creates line of length lf.size.y
				var line_len := lf.size.y
				if line_len > arena_major * cross_max_frac:
					continue  # Too long — would create cross

				# Try split position with center-avoid
				var sx := 0.0
				var valid_pos := false
				for _try in range(5):
					sx = lf.position.x + lf.size.x * randf_range(0.25, 0.75)
					# Center-avoid: if arena center X is within leaf range
					if arena_cx >= lf.position.x and arena_cx <= lf.end.x:
						if absf(sx - arena_cx) < _arena.size.x * center_avoid:
							continue
					valid_pos = true
					break
				if not valid_pos:
					sx = lf.position.x + lf.size.x * randf_range(0.35, 0.65)

				var left_w := sx - lf.position.x
				var right_w := lf.end.x - sx
				var left_ar := maxf(left_w, lf.size.y) / maxf(minf(left_w, lf.size.y), 1.0)
				var right_ar := maxf(right_w, lf.size.y) / maxf(minf(right_w, lf.size.y), 1.0)
				if left_ar > MAX_ASPECT or right_ar > MAX_ASPECT:
					continue
				best["left"] = {"rect": Rect2(lf.position, Vector2(left_w, lf.size.y)), "left": null, "right": null, "leaf_id": -1, "is_corridor": false}
				best["right"] = {"rect": Rect2(Vector2(sx, lf.position.y), Vector2(right_w, lf.size.y)), "left": null, "right": null, "leaf_id": -1, "is_corridor": false}
				split_ok = true
				break

		if not split_ok:
			break

		all_nodes.append(best["left"])
		all_nodes.append(best["right"])

	return root


func _collect_leaves_dfs(node: Dictionary, result: Array) -> void:
	if node["left"] == null:
		result.append(node)
		return
	_collect_leaves_dfs(node["left"], result)
	_collect_leaves_dfs(node["right"], result)


func _get_leaf_ids(node: Dictionary) -> Array:
	if node["left"] == null:
		return [int(node["leaf_id"])]
	var result: Array = []
	result.append_array(_get_leaf_ids(node["left"]))
	result.append_array(_get_leaf_ids(node["right"]))
	return result


## ============================================================================
## ROOMS (space-filling leaves, no shrink)
## ============================================================================

func _create_rooms_from_leaves() -> void:
	for i in range(_leaves.size()):
		var leaf: Dictionary = _leaves[i]
		var lf: Rect2 = leaf["rect"]
		var is_corr: bool = leaf["is_corridor"] == true

		rooms.append({
			"id": i,
			"rects": [lf],
			"center": lf.get_center(),
			"is_corridor": is_corr,
			"is_void": false,
		})

		if is_corr:
			corridors.append(lf)


## ============================================================================
## ROOM IDENTITY CHECK (Part 6)
## ============================================================================

func _check_room_identity() -> bool:
	var corridor_w_min_val: float = GameConfig.corridor_w_min if GameConfig else 80.0
	var narrow_max: int = GameConfig.narrow_room_max if GameConfig else 1
	var narrow_count := 0

	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] == true:
			continue
		var r: Rect2 = (rooms[i]["rects"] as Array)[0] as Rect2

		# If min dimension < corridor_w_min → effectively a corridor → invalid
		if minf(r.size.x, r.size.y) < corridor_w_min_val:
			return false

		# Count narrow rooms (aspect > 2.7)
		var aspect := maxf(r.size.x, r.size.y) / maxf(minf(r.size.x, r.size.y), 1.0)
		if aspect > 2.7:
			narrow_count += 1

	if narrow_count > narrow_max:
		return false

	return true


## ============================================================================
## TOPOLOGY ROLES
## ============================================================================

func _build_leaf_adjacency() -> void:
	_leaf_adj.clear()
	for i in range(rooms.size()):
		_leaf_adj[i] = []
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			if _rooms_touch(i, j):
				(_leaf_adj[i] as Array).append(j)
				(_leaf_adj[j] as Array).append(i)


func _rooms_touch(a: int, b: int) -> bool:
	for ra: Rect2 in rooms[a]["rects"]:
		for rb: Rect2 in rooms[b]["rects"]:
			if _rects_touch(ra, rb):
				return true
	return false


func _rects_touch(ra: Rect2, rb: Rect2) -> bool:
	if absf(ra.end.x - rb.position.x) < 1.0 or absf(rb.end.x - ra.position.x) < 1.0:
		var y0 := maxf(ra.position.y, rb.position.y)
		var y1 := minf(ra.end.y, rb.end.y)
		if y1 - y0 > 10.0:
			return true
	if absf(ra.end.y - rb.position.y) < 1.0 or absf(rb.end.y - ra.position.y) < 1.0:
		var x0 := maxf(ra.position.x, rb.position.x)
		var x1 := minf(ra.end.x, rb.end.x)
		if x1 - x0 > 10.0:
			return true
	return false


func _room_bounding_box(room_id: int) -> Rect2:
	var rects: Array = rooms[room_id]["rects"]
	var bbox: Rect2 = rects[0] as Rect2
	for i in range(1, rects.size()):
		bbox = bbox.merge(rects[i] as Rect2)
	return bbox


func _room_total_area(room_id: int) -> float:
	var total := 0.0
	for r: Rect2 in rooms[room_id]["rects"]:
		total += r.get_area()
	return total


func _area_weighted_center(rects: Array) -> Vector2:
	var sum := Vector2.ZERO
	var total_area := 0.0
	for rect in rects:
		var r := rect as Rect2
		var a := r.get_area()
		sum += r.get_center() * a
		total_area += a
	return sum / maxf(total_area, 1.0)


func _perimeter_sides_for_rect(r: Rect2) -> Array:
	var sides: Array = []
	if absf(r.position.y - _arena.position.y) < 1.0:
		sides.append("TOP")
	if absf(r.end.y - _arena.end.y) < 1.0:
		sides.append("BOTTOM")
	if absf(r.position.x - _arena.position.x) < 1.0:
		sides.append("LEFT")
	if absf(r.end.x - _arena.end.x) < 1.0:
		sides.append("RIGHT")
	return sides


func _assign_topology_roles() -> void:
	_hub_ids.clear()
	_ring_ids.clear()
	_low_priority_ids.clear()

	# Edge corridor suppression: perimeter corridors → low priority
	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] != true:
			continue
		var r: Rect2 = (rooms[i]["rects"] as Array)[0] as Rect2
		var long_side := maxf(r.size.x, r.size.y)
		var perim_contact := 0.0
		if absf(r.position.x - _arena.position.x) < 1.0:
			perim_contact += r.size.y
		if absf(r.end.x - _arena.end.x) < 1.0:
			perim_contact += r.size.y
		if absf(r.position.y - _arena.position.y) < 1.0:
			perim_contact += r.size.x
		if absf(r.end.y - _arena.end.y) < 1.0:
			perim_contact += r.size.x
		if perim_contact > long_side * 0.5:
			_low_priority_ids.append(i)

	# Pick topology mode (weighted)
	_layout_mode = _choose_composition_mode()
	var mode_names := ["HALL", "SPINE", "RING", "DUAL_HUB"]
	layout_mode_name = mode_names[_layout_mode]
	var center := _arena.get_center()

	if _layout_mode == LayoutMode.CENTRAL_HALL:
		_assign_central_hall(center)
	elif _layout_mode == LayoutMode.CENTRAL_SPINE:
		_assign_central_spine(center)
	elif _layout_mode == LayoutMode.CENTRAL_RING:
		_assign_central_ring(center)
	else:
		_assign_central_like_hub(center)


func _choose_composition_mode() -> int:
	# CENTRAL_SPINE fixed at 20%.
	# Remaining 80% distributed across HALL, RING, DUAL_HUB.
	var roll := randf()
	if roll < 0.20:
		return LayoutMode.CENTRAL_SPINE
	if roll < 0.55:
		return LayoutMode.CENTRAL_HALL
	if roll < 0.80:
		return LayoutMode.CENTRAL_RING
	return LayoutMode.CENTRAL_LIKE_HUB


func _assign_central_hall(center: Vector2) -> void:
	# Largest non-corridor leaf near arena center → hub
	var best_id := -1
	var best_score := -1.0
	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] == true:
			continue
		if i in _low_priority_ids:
			continue
		var r: Rect2 = (rooms[i]["rects"] as Array)[0] as Rect2
		var dist := r.get_center().distance_to(center)
		var score := r.get_area() / maxf(dist, 1.0)
		if score > best_score:
			best_score = score
			best_id = i
	if best_id >= 0:
		_hub_ids.append(best_id)


func _assign_central_spine(center: Vector2) -> void:
	# Interior corridor leaf nearest center; fallback to longest rectangular leaf
	var best_id := -1
	var best_dist := INF
	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] != true:
			continue
		if i in _low_priority_ids:
			continue
		var dist := (rooms[i]["center"] as Vector2).distance_to(center)
		if dist < best_dist:
			best_dist = dist
			best_id = i
	if best_id < 0:
		var best_ratio := 0.0
		for i in range(rooms.size()):
			if i in _low_priority_ids:
				continue
			var r: Rect2 = (rooms[i]["rects"] as Array)[0] as Rect2
			var ratio := maxf(r.size.x, r.size.y) / maxf(minf(r.size.x, r.size.y), 1.0)
			if ratio > best_ratio:
				best_ratio = ratio
				best_id = i
	if best_id >= 0:
		_hub_ids.append(best_id)


func _assign_central_ring(center: Vector2) -> void:
	# Detect 3-5 adjacent leaves forming a loop
	var cycle := _find_short_cycle(3, 5)
	if cycle.is_empty():
		# Fallback: switch mode to HALL
		_layout_mode = LayoutMode.CENTRAL_HALL
		layout_mode_name = "HALL"
		_assign_central_hall(center)
		return
	_ring_ids = cycle
	_hub_ids = cycle.duplicate()


func _find_short_cycle(min_len: int, max_len: int) -> Array:
	for start in range(rooms.size()):
		var result := _dfs_cycle(start, start, [start], min_len, max_len)
		if not result.is_empty():
			return result
	return []


func _dfs_cycle(start: int, current: int, path: Array, min_len: int, max_len: int) -> Array:
	if path.size() > max_len:
		return []
	for neighbor in _leaf_adj[current]:
		var n := int(neighbor)
		if n == start and path.size() >= min_len:
			return path
		if n in path:
			continue
		if path.size() >= max_len:
			continue
		var new_path := path.duplicate()
		new_path.append(n)
		var result := _dfs_cycle(start, n, new_path, min_len, max_len)
		if not result.is_empty():
			return result
	return []


func _assign_central_like_hub(center: Vector2) -> void:
	# Select 2 adjacent large non-corridor leaves → dual hub
	var best_pair := [-1, -1]
	var best_score := 0.0
	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] == true:
			continue
		var ri: Rect2 = (rooms[i]["rects"] as Array)[0] as Rect2
		for j in _leaf_adj[i]:
			var jj := int(j)
			if jj <= i:
				continue
			if rooms[jj]["is_corridor"] == true:
				continue
			var rj: Rect2 = (rooms[jj]["rects"] as Array)[0] as Rect2
			var combined_area := ri.get_area() + rj.get_area()
			var avg_dist := ((rooms[i]["center"] as Vector2).distance_to(center) + (rooms[jj]["center"] as Vector2).distance_to(center)) * 0.5
			var score := combined_area / maxf(avg_dist, 1.0)
			if score > best_score:
				best_score = score
				best_pair = [i, jj]
	if best_pair[0] >= 0:
		_hub_ids.append(best_pair[0])
		_hub_ids.append(best_pair[1])
	else:
		# Fallback: switch mode to HALL
		_layout_mode = LayoutMode.CENTRAL_HALL
		layout_mode_name = "HALL"
		_assign_central_hall(center)


func _door_pair_priority(a: int, b: int) -> float:
	var score := 0.0
	var a_hub := a in _hub_ids
	var b_hub := b in _hub_ids
	if a_hub or b_hub:
		score += 1000.0
	if a in _ring_ids or b in _ring_ids:
		score += 800.0
	if a in _big_leaf_set or b in _big_leaf_set:
		score += 400.0
	if a not in _low_priority_ids and b not in _low_priority_ids:
		score += 200.0
	# CENTRAL_SPINE: penalize non-spine↔non-spine
	if _layout_mode == LayoutMode.CENTRAL_SPINE and not a_hub and not b_hub:
		score -= 500.0
	return score


func _max_doors_for_room(room_id: int) -> int:
	if room_id in _hub_ids:
		return 3
	if room_id in _ring_ids:
		return 3
	return mini(GameConfig.max_doors_per_room if GameConfig else 2, 2)


func _is_hub_adjacent(room_id: int) -> bool:
	if room_id in _hub_ids:
		return true
	if _leaf_adj.has(room_id):
		for neighbor in _leaf_adj[room_id]:
			if int(neighbor) in _hub_ids:
				return true
	return false


func _has_long_perimeter_corridor_chain(max_allowed: int) -> bool:
	var checked: Array = []
	for start in _low_priority_ids:
		var si := int(start)
		if si in checked:
			continue
		var component: Array = []
		var queue: Array = [si]
		while queue.size() > 0:
			var current: int = queue.pop_front()
			if current in component:
				continue
			component.append(current)
			if _door_adj.has(current):
				for neighbor in _door_adj[current]:
					var n := int(neighbor)
					if n in _low_priority_ids and n not in component:
						queue.append(n)
		checked.append_array(component)
		if component.size() > max_allowed:
			return true
	return false


## ============================================================================
## BFS HELPERS
## ============================================================================

func _bfs_connected(start: int) -> Array:
	var visited: Array = []
	var queue: Array = [start]
	while queue.size() > 0:
		var current: int = queue.pop_front()
		if current in visited:
			continue
		visited.append(current)
		if _door_adj.has(current):
			for n in _door_adj[current]:
				if int(n) not in visited:
					queue.append(int(n))
	return visited


func _bfs_distance(from_id: int, to_id: int) -> int:
	if from_id == to_id:
		return 0
	var visited: Dictionary = {}
	visited[from_id] = 0
	var queue: Array = [from_id]
	while queue.size() > 0:
		var current: int = queue.pop_front()
		var dist: int = int(visited[current])
		if _door_adj.has(current):
			for n in _door_adj[current]:
				var ni := int(n)
				if ni == to_id:
					return dist + 1
				if not visited.has(ni):
					visited[ni] = dist + 1
					queue.append(ni)
	return 999


## ============================================================================
## VOID CUTOUTS (Hotline silhouette — Part 5: strengthened)
## ============================================================================

func _assign_void_cutouts() -> void:
	_void_ids.clear()
	void_rects.clear()

	# Part 5: Always attempt voids; target 1..3
	var void_target := randi_range(1, 3)
	var min_center_dist := minf(_arena.size.x, _arena.size.y) * 0.15
	var arena_center := _arena.get_center()

	# Compute median leaf area for "large void" requirement
	var leaf_areas: Array = []
	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] == true:
			continue
		leaf_areas.append(_room_total_area(i))
	leaf_areas.sort()
	var median_area := 0.0
	if leaf_areas.size() > 0:
		median_area = float(leaf_areas[leaf_areas.size() / 2])

	# Candidates: exterior-void-valid, non-corridor, non-hub, non-ring
	var candidates: Array = []
	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] == true:
			continue
		if i in _hub_ids:
			continue
		if i in _ring_ids:
			continue
		if not _is_valid_exterior_void(i):
			continue
		# Part 5: center distance check
		var rc: Vector2 = rooms[i]["center"] as Vector2
		if rc.distance_to(arena_center) < min_center_dist:
			continue
		candidates.append(i)

	# Sort: corner rooms first (touching >= 2 sides), then by area descending
	candidates.sort_custom(func(a, b):
		var sides_a := _count_perimeter_sides(int(a))
		var sides_b := _count_perimeter_sides(int(b))
		var corner_a := 1 if sides_a >= 2 else 0
		var corner_b := 1 if sides_b >= 2 else 0
		if corner_a != corner_b:
			return corner_a > corner_b
		var area_a: float = ((rooms[int(a)]["rects"] as Array)[0] as Rect2).get_area()
		var area_b: float = ((rooms[int(b)]["rects"] as Array)[0] as Rect2).get_area()
		return area_a > area_b)

	# First pass: pick top candidates
	var chosen: Array = []
	for c in candidates:
		if chosen.size() >= void_target:
			break
		chosen.append(int(c))
		if not _solid_rooms_connected(chosen):
			chosen.pop_back()

	# Second pass: L-cut — prefer adjacent perimeter pairs for stepped silhouette
	if chosen.size() < void_target:
		for c in candidates:
			if chosen.size() >= void_target:
				break
			if int(c) in chosen:
				continue
			var adjacent := false
			for vid in chosen:
				if _rooms_touch(int(c), int(vid)):
					adjacent = true
					break
			if not adjacent:
				# Also try: find a perimeter neighbor to create L-cut
				var found_lcut := false
				if _leaf_adj.has(int(c)):
					for n in _leaf_adj[int(c)]:
						var ni := int(n)
						if ni in chosen:
							found_lcut = true
							break
						if ni in candidates and ni not in chosen:
							# Try voiding this neighbor to create stepped outline
							var test_void := chosen.duplicate()
							test_void.append(ni)
							if _solid_rooms_connected(test_void):
								chosen.append(ni)
								found_lcut = true
								break
				if not found_lcut:
					continue
			if int(c) in chosen:
				continue
			chosen.append(int(c))
			if not _solid_rooms_connected(chosen):
				chosen.pop_back()

	# Part 5: Ensure at least 1 large void (area >= median)
	var has_large := false
	for vid in chosen:
		if _room_total_area(vid) >= median_area:
			has_large = true
			break
	if not has_large and chosen.size() > 0:
		# Replace smallest void with largest available candidate
		for c in candidates:
			if int(c) in chosen:
				continue
			if _room_total_area(int(c)) >= median_area:
				var test := chosen.duplicate()
				test.append(int(c))
				if _solid_rooms_connected(test):
					chosen.append(int(c))
					has_large = true
					break

	for vid in chosen:
		rooms[vid]["is_void"] = true
		_void_ids.append(vid)
		void_rects.append((rooms[vid]["rects"] as Array)[0] as Rect2)


func _touches_arena_perimeter(room_id: int) -> bool:
	for r: Rect2 in rooms[room_id]["rects"]:
		if absf(r.position.x - _arena.position.x) < 1.0:
			return true
		if absf(r.end.x - _arena.end.x) < 1.0:
			return true
		if absf(r.position.y - _arena.position.y) < 1.0:
			return true
		if absf(r.end.y - _arena.end.y) < 1.0:
			return true
	return false


func _room_touch_perimeter(room_id: int) -> bool:
	return _touches_arena_perimeter(room_id)


func _rect_aspect(r: Rect2) -> float:
	return maxf(r.size.x, r.size.y) / maxf(minf(r.size.x, r.size.y), 1.0)


func _is_gut_rect(r: Rect2) -> bool:
	var mn := minf(r.size.x, r.size.y)
	var mx := maxf(r.size.x, r.size.y)
	return mn < 128.0 and mx > 256.0


func _is_bad_edge_corridor(room_id: int) -> bool:
	if room_id < 0 or room_id >= rooms.size():
		return false
	if rooms[room_id]["is_corridor"] != true:
		return false
	if room_id in _void_ids:
		return false
	if not _room_touch_perimeter(room_id):
		return false

	var arena_major := maxf(_arena.size.x, _arena.size.y)
	var has_edge_run := false
	var rects: Array = rooms[room_id]["rects"] as Array
	for rect in rects:
		var r := rect as Rect2
		var horizontal := r.size.x >= r.size.y
		var along_edge := false
		if horizontal:
			along_edge = absf(r.position.y - _arena.position.y) < 1.0 or absf(r.end.y - _arena.end.y) < 1.0
		else:
			along_edge = absf(r.position.x - _arena.position.x) < 1.0 or absf(r.end.x - _arena.end.x) < 1.0
		if not along_edge:
			continue
		has_edge_run = true
		var width := minf(r.size.x, r.size.y)
		var length := maxf(r.size.x, r.size.y)
		if width < 128.0:
			return true
		if length / maxf(width, 1.0) > 12.0:
			return true
		if length > arena_major * 0.80:
			return true

	if not has_edge_run:
		return false

	var bbox := _room_bounding_box(room_id)
	var bbox_horizontal := bbox.size.x >= bbox.size.y
	var bbox_along_edge := false
	if bbox_horizontal:
		bbox_along_edge = absf(bbox.position.y - _arena.position.y) < 1.0 or absf(bbox.end.y - _arena.end.y) < 1.0
	else:
		bbox_along_edge = absf(bbox.position.x - _arena.position.x) < 1.0 or absf(bbox.end.x - _arena.end.x) < 1.0
	if not bbox_along_edge:
		return false

	var bbox_width := minf(bbox.size.x, bbox.size.y)
	var bbox_length := maxf(bbox.size.x, bbox.size.y)
	if bbox_width < 128.0:
		return true
	if bbox_length / maxf(bbox_width, 1.0) > 12.0:
		return true
	if bbox_length > arena_major * 0.80:
		return true

	return false


func _is_valid_exterior_void(room_id: int) -> bool:
	# Strategy 1: every rect touches arena boundary on at least one side.
	var rects: Array = rooms[room_id]["rects"] as Array
	var all_touch_perimeter := true
	var total_perimeter := 0.0
	var boundary_perimeter := 0.0

	for r: Rect2 in rects:
		var touches := false
		var perim := 2.0 * (r.size.x + r.size.y)
		total_perimeter += perim

		if absf(r.position.x - _arena.position.x) < 1.0:
			touches = true
			boundary_perimeter += r.size.y
		if absf(r.end.x - _arena.end.x) < 1.0:
			touches = true
			boundary_perimeter += r.size.y
		if absf(r.position.y - _arena.position.y) < 1.0:
			touches = true
			boundary_perimeter += r.size.x
		if absf(r.end.y - _arena.end.y) < 1.0:
			touches = true
			boundary_perimeter += r.size.x

		if not touches:
			all_touch_perimeter = false

	if all_touch_perimeter:
		return true

	# Strategy 2: exposure ratio threshold.
	var exposure_ratio := boundary_perimeter / maxf(total_perimeter, 1.0)
	return exposure_ratio >= 0.60


func _count_perimeter_sides(room_id: int) -> int:
	var sides := 0
	for r: Rect2 in rooms[room_id]["rects"]:
		if absf(r.position.x - _arena.position.x) < 1.0:
			sides |= 1
		if absf(r.end.x - _arena.end.x) < 1.0:
			sides |= 2
		if absf(r.position.y - _arena.position.y) < 1.0:
			sides |= 4
		if absf(r.end.y - _arena.end.y) < 1.0:
			sides |= 8
	var count := 0
	for bit in [1, 2, 4, 8]:
		if sides & bit:
			count += 1
	return count


func _solid_rooms_connected(test_void_ids: Array) -> bool:
	var solid: Array = []
	for i in range(rooms.size()):
		if i not in test_void_ids:
			solid.append(i)
	if solid.is_empty():
		return false

	var visited: Array = []
	var queue: Array = [solid[0]]
	while queue.size() > 0:
		var current: int = queue.pop_front()
		if current in visited:
			continue
		visited.append(current)
		if _leaf_adj.has(current):
			for neighbor in _leaf_adj[current]:
				var n := int(neighbor)
				if n not in test_void_ids and n not in visited:
					queue.append(n)

	return visited.size() == solid.size()


## ============================================================================
## PERIMETER NOTCHES (real 3-rect perimeter cuts)
## ============================================================================

func _apply_perimeter_notches() -> void:
	_perimeter_notches.clear()
	var notch_chance := 0.35
	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] == true:
			continue
		if rooms[i].get("is_void", false) == true:
			continue

		var rects: Array = rooms[i]["rects"] as Array
		if rects.size() != 1:
			continue
		var base := rects[0] as Rect2
		var sides := _perimeter_sides_for_rect(base)
		if sides.is_empty():
			continue
		if randf() > notch_chance:
			continue

		sides.shuffle()
		for side_variant in sides:
			var side: String = side_variant as String
			var split := _build_perimeter_notch_split(base, side)
			if split.is_empty():
				continue
			var new_rects: Array = split["rects"] as Array
			rooms[i]["rects"] = new_rects
			rooms[i]["center"] = _area_weighted_center(new_rects)
			rooms[i]["is_perimeter_notched"] = true
			_perimeter_notches.append({
				"room_id": i,
				"notch_rect": split["notch_rect"] as Rect2,
				"side": side,
			})
			break


func _build_perimeter_notch_split(base: Rect2, side: String) -> Dictionary:
	var depth_min := 64.0
	var depth_max := 128.0
	var len_min := 80.0
	var len_max := 160.0
	var min_piece := 96.0

	var rect_a := Rect2()
	var rect_b := Rect2()
	var rect_c := Rect2()
	var notch := Rect2()

	if side == "TOP" or side == "BOTTOM":
		var max_depth := minf(depth_max, base.size.y - min_piece)
		var max_len := minf(len_max, base.size.x - min_piece * 2.0)
		if max_depth < depth_min or max_len < len_min:
			return {}

		var d := randf_range(depth_min, max_depth)
		var l := randf_range(len_min, max_len)
		var nx_min := base.position.x + min_piece
		var nx_max := base.end.x - min_piece - l
		if nx_max < nx_min:
			return {}
		var nx := randf_range(nx_min, nx_max)
		var left_w := nx - base.position.x
		var right_w := base.end.x - (nx + l)

		if side == "TOP":
			rect_a = Rect2(base.position.x, base.position.y, left_w, base.size.y)
			rect_b = Rect2(nx, base.position.y + d, l, base.size.y - d)
			rect_c = Rect2(nx + l, base.position.y, right_w, base.size.y)
			notch = Rect2(nx, base.position.y, l, d)
		else:
			rect_a = Rect2(base.position.x, base.position.y, left_w, base.size.y)
			rect_b = Rect2(nx, base.position.y, l, base.size.y - d)
			rect_c = Rect2(nx + l, base.position.y, right_w, base.size.y)
			notch = Rect2(nx, base.end.y - d, l, d)
	elif side == "LEFT" or side == "RIGHT":
		var max_depth := minf(depth_max, base.size.x - min_piece)
		var max_len := minf(len_max, base.size.y - min_piece * 2.0)
		if max_depth < depth_min or max_len < len_min:
			return {}

		var d := randf_range(depth_min, max_depth)
		var l := randf_range(len_min, max_len)
		var ny_min := base.position.y + min_piece
		var ny_max := base.end.y - min_piece - l
		if ny_max < ny_min:
			return {}
		var ny := randf_range(ny_min, ny_max)
		var top_h := ny - base.position.y
		var bottom_h := base.end.y - (ny + l)

		if side == "LEFT":
			rect_a = Rect2(base.position.x, base.position.y, base.size.x, top_h)
			rect_b = Rect2(base.position.x + d, ny, base.size.x - d, l)
			rect_c = Rect2(base.position.x, ny + l, base.size.x, bottom_h)
			notch = Rect2(base.position.x, ny, d, l)
		else:
			rect_a = Rect2(base.position.x, base.position.y, base.size.x, top_h)
			rect_b = Rect2(base.position.x, ny, base.size.x - d, l)
			rect_c = Rect2(base.position.x, ny + l, base.size.x, bottom_h)
			notch = Rect2(base.end.x - d, ny, d, l)
	else:
		return {}

	var new_rects: Array = [rect_a, rect_b, rect_c]
	for rect in new_rects:
		var r := rect as Rect2
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			return {}
		if minf(r.size.x, r.size.y) < 96.0:
			return {}
		if _is_gut_rect(r):
			return {}

	return {"rects": new_rects, "notch_rect": notch}


## ============================================================================
## L-SHAPED ROOMS (internal notch cuts inside BSP leaves)
## ============================================================================

func _apply_l_rooms() -> void:
	_l_room_ids.clear()
	_l_room_notches.clear()
	var chance: float = GameConfig.l_room_chance if GameConfig else 0.12
	var leg_min: float = GameConfig.l_leg_min if GameConfig else 160.0
	var cut_max_frac: float = GameConfig.l_cut_max_frac if GameConfig else 0.40

	# Candidates: non-corridor, non-void, non-hub, non-ring, large enough
	var candidates: Array = []
	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] == true:
			continue
		if rooms[i].get("is_void", false) == true:
			continue
		if i in _hub_ids:
			continue
		if i in _ring_ids:
			continue
		var r: Rect2 = (rooms[i]["rects"] as Array)[0] as Rect2
		if r.size.x < leg_min * 2.0 or r.size.y < leg_min * 2.0:
			continue
		candidates.append(i)

	# Select up to 2 L-rooms
	var max_l := mini(2, candidates.size())
	var selected: Array = []
	for c in candidates:
		if selected.size() >= max_l:
			break
		if randf() < chance * 2.5:
			selected.append(int(c))

	# Guarantee at least 1 if candidates exist
	if selected.is_empty() and not candidates.is_empty() and randf() < chance * 4.0:
		selected.append(int(candidates[randi() % candidates.size()]))

	for room_id in selected:
		var r: Rect2 = (rooms[room_id]["rects"] as Array)[0] as Rect2
		var corners := ["NE", "NW", "SE", "SW"]
		var corner: String = corners[randi() % 4]

		var cut_w := clampf(randf_range(leg_min, r.size.x * cut_max_frac), leg_min, r.size.x - leg_min)
		var cut_h := clampf(randf_range(leg_min, r.size.y * cut_max_frac), leg_min, r.size.y - leg_min)

		if r.size.x - cut_w < 64.0 or r.size.y - cut_h < 64.0:
			continue
		if cut_w < 64.0 or cut_h < 64.0:
			continue

		var rect1: Rect2
		var rect2: Rect2
		var notch: Rect2

		match corner:
			"NE":
				rect1 = Rect2(r.position.x, r.position.y, r.size.x - cut_w, r.size.y)
				rect2 = Rect2(r.position.x + r.size.x - cut_w, r.position.y + cut_h, cut_w, r.size.y - cut_h)
				notch = Rect2(r.position.x + r.size.x - cut_w, r.position.y, cut_w, cut_h)
			"NW":
				rect1 = Rect2(r.position.x + cut_w, r.position.y, r.size.x - cut_w, r.size.y)
				rect2 = Rect2(r.position.x, r.position.y + cut_h, cut_w, r.size.y - cut_h)
				notch = Rect2(r.position.x, r.position.y, cut_w, cut_h)
			"SE":
				rect1 = Rect2(r.position.x, r.position.y, r.size.x - cut_w, r.size.y)
				rect2 = Rect2(r.position.x + r.size.x - cut_w, r.position.y, cut_w, r.size.y - cut_h)
				notch = Rect2(r.position.x + r.size.x - cut_w, r.position.y + r.size.y - cut_h, cut_w, cut_h)
			"SW":
				rect1 = Rect2(r.position.x + cut_w, r.position.y, r.size.x - cut_w, r.size.y)
				rect2 = Rect2(r.position.x, r.position.y, cut_w, r.size.y - cut_h)
				notch = Rect2(r.position.x, r.position.y + r.size.y - cut_h, cut_w, cut_h)

		rooms[room_id]["rects"] = [rect1, rect2]
		rooms[room_id]["is_l_room"] = true
		var a1 := rect1.get_area()
		var a2 := rect2.get_area()
		rooms[room_id]["center"] = (rect1.get_center() * a1 + rect2.get_center() * a2) / maxf(a1 + a2, 1.0)

		_l_room_ids.append(room_id)
		_l_room_notches.append({"room_id": room_id, "notch_rect": notch, "corner": corner})


## ============================================================================
## T/U COMPLEX SHAPES
## ============================================================================

func _apply_t_u_shapes() -> void:
	_t_u_room_ids.clear()
	_complex_shape_wall_segs.clear()

	var candidates: Array = []
	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] == true:
			continue
		if rooms[i].get("is_void", false) == true:
			continue
		var rects: Array = rooms[i]["rects"] as Array
		if rects.size() != 1:
			continue
		var r := rects[0] as Rect2
		if r.size.x < 320.0 or r.size.y < 320.0:
			continue
		candidates.append(i)

	if candidates.is_empty():
		return

	candidates.shuffle()
	var target_count := randi_range(0, mini(2, candidates.size()))
	for idx in range(target_count):
		if randf() > COMPLEX_SHAPES_CHANCE:
			continue

		var room_id := int(candidates[idx])
		var base := ((rooms[room_id]["rects"] as Array)[0] as Rect2)
		var shape_data: Dictionary = {}
		if randf() < 0.5:
			shape_data = _build_t_shape_from_rect(base)
			if shape_data.is_empty():
				shape_data = _build_u_shape_from_rect(base)
		else:
			shape_data = _build_u_shape_from_rect(base)
			if shape_data.is_empty():
				shape_data = _build_t_shape_from_rect(base)
		if shape_data.is_empty():
			continue

		var new_rects: Array = shape_data["rects"] as Array
		if not _rects_pass_complex_shape_rules(new_rects):
			continue
		var total_area := 0.0
		for rr in new_rects:
			total_area += (rr as Rect2).get_area()
		if total_area < base.get_area() * 0.65:
			continue

		rooms[room_id]["rects"] = new_rects
		rooms[room_id]["center"] = _area_weighted_center(new_rects)
		rooms[room_id]["complex_shape"] = shape_data["shape"] as String
		_t_u_room_ids.append(room_id)
		for seg in (shape_data["wall_segs"] as Array):
			_complex_shape_wall_segs.append(seg)


func _rects_pass_complex_shape_rules(rects: Array) -> bool:
	for rect in rects:
		var r := rect as Rect2
		if r.size.x <= 0.0 or r.size.y <= 0.0:
			return false
		if minf(r.size.x, r.size.y) < 96.0:
			return false
		if _is_gut_rect(r):
			return false
	return true


func _build_t_shape_from_rect(base: Rect2) -> Dictionary:
	var stem_min := 128.0
	var stem_max := minf(base.size.x - 192.0, base.size.x * 0.45)
	if stem_max < stem_min:
		return {}
	var stem_w := randf_range(stem_min, stem_max)
	var stem_x_min := 96.0
	var stem_x_max := base.size.x - 96.0 - stem_w
	if stem_x_max < stem_x_min:
		return {}
	var stem_x := randf_range(stem_x_min, stem_x_max)

	var bar_h_min := 128.0
	var bar_h_max := minf(192.0, base.size.y - 96.0)
	if bar_h_max < bar_h_min:
		return {}
	var bar_h := randf_range(bar_h_min, bar_h_max)

	var rect_stem := Rect2(base.position.x + stem_x, base.position.y, stem_w, base.size.y)
	var rect_left := Rect2(base.position.x, base.position.y, stem_x, bar_h)
	var rect_right := Rect2(base.position.x + stem_x + stem_w, base.position.y, base.size.x - stem_x - stem_w, bar_h)
	var rects: Array = [rect_stem, rect_left, rect_right]

	var y_cut := base.position.y + bar_h
	var x_left := base.position.x + stem_x
	var x_right := base.position.x + stem_x + stem_w
	var wall_segs: Array = [
		{"type": "V", "pos": x_left, "t0": y_cut, "t1": base.end.y},
		{"type": "H", "pos": y_cut, "t0": base.position.x, "t1": x_left},
		{"type": "V", "pos": x_right, "t0": y_cut, "t1": base.end.y},
		{"type": "H", "pos": y_cut, "t0": x_right, "t1": base.end.x},
	]
	return {"shape": "T", "rects": rects, "wall_segs": wall_segs}


func _build_u_shape_from_rect(base: Rect2) -> Dictionary:
	var leg_min := 128.0
	var leg_max := minf(180.0, (base.size.x - 96.0) * 0.5)
	if leg_max < leg_min:
		return {}
	var leg_w := randf_range(leg_min, leg_max)

	var bridge_h_min := 128.0
	var bridge_h_max := minf(192.0, base.size.y - 96.0)
	if bridge_h_max < bridge_h_min:
		return {}
	var bridge_h := randf_range(bridge_h_min, bridge_h_max)
	var bridge_w := base.size.x - leg_w * 2.0
	if bridge_w < 96.0:
		return {}

	var rect_left := Rect2(base.position.x, base.position.y, leg_w, base.size.y)
	var rect_right := Rect2(base.end.x - leg_w, base.position.y, leg_w, base.size.y)
	var rect_bridge := Rect2(base.position.x + leg_w, base.end.y - bridge_h, bridge_w, bridge_h)
	var rects: Array = [rect_left, rect_right, rect_bridge]

	var x_left := base.position.x + leg_w
	var x_right := base.end.x - leg_w
	var y_cut := base.end.y - bridge_h
	var wall_segs: Array = [
		{"type": "V", "pos": x_left, "t0": base.position.y, "t1": y_cut},
		{"type": "V", "pos": x_right, "t0": base.position.y, "t1": y_cut},
		{"type": "H", "pos": y_cut, "t0": x_left, "t1": x_right},
	]
	return {"shape": "U", "rects": rects, "wall_segs": wall_segs}


## ============================================================================
## SPLIT SEGMENTS (source of walls + door placement)
## ============================================================================

func _collect_split_segments(node: Dictionary) -> void:
	if node["left"] == null:
		return

	_collect_split_segments(node["left"])
	_collect_split_segments(node["right"])

	var left_node: Dictionary = node["left"]
	var right_node: Dictionary = node["right"]
	var left_rect: Rect2 = left_node["rect"]
	var right_rect: Rect2 = right_node["rect"]
	var parent_rect: Rect2 = node["rect"]

	var left_ids := _get_leaf_ids(left_node)
	var right_ids := _get_leaf_ids(right_node)

	if absf(left_rect.end.y - right_rect.position.y) < 1.0:
		# Horizontal split at y = left_rect.end.y
		_split_segs.append({
			"type": "H",
			"pos": left_rect.end.y,
			"t0": parent_rect.position.x,
			"t1": parent_rect.end.x,
			"left_ids": left_ids,
			"right_ids": right_ids,
		})
	elif absf(left_rect.end.x - right_rect.position.x) < 1.0:
		# Vertical split at x = left_rect.end.x
		_split_segs.append({
			"type": "V",
			"pos": left_rect.end.x,
			"t0": parent_rect.position.y,
			"t1": parent_rect.end.y,
			"left_ids": left_ids,
			"right_ids": right_ids,
		})


## ============================================================================
## DOORS (BSP TREE — Part 7: up to 2 doors per split)
## ============================================================================

func _create_doors_bsp(node: Dictionary) -> void:
	if node["left"] == null:
		return

	_create_doors_bsp(node["left"])
	_create_doors_bsp(node["right"])

	var left_ids := _get_leaf_ids(node["left"])
	var right_ids := _get_leaf_ids(node["right"])

	var door_min: float = GameConfig.door_opening_min if GameConfig else 96.0
	var door_max: float = GameConfig.door_opening_max if GameConfig else 128.0
	var corner_min: float = GameConfig.door_from_corner_min if GameConfig else 48.0
	var wall_t: float = GameConfig.wall_thickness if GameConfig else 16.0

	# Compute split info directly from node children
	var split_type: String = ""
	var split_pos: float = 0.0
	var left_rect: Rect2 = node["left"]["rect"]
	var right_rect: Rect2 = node["right"]["rect"]

	if absf(left_rect.end.y - right_rect.position.y) < 1.0:
		split_type = "H"
		split_pos = left_rect.end.y
	elif absf(left_rect.end.x - right_rect.position.x) < 1.0:
		split_type = "V"
		split_pos = left_rect.end.x

	if split_type.is_empty():
		return

	# Sort room pairs by distance (closest first)
	var pairs: Array = []
	for li in left_ids:
		for ri in right_ids:
			var ci: Vector2 = rooms[li]["center"]
			var cj: Vector2 = rooms[ri]["center"]
			pairs.append({"a": int(li), "b": int(ri), "dist": ci.distance_to(cj)})
	pairs.sort_custom(func(x, y):
		var px := _door_pair_priority(int(x["a"]), int(x["b"]))
		var py := _door_pair_priority(int(y["a"]), int(y["b"]))
		if absf(px - py) > 0.1:
			return px > py
		return float(x["dist"]) < float(y["dist"]))

	# Part 7: up to 2 doors per split
	var doors_on_split := 0
	var max_doors_per_split := 2

	# Count SOLID leaves on each side for 2nd door eligibility
	var left_solid := 0
	for lid in left_ids:
		if int(lid) not in _void_ids:
			left_solid += 1
	var right_solid := 0
	for rid in right_ids:
		if int(rid) not in _void_ids:
			right_solid += 1

	for pair in pairs:
		if doors_on_split >= max_doors_per_split:
			break
		var a: int = int(pair["a"])
		var b: int = int(pair["b"])
		if a in _void_ids or b in _void_ids:
			continue

		# 2nd door: only if both sides have >1 SOLID leaf
		if doors_on_split >= 1:
			if left_solid <= 1 or right_solid <= 1:
				break
			if b in (_door_adj[a] as Array):
				continue

		var door := _make_door_on_split_line(split_type, split_pos, a, b, door_min, door_max, corner_min, wall_t)
		if _try_add_door(a, b, door):
			doors_on_split += 1


func _make_door_on_split_line(split_type: String, split_pos: float, a: int, b: int, dmin: float, dmax: float, cmin: float, wall_t: float) -> Rect2:
	var ra := _room_bounding_box(a)
	var rb := _room_bounding_box(b)

	if split_type == "V":
		# Vertical wall at x=split_pos. Shared Y range.
		var y0 := maxf(ra.position.y, rb.position.y)
		var y1 := minf(ra.end.y, rb.end.y)
		var dy0 := y0 + cmin
		var dy1 := y1 - cmin
		if dy1 - dy0 < dmin:
			return Rect2()
		var door_len := clampf(randf_range(dmin, dmax), dmin, dy1 - dy0)
		var center := (dy0 + dy1) * 0.5 + randf_range(-0.2, 0.2) * (dy1 - dy0)
		var dy := clampf(center - door_len * 0.5, dy0, dy1 - door_len)
		return Rect2(split_pos - wall_t * 0.5, dy, wall_t, door_len)
	else:
		# Horizontal wall at y=split_pos. Shared X range.
		var x0 := maxf(ra.position.x, rb.position.x)
		var x1 := minf(ra.end.x, rb.end.x)
		var dx0 := x0 + cmin
		var dx1 := x1 - cmin
		if dx1 - dx0 < dmin:
			return Rect2()
		var door_len := clampf(randf_range(dmin, dmax), dmin, dx1 - dx0)
		var center := (dx0 + dx1) * 0.5 + randf_range(-0.2, 0.2) * (dx1 - dx0)
		var dx := clampf(center - door_len * 0.5, dx0, dx1 - door_len)
		return Rect2(dx, split_pos - wall_t * 0.5, door_len, wall_t)


## Check if a candidate door overlaps an existing door on same wall line within 48px
func _door_too_close(candidate: Rect2) -> bool:
	var min_spacing := 48.0
	for existing_dm in _door_map:
		var er: Rect2 = existing_dm["rect"]
		if absf(candidate.position.x - er.position.x) < 8.0:
			if candidate.position.y < er.end.y + min_spacing and candidate.end.y > er.position.y - min_spacing:
				return true
		if absf(candidate.position.y - er.position.y) < 8.0:
			if candidate.position.x < er.end.x + min_spacing and candidate.end.x > er.position.x - min_spacing:
				return true
	return false


func _can_add_door_between(a: int, b: int) -> bool:
	if a == b:
		return false
	if a < 0 or b < 0 or a >= rooms.size() or b >= rooms.size():
		return false
	if a in _void_ids or b in _void_ids:
		return false
	if not _door_adj.has(a) or not _door_adj.has(b):
		return false
	if b in (_door_adj[a] as Array):
		return false
	if (_door_adj[a] as Array).size() >= _max_doors_for_room(a):
		return false
	if (_door_adj[b] as Array).size() >= _max_doors_for_room(b):
		return false
	return true


func _try_add_door(a: int, b: int, rect: Rect2) -> bool:
	if rect.size == Vector2.ZERO:
		return false
	if _door_too_close(rect):
		return false
	if not _can_add_door_between(a, b):
		return false
	doors.append(rect)
	_register_door_connection(a, b, rect)
	return true


func _add_extra_loops(max_extra: int) -> void:
	if max_extra <= 0:
		return

	var door_min: float = GameConfig.door_opening_min if GameConfig else 96.0
	var door_max: float = GameConfig.door_opening_max if GameConfig else 128.0
	var corner_min: float = GameConfig.door_from_corner_min if GameConfig else 48.0
	var wall_t: float = GameConfig.wall_thickness if GameConfig else 16.0
	var candidates: Array = []
	for i in range(rooms.size()):
		if i in _void_ids:
			continue
		for j in range(i + 1, rooms.size()):
			if j in _void_ids:
				continue
			if j in (_door_adj[i] as Array):
				continue
			var mdpr_i := _max_doors_for_room(i)
			var mdpr_j := _max_doors_for_room(j)
			if (_door_adj[i] as Array).size() >= mdpr_i:
				continue
			if (_door_adj[j] as Array).size() >= mdpr_j:
				continue
			# Only between rooms sharing a split segment
			var seg := _find_shared_split_seg(i, j)
			if seg.is_empty():
				continue
			var door := _make_door_on_split_line(
				seg["type"] as String, float(seg["pos"]),
				i, j, door_min, door_max, corner_min, wall_t)
			if door.size != Vector2.ZERO and not _door_too_close(door):
				var r0_area := _room_total_area(i)
				var r1_area := _room_total_area(j)
				var topo_bonus := _door_pair_priority(i, j)
				candidates.append({"a": i, "b": j, "door": door, "priority": r0_area + r1_area + topo_bonus})

	candidates.sort_custom(func(a, b): return float(a["priority"]) > float(b["priority"]))

	var added := 0
	for c in candidates:
		if added >= max_extra:
			break
		if _try_add_door(int(c["a"]), int(c["b"]), c["door"] as Rect2):
			added += 1
	extra_loops = added


func _find_shared_split_seg(room_a: int, room_b: int) -> Dictionary:
	for seg in _split_segs:
		var left_ids: Array = seg["left_ids"]
		var right_ids: Array = seg["right_ids"]
		if (room_a in left_ids and room_b in right_ids) or (room_b in left_ids and room_a in right_ids):
			return seg
	return {}


## ============================================================================
## COMPOSITION ENFORCEMENT (Part 4)
## ============================================================================

func _enforce_composition() -> bool:
	match _layout_mode:
		LayoutMode.CENTRAL_HALL:
			return _enforce_composition_hall()
		LayoutMode.CENTRAL_SPINE:
			return _enforce_composition_spine()
		LayoutMode.CENTRAL_RING:
			return _enforce_composition_ring()
		LayoutMode.CENTRAL_LIKE_HUB:
			return _enforce_composition_dual_hub()
	return true


func _enforce_composition_hall() -> bool:
	if _hub_ids.is_empty():
		return false
	var hub: int = _hub_ids[0]
	if hub in _void_ids:
		return false

	var door_min: float = GameConfig.door_opening_min if GameConfig else 96.0
	var door_max: float = GameConfig.door_opening_max if GameConfig else 128.0
	var corner_min: float = GameConfig.door_from_corner_min if GameConfig else 48.0
	var wall_t: float = GameConfig.wall_thickness if GameConfig else 16.0

	# Target degree 2..4, capped by door limits
	var target_deg := mini(randi_range(2, 4), _max_doors_for_room(hub))
	var current_deg := (_door_adj[hub] as Array).size()

	# Get leaf-adjacent neighbors not yet connected
	var neighbors: Array = []
	if _leaf_adj.has(hub):
		for n in _leaf_adj[hub]:
			var ni := int(n)
			if ni in _void_ids:
				continue
			if ni in (_door_adj[hub] as Array):
				continue
			neighbors.append(ni)

	neighbors.sort_custom(func(a, b):
		var pa := _door_pair_priority(hub, int(a))
		var pb := _door_pair_priority(hub, int(b))
		if absf(pa - pb) > 0.1:
			return pa > pb
		return _room_total_area(int(a)) > _room_total_area(int(b)))

	while current_deg < target_deg and not neighbors.is_empty():
		var ni: int = neighbors.pop_front()
		var seg := _find_shared_split_seg(hub, ni)
		if seg.is_empty():
			continue
		var door := _make_door_on_split_line(seg["type"] as String, float(seg["pos"]), hub, ni, door_min, door_max, corner_min, wall_t)
		if _try_add_door(hub, ni, door):
			_protected_doors.append({"a": mini(hub, ni), "b": maxi(hub, ni)})
			current_deg += 1

	# Mark existing hub doors as protected
	for n in _door_adj[hub]:
		var ni := int(n)
		var pa := mini(hub, ni)
		var pb := maxi(hub, ni)
		if not _is_protected_door(pa, pb):
			_protected_doors.append({"a": pa, "b": pb})

	# HALL always succeeds — hub is the largest central room, connectivity enforced elsewhere
	return true


func _enforce_composition_spine() -> bool:
	if _hub_ids.is_empty():
		return false
	var spine: int = _hub_ids[0]
	if spine in _void_ids:
		return false

	var door_min: float = GameConfig.door_opening_min if GameConfig else 96.0
	var door_max: float = GameConfig.door_opening_max if GameConfig else 128.0
	var corner_min: float = GameConfig.door_from_corner_min if GameConfig else 48.0
	var wall_t: float = GameConfig.wall_thickness if GameConfig else 16.0

	# Mark spine doors as protected
	for n in _door_adj[spine]:
		var ni := int(n)
		_protected_doors.append({"a": mini(spine, ni), "b": maxi(spine, ni)})

	# Every non-corridor room must be within 2 hops of spine
	for i in range(rooms.size()):
		if i in _void_ids:
			continue
		if i == spine:
			continue
		if rooms[i]["is_corridor"] == true:
			continue

		var dist := _bfs_distance(i, spine)
		if dist <= 2:
			continue

		# Try to add a door to get closer
		var connected := false
		if _leaf_adj.has(i):
			# Sort neighbors by distance to spine
			var adj_list: Array = []
			for n in _leaf_adj[i]:
				var ni := int(n)
				if ni in _void_ids:
					continue
				if ni in (_door_adj[i] as Array):
					continue
				adj_list.append({"id": ni, "spine_dist": _bfs_distance(ni, spine)})
			adj_list.sort_custom(func(a, b): return int(a["spine_dist"]) < int(b["spine_dist"]))

			for entry in adj_list:
				var ni: int = int(entry["id"])
				if int(entry["spine_dist"]) >= dist:
					continue
				var seg := _find_shared_split_seg(i, ni)
				if seg.is_empty():
					continue
				var door := _make_door_on_split_line(seg["type"] as String, float(seg["pos"]), i, ni, door_min, door_max, corner_min, wall_t)
				if _try_add_door(i, ni, door):
					_protected_doors.append({"a": mini(i, ni), "b": maxi(i, ni)})
					connected = true
					break
				# Try relaxed
				var door2 := _make_door_on_split_line(seg["type"] as String, float(seg["pos"]), i, ni, door_min * 0.6, door_max, corner_min * 0.5, wall_t)
				if _try_add_door(i, ni, door2):
					_protected_doors.append({"a": mini(i, ni), "b": maxi(i, ni)})
					connected = true
					break

		if not connected:
			return false

	return true


func _enforce_composition_ring() -> bool:
	if _ring_ids.size() < 3:
		return false

	var door_min: float = GameConfig.door_opening_min if GameConfig else 96.0
	var door_max: float = GameConfig.door_opening_max if GameConfig else 128.0
	var corner_min: float = GameConfig.door_from_corner_min if GameConfig else 48.0
	var wall_t: float = GameConfig.wall_thickness if GameConfig else 16.0

	# Ensure doors on each ring edge (i → i+1, wrapping)
	for idx in range(_ring_ids.size()):
		var a: int = _ring_ids[idx]
		var b: int = _ring_ids[(idx + 1) % _ring_ids.size()]
		if a in _void_ids or b in _void_ids:
			return false

		var pa := mini(a, b)
		var pb := maxi(a, b)

		if b in (_door_adj[a] as Array):
			if not _is_protected_door(pa, pb):
				_protected_doors.append({"a": pa, "b": pb})
			continue

		var seg := _find_shared_split_seg(a, b)
		if seg.is_empty():
			return false
		var door := _make_door_on_split_line(seg["type"] as String, float(seg["pos"]), a, b, door_min, door_max, corner_min, wall_t)
		if _try_add_door(a, b, door):
			_protected_doors.append({"a": pa, "b": pb})
		else:
			# Try relaxed constraints
			var door2 := _make_door_on_split_line(seg["type"] as String, float(seg["pos"]), a, b, door_min * 0.6, door_max, corner_min * 0.5, wall_t)
			if _try_add_door(a, b, door2):
				_protected_doors.append({"a": pa, "b": pb})
			else:
				return false

	return true


func _enforce_composition_dual_hub() -> bool:
	if _hub_ids.size() < 2:
		return false
	var h1: int = _hub_ids[0]
	var h2: int = _hub_ids[1]
	if h1 in _void_ids or h2 in _void_ids:
		return false

	var door_min: float = GameConfig.door_opening_min if GameConfig else 96.0
	var door_max: float = GameConfig.door_opening_max if GameConfig else 128.0
	var corner_min: float = GameConfig.door_from_corner_min if GameConfig else 48.0
	var wall_t: float = GameConfig.wall_thickness if GameConfig else 16.0

	var pa := mini(h1, h2)
	var pb := maxi(h1, h2)

	# Ensure door between hubs
	if h2 not in (_door_adj[h1] as Array):
		var seg := _find_shared_split_seg(h1, h2)
		if seg.is_empty():
			return false
		var door := _make_door_on_split_line(seg["type"] as String, float(seg["pos"]), h1, h2, door_min, door_max, corner_min, wall_t)
		if _try_add_door(h1, h2, door):
			_protected_doors.append({"a": pa, "b": pb})
		else:
			return false
	else:
		if not _is_protected_door(pa, pb):
			_protected_doors.append({"a": pa, "b": pb})

	# Each hub needs 3-4 total connections (capped by limits)
	for hub in [h1, h2]:
		var target_deg := mini(randi_range(3, 4), _max_doors_for_room(hub))
		var current_deg := (_door_adj[hub] as Array).size()
		var neighbors: Array = []
		if _leaf_adj.has(hub):
			for n in _leaf_adj[hub]:
				var ni := int(n)
				if ni in _void_ids or ni in (_door_adj[hub] as Array):
					continue
				neighbors.append(ni)

		neighbors.sort_custom(func(a, b):
			return _room_total_area(int(a)) > _room_total_area(int(b)))

		while current_deg < target_deg and not neighbors.is_empty():
			var ni: int = neighbors.pop_front()
			var seg := _find_shared_split_seg(hub, ni)
			if seg.is_empty():
				continue
			var door := _make_door_on_split_line(seg["type"] as String, float(seg["pos"]), hub, ni, door_min, door_max, corner_min, wall_t)
			if _try_add_door(hub, ni, door):
				_protected_doors.append({"a": mini(hub, ni), "b": maxi(hub, ni)})
				current_deg += 1

		# Mark existing hub doors as protected
		for n in _door_adj[hub]:
			var ni := int(n)
			var ppa := mini(hub, ni)
			var ppb := maxi(hub, ni)
			if not _is_protected_door(ppa, ppb):
				_protected_doors.append({"a": ppa, "b": ppb})

		if current_deg < 3:
			return false

	return true


## ============================================================================
## PROTECTED DOORS (Part 4)
## ============================================================================

func _is_protected_door(a: int, b: int) -> bool:
	var pa := mini(a, b)
	var pb := maxi(a, b)
	for pd in _protected_doors:
		if int(pd["a"]) == pa and int(pd["b"]) == pb:
			return true
	return false


## ============================================================================
## ENFORCE MAX DOORS (Part 4: skip protected doors)
## ============================================================================

func _enforce_max_doors() -> void:
	for _pass in range(20):
		var any_excess := false
		for i in range(rooms.size()):
			var mdpr := _max_doors_for_room(i)
			while (_door_adj[i] as Array).size() > mdpr:
				any_excess = true
				var adj: Array = _door_adj[i]
				var sorted_n := adj.duplicate()
				sorted_n.sort_custom(func(a, b): return (_door_adj[int(a)] as Array).size() > (_door_adj[int(b)] as Array).size())

				var removed := false
				for j in sorted_n:
					if _can_remove_door(i, int(j)):
						_remove_door(i, int(j))
						removed = true
						break
				if not removed:
					break
		if not any_excess:
			break


func _can_remove_door(a: int, b: int) -> bool:
	# Part 4: protected doors cannot be removed
	if _is_protected_door(a, b):
		return false

	var visited: Array = []
	var queue: Array = [a]
	while queue.size() > 0:
		var current: int = queue.pop_front()
		if current in visited:
			continue
		visited.append(current)
		for neighbor in _door_adj[current]:
			var n := int(neighbor)
			if current == a and n == b:
				continue
			if current == b and n == a:
				continue
			if n not in visited:
				queue.append(n)
	return b in visited


func _remove_door(a: int, b: int) -> void:
	(_door_adj[a] as Array).erase(b)
	(_door_adj[b] as Array).erase(a)
	for i in range(_door_map.size() - 1, -1, -1):
		var dm: Dictionary = _door_map[i]
		if (int(dm["a"]) == a and int(dm["b"]) == b) or (int(dm["a"]) == b and int(dm["b"]) == a):
			var rect: Rect2 = dm["rect"]
			doors.erase(rect)
			_door_map.remove_at(i)
			break


func _register_door_connection(a: int, b: int, rect: Rect2) -> void:
	if b not in (_door_adj[a] as Array):
		(_door_adj[a] as Array).append(b)
	if a not in (_door_adj[b] as Array):
		(_door_adj[b] as Array).append(a)
	_door_map.append({"a": a, "b": b, "rect": rect})


## ============================================================================
## CONNECTIVITY (Part 7: BFS recompute after each door)
## ============================================================================

func _ensure_connectivity() -> bool:
	if rooms.size() <= 1:
		return true

	# Find first non-void room to start BFS
	var start_id := -1
	for i in range(rooms.size()):
		if i not in _void_ids:
			start_id = i
			break
	if start_id < 0:
		return false

	var door_min: float = GameConfig.door_opening_min if GameConfig else 96.0
	var door_max: float = GameConfig.door_opening_max if GameConfig else 128.0
	var corner_min: float = GameConfig.door_from_corner_min if GameConfig else 48.0
	var wall_t: float = GameConfig.wall_thickness if GameConfig else 16.0

	# Part 7: recompute BFS after each door addition
	for _pass in range(rooms.size()):
		var visited := _bfs_connected(start_id)

		var all_connected := true
		for i in range(rooms.size()):
			if i in _void_ids:
				continue
			if i in visited:
				continue
			all_connected = false
			isolated_fixed += 1

			# Try every visited room that shares a split segment, sorted by distance
			var cand_j: Array = []
			for j in visited:
				var seg := _find_shared_split_seg(i, int(j))
				if not seg.is_empty():
					var ci: Vector2 = rooms[i]["center"]
					var cj: Vector2 = rooms[int(j)]["center"]
					cand_j.append({"j": int(j), "dist": ci.distance_to(cj), "seg": seg})
			cand_j.sort_custom(func(a, b): return float(a["dist"]) < float(b["dist"]))

			var repaired := false
			for cj in cand_j:
				var j_id: int = int(cj["j"])
				var seg: Dictionary = cj["seg"]
				# Try normal constraints
				var door := _make_door_on_split_line(
					seg["type"] as String, float(seg["pos"]),
					i, j_id, door_min, door_max, corner_min, wall_t)
				if _try_add_door(i, j_id, door):
					repaired = true
					break
				# Try relaxed constraints
				var door2 := _make_door_on_split_line(
					seg["type"] as String, float(seg["pos"]),
					i, j_id, door_min * 0.5, door_max, corner_min * 0.5, wall_t)
				if _try_add_door(i, j_id, door2):
					repaired = true
					break

			if not repaired:
				return false

			break  # Restart BFS from top after any connection attempt

		if all_connected:
			return true

	return false


## ============================================================================
## ARENA TIGHTNESS CHECK (Part 1)
## ============================================================================

func _arena_is_too_tight() -> bool:
	var rmw: float = GameConfig.room_min_w if GameConfig else 220.0
	var rmh: float = GameConfig.room_min_h if GameConfig else 200.0
	var cwmax: float = GameConfig.corridor_w_max if GameConfig else 110.0
	var clmin: float = GameConfig.corridor_len_min if GameConfig else 320.0

	var aw := _arena.size.x
	var ah := _arena.size.y

	# Need room for at least one corridor triplet in at least one direction
	if aw < (rmw * 2.0 + cwmax) and ah < (rmh * 2.0 + cwmax):
		return true

	# Min dimension must allow corridor length
	if minf(aw, ah) < clmin:
		return true

	return false


## ============================================================================
## VALIDATION (Part 8: Hotline composition checks)
## ============================================================================

func _validate() -> bool:
	if not _composition_ok:
		return false

	if _arena_is_too_tight():
		return false

	var solid_ids: Array = []
	for i in range(rooms.size()):
		if i not in _void_ids:
			solid_ids.append(i)

	if solid_ids.size() < (GameConfig.rooms_count_min if GameConfig else 5):
		return false

	# Global geometry constraints for non-void rooms:
	# - gut rects are forbidden
	# - closet rooms allowed only as single-rect non-corridor, max 2 per layout
	var closet_count := 0
	for i in solid_ids:
		var room: Dictionary = rooms[i]
		var is_corridor: bool = room["is_corridor"] == true
		var rects: Array = room["rects"] as Array

		for rect in rects:
			var r := rect as Rect2
			if _is_gut_rect(r):
				return false

		if is_corridor:
			continue

		if rects.size() == 1:
			var base := rects[0] as Rect2
			var min_side := minf(base.size.x, base.size.y)
			if min_side >= 96.0 and min_side <= 127.0 and _rect_aspect(base) <= 2.5:
				closet_count += 1

	if closet_count > 2:
		return false

	var corr_max_aspect: float = GameConfig.corridor_max_aspect if GameConfig else 30.0
	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] != true:
			continue
		if i in _void_ids:
			continue
		var corr_rects: Array = rooms[i]["rects"] as Array
		for rect in corr_rects:
			var r := rect as Rect2
			if minf(r.size.x, r.size.y) < 128.0:
				return false
			if _rect_aspect(r) > corr_max_aspect:
				return false
		if _is_bad_edge_corridor(i):
			return false

	var total_corr_area := 0.0
	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] != true:
			continue
		if i in _void_ids:
			continue
		total_corr_area += _room_total_area(i)
	var arena_area := _arena.get_area()
	var cap: float = GameConfig.corridor_area_cap if GameConfig else 0.25
	if total_corr_area / maxf(arena_area, 1.0) > cap:
		return false

	# Corridor degree check (void-adjacent corridors allowed degree 1)
	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] != true:
			continue
		if i in _void_ids:
			continue
		var deg: int = (_door_adj[i] as Array).size() if _door_adj.has(i) else 0
		var has_void_neighbor := false
		if _leaf_adj.has(i):
			for n in _leaf_adj[i]:
				if int(n) in _void_ids:
					has_void_neighbor = true
					break
		var min_deg := 1 if (i in _low_priority_ids or has_void_neighbor) else 2
		if deg < min_deg:
			return false

	var high_degree_count := 0
	var total_deg := 0.0
	for i in solid_ids:
		var deg: int = (_door_adj[i] as Array).size() if _door_adj.has(i) else 0
		if deg == 0:
			return false
		if deg > 3:
			high_degree_count += 1
		total_deg += float(deg)

	var start_id: int = int(solid_ids[0]) if not solid_ids.is_empty() else 0
	var visited: Array = []
	var queue: Array = [start_id]
	while queue.size() > 0:
		var current: int = queue.pop_front()
		if current in visited:
			continue
		visited.append(current)
		if _door_adj.has(current):
			for n in _door_adj[current]:
				if int(n) not in visited:
					queue.append(int(n))

	if visited.size() != solid_ids.size():
		return false

	if high_degree_count > 3:
		return false

	var ad := total_deg / maxf(float(solid_ids.size()), 1.0)
	if ad > 2.8:
		return false

	if _has_long_perimeter_corridor_chain(2):
		return false

	var active_perim_corr := 0
	for lid in _low_priority_ids:
		if int(lid) not in _void_ids:
			active_perim_corr += 1
	if active_perim_corr > 1:
		return false

	for hid in _hub_ids:
		if hid in _void_ids:
			continue
		var hdeg: int = (_door_adj[hid] as Array).size() if _door_adj.has(hid) else 0
		if hdeg < 2:
			return false
		if hdeg > 3:
			return false

	# Dead-end rules for solid non-corridor rooms:
	# - degree==1 allowed only on perimeter rooms
	# - interior rooms must have degree >= 2
	# - dead_end_count <= 3 and ratio <= 0.20 of perimeter rooms
	var perimeter_room_count := 0
	var dead_end_count := 0
	for i in solid_ids:
		if rooms[i]["is_corridor"] == true:
			continue
		var deg: int = (_door_adj[i] as Array).size() if _door_adj.has(i) else 0
		var is_perimeter := _room_touch_perimeter(i)
		if is_perimeter:
			perimeter_room_count += 1
		if deg == 1:
			if not is_perimeter:
				return false
			dead_end_count += 1
		elif not is_perimeter and deg < 2:
			return false

	if dead_end_count > 3:
		return false
	if perimeter_room_count > 0:
		var dead_end_ratio := float(dead_end_count) / float(perimeter_room_count)
		if dead_end_ratio > 0.20:
			return false
	elif dead_end_count > 0:
		return false

	if not _validate_structure():
		return false

	var void_min_frac: float = GameConfig.void_area_min_frac if GameConfig else 0.08
	if _void_ids.size() > 0:
		var total_void_area := 0.0
		for vr: Rect2 in void_rects:
			total_void_area += vr.get_area()
		if total_void_area < arena_area * void_min_frac:
			return false

	if _void_ids.size() < 1:
		return false

	var has_diverse := false
	for i in solid_ids:
		if rooms[i]["is_corridor"] == true:
			continue
		var r := _room_bounding_box(i)
		var aspect := r.size.x / maxf(r.size.y, 1.0)
		if aspect >= 1.5 or aspect <= 0.67:
			has_diverse = true
			break
	if not has_diverse and solid_ids.size() >= 6:
		return false

	return true


func _validate_structure() -> bool:
	match _layout_mode:
		LayoutMode.CENTRAL_HALL:
			if _hub_ids.is_empty():
				return false
			var hub: int = _hub_ids[0]
			if hub in _void_ids:
				return false
			var deg := (_door_adj[hub] as Array).size() if _door_adj.has(hub) else 0
			return deg >= 2

		LayoutMode.CENTRAL_SPINE:
			if _hub_ids.is_empty():
				return false
			var spine: int = _hub_ids[0]
			if spine in _void_ids:
				return false
			var deg := (_door_adj[spine] as Array).size() if _door_adj.has(spine) else 0
			return deg >= 2

		LayoutMode.CENTRAL_RING:
			if _ring_ids.size() < 3:
				return false
			for idx in range(_ring_ids.size()):
				var a: int = _ring_ids[idx]
				var b: int = _ring_ids[(idx + 1) % _ring_ids.size()]
				if a in _void_ids or b in _void_ids:
					return false
				if b not in (_door_adj[a] as Array):
					return false
			return true

		LayoutMode.CENTRAL_LIKE_HUB:
			if _hub_ids.size() < 2:
				return false
			var h1: int = _hub_ids[0]
			var h2: int = _hub_ids[1]
			if h1 in _void_ids or h2 in _void_ids:
				return false
			var d1 := (_door_adj[h1] as Array).size() if _door_adj.has(h1) else 0
			var d2 := (_door_adj[h2] as Array).size() if _door_adj.has(h2) else 0
			if d1 < 2 or d2 < 2:
				return false
			if h2 not in (_door_adj[h1] as Array):
				return false
			return true

	return true


## ============================================================================
## PLAYER ROOM
## ============================================================================

func _find_player_room() -> void:
	# North-central NON-corridor room, prefer largest among top candidates
	var arena_cx := _arena.position.x + _arena.size.x * 0.5
	var candidates: Array = []
	for room in rooms:
		if room["is_corridor"] == true:
			continue
		if room.get("is_void", false) == true:
			continue
		candidates.append(room)

	if candidates.is_empty():
		for room in rooms:
			if room.get("is_void", false) != true:
				candidates.append(room)

	# Sort: prefer hub-adjacent, then north (lower y), then closest to horizontal center
	candidates.sort_custom(func(a, b):
		var a_adj := _is_hub_adjacent(int(a["id"]))
		var b_adj := _is_hub_adjacent(int(b["id"]))
		if a_adj != b_adj:
			return a_adj
		var ay: float = float((a["center"] as Vector2).y)
		var by: float = float((b["center"] as Vector2).y)
		if absf(ay - by) > 50.0:
			return ay < by
		return absf(float((a["center"] as Vector2).x) - arena_cx) < absf(float((b["center"] as Vector2).x) - arena_cx)
	)

	# Among top 3, pick largest (total area of all rects)
	var top_count := mini(3, candidates.size())
	var best = candidates[0]
	var best_area := _room_total_area(int(best["id"]))
	for i in range(1, top_count):
		var area := _room_total_area(int(candidates[i]["id"]))
		if area > best_area:
			best = candidates[i]
			best_area = area

	player_room_id = int(best["id"])
	player_spawn_pos = best["center"] as Vector2


func _place_player(player_node: Node2D) -> void:
	if not player_node or not valid:
		return

	var pad: float = GameConfig.inner_padding if GameConfig else 32.0
	var room_rect: Rect2 = (rooms[player_room_id]["rects"] as Array)[0] as Rect2
	var spawn := room_rect.grow(-pad).get_center()
	player_spawn_pos = spawn
	player_node.global_position = spawn

	if player_node is CharacterBody2D:
		var cb := player_node as CharacterBody2D
		if (cb.collision_mask & 1) == 0:
			cb.collision_mask |= 1
		if cb.test_move(cb.global_transform, Vector2.ZERO):
			var clamp_rect := room_rect.grow(-pad)
			var safe := _spiral_search_safe(cb, spawn, 160.0, clamp_rect)
			if safe != spawn:
				player_node.global_position = safe
				player_spawn_pos = safe


func _spiral_search_safe(cb: CharacterBody2D, center: Vector2, max_radius: float, clamp_rect: Rect2) -> Vector2:
	var step := _cell_size
	var max_steps := int(ceilf(max_radius / step))
	var orig_pos := cb.global_position
	for ring in range(1, max_steps + 1):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				var test_pos := center + Vector2(float(dx) * step, float(dy) * step)
				test_pos.x = clampf(test_pos.x, clamp_rect.position.x, clamp_rect.end.x)
				test_pos.y = clampf(test_pos.y, clamp_rect.position.y, clamp_rect.end.y)
				cb.global_position = test_pos
				if not cb.test_move(cb.global_transform, Vector2.ZERO):
					cb.global_position = orig_pos
					return test_pos
	cb.global_position = orig_pos
	return center


## ============================================================================
## ENTRY GATE (top perimeter opening)
## ============================================================================

func _compute_entry_gate() -> void:
	_entry_gate = Rect2()
	var wall_t: float = GameConfig.wall_thickness if GameConfig else 16.0
	var door_max: float = GameConfig.door_opening_max if GameConfig else 128.0
	var gate_width := clampf(door_max * 1.5, 140.0, 220.0)

	# Find solid spans on top edge
	var ay := _arena.position.y
	var top_spans: Array = []
	for i in range(rooms.size()):
		if i in _void_ids:
			continue
		var r := _room_bounding_box(i)
		if absf(r.position.y - ay) < 1.0:
			top_spans.append({"x0": r.position.x, "x1": r.end.x})

	if top_spans.is_empty():
		return

	# Merge spans
	top_spans.sort_custom(func(a, b): return float(a["x0"]) < float(b["x0"]))
	var merged: Array = [top_spans[0].duplicate()]
	for i in range(1, top_spans.size()):
		var last: Dictionary = merged.back()
		if float(top_spans[i]["x0"]) <= float(last["x1"]) + 1.0:
			last["x1"] = maxf(float(last["x1"]), float(top_spans[i]["x1"]))
		else:
			merged.append(top_spans[i].duplicate())

	# Try to place gate centered on player spawn X
	var gate_cx := clampf(player_spawn_pos.x, _arena.position.x + 200.0, _arena.end.x - 200.0)
	var gate_x0 := gate_cx - gate_width * 0.5
	var gate_x1 := gate_cx + gate_width * 0.5

	var fits := false
	for span in merged:
		var sx0: float = float(span["x0"])
		var sx1: float = float(span["x1"])
		if gate_x0 >= sx0 + 48.0 and gate_x1 <= sx1 - 48.0:
			fits = true
			break

	if not fits:
		# Shift gate to fit in largest solid span
		var best_span = null
		var best_len := 0.0
		for span in merged:
			var slen: float = float(span["x1"]) - float(span["x0"])
			if slen > best_len:
				best_len = slen
				best_span = span
		if best_span != null and best_len >= gate_width + 96.0:
			var sx0: float = float(best_span["x0"])
			var sx1: float = float(best_span["x1"])
			gate_cx = clampf(gate_cx, sx0 + 48.0 + gate_width * 0.5, sx1 - 48.0 - gate_width * 0.5)
			gate_x0 = gate_cx - gate_width * 0.5
			fits = true

	if fits:
		_entry_gate = Rect2(gate_x0, ay - wall_t * 0.5, gate_width, wall_t)


## ============================================================================
## WALLS (split segments + perimeter; doors cut openings)
## ============================================================================

func _build_walls(walls_node: Node2D) -> void:
	var wall_t: float = GameConfig.wall_thickness if GameConfig else 16.0

	# 1) Base wall segments: VOID-aware perimeter + filtered split lines
	var base_segs: Array = []

	var ax := _arena.position.x
	var ay := _arena.position.y
	var ax1 := _arena.end.x
	var ay1 := _arena.end.y

	# Perimeter walls only where SOLID room rects touch arena edge.
	for i in range(rooms.size()):
		if i in _void_ids:
			continue
		for rr in rooms[i]["rects"]:
			var r := rr as Rect2
			if absf(r.position.y - ay) < 1.0:
				base_segs.append({"type": "H", "pos": ay, "t0": r.position.x, "t1": r.end.x})
			if absf(r.end.y - ay1) < 1.0:
				base_segs.append({"type": "H", "pos": ay1, "t0": r.position.x, "t1": r.end.x})
			if absf(r.position.x - ax) < 1.0:
				base_segs.append({"type": "V", "pos": ax, "t0": r.position.y, "t1": r.end.y})
			if absf(r.end.x - ax1) < 1.0:
				base_segs.append({"type": "V", "pos": ax1, "t0": r.position.y, "t1": r.end.y})

	# Internal split walls: skip if ALL leaves on BOTH sides are VOID
	for ss in _split_segs:
		var left_ids: Array = ss["left_ids"]
		var right_ids: Array = ss["right_ids"]
		var all_left_void := true
		for lid in left_ids:
			if int(lid) not in _void_ids:
				all_left_void = false
				break
		var all_right_void := true
		for rid in right_ids:
			if int(rid) not in _void_ids:
				all_right_void = false
				break
		if all_left_void and all_right_void:
			continue
		base_segs.append({
			"type": ss["type"],
			"pos": float(ss["pos"]),
			"t0": float(ss["t0"]),
			"t1": float(ss["t1"]),
		})

	# L-room notch walls (internal walls for cut corners)
	for notch_data in _l_room_notches:
		var notch: Rect2 = notch_data["notch_rect"] as Rect2
		var corner: String = notch_data["corner"] as String
		match corner:
			"NE":
				base_segs.append({"type": "V", "pos": notch.position.x, "t0": notch.position.y, "t1": notch.end.y})
				base_segs.append({"type": "H", "pos": notch.end.y, "t0": notch.position.x, "t1": notch.end.x})
			"NW":
				base_segs.append({"type": "V", "pos": notch.end.x, "t0": notch.position.y, "t1": notch.end.y})
				base_segs.append({"type": "H", "pos": notch.end.y, "t0": notch.position.x, "t1": notch.end.x})
			"SE":
				base_segs.append({"type": "V", "pos": notch.position.x, "t0": notch.position.y, "t1": notch.end.y})
				base_segs.append({"type": "H", "pos": notch.position.y, "t0": notch.position.x, "t1": notch.end.x})
			"SW":
				base_segs.append({"type": "V", "pos": notch.end.x, "t0": notch.position.y, "t1": notch.end.y})
				base_segs.append({"type": "H", "pos": notch.position.y, "t0": notch.position.x, "t1": notch.end.x})

	# Perimeter notches (3-segment inward walls).
	for notch_data in _perimeter_notches:
		var notch: Rect2 = notch_data["notch_rect"] as Rect2
		var side: String = notch_data["side"] as String
		match side:
			"TOP":
				base_segs.append({"type": "V", "pos": notch.position.x, "t0": notch.position.y, "t1": notch.end.y})
				base_segs.append({"type": "V", "pos": notch.end.x, "t0": notch.position.y, "t1": notch.end.y})
				base_segs.append({"type": "H", "pos": notch.end.y, "t0": notch.position.x, "t1": notch.end.x})
			"BOTTOM":
				base_segs.append({"type": "V", "pos": notch.position.x, "t0": notch.position.y, "t1": notch.end.y})
				base_segs.append({"type": "V", "pos": notch.end.x, "t0": notch.position.y, "t1": notch.end.y})
				base_segs.append({"type": "H", "pos": notch.position.y, "t0": notch.position.x, "t1": notch.end.x})
			"LEFT":
				base_segs.append({"type": "H", "pos": notch.position.y, "t0": notch.position.x, "t1": notch.end.x})
				base_segs.append({"type": "H", "pos": notch.end.y, "t0": notch.position.x, "t1": notch.end.x})
				base_segs.append({"type": "V", "pos": notch.end.x, "t0": notch.position.y, "t1": notch.end.y})
			"RIGHT":
				base_segs.append({"type": "H", "pos": notch.position.y, "t0": notch.position.x, "t1": notch.end.x})
				base_segs.append({"type": "H", "pos": notch.end.y, "t0": notch.position.x, "t1": notch.end.x})
				base_segs.append({"type": "V", "pos": notch.position.x, "t0": notch.position.y, "t1": notch.end.y})

	# T/U complex shape cut walls.
	for seg in _complex_shape_wall_segs:
		base_segs.append(seg)

	# Part 5: Merge collinear perimeter segments (dedup)
	base_segs = _merge_collinear_segments(base_segs)

	# 2) Cut door openings (include entry gate)
	var all_door_rects: Array = doors.duplicate()
	if _entry_gate != Rect2():
		all_door_rects.append(_entry_gate)
	_wall_segs = _cut_doors_from_segments(base_segs, all_door_rects, wall_t)

	# 3) Build StaticBody2D walls
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	var white_tex := ImageTexture.create_from_image(img)
	var wall_color := Color(0.28, 0.24, 0.22, 1.0)

	for seg in _wall_segs:
		var seg_type: String = seg["type"]
		var seg_pos: float = float(seg["pos"])
		var seg_t0: float = float(seg["t0"])
		var seg_t1: float = float(seg["t1"])
		var seg_len := seg_t1 - seg_t0
		if seg_len < 2.0:
			continue

		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 1

		var shape := RectangleShape2D.new()
		var pos: Vector2
		var sz: Vector2

		if seg_type == "H":
			sz = Vector2(seg_len, wall_t)
			pos = Vector2(seg_t0 + seg_len * 0.5, seg_pos)
			# Symmetric overlap to close corner gaps
			pos.x -= 2.0
			sz.x += 4.0
		else:
			sz = Vector2(wall_t, seg_len)
			pos = Vector2(seg_pos, seg_t0 + seg_len * 0.5)
			pos.y -= 2.0
			sz.y += 4.0

		# Snap to 2px grid
		pos.x = roundf(pos.x * 0.5) * 2.0
		pos.y = roundf(pos.y * 0.5) * 2.0
		sz.x = maxf(roundf(sz.x * 0.5) * 2.0, 2.0)
		sz.y = maxf(roundf(sz.y * 0.5) * 2.0, 2.0)

		shape.size = sz
		var col := CollisionShape2D.new()
		col.shape = shape
		body.add_child(col)
		body.position = pos

		var spr := Sprite2D.new()
		spr.texture = white_tex
		spr.scale = sz
		spr.modulate = wall_color
		body.add_child(spr)

		walls_node.add_child(body)


## ============================================================================
## MERGE COLLINEAR SEGMENTS (Part 5: dedup perimeter)
## ============================================================================

func _merge_collinear_segments(segs: Array) -> Array:
	if segs.is_empty():
		return segs

	var h_segs: Array = []
	var v_segs: Array = []
	for s in segs:
		if s["type"] == "H":
			h_segs.append(s)
		else:
			v_segs.append(s)

	var result: Array = []
	result.append_array(_merge_segs_by_pos(h_segs, "H"))
	result.append_array(_merge_segs_by_pos(v_segs, "V"))
	return result


func _merge_segs_by_pos(segs: Array, seg_type: String) -> Array:
	if segs.is_empty():
		return []

	# Group by pos value (snapped to 0.5 tolerance)
	var groups: Dictionary = {}
	for s in segs:
		var pos: float = float(s["pos"])
		var key := roundf(pos * 2.0) / 2.0  # Snap to 0.5
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(s)

	var result: Array = []
	for key in groups:
		var group: Array = groups[key]
		group.sort_custom(func(a, b): return float(a["t0"]) < float(b["t0"]))

		var merged: Array = [group[0].duplicate()]
		for i in range(1, group.size()):
			var last: Dictionary = merged.back()
			var curr: Dictionary = group[i]
			if float(curr["t0"]) <= float(last["t1"]) + 1.0:
				last["t1"] = maxf(float(last["t1"]), float(curr["t1"]))
			else:
				merged.append(curr.duplicate())
		result.append_array(merged)

	return result


func _cut_doors_from_segments(base_segs: Array, door_rects: Array, wall_t: float) -> Array:
	var result: Array = base_segs.duplicate(true)

	for door: Rect2 in door_rects:
		var new_result: Array = []
		for seg in result:
			var seg_type: String = seg["type"]
			var seg_pos: float = float(seg["pos"])
			var seg_t0: float = float(seg["t0"])
			var seg_t1: float = float(seg["t1"])

			var cut := false

			if seg_type == "V":
				var door_x := door.position.x + door.size.x * 0.5
				if absf(door_x - seg_pos) < wall_t:
					var d_t0 := door.position.y
					var d_t1 := door.end.y
					if d_t0 < seg_t1 and d_t1 > seg_t0:
						cut = true
						if d_t0 > seg_t0 + 2.0:
							new_result.append({"type": "V", "pos": seg_pos, "t0": seg_t0, "t1": d_t0})
						if d_t1 < seg_t1 - 2.0:
							new_result.append({"type": "V", "pos": seg_pos, "t0": d_t1, "t1": seg_t1})
			elif seg_type == "H":
				var door_y := door.position.y + door.size.y * 0.5
				if absf(door_y - seg_pos) < wall_t:
					var d_t0 := door.position.x
					var d_t1 := door.end.x
					if d_t0 < seg_t1 and d_t1 > seg_t0:
						cut = true
						if d_t0 > seg_t0 + 2.0:
							new_result.append({"type": "H", "pos": seg_pos, "t0": seg_t0, "t1": d_t0})
						if d_t1 < seg_t1 - 2.0:
							new_result.append({"type": "H", "pos": seg_pos, "t0": d_t1, "t1": seg_t1})

			if not cut:
				new_result.append(seg)
		result = new_result

	return result


## ============================================================================
## DEBUG DRAW (Part 9: enhanced info)
## ============================================================================

func _build_debug(debug_node: Node2D) -> void:
	for room in rooms:
		var rid := int(room["id"])
		var is_corr: bool = room.get("is_corridor", false)
		var is_hub: bool = rid in _hub_ids
		var is_ring: bool = rid in _ring_ids
		var is_void: bool = rid in _void_ids
		var color: Color
		if is_void:
			color = Color(0.4, 0.4, 0.4, 0.3)
		elif is_hub:
			color = Color(1.0, 0.3, 0.3, 0.7)
		elif is_ring:
			color = Color(1.0, 0.6, 0.2, 0.7)
		elif is_corr:
			color = Color(0.8, 0.8, 0.2, 0.6)
		else:
			color = Color(0.2, 0.8, 0.2, 0.6)
		for r: Rect2 in room["rects"]:
			_draw_rect_outline(debug_node, r, color, 3.0 if is_hub else 2.0)

		# Room label with degree info
		var is_l: bool = room.get("is_l_room", false)
		var prefix := "V" if is_void else ("H" if is_hub else ("L" if is_l else ("C" if is_corr else "R")))
		var deg: int = (_door_adj[rid] as Array).size() if _door_adj.has(rid) else 0
		var lbl := Label.new()
		lbl.text = "%s%d d%d" % [prefix, rid, deg]
		lbl.position = (room["center"] as Vector2) - Vector2(14, 10)
		var lbl_color := Color.RED if is_hub else (Color.YELLOW if is_corr else Color.GREEN)
		lbl.add_theme_color_override("font_color", lbl_color)
		debug_node.add_child(lbl)

	# L-room notches (dark gray fill)
	for notch_data in _l_room_notches:
		var notch: Rect2 = notch_data["notch_rect"] as Rect2
		_draw_rect_outline(debug_node, notch, Color(0.2, 0.2, 0.2, 0.5), 2.0)
		var fill := ColorRect.new()
		fill.color = Color(0.15, 0.15, 0.15, 0.3)
		fill.position = notch.position
		fill.size = notch.size
		debug_node.add_child(fill)

	for d: Rect2 in doors:
		_draw_rect_outline(debug_node, d, Color(0.2, 0.5, 1.0, 0.7), 2.0)

	# Entry gate (cyan)
	if _entry_gate != Rect2():
		_draw_rect_outline(debug_node, _entry_gate, Color(0.0, 1.0, 1.0, 0.8), 3.0)

	var ps := player_spawn_pos
	var m1 := Line2D.new()
	m1.width = 3.0
	m1.default_color = Color.RED
	m1.add_point(ps + Vector2(-8, -8))
	m1.add_point(ps + Vector2(8, 8))
	debug_node.add_child(m1)
	var m2 := Line2D.new()
	m2.width = 3.0
	m2.default_color = Color.RED
	m2.add_point(ps + Vector2(8, -8))
	m2.add_point(ps + Vector2(-8, 8))
	debug_node.add_child(m2)

	# Part 9: Enhanced layout mode label with composition info
	var ring_len := _ring_ids.size() if not _ring_ids.is_empty() else 0
	var mode_lbl := Label.new()
	mode_lbl.text = "Mode:%s  Hubs:%d  Voids:%d  L:%d  Gate:%s  AvgDeg:%.1f  MaxD:%d  Ring:%d" % [
		layout_mode_name, _hub_ids.size(), _void_ids.size(), _l_room_ids.size(),
		str(_entry_gate != Rect2()), avg_degree, max_doors_stat, ring_len]
	mode_lbl.position = Vector2(_arena.position.x + 4, _arena.position.y + 4)
	mode_lbl.add_theme_color_override("font_color", Color(1.0, 0.5, 0.0, 0.9))
	debug_node.add_child(mode_lbl)


func _draw_rect_outline(parent: Node2D, r: Rect2, color: Color, width: float) -> void:
	var line := Line2D.new()
	line.width = width
	line.default_color = color
	line.add_point(r.position)
	line.add_point(Vector2(r.end.x, r.position.y))
	line.add_point(r.end)
	line.add_point(Vector2(r.position.x, r.end.y))
	line.add_point(r.position)
	parent.add_child(line)
