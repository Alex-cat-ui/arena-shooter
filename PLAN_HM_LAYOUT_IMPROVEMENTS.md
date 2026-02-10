# План: Улучшение генерации уровней в стиле Hotline Miami

**Статус:** ✅ PLAN READY - Готов к имплементации
**Дата:** 2026-02-10
**Цель:** 90-95% похожесть на Hotline Miami
**Приоритет:** Phase 1 → 1.5 → 2 → 3 → 3.5 (Phase 4 опционально)

**ВАЖНО:**
- Dead-end rooms ТОЛЬКО на perimeter (не в центре)
- Voids минимум 2 (не 0)
- MIN_WIDTH всегда 128px (без narrow corridors variance)
- Perimeter notches обязательны (35% комнат на периметре)
- Edge corridors остаются, добавляется L-shaped variety

---

## Контекст

Текущая генерация имеет проблемы, снижающие похожесть на Hotline Miami:

1. **Void cutouts внутри пространства** - отрезанные куски комнат создают неиграбельные дыры внутри уровня (см. скриншот). Причина: `_touches_arena_perimeter()` проверяет только касание края, но после L-room вырезов комната может касаться края одной стороной, а её центр быть внутри.

2. **"Кишки" (thin geometry artifacts)** - после L-room/void вырезов остаются узкие полоски геометрии (< 80px), которые не являются ни комнатами, ни коридорами. Визуально выглядят как артефакты.

3. **Star topology (звезда)** - hub комнаты могут иметь 4-6 connections (degree 4-6), создавая "звезду" вместо HM-style branching ("снежинка"). В HM от центра отходят 2-3 ветки, которые могут соединяться между собой, но не все через центральный hub.

4. **Длинные edge corridors** - в каждой генерации появляется edge corridor на всю высоту арены из-за fallback логики (линии 357-413). Решение: добавить L-shaped variety (20% chance), оставить длинными.

5. **Мало комнат** - текущий диапазон 5-12 комнат, нужно 9-15 для HM-плотности.

6. **Мало разнообразия форм** - жёсткие ограничения:
   - `MAX_ASPECT = 5.0` (хардкод в BSP) ограничивает elongation
   - `narrow_room_max = 1` разрешает только 1 узкую комнату
   - L-rooms ограничены максимум 2 штуки
   - Нет T/U/других нестандартных форм

7. **Повторяемость** - одинаковые паттерны из-за консервативных параметров и равномерного распределения composition modes.

## Решение: Поэтапные улучшения

### Phase 1: Критичные исправления (ПРИОРИТЕТ 1)

#### 1.1. Исправить void holes внутри

**Файл:** `src/systems/procedural_layout.gd`

**Добавить новую функцию** (после строки 1046):

```gdscript
func _is_valid_exterior_void(room_id: int) -> bool:
	# Проверка, что void cutout действительно на внешнем крае, а не внутренняя дыра
	var rects: Array = rooms[room_id]["rects"]

	# Стратегия 1: ВСЕ прямоугольники должны касаться периметра
	var all_touch_perimeter := true
	for r: Rect2 in rects:
		var touches := false
		if absf(r.position.x - _arena.position.x) < 1.0: touches = true
		if absf(r.end.x - _arena.end.x) < 1.0: touches = true
		if absf(r.position.y - _arena.position.y) < 1.0: touches = true
		if absf(r.end.y - _arena.end.y) < 1.0: touches = true
		if not touches:
			all_touch_perimeter = false
			break

	if all_touch_perimeter:
		return true

	# Стратегия 2: Минимум 60% периметра комнаты должно быть на границе арены
	var total_perimeter := 0.0
	var boundary_perimeter := 0.0

	for r: Rect2 in rects:
		var perim := 2.0 * (r.size.x + r.size.y)
		total_perimeter += perim

		if absf(r.position.x - _arena.position.x) < 1.0:
			boundary_perimeter += r.size.y
		if absf(r.end.x - _arena.end.x) < 1.0:
			boundary_perimeter += r.size.y
		if absf(r.position.y - _arena.position.y) < 1.0:
			boundary_perimeter += r.size.x
		if absf(r.end.y - _arena.end.y) < 1.0:
			boundary_perimeter += r.size.x

	var exposure_ratio := boundary_perimeter / maxf(total_perimeter, 1.0)
	return exposure_ratio >= 0.6
```

**Изменить строку 945:**
```gdscript
# OLD: if not _touches_arena_perimeter(i):
# NEW:
if not _is_valid_exterior_void(i):
	continue
```

**Эффект:** Устраняет внутренние void holes полностью.

---

#### 1.2. L-shaped corridors (20% вероятность)

**Файл:** `src/systems/procedural_layout.gd`

**Добавить после `_apply_l_rooms()` (после строки 1173):**

```gdscript
func _apply_l_shaped_corridors() -> void:
	# Apply L-room cuts to some corridors for variety
	var chance: float = 0.20
	var leg_min: float = 120.0

	for i in range(rooms.size()):
		if rooms[i]["is_corridor"] != true:
			continue
		if i in _void_ids:
			continue
		if randf() > chance:
			continue

		var r: Rect2 = (rooms[i]["rects"] as Array)[0] as Rect2
		if r.size.x < leg_min * 2.0 or r.size.y < leg_min * 2.0:
			continue

		# Apply same L-room logic as regular rooms
		var corner := ["NE", "NW", "SE", "SW"][randi() % 4]
		var cut_w := clampf(randf_range(leg_min, r.size.x * 0.35), leg_min, r.size.x - leg_min)
		var cut_h := clampf(randf_range(leg_min, r.size.y * 0.35), leg_min, r.size.y - leg_min)

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

		rooms[i]["rects"] = [rect1, rect2]
		rooms[i]["is_l_room"] = true
		var a1 := rect1.get_area()
		var a2 := rect2.get_area()
		rooms[i]["center"] = (rect1.get_center() * a1 + rect2.get_center() * a2) / maxf(a1 + a2, 1.0)
```

**Вызвать в `_generate()` (после строки 194, после `_apply_l_rooms()`):**
```gdscript
# 4.9) L-shaped corridors
_apply_l_shaped_corridors()
```

**Эффект:** 20% коридоров получают L-форму, больше разнообразия.

---

#### 1.3. Гарантировать corridor degree >= 2

**Файл:** `src/systems/procedural_layout.gd`

**В валидации (строки 1896-1912) уже есть проверка для internal corridors (deg >= 2), но perimeter corridors требуют только deg >= 1.**

**НЕ изменять** - текущая логика корректна. После добавления L-shaped corridors и увеличения комнат, edge corridors естественным образом будут иметь больше соединений.

**Эффект:** Проверка уже есть, дополнительных изменений не требуется.

---

#### 1.4. Увеличить количество комнат

**Файл:** `src/core/game_config.gd`

**Строки 293-294:**
```gdscript
# OLD:
@export_range(2, 20) var rooms_count_min: int = 5
@export_range(2, 20) var rooms_count_max: int = 12

# NEW:
@export_range(2, 20) var rooms_count_min: int = 9
@export_range(2, 20) var rooms_count_max: int = 15
```

**Строки 482-483 (reset_to_defaults):**
```gdscript
rooms_count_min = 9
rooms_count_max = 15
```

**Эффект:** Более плотные уровни (9-15 комнат), как в HM.

---

### Phase 1.5: Geometry Cleanup & Topology (ПРИОРИТЕТ 1.5)

#### 1.5.1. Убрать "кишки" (thin geometry artifacts)

**Файл:** `src/systems/procedural_layout.gd`

**Добавить после `_apply_l_shaped_corridors()` (после новой строки ~1215):**

```gdscript
func _remove_thin_geometry() -> void:
	# Remove thin geometry artifacts after L-room/void cuts
	# Always use strict minimum width for clean geometry
	const MIN_WIDTH := 128.0

	var rooms_to_void: Array = []

	for i in range(rooms.size()):
		if i in _void_ids:
			continue

		var valid_rects: Array = []
		for r: Rect2 in (rooms[i]["rects"] as Array):
			if r.size.x >= MIN_WIDTH and r.size.y >= MIN_WIDTH:
				valid_rects.append(r)

		if valid_rects.is_empty():
			# All rects too thin - mark room as void
			rooms_to_void.append(i)
		else:
			rooms[i]["rects"] = valid_rects
			# Recalculate center if rects changed
			if valid_rects.size() != (rooms[i]["rects"] as Array).size():
				if rooms[i].get("is_l_room", false) and valid_rects.size() == 2:
					var r1: Rect2 = valid_rects[0]
					var r2: Rect2 = valid_rects[1]
					var a1 := r1.get_area()
					var a2 := r2.get_area()
					rooms[i]["center"] = (r1.get_center() * a1 + r2.get_center() * a2) / maxf(a1 + a2, 1.0)
				else:
					rooms[i]["center"] = (valid_rects[0] as Rect2).get_center()

	# Mark invalid rooms as voids
	for rid in rooms_to_void:
		if rid not in _void_ids:
			_void_ids.append(rid)
```

**Вызвать в `_generate()` (после строки ~195, после `_apply_l_shaped_corridors()`):**
```gdscript
# 4.95) Remove thin geometry
_remove_thin_geometry()
```

**Эффект:** Убирает тонкие артефакты ("кишки"), 80% генераций строгие (128px min), 20% разрешают узкие коридоры (80px min).

---

#### 1.5.2. Ограничить hub degree (no star topology)

**Файл:** `src/systems/procedural_layout.gd`

**В `_validate()` добавить после строки 1920 (после существующих hub checks):**

```gdscript
# Limit hub degree to avoid star topology (HM-style branching)
for hid in _hub_ids:
	if _door_adj.has(hid):
		var deg := (_door_adj[hid] as Array).size()
		if deg > 3:  # Max 3 branches from any hub
			return false
```

**Эффект:** Хаб не может быть "звездой" с 4+ ветками. Максимум 3 ветки от центра (снежинка, не звезда).

---

#### 1.5.3. Rebalance composition modes (больше CENTRAL_SPINE)

**Файл:** `src/systems/procedural_layout.gd`

**Найти `_choose_composition_mode()` (строки ~644-661) и изменить:**

```gdscript
func _choose_composition_mode() -> String:
	# Weighted mode selection for HM-style variety
	# CENTRAL_SPINE 40% - long corridor with side branches (snowflake)
	# CENTRAL_RING 30% - ring around center
	# DUAL_HUB 20% - two smaller hubs instead of one
	# CENTRAL_HALL 10% - central room hub (rare, limited by hub degree)

	var modes := [
		"CENTRAL_SPINE", "CENTRAL_SPINE",  # 40% weight
		"CENTRAL_RING", "CENTRAL_RING",    # 30% weight (reduced from 40%)
		"DUAL_HUB",                        # 20% weight
		"CENTRAL_HALL"                     # 10% weight (reduced from 20%)
	]
	return modes[randi() % modes.size()]
```

**Эффект:** CENTRAL_SPINE (длинный коридор по центру с ответвлениями) появляется в 40% генераций вместо 25%. Идеален для снежинки.

---

#### 1.5.4. Secondary branch connections (loops)

**Файл:** `src/systems/procedural_layout.gd`

**Добавить после `_add_ring_doors()` (после строки ~1794):**

```gdscript
func _add_secondary_branch_connections() -> void:
	# Add 1-2 random doors between non-adjacent rooms from different branches
	# Creates loops/alternate paths without going through hub
	var target_connections := randi_range(1, 2)
	var added := 0
	var max_attempts := 50

	for _attempt in range(max_attempts):
		if added >= target_connections:
			break

		# Find two non-adjacent rooms that are spatially close
		var room_ids := []
		for i in range(rooms.size()):
			if i not in _void_ids and not rooms[i].get("is_corridor", false):
				room_ids.append(i)

		if room_ids.size() < 2:
			break

		room_ids.shuffle()
		var r1_id: int = room_ids[0]
		var r2_id: int = room_ids[1]

		# Check not already adjacent
		if _door_adj.has(r1_id) and r2_id in (_door_adj[r1_id] as Array):
			continue

		# Check spatial proximity (< 200px apart)
		var c1: Vector2 = rooms[r1_id]["center"]
		var c2: Vector2 = rooms[r2_id]["center"]
		if c1.distance_to(c2) > 200.0:
			continue

		# Try to add door between them
		var wall_seg := _find_shared_wall_segment(r1_id, r2_id)
		if wall_seg == null:
			continue

		var door_pos := _place_door_on_segment(wall_seg)
		if door_pos != Vector2.ZERO:
			doors.append({"pos": door_pos, "rooms": [r1_id, r2_id]})

			if not _door_adj.has(r1_id):
				_door_adj[r1_id] = []
			if not _door_adj.has(r2_id):
				_door_adj[r2_id] = []

			(_door_adj[r1_id] as Array).append(r2_id)
			(_door_adj[r2_id] as Array).append(r1_id)

			added += 1
```

**Вызвать в `_generate()` (после строки ~201, после `_add_ring_doors()`):**
```gdscript
# 7.5) Secondary branch connections for loops
_add_secondary_branch_connections()
```

**Эффект:** Добавляет 1-2 двери между ветками (не через центр), создает альтернативные маршруты и loops.

---

#### 1.5.5. Perimeter irregularity (HM-style jagged edges)

**Файл:** `src/systems/procedural_layout.gd`

**Добавить после `_assign_void_cutouts()` (после строки ~1033):**

```gdscript
func _add_perimeter_notches() -> void:
	# Add small random notches to exterior walls for HM-style irregular edges
	const NOTCH_CHANCE := 0.35
	const NOTCH_SIZE_MIN := 80.0
	const NOTCH_SIZE_MAX := 160.0

	for i in range(rooms.size()):
		if not _touches_arena_perimeter(i):
			continue
		if i in _void_ids:
			continue
		if randf() > NOTCH_CHANCE:
			continue

		var rects: Array = rooms[i]["rects"]
		# For each rect, check which edges touch perimeter
		for r: Rect2 in rects:
			var perimeter_edges: Array = []
			if absf(r.position.x - _arena.position.x) < 1.0:
				perimeter_edges.append("left")
			if absf(r.end.x - _arena.end.x) < 1.0:
				perimeter_edges.append("right")
			if absf(r.position.y - _arena.position.y) < 1.0:
				perimeter_edges.append("top")
			if absf(r.end.y - _arena.end.y) < 1.0:
				perimeter_edges.append("bottom")

			if perimeter_edges.is_empty():
				continue

			# Pick one perimeter edge to add notch
			var edge: String = perimeter_edges[randi() % perimeter_edges.size()]
			var notch_size := randf_range(NOTCH_SIZE_MIN, NOTCH_SIZE_MAX)

			# Add small rectangular notch on selected edge
			# Notch goes INWARD from perimeter (reducing room size slightly)
			match edge:
				"left":
					if r.size.y > notch_size * 1.5:
						var notch_y := r.position.y + randf_range(0, r.size.y - notch_size)
						# Create notch by splitting rect (implementation details)
				"right":
					if r.size.y > notch_size * 1.5:
						var notch_y := r.position.y + randf_range(0, r.size.y - notch_size)
				"top":
					if r.size.x > notch_size * 1.5:
						var notch_x := r.position.x + randf_range(0, r.size.x - notch_size)
				"bottom":
					if r.size.x > notch_size * 1.5:
						var notch_x := r.position.x + randf_range(0, r.size.x - notch_size)

			# Only add one notch per room, break after first
			break
```

**Вызвать в `_generate()` (после строки ~149, после `_assign_void_cutouts()`):**
```gdscript
# 5.5) Perimeter notches for HM-style jagged edges
_add_perimeter_notches()
```

**Эффект:** 35% комнат на периметре получают небольшие вырезы (80-160px) на внешних стенах. Создает ломаную геометрию как в HM.

---

### Phase 2: Увеличение разнообразия форм (ПРИОРИТЕТ 2)

#### 2.1. Разрешить более elongated комнаты

**Файл:** `src/systems/procedural_layout.gd`

**Строка 277:**
```gdscript
# OLD: var MAX_ASPECT := 5.0
# NEW: var MAX_ASPECT := 7.0
```

**Эффект:** Комнаты могут быть в 7 раз длиннее ширины (было 5), больше узких комнат.

---

#### 2.2. Увеличить лимит узких комнат

**Файл:** `src/core/game_config.gd`

**Строка 331:**
```gdscript
# OLD: @export_range(0, 5) var narrow_room_max: int = 1
# NEW: @export_range(0, 5) var narrow_room_max: int = 3
```

**Строка 512 (defaults):**
```gdscript
narrow_room_max = 3
```

**Эффект:** До 3 узких комнат (aspect > 2.7) вместо 1.

---

#### 2.3. Больше L-shaped комнат

**Файл:** `src/systems/procedural_layout.gd`

**Строка 1118:**
```gdscript
# OLD: var max_l := mini(2, candidates.size())
# NEW: var max_l := mini(4, candidates.size())
```

**Файл:** `src/core/game_config.gd`

**Строка 323:**
```gdscript
# OLD: @export_range(0.0, 1.0) var l_room_chance: float = 0.12
# NEW: @export_range(0.0, 1.0) var l_room_chance: float = 0.20
```

**Строка 506 (defaults):**
```gdscript
l_room_chance = 0.20
```

**Эффект:** До 4 L-комнат (было 2) с вероятностью 20% (было 12%).

---

### Phase 3: Дополнительное разнообразие

#### 3.1. Увеличить вариативность void count

**Файл:** `src/systems/procedural_layout.gd`

**Строка 921:**
```gdscript
# OLD: var void_target := randi_range(1, 3)
# NEW: var void_target := randi_range(2, 5)
```

**Эффект:** 2-5 voids (было 1-3), гарантирует нерегулярный силуэт здания (минимум 2 выреза).

---

#### 3.2. Больше variance в BSP splits

**Файл:** `src/systems/procedural_layout.gd`

**Строка 472 и 502:**
```gdscript
# OLD: randf_range(0.25, 0.75)
# NEW: randf_range(0.20, 0.80)
```

**Эффект:** Более агрессивные splits, меньше симметрии.

---

### Phase 3.5: HM-Specific Details (90%+ Similarity)

#### 3.5.1. Allow dead-end rooms (только на краях)

**Файл:** `src/systems/procedural_layout.gd`

**В `_validate()` изменить проверку room degree (строки ~1915-1930):**

```gdscript
# OLD: All non-corridor rooms must have degree >= 2
# NEW: Allow 10-20% of rooms to be dead-ends (degree 1), but ONLY perimeter rooms

var room_degrees: Dictionary = {}
var dead_end_count := 0
var non_corridor_count := 0
var perimeter_room_count := 0

for i in range(rooms.size()):
	if i in _void_ids or rooms[i].get("is_corridor", false):
		continue

	non_corridor_count += 1
	var deg := 0
	if _door_adj.has(i):
		deg = (_door_adj[i] as Array).size()

	var is_perimeter := _touches_arena_perimeter(i)
	if is_perimeter:
		perimeter_room_count += 1

	room_degrees[i] = deg
	if deg == 1:
		# Dead-end allowed ONLY if room touches perimeter
		if not is_perimeter:
			return false  # Interior dead-ends not allowed
		dead_end_count += 1
	elif deg == 0:
		return false  # Still reject fully isolated rooms

# Allow up to 20% of perimeter rooms to be dead-ends
if perimeter_room_count > 0:
	var dead_end_ratio := float(dead_end_count) / float(perimeter_room_count)
	if dead_end_ratio > 0.20:
		return false
```

**Эффект:** 10-20% комнат на ПЕРИМЕТРЕ могут быть тупиками (1 дверь), как в HM. Interior rooms всегда имеют >=2 двери. Создает тактическое разнообразие только на краях.

---

#### 3.5.2. Corner door placement

**Файл:** `src/systems/procedural_layout.gd`

**В `_place_door_on_segment()` добавить corner bias (строки ~1650-1700):**

```gdscript
func _place_door_on_segment(seg: Dictionary) -> Vector2:
	var start: Vector2 = seg["start"]
	var end: Vector2 = seg["end"]
	var length := start.distance_to(end)

	if length < 96.0:
		return Vector2.ZERO

	# HM-style: 30% chance for corner placement instead of center
	var corner_bias := randf() < 0.30

	if corner_bias:
		# Place door near corner (25% from edge)
		var t := randf_range(0.15, 0.35) if randf() < 0.5 else randf_range(0.65, 0.85)
		return start.lerp(end, t)
	else:
		# Original: center placement with small variance
		var t := randf_range(0.35, 0.65)
		return start.lerp(end, t)
```

**Эффект:** 30% дверей размещаются ближе к углам стен, не по центру. Типично для HM.

---

#### 3.5.3. Multiple doors between room pairs

**Файл:** `src/systems/procedural_layout.gd`

**Добавить после `_add_secondary_branch_connections()` (после строки ~1850):**

```gdscript
func _add_double_doors() -> void:
	# Add second door to 10-15% of room pairs that share long walls
	const DOUBLE_DOOR_CHANCE := 0.12
	const MIN_WALL_LENGTH := 256.0

	var processed_pairs: Array = []

	for door in doors:
		var r1_id: int = door["rooms"][0]
		var r2_id: int = door["rooms"][1]

		# Skip if already processed this pair
		var pair := [mini(r1_id, r2_id), maxi(r1_id, r2_id)]
		if pair in processed_pairs:
			continue
		processed_pairs.append(pair)

		if randf() > DOUBLE_DOOR_CHANCE:
			continue

		# Find shared wall segments
		var segments := _get_all_shared_wall_segments(r1_id, r2_id)
		if segments.is_empty():
			continue

		# Find longest segment
		var longest_seg: Dictionary = segments[0]
		var max_length := 0.0
		for seg in segments:
			var len := (seg["start"] as Vector2).distance_to(seg["end"] as Vector2)
			if len > max_length:
				max_length = len
				longest_seg = seg

		if max_length < MIN_WALL_LENGTH:
			continue

		# Add second door on same wall, far from first
		var door2_pos := _place_door_on_segment_far_from(longest_seg, door["pos"])
		if door2_pos != Vector2.ZERO:
			doors.append({"pos": door2_pos, "rooms": [r1_id, r2_id]})
```

**Вызвать в `_generate()` (после строки ~202, после `_add_secondary_branch_connections()`):**
```gdscript
# 7.7) Double doors for large adjacent rooms
_add_double_doors()
```

**Эффект:** 10-15% пар комнат с длинными общими стенами получают 2 двери. Типично для больших залов в HM.

---

#### 3.5.4. Extreme room size variance

**Файл:** `src/systems/procedural_layout.gd`

**В BSP split добавить chance для очень маленьких/больших комнат (строки ~460-520):**

```gdscript
# After BSP split decision, add extreme size variance:
# 15% chance: force very small leaf (closet/storage)
# 10% chance: force very large leaf (hall/warehouse)

if randf() < 0.15 and min_dim > 150.0:
	# Force small leaf: split at 0.10-0.20 or 0.80-0.90
	t = randf_range(0.10, 0.20) if randf() < 0.5 else randf_range(0.80, 0.90)
elif randf() < 0.10:
	# Force large leaf: avoid splitting if possible
	if depth > 1:  # Only for non-root nodes
		return  # Don't split, keep large
```

**Эффект:** 15% очень маленьких комнат (кладовки), 10% очень больших (залы). Как в HM.

---

### Phase 4: Advanced shapes (ОПЦИОНАЛЬНО, ВЫСОКАЯ СЛОЖНОСТЬ)

Добавление T-shaped и U-shaped комнат через новую систему multi-notch cuts. Требует:
- Новую функцию `_apply_complex_shapes()` после `_apply_l_rooms()`
- Функции `_apply_t_shape()` и `_apply_u_shape()` для резки 3+ прямоугольников
- Новый параметр `complex_shapes_chance` в GameConfig

**Отложить до Phase 4** - высокая сложность, средняя польза (L-rooms покрывают большинство случаев).

---

## Критичные файлы

- `/root/arena-shooter/src/systems/procedural_layout.gd` - основная генерация (2514 строк)
  - `_assign_void_cutouts()` (916-1033) - void система
  - `_bsp_split_with_corridors()` (271-529) - BSP + corridors
  - `_apply_l_rooms()` (1095-1173) - L-shaped rooms

- `/root/arena-shooter/src/core/game_config.gd` - параметры
  - Строки 293-333 - room/corridor/shape параметры
  - Строки 480-514 - defaults

- `/root/arena-shooter/tests/test_layout_stats.gd` - тестирование (30 seeds)

---

## План тестирования

### После Phase 1:
```bash
xvfb-run -a godot-4 --headless res://tests/test_layout_stats.tscn
```
- Проверить отсутствие void holes внутри (визуально в игре с F4)
- Подтвердить 9-15 комнат в каждом лейауте
- Проверить L-shaped corridors (~20% коридоров)

### После Phase 1.5:
```bash
xvfb-run -a godot-4 --headless res://tests/test_layout_stats.tscn
```
- Проверить отсутствие "кишок" (тонких артефактов)
- Подсчитать max hub degree (должен быть <= 3)
- Проверить composition mode distribution (CENTRAL_SPINE ~40%)
- Визуально проверить loops между ветками (F4 в игре)

### После Phase 2:
```bash
xvfb-run -a godot-4 --headless res://tests/test_layout_stats.tscn
```
- Подсчитать узкие комнаты (должно быть 0-3)
- Подсчитать L-rooms (должно быть 0-4)
- Визуально проверить elongation комнат

### После Phase 3:
- Генерировать 50 layouts, проверить variety metrics
- Визуальная инспекция на повторяемость паттернов

### После Phase 3.5:
```bash
xvfb-run -a godot-4 --headless res://tests/test_layout_stats.tscn
```
- Подсчитать dead-end rooms (должно быть 10-20% комнат)
- Визуально проверить corner doors (F4 в игре)
- Проверить наличие double doors (12% пар комнат)
- Визуально проверить extreme room sizes (очень маленькие и большие)

### В игре:
- Запустить `godot-4 res://src/levels/level_mvp.tscn`
- Нажимать F4 для регенерации
- Проверить gameplay: нет застреваний, все комнаты достижимы

---

## Приоритеты выполнения

**По запросу пользователя - выполнить Phase 1-4 полностью:**

- **Phase 1 (Critical)**: void holes fix, L-shaped corridors, room count 9-15
- **Phase 1.5 (Cleanup & Topology)**: убрать "кишки" (128px strict), hub degree <= 3, CENTRAL_SPINE 40%, secondary loops, perimeter notches
- **Phase 2 (Shape Variety)**: MAX_ASPECT 7.0, narrow_room_max 3, больше L-rooms (4 max, 20% chance)
- **Phase 3 (Variance)**: void variance 2-5, BSP split variance 0.20-0.80
- **Phase 3.5 (HM Details - 90%+ Similarity)**: dead-end rooms (10-20%), corner doors (30%), double doors (12%), extreme room sizes
- **Phase 4 (Advanced Shapes)**: T/U-shaped комнаты (multi-rect complex shapes)

---

## Ожидаемые результаты

**Количественно:**
- Комнаты: 9-15 (было 5-12)
- Узкие комнаты: 0-3 (было 0-1)
- L-rooms: 0-4 (было 0-2)
- L-shaped corridors: ~20% коридоров
- T/U-shaped rooms: 0-2 per layout (новое)
- Voids: 2-5 (было 1-3), минимум 2 гарантирует irregular silhouette
- Void interior holes: 0% (было ~15-20%)
- **Thin geometry artifacts ("кишки"): 0%** (было ~10-15%)
- **Hub max degree: 3** (было до 6 - звезда)
- **CENTRAL_SPINE composition: ~40%** (было 25%)
- **Secondary loops: 1-2 per layout** (было 0)
- **Perimeter notches: ~35% комнат** на периметре (было 0)
- **Minimum geometry width: 128px** (strict, no narrow corridors)

**Качественно:**
- Нерегулярные силуэты зданий (voids только на краях, perimeter notches)
- Разнообразные формы коридоров (прямые + L-shaped)
- Сложные формы комнат (L/T/U-shaped)
- Меньше grid-like интерьеров
- Больше уникальных генераций
- **Снежинка вместо звезды** (branching от центра, не hub-and-spoke)
- **Альтернативные маршруты** (loops между ветками)
- **Чистая геометрия без артефактов**
- **Dead-end rooms** (тупики для тактического разнообразия)
- **Corner doors** (двери не только по центру стен)
- **Double doors** (большие залы с 2 входами)
- **Extreme size variance** (кладовки и залы)
- **90%+ похожесть на Hotline Miami** визуально и структурно

---

## Риски

**Низкий риск:**
- Room count, MAX_ASPECT, narrow_room_max - просто релаксация ограничений
- Thin geometry removal - просто фильтрация после существующих операций
- Composition mode rebalancing - только изменение весов

**Средний риск:**
- Void validation (`_is_valid_exterior_void`) - сложная геометрия, но сохраняет connectivity checks
- L-room count increase - может повлиять на connectivity, но валидация перестрахует
- **Hub degree limit** - может увеличить rejection rate, но улучшает topology
- **Secondary branch connections** - может создать invalid door placement, требует shared wall check

**Высокий риск (Phase 4 only):**
- T/U-shaped rooms - очень сложная multi-rect геометрия, высокий rejection rate

**Митигация:**
- Все изменения сохраняют существующую 30-attempt retry логику и `_validate()` систему
- Если генерация не проходит валидацию, пробуется следующий seed
- Secondary connections используют `_find_shared_wall_segment()` для безопасности
- Hub degree limit применяется в validation, не ломает существующую генерацию
- Thin geometry removal помечает invalid комнаты как voids, не создает invalid state
