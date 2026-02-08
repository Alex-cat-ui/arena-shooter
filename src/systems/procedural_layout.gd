## procedural_layout.gd
## ProceduralLayout – BSP room generator with Hotline-style connectivity.
## CANON: BSP-tree doors (no all-pairs scan), MAX_DOORS_PER_ROOM from config (default 2), 0..1 extra loops.
## CANON: Strict 1..2 corridors (3 only if rooms>=9). Safe player spawn. 2px-snapped walls with overlap.
class_name ProceduralLayout
extends RefCounted

## Layout output data
var rooms: Array = []           # [{id:int, rects:[Rect2,...], center:Vector2}]
var corridors: Array = []       # [Rect2]
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

## Internal grid
var _arena: Rect2
var _grid: Array = []           # Flat bool array, row-major
var _grid_w: int = 0
var _grid_h: int = 0
var _cell_size: float = 8.0

## BSP tree and door tracking
var _bsp_root: Dictionary = {}
var _door_adj: Dictionary = {}   # room_id -> Array[int] connected via doors
var _door_map: Array = []        # [{a:int, b:int, rect:Rect2}]
var _logical_corr_count: int = 0
var _big_leaf_set: Array = []    # Indices of 2 largest BSP leaves


## ============================================================================
## PUBLIC API
## ============================================================================

static func generate_and_build(arena_rect: Rect2, p_seed: int, walls_node: Node2D, debug_node: Node2D, player_node: Node2D) -> ProceduralLayout:
	var layout := ProceduralLayout.new()
	layout._arena = arena_rect

	var current_seed := p_seed
	for attempt in range(10):
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

	if layout.valid:
		layout._build_grid()
		layout._build_walls(walls_node)
		layout._place_player(player_node)
		if GameConfig and GameConfig.layout_debug_draw:
			layout._build_debug(debug_node)
		print("[ProceduralLayout] OK seed=%d rooms=%d corridors=%d(logical=%d) doors=%d big=%d avg_deg=%.1f max_doors=%d loops=%d isolated=%d" % [
			layout.layout_seed, layout.rooms.size(), layout.corridors.size(),
			layout._logical_corr_count, layout.doors.size(), layout.big_rooms_count,
			layout.avg_degree, layout.max_doors_stat, layout.extra_loops, layout.isolated_fixed])
	else:
		push_warning("[ProceduralLayout] FAILED after 10 attempts")

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
	_logical_corr_count = 0
	_big_leaf_set.clear()
	extra_loops = 0
	isolated_fixed = 0
	big_rooms_count = 0
	avg_degree = 0.0

	var target := randi_range(
		GameConfig.rooms_count_min if GameConfig else 6,
		GameConfig.rooms_count_max if GameConfig else 9)

	# 1) BSP split -> tree
	_bsp_root = _bsp_split(target)

	# 2) Collect leaves and identify 2 largest
	var leaf_nodes: Array = []
	_collect_leaves_dfs(_bsp_root, leaf_nodes)
	var leaf_rects: Array = []
	for i in range(leaf_nodes.size()):
		leaf_rects.append(leaf_nodes[i]["rect"] as Rect2)
		leaf_nodes[i]["leaf_id"] = i

	var big_target: int = GameConfig.big_rooms_target if GameConfig else 2
	_big_leaf_set = _find_largest_leaves(leaf_rects, big_target)

	_create_rooms(leaf_rects)

	# Init door adjacency
	for i in range(rooms.size()):
		_door_adj[i] = []

	# 3) BSP-tree doors (spanning tree connectivity)
	_create_doors_bsp(_bsp_root)

	# 4) Optional extra loops (0..config max, clamped to 1 for Hotline)
	var el_max: int = mini(GameConfig.extra_loops_max if GameConfig else 1, 1)
	_add_extra_loops(randi_range(0, el_max))

	# 5) Enforce max doors per room
	_enforce_max_doors()

	# 6) Corridors
	_create_corridors()

	# 7) Force-connect isolated rooms
	_ensure_connectivity()

	# 8) Player room
	_find_player_room()

	# Compute debug stats
	var md := 0
	var total_degree := 0.0
	for i in range(rooms.size()):
		var deg := 0
		if _door_adj.has(i):
			deg = (_door_adj[i] as Array).size()
		md = maxi(md, deg)
		total_degree += float(deg)
	max_doors_stat = md
	avg_degree = total_degree / maxf(float(rooms.size()), 1.0)

	# Count big rooms
	var big_w: float = GameConfig.big_room_min_w if GameConfig else 360.0
	var big_h: float = GameConfig.big_room_min_h if GameConfig else 280.0
	big_rooms_count = 0
	for room in rooms:
		var r0: Rect2 = (room["rects"] as Array)[0]
		if r0.size.x >= big_w or r0.size.y >= big_h:
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
## BSP TREE
## ============================================================================

## BSP node format: {"rect":Rect2, "left":dict|null, "right":dict|null, "leaf_id":-1}

func _bsp_split(target_count: int) -> Dictionary:
	var pad: float = GameConfig.inner_padding if GameConfig else 32.0
	var min_leaf_w := (GameConfig.room_min_w if GameConfig else 220.0) + pad * 2
	var min_leaf_h := (GameConfig.room_min_h if GameConfig else 200.0) + pad * 2

	var root := {"rect": _arena, "left": null, "right": null, "leaf_id": -1}
	var all_nodes: Array = [root]

	while true:
		var leaf_count := 0
		for n in all_nodes:
			if n["left"] == null:
				leaf_count += 1
		if leaf_count >= target_count:
			break

		# Find largest splittable leaf
		var best = null
		var best_area := 0.0
		for n in all_nodes:
			if n["left"] != null:
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
		var horiz: bool
		if can_h and can_v:
			horiz = lf.size.y >= lf.size.x if absf(lf.size.y - lf.size.x) > 40.0 else randf() > 0.5
		else:
			horiz = can_h

		if horiz:
			var sy := lf.position.y + lf.size.y * randf_range(0.35, 0.65)
			best["left"] = {"rect": Rect2(lf.position, Vector2(lf.size.x, sy - lf.position.y)), "left": null, "right": null, "leaf_id": -1}
			best["right"] = {"rect": Rect2(Vector2(lf.position.x, sy), Vector2(lf.size.x, lf.end.y - sy)), "left": null, "right": null, "leaf_id": -1}
		else:
			var sx := lf.position.x + lf.size.x * randf_range(0.35, 0.65)
			best["left"] = {"rect": Rect2(lf.position, Vector2(sx - lf.position.x, lf.size.y)), "left": null, "right": null, "leaf_id": -1}
			best["right"] = {"rect": Rect2(Vector2(sx, lf.position.y), Vector2(lf.end.x - sx, lf.size.y)), "left": null, "right": null, "leaf_id": -1}

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
## ROOMS
## ============================================================================

func _create_rooms(leaves: Array) -> void:
	var pad: float = GameConfig.inner_padding if GameConfig else 32.0
	var l_chance: float = GameConfig.l_room_chance if GameConfig else 0.12
	var min_w: float = GameConfig.room_min_w if GameConfig else 220.0
	var min_h: float = GameConfig.room_min_h if GameConfig else 200.0
	var max_w: float = GameConfig.room_max_w if GameConfig else 520.0
	var max_h: float = GameConfig.room_max_h if GameConfig else 420.0
	var aspect_min: float = GameConfig.room_aspect_min if GameConfig else 0.65
	var aspect_max: float = GameConfig.room_aspect_max if GameConfig else 1.75
	var big_min_w: float = GameConfig.big_room_min_w if GameConfig else 360.0
	var big_min_h: float = GameConfig.big_room_min_h if GameConfig else 280.0
	var leg_min: float = GameConfig.l_leg_min if GameConfig else 160.0
	var cut_max_frac: float = GameConfig.l_cut_max_frac if GameConfig else 0.40

	for i in range(leaves.size()):
		var lf: Rect2 = leaves[i]
		var avail_w := lf.size.x - pad * 2
		var avail_h := lf.size.y - pad * 2

		var rw := clampf(avail_w, min_w, max_w)
		var rh := clampf(avail_h, min_h, max_h)
		rw = minf(rw, avail_w)
		rh = minf(rh, avail_h)

		if rw < min_w or rh < min_h:
			rw = maxf(avail_w, 60.0)
			rh = maxf(avail_h, 60.0)

		# Clamp aspect ratio to [aspect_min..aspect_max]
		if rw > 0.0 and rh > 0.0:
			var aspect := rw / rh
			if aspect < aspect_min:
				# Too tall/narrow -> reduce height
				rh = rw / aspect_min
				rh = minf(rh, avail_h)
			elif aspect > aspect_max:
				# Too wide -> reduce width
				rw = rh * aspect_max
				rw = minf(rw, avail_w)

		# Inflate big rooms for "largest N" leaves
		if i in _big_leaf_set:
			if avail_w >= big_min_w and rw < big_min_w:
				rw = big_min_w
			if avail_h >= big_min_h and rh < big_min_h:
				rh = big_min_h

		var rx := lf.position.x + pad + (avail_w - rw) * 0.5
		var ry := lf.position.y + pad + (avail_h - rh) * 0.5
		var room_rect := Rect2(rx, ry, rw, rh)

		var rects: Array = [room_rect]

		# L-room attempt with Hotline constraints
		if randf() < l_chance and rw >= leg_min * 1.4 and rh >= leg_min * 1.4:
			var cut_w := rw * randf_range(0.25, 0.45)
			var cut_h := rh * randf_range(0.25, 0.45)
			# Enforce: cut area <= l_cut_max_frac * total area
			if cut_w * cut_h <= cut_max_frac * rw * rh:
				var leg_w := rw - cut_w
				var leg_h := rh - cut_h
				# Enforce: both legs >= leg_min
				if leg_w >= leg_min and leg_h >= leg_min:
					var corner := randi() % 4
					var candidate: Array = []
					match corner:
						0:
							candidate = [
								Rect2(rx, ry + cut_h, rw, rh - cut_h),
								Rect2(rx, ry, rw - cut_w, cut_h),
							]
						1:
							candidate = [
								Rect2(rx, ry + cut_h, rw, rh - cut_h),
								Rect2(rx + cut_w, ry, rw - cut_w, cut_h),
							]
						2:
							candidate = [
								Rect2(rx, ry, rw, rh - cut_h),
								Rect2(rx, ry + rh - cut_h, rw - cut_w, cut_h),
							]
						3:
							candidate = [
								Rect2(rx, ry, rw, rh - cut_h),
								Rect2(rx + cut_w, ry + rh - cut_h, rw - cut_w, cut_h),
							]
					# Validate all resulting rects have min dimension
					var l_valid := true
					for cr: Rect2 in candidate:
						if cr.size.x < leg_min * 0.5 or cr.size.y < leg_min * 0.5:
							l_valid = false
							break
					if l_valid:
						rects = candidate

		rooms.append({
			"id": i,
			"rects": rects,
			"center": room_rect.get_center(),
		})


## ============================================================================
## DOORS (BSP TREE)
## ============================================================================

func _create_doors_bsp(node: Dictionary) -> void:
	if node["left"] == null:
		return

	_create_doors_bsp(node["left"])
	_create_doors_bsp(node["right"])

	# Connect closest room pair across left/right subtrees
	var left_ids := _get_leaf_ids(node["left"])
	var right_ids := _get_leaf_ids(node["right"])

	var door_min: float = GameConfig.door_opening_min if GameConfig else 96.0
	var door_max: float = GameConfig.door_opening_max if GameConfig else 128.0
	var corner_min: float = GameConfig.door_from_corner_min if GameConfig else 48.0
	var pad: float = GameConfig.inner_padding if GameConfig else 32.0
	var threshold := pad * 2 + 20.0

	# Sort pairs by distance
	var pairs: Array = []
	for li in left_ids:
		for ri in right_ids:
			var ci: Vector2 = rooms[li]["center"]
			var cj: Vector2 = rooms[ri]["center"]
			pairs.append({"a": int(li), "b": int(ri), "dist": ci.distance_to(cj)})
	pairs.sort_custom(func(x, y): return float(x["dist"]) < float(y["dist"]))

	for pair in pairs:
		var a: int = int(pair["a"])
		var b: int = int(pair["b"])
		var door := _try_door(rooms[a], rooms[b], threshold, door_min, door_max, corner_min)
		if door.size != Vector2.ZERO:
			doors.append(door)
			_register_door_connection(a, b, door)
			break


func _add_extra_loops(max_extra: int) -> void:
	if max_extra <= 0:
		return

	var door_min: float = GameConfig.door_opening_min if GameConfig else 96.0
	var door_max: float = GameConfig.door_opening_max if GameConfig else 128.0
	var corner_min: float = GameConfig.door_from_corner_min if GameConfig else 48.0
	var pad: float = GameConfig.inner_padding if GameConfig else 32.0
	var threshold := pad * 2 + 20.0
	var mdpr: int = mini(GameConfig.max_doors_per_room if GameConfig else 2, 2)

	var candidates: Array = []
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			if j in (_door_adj[i] as Array):
				continue
			if (_door_adj[i] as Array).size() >= mdpr:
				continue
			if (_door_adj[j] as Array).size() >= mdpr:
				continue
			var door := _try_door(rooms[i], rooms[j], threshold, door_min, door_max, corner_min)
			if door.size != Vector2.ZERO:
				# Prefer big/medium rooms for loops
				var r0_area: float = ((rooms[i]["rects"] as Array)[0] as Rect2).get_area()
				var r1_area: float = ((rooms[j]["rects"] as Array)[0] as Rect2).get_area()
				candidates.append({"a": i, "b": j, "door": door, "priority": r0_area + r1_area})

	# Sort by priority (larger rooms first)
	candidates.sort_custom(func(a, b): return float(a["priority"]) > float(b["priority"]))

	var added := 0
	for c in candidates:
		if added >= max_extra:
			break
		doors.append(c["door"] as Rect2)
		_register_door_connection(int(c["a"]), int(c["b"]), c["door"] as Rect2)
		added += 1
	extra_loops = added


func _enforce_max_doors() -> void:
	var mdpr: int = mini(GameConfig.max_doors_per_room if GameConfig else 2, 2)
	for _pass in range(20):
		var any_excess := false
		for i in range(rooms.size()):
			while (_door_adj[i] as Array).size() > mdpr:
				any_excess = true
				var adj: Array = _door_adj[i]
				# Sort neighbors by degree descending (remove highest-degree neighbor first)
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
	# Check if removing door (a,b) keeps the door-only graph connected
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
## DOOR GEOMETRY
## ============================================================================

func _try_door(a: Dictionary, b: Dictionary, threshold: float, dmin: float, dmax: float, cmin: float) -> Rect2:
	for ra: Rect2 in a["rects"]:
		for rb: Rect2 in b["rects"]:
			var d := _door_rect(ra, rb, threshold, dmin, dmax, cmin)
			if d.size != Vector2.ZERO:
				if not _door_too_close(d):
					return d
	return Rect2()


func _door_rect(ra: Rect2, rb: Rect2, threshold: float, dmin: float, dmax: float, cmin: float) -> Rect2:
	var gap := rb.position.x - ra.end.x
	if gap >= 0 and gap <= threshold:
		var d := _horiz_door(ra, rb, gap, dmin, dmax, cmin)
		if d.size != Vector2.ZERO:
			return d
	gap = ra.position.x - rb.end.x
	if gap >= 0 and gap <= threshold:
		var d := _horiz_door(rb, ra, gap, dmin, dmax, cmin)
		if d.size != Vector2.ZERO:
			return d
	gap = rb.position.y - ra.end.y
	if gap >= 0 and gap <= threshold:
		var d := _vert_door(ra, rb, gap, dmin, dmax, cmin)
		if d.size != Vector2.ZERO:
			return d
	gap = ra.position.y - rb.end.y
	if gap >= 0 and gap <= threshold:
		var d := _vert_door(rb, ra, gap, dmin, dmax, cmin)
		if d.size != Vector2.ZERO:
			return d
	return Rect2()


func _horiz_door(left: Rect2, right: Rect2, gap: float, dmin: float, dmax: float, cmin: float) -> Rect2:
	var oy0 := maxf(left.position.y + cmin, right.position.y + cmin)
	var oy1 := minf(left.end.y - cmin, right.end.y - cmin)
	if oy1 - oy0 >= dmin:
		var dh := clampf(randf_range(dmin, dmax), dmin, oy1 - oy0)
		# Center-of-wall with +/-20% jitter
		var center := (oy0 + oy1) * 0.5 + randf_range(-0.2, 0.2) * (oy1 - oy0)
		var dy := clampf(center - dh * 0.5, oy0, oy1 - dh)
		return Rect2(left.end.x, dy, maxf(gap, 4.0), dh)
	return Rect2()


func _vert_door(top: Rect2, bot: Rect2, gap: float, dmin: float, dmax: float, cmin: float) -> Rect2:
	var ox0 := maxf(top.position.x + cmin, bot.position.x + cmin)
	var ox1 := minf(top.end.x - cmin, bot.end.x - cmin)
	if ox1 - ox0 >= dmin:
		var dw := clampf(randf_range(dmin, dmax), dmin, ox1 - ox0)
		# Center-of-wall with +/-20% jitter
		var center := (ox0 + ox1) * 0.5 + randf_range(-0.2, 0.2) * (ox1 - ox0)
		var dx := clampf(center - dw * 0.5, ox0, ox1 - dw)
		return Rect2(dx, top.end.y, dw, maxf(gap, 4.0))
	return Rect2()


## Check if a candidate door overlaps an existing door on same wall line within 48px
func _door_too_close(candidate: Rect2) -> bool:
	var min_spacing := 48.0
	for existing_dm in _door_map:
		var er: Rect2 = existing_dm["rect"]
		# Same horizontal wall line (similar x position)
		if absf(candidate.position.x - er.position.x) < 8.0:
			if candidate.position.y < er.end.y + min_spacing and candidate.end.y > er.position.y - min_spacing:
				return true
		# Same vertical wall line (similar y position)
		if absf(candidate.position.y - er.position.y) < 8.0:
			if candidate.position.x < er.end.x + min_spacing and candidate.end.x > er.position.x - min_spacing:
				return true
	return false


## ============================================================================
## CORRIDORS
## ============================================================================

func _create_corridors() -> void:
	var w_min: float = GameConfig.corridor_w_min if GameConfig else 80.0
	var w_max: float = GameConfig.corridor_w_max if GameConfig else 110.0
	var len_min: float = GameConfig.corridor_len_min if GameConfig else 320.0
	var bends_max: int = GameConfig.corridor_bends_max if GameConfig else 1
	var area_cap: float = GameConfig.corridor_area_cap if GameConfig else 0.25

	# Hotline: 1..2 corridors, 3 only if rooms>=9
	var c_max_logical := 2
	if rooms.size() >= 9:
		c_max_logical = 3
	var count := randi_range(1, c_max_logical)

	var arena_area := _arena.size.x * _arena.size.y

	for _c in range(count):
		if rooms.size() < 2:
			break

		# Check corridor area budget
		var current_corr_area := 0.0
		for cr: Rect2 in corridors:
			current_corr_area += cr.get_area()
		if current_corr_area > area_cap * arena_area:
			break

		# Pick two distant rooms, prefer big rooms
		var best_dist := 0.0
		var best_a := 0
		var best_b := 1
		for _try in range(15):
			var ia := randi() % rooms.size()
			var ib := randi() % rooms.size()
			if ia == ib:
				continue
			var ca: Vector2 = rooms[ia]["center"]
			var cb_pos: Vector2 = rooms[ib]["center"]
			var dist := ca.distance_to(cb_pos)
			# Bonus for big rooms
			if ia in _big_leaf_set or ib in _big_leaf_set:
				dist *= 1.3
			if dist > best_dist:
				best_dist = dist
				best_a = ia
				best_b = ib

		var ca: Vector2 = rooms[best_a]["center"]
		var cb: Vector2 = rooms[best_b]["center"]
		var cw := randf_range(w_min, w_max)

		var do_bend := bends_max > 0 and randf() > 0.35 and absf(ca.x - cb.x) > cw and absf(ca.y - cb.y) > cw

		if do_bend:
			var x0 := minf(ca.x, cb.x)
			var x1 := maxf(ca.x, cb.x)
			var y0 := minf(ca.y, cb.y)
			var y1 := maxf(ca.y, cb.y)
			if x1 - x0 >= len_min or y1 - y0 >= len_min:
				corridors.append(Rect2(x0, ca.y - cw * 0.5, x1 - x0, cw))
				corridors.append(Rect2(cb.x - cw * 0.5, y0, cw, y1 - y0))
				_logical_corr_count += 1
		else:
			if absf(ca.x - cb.x) >= absf(ca.y - cb.y):
				var x0 := minf(ca.x, cb.x)
				var x1 := maxf(ca.x, cb.x)
				if x1 - x0 >= len_min:
					var my := (ca.y + cb.y) * 0.5
					corridors.append(Rect2(x0, my - cw * 0.5, x1 - x0, cw))
					_logical_corr_count += 1
			else:
				var y0 := minf(ca.y, cb.y)
				var y1 := maxf(ca.y, cb.y)
				if y1 - y0 >= len_min:
					var mx := (ca.x + cb.x) * 0.5
					corridors.append(Rect2(mx - cw * 0.5, y0, cw, y1 - y0))
					_logical_corr_count += 1


## ============================================================================
## CONNECTIVITY
## ============================================================================

func _get_full_adjacency() -> Dictionary:
	var adj: Dictionary = {}
	for i in range(rooms.size()):
		adj[i] = (_door_adj[i] as Array).duplicate() if _door_adj.has(i) else []

	for corr: Rect2 in corridors:
		var connected := _rooms_touching_rect(corr)
		for i in range(connected.size()):
			for j in range(i + 1, connected.size()):
				var a: int = connected[i]
				var b: int = connected[j]
				if b not in (adj[a] as Array):
					(adj[a] as Array).append(b)
				if a not in (adj[b] as Array):
					(adj[b] as Array).append(a)

	return adj


func _rooms_touching_rect(r: Rect2) -> Array:
	var result: Array = []
	var expanded := r.grow(8.0)
	for room in rooms:
		for rr: Rect2 in room["rects"]:
			if expanded.intersects(rr):
				result.append(int(room["id"]))
				break
	return result


func _ensure_connectivity() -> void:
	if rooms.size() <= 1:
		return

	var adj := _get_full_adjacency()

	var visited: Array = []
	var queue: Array = [0]
	while queue.size() > 0:
		var current: int = queue.pop_front()
		if current in visited:
			continue
		visited.append(current)
		for neighbor in adj[current]:
			if int(neighbor) not in visited:
				queue.append(int(neighbor))

	var area_cap: float = GameConfig.corridor_area_cap if GameConfig else 0.25
	var arena_area := _arena.size.x * _arena.size.y

	for i in range(rooms.size()):
		if i in visited:
			continue
		isolated_fixed += 1

		# Find nearest visited room
		var best_dist := INF
		var best_j := 0
		for j in visited:
			var ci: Vector2 = rooms[i]["center"]
			var cj: Vector2 = rooms[int(j)]["center"]
			var dist := ci.distance_to(cj)
			if dist < best_dist:
				best_dist = dist
				best_j = int(j)

		# 1) Prefer adding a door between adjacent rooms
		var door_min: float = GameConfig.door_opening_min if GameConfig else 96.0
		var door_max: float = GameConfig.door_opening_max if GameConfig else 128.0
		var corner_min: float = GameConfig.door_from_corner_min if GameConfig else 48.0
		var pad: float = GameConfig.inner_padding if GameConfig else 32.0
		var threshold := pad * 2 + 20.0

		var door := _try_door(rooms[i], rooms[best_j], threshold, door_min, door_max, corner_min)
		if door.size != Vector2.ZERO:
			doors.append(door)
			_register_door_connection(i, best_j, door)
			visited.append(i)
			continue

		# 2) Try wider threshold door
		var wide_door := _try_door(rooms[i], rooms[best_j], threshold * 2.5, door_min * 0.5, door_max, corner_min * 0.5)
		if wide_door.size != Vector2.ZERO:
			doors.append(wide_door)
			_register_door_connection(i, best_j, wide_door)
			visited.append(i)
			continue

		# 3) Short corridor if within budget (max 2 rects, counted as 1 logical corridor)
		var current_corr_area := 0.0
		for cr: Rect2 in corridors:
			current_corr_area += cr.get_area()
		var c_max_logical := 2
		if rooms.size() >= 9:
			c_max_logical = 3
		if _logical_corr_count < c_max_logical and current_corr_area < area_cap * arena_area:
			var ci: Vector2 = rooms[i]["center"]
			var cj: Vector2 = rooms[best_j]["center"]
			var cw := 80.0
			# Prefer straight connector; use L-shape only if needed
			if absf(ci.x - cj.x) < cw * 2:
				# Nearly vertical: single straight corridor
				var mx := (ci.x + cj.x) * 0.5
				corridors.append(Rect2(mx - cw * 0.5, minf(ci.y, cj.y) - 2, cw, absf(cj.y - ci.y) + 4))
			elif absf(ci.y - cj.y) < cw * 2:
				# Nearly horizontal: single straight corridor
				var my := (ci.y + cj.y) * 0.5
				corridors.append(Rect2(minf(ci.x, cj.x) - 2, my - cw * 0.5, absf(cj.x - ci.x) + 4, cw))
			else:
				# L-shape: 2 rects max
				corridors.append(Rect2(minf(ci.x, cj.x) - 2, ci.y - cw * 0.5, absf(cj.x - ci.x) + 4, cw))
				corridors.append(Rect2(cj.x - cw * 0.5, minf(ci.y, cj.y) - 2, cw, absf(cj.y - ci.y) + 4))
			_logical_corr_count += 1

		visited.append(i)


## ============================================================================
## VALIDATION
## ============================================================================

func _validate() -> bool:
	if rooms.size() < (GameConfig.rooms_count_min if GameConfig else 6):
		return false

	var adj := _get_full_adjacency()

	# Every room must have at least 1 connection; track degrees
	var high_degree_count := 0
	var total_deg := 0.0
	for i in range(rooms.size()):
		var deg: int = (adj[i] as Array).size()
		if deg == 0:
			return false
		if deg > 3:
			high_degree_count += 1
		total_deg += float(deg)

	# Graph must be connected (BFS)
	var visited: Array = []
	var queue: Array = [0]
	while queue.size() > 0:
		var current: int = queue.pop_front()
		if current in visited:
			continue
		visited.append(current)
		for n in adj[current]:
			if int(n) not in visited:
				queue.append(int(n))

	if visited.size() != rooms.size():
		return false

	# Hotline: max 1 room with degree > 3
	if high_degree_count > 1:
		return false

	# Hotline: avg_degree <= 2.2
	var ad := total_deg / maxf(float(rooms.size()), 1.0)
	if ad > 2.2:
		return false

	# Corridor area cap
	var area_cap_val: float = GameConfig.corridor_area_cap if GameConfig else 0.25
	var arena_area := _arena.size.x * _arena.size.y
	var corr_area := 0.0
	for cr: Rect2 in corridors:
		corr_area += cr.get_area()
	if arena_area > 0.0 and corr_area > area_cap_val * arena_area:
		return false

	# At least 2 big rooms if arena is large enough
	var big_w: float = GameConfig.big_room_min_w if GameConfig else 360.0
	var big_h: float = GameConfig.big_room_min_h if GameConfig else 280.0
	var big_count := 0
	for room in rooms:
		var r0: Rect2 = (room["rects"] as Array)[0]
		if r0.size.x >= big_w or r0.size.y >= big_h:
			big_count += 1
	if arena_area > 800000.0 and big_count < 2:
		return false

	return true


## ============================================================================
## PLAYER ROOM
## ============================================================================

func _find_player_room() -> void:
	var best_id := 0
	var best_y := INF
	var best_ax := INF
	for room in rooms:
		var c: Vector2 = room["center"]
		if c.y < best_y or (absf(c.y - best_y) < 1.0 and absf(c.x) < best_ax):
			best_y = c.y
			best_ax = absf(c.x)
			best_id = int(room["id"])
	player_room_id = best_id
	player_spawn_pos = rooms[best_id]["center"] as Vector2


func _place_player(player_node: Node2D) -> void:
	if not player_node or not valid:
		return

	# Validate spawn is on walkable grid cell
	var spawn := player_spawn_pos
	if not _is_world_pos_walkable(spawn):
		spawn = _spiral_search_walkable(spawn, 160.0)
		player_spawn_pos = spawn

	player_node.global_position = spawn

	# Ensure player collision_mask includes bit 1 (walls) - strict check
	if player_node is CharacterBody2D:
		var cb := player_node as CharacterBody2D
		if (cb.collision_mask & 1) == 0:
			cb.collision_mask |= 1
		# Safety: ensure non-colliding spawn
		if cb.test_move(cb.global_transform, Vector2.ZERO):
			var safe := _spiral_search_safe(cb, spawn, 160.0)
			if safe != spawn:
				player_node.global_position = safe
				player_spawn_pos = safe


func _spiral_search_safe(cb: CharacterBody2D, center: Vector2, max_radius: float) -> Vector2:
	var step := _cell_size
	var max_steps := int(ceilf(max_radius / step))
	var orig_pos := cb.global_position
	for ring in range(1, max_steps + 1):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				var test_pos := center + Vector2(float(dx) * step, float(dy) * step)
				if _is_world_pos_walkable(test_pos):
					cb.global_position = test_pos
					if not cb.test_move(cb.global_transform, Vector2.ZERO):
						cb.global_position = orig_pos
						return test_pos
	cb.global_position = orig_pos
	return center


func _is_world_pos_walkable(pos: Vector2) -> bool:
	var gx := int(floorf((pos.x - _arena.position.x) / _cell_size))
	var gy := int(floorf((pos.y - _arena.position.y) / _cell_size))
	return _is_walkable(gx, gy)


func _spiral_search_walkable(center: Vector2, max_radius: float) -> Vector2:
	var step := _cell_size
	var max_steps := int(ceilf(max_radius / step))
	for ring in range(1, max_steps + 1):
		for dx in range(-ring, ring + 1):
			for dy in range(-ring, ring + 1):
				if absi(dx) != ring and absi(dy) != ring:
					continue
				var test_pos := center + Vector2(float(dx) * step, float(dy) * step)
				if _is_world_pos_walkable(test_pos):
					return test_pos
	return center


## ============================================================================
## GRID
## ============================================================================

func _build_grid() -> void:
	_grid_w = int(ceilf(_arena.size.x / _cell_size))
	_grid_h = int(ceilf(_arena.size.y / _cell_size))
	_grid.resize(_grid_w * _grid_h)
	_grid.fill(false)

	for room in rooms:
		for r: Rect2 in room["rects"]:
			_mark_rect_walkable(r)

	for c: Rect2 in corridors:
		_mark_rect_walkable(c)

	for d: Rect2 in doors:
		_mark_rect_walkable(d)


func _mark_rect_walkable(r: Rect2) -> void:
	var gx0 := int(floorf((r.position.x - _arena.position.x) / _cell_size))
	var gy0 := int(floorf((r.position.y - _arena.position.y) / _cell_size))
	var gx1 := int(ceilf((r.end.x - _arena.position.x) / _cell_size))
	var gy1 := int(ceilf((r.end.y - _arena.position.y) / _cell_size))
	gx0 = clampi(gx0, 0, _grid_w - 1)
	gy0 = clampi(gy0, 0, _grid_h - 1)
	gx1 = clampi(gx1, 0, _grid_w)
	gy1 = clampi(gy1, 0, _grid_h)
	for gy in range(gy0, gy1):
		for gx in range(gx0, gx1):
			_grid[gy * _grid_w + gx] = true


func _is_walkable(gx: int, gy: int) -> bool:
	if gx < 0 or gx >= _grid_w or gy < 0 or gy >= _grid_h:
		return false
	return _grid[gy * _grid_w + gx] == true


## ============================================================================
## WALLS (2px snap + symmetric overlap)
## ============================================================================

func _build_walls(walls_node: Node2D) -> void:
	var wall_t: float = GameConfig.wall_thickness if GameConfig else 16.0
	var segments := _collect_wall_segments()

	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color.WHITE)
	var white_tex := ImageTexture.create_from_image(img)

	var wall_color := Color(0.28, 0.24, 0.22, 1.0)

	for seg in segments:
		var body := StaticBody2D.new()
		body.collision_layer = 1
		body.collision_mask = 1

		var shape := RectangleShape2D.new()
		var pos: Vector2
		var sz: Vector2

		if seg["horizontal"] == true:
			var wx: float = _arena.position.x + float(seg["start"]) * _cell_size
			var wy: float = _arena.position.y + float(seg["line"]) * _cell_size
			var ww: float = (float(seg["end"]) - float(seg["start"])) * _cell_size
			sz = Vector2(ww, wall_t)
			pos = Vector2(wx + ww * 0.5, wy)
			# Symmetric overlap to close corner gaps
			pos.x -= 2.0
			sz.x += 4.0
		else:
			var wx: float = _arena.position.x + float(seg["line"]) * _cell_size
			var wy: float = _arena.position.y + float(seg["start"]) * _cell_size
			var wh: float = (float(seg["end"]) - float(seg["start"])) * _cell_size
			sz = Vector2(wall_t, wh)
			pos = Vector2(wx, wy + wh * 0.5)
			# Symmetric overlap to close corner gaps
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


func _collect_wall_segments() -> Array:
	var segments: Array = []

	# Horizontal edges
	for gy in range(_grid_h + 1):
		var seg_start := -1
		for gx in range(_grid_w):
			var above := _is_walkable(gx, gy - 1)
			var below := _is_walkable(gx, gy)
			var is_boundary := (above != below)
			if is_boundary:
				if seg_start < 0:
					seg_start = gx
			else:
				if seg_start >= 0:
					segments.append({"horizontal": true, "line": gy, "start": seg_start, "end": gx})
					seg_start = -1
		if seg_start >= 0:
			segments.append({"horizontal": true, "line": gy, "start": seg_start, "end": _grid_w})

	# Vertical edges
	for gx in range(_grid_w + 1):
		var seg_start := -1
		for gy in range(_grid_h):
			var left := _is_walkable(gx - 1, gy)
			var right := _is_walkable(gx, gy)
			var is_boundary := (left != right)
			if is_boundary:
				if seg_start < 0:
					seg_start = gy
			else:
				if seg_start >= 0:
					segments.append({"horizontal": false, "line": gx, "start": seg_start, "end": gy})
					seg_start = -1
		if seg_start >= 0:
			segments.append({"horizontal": false, "line": gx, "start": seg_start, "end": _grid_h})

	return segments


## ============================================================================
## DEBUG DRAW
## ============================================================================

func _build_debug(debug_node: Node2D) -> void:
	for room in rooms:
		for r: Rect2 in room["rects"]:
			_draw_rect_outline(debug_node, r, Color(0.2, 0.8, 0.2, 0.6), 2.0)
		var lbl := Label.new()
		lbl.text = "R%d" % int(room["id"])
		lbl.position = (room["center"] as Vector2) - Vector2(10, 10)
		lbl.add_theme_color_override("font_color", Color.GREEN)
		debug_node.add_child(lbl)

	for c: Rect2 in corridors:
		_draw_rect_outline(debug_node, c, Color(0.8, 0.8, 0.2, 0.4), 1.5)

	for d: Rect2 in doors:
		_draw_rect_outline(debug_node, d, Color(0.2, 0.5, 1.0, 0.7), 2.0)

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
