extends SceneTree

const OUTPUT_DIR := "res://assets/textures/ui/markers"
const CANVAS_SIZE := Vector2i(16, 16)

## Question-mark glyph (5x10) for SUSPICIOUS state.
const GLYPH_Q_ROWS := [
	"01110",
	"10001",
	"00001",
	"00010",
	"00100",
	"00100",
	"00000",
	"00000",
	"00100",
	"00100",
]

## Exclamation-mark glyph (3x10) for ALERT / COMBAT states.
const GLYPH_EXCL_ROWS := [
	"010",
	"010",
	"010",
	"010",
	"010",
	"010",
	"000",
	"000",
	"010",
	"010",
]

const OUTLINE_DIRS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]

## Each marker entry specifies: file name, glyph source, fill color, outline flag.
const MARKERS := [
	{
		"file": "enemy_q_suspicious.png",
		"glyph": "question",
		"fill": Color8(255, 255, 255, 255),
		"outline": false,
	},
	{
		"file": "enemy_excl_alert.png",
		"glyph": "exclamation",
		"fill": Color8(255, 220, 40, 255),
		"outline": true,
	},
	{
		"file": "enemy_excl_combat.png",
		"glyph": "exclamation",
		"fill": Color8(230, 50, 40, 255),
		"outline": true,
	},
]


func _init() -> void:
	var abs_dir := ProjectSettings.globalize_path(OUTPUT_DIR)
	var dir_err := DirAccess.make_dir_recursive_absolute(abs_dir)
	if dir_err != OK:
		push_error("[generate_enemy_alert_markers] Failed to create output dir: %s" % OUTPUT_DIR)
		quit(1)
		return

	var glyph_question := _build_glyph_pixels(GLYPH_Q_ROWS)
	var glyph_exclamation := _build_glyph_pixels(GLYPH_EXCL_ROWS)

	for marker_variant in MARKERS:
		var marker := marker_variant as Dictionary
		var out_path := "%s/%s" % [OUTPUT_DIR, String(marker.get("file", ""))]
		var fill := marker.get("fill", Color.WHITE) as Color
		var with_outline := bool(marker.get("outline", false))
		var glyph_key := String(marker.get("glyph", "question"))
		var glyph: Dictionary
		if glyph_key == "exclamation":
			glyph = glyph_exclamation
		else:
			glyph = glyph_question
		var err := _save_marker(out_path, glyph, fill, with_outline)
		if err != OK:
			push_error("[generate_enemy_alert_markers] Failed to save marker: %s" % out_path)
			quit(1)
			return
		print("[generate_enemy_alert_markers] Wrote %s" % out_path)

	quit(0)


func _save_marker(path: String, glyph: Dictionary, fill_color: Color, with_outline: bool) -> int:
	var img := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))

	if with_outline:
		var outline := _build_outline_pixels(glyph)
		for pixel_variant in outline.keys():
			var p := pixel_variant as Vector2i
			img.set_pixelv(p, Color8(255, 255, 255, 255))

	for pixel_variant in glyph.keys():
		var p := pixel_variant as Vector2i
		img.set_pixelv(p, fill_color)

	return img.save_png(ProjectSettings.globalize_path(path))


func _build_glyph_pixels(rows: Array) -> Dictionary:
	var pixels := {}
	if rows.is_empty():
		return pixels

	var glyph_h := rows.size()
	var glyph_w := String(rows[0]).length()
	var offset := Vector2i(
		(CANVAS_SIZE.x - glyph_w) / 2,
		(CANVAS_SIZE.y - glyph_h) / 2
	)

	for y in range(glyph_h):
		var row := String(rows[y])
		for x in range(glyph_w):
			if row.substr(x, 1) != "1":
				continue
			var p := Vector2i(x, y) + offset
			if _is_inside_canvas(p):
				pixels[p] = true
	return pixels


func _build_outline_pixels(glyph: Dictionary) -> Dictionary:
	var outline := {}
	for pixel_variant in glyph.keys():
		var p := pixel_variant as Vector2i
		for dir_variant in OUTLINE_DIRS:
			var d := dir_variant as Vector2i
			var neighbor := p + d
			if not _is_inside_canvas(neighbor):
				continue
			if glyph.has(neighbor):
				continue
			outline[neighbor] = true
	return outline


func _is_inside_canvas(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < CANVAS_SIZE.x and p.y < CANVAS_SIZE.y
