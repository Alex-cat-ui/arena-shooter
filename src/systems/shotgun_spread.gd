## shotgun_spread.gd
## Shared shotgun spread sampling for player and enemy weapons.
class_name ShotgunSpread
extends RefCounted


const EDGE_BREAK_MULT := 1.30
const HARD_BREAK_MULT := 1.45
const SPEED_JITTER_SIGMA := 0.07
const SPEED_MIN_MULT := 0.82
const SPEED_MAX_MULT := 1.18


## Returns per-pellet profile dictionaries:
## { "angle_offset": float (radians), "speed_scale": float (multiplier) }.
## Distribution intentionally keeps more pellets near center with rare edge breaks.
static func sample_pellets(pellets: int, cone_deg: float, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	if pellets <= 0:
		return out

	var half_cone := deg_to_rad(maxf(cone_deg, 0.0)) * 0.5
	var shot_rotation := _sample_clamped_gaussian(rng, 0.0, half_cone * 0.08, half_cone * 0.20)
	var edge_break_abs := half_cone * EDGE_BREAK_MULT
	var hard_break_abs := half_cone * HARD_BREAK_MULT

	for _i in range(pellets):
		var roll := rng.randf()
		var base_angle := 0.0
		if roll < 0.58:
			base_angle = _sample_clamped_gaussian(rng, 0.0, half_cone * 0.32, half_cone * 0.70)
		elif roll < 0.88:
			base_angle = _sample_clamped_gaussian(rng, 0.0, half_cone * 0.58, edge_break_abs)
		elif roll < 0.97:
			var sign_dir := -1.0 if rng.randf() < 0.5 else 1.0
			base_angle = sign_dir * rng.randf_range(half_cone * 0.78, edge_break_abs)
		else:
			var hard_sign := -1.0 if rng.randf() < 0.5 else 1.0
			base_angle = hard_sign * rng.randf_range(edge_break_abs, hard_break_abs)

		var micro_jitter := _sample_clamped_gaussian(rng, 0.0, half_cone * 0.04, half_cone * 0.10)
		var angle_offset := clampf(base_angle + shot_rotation + micro_jitter, -hard_break_abs, hard_break_abs)
		var speed_scale := _speed_scale_for_angle(angle_offset, half_cone, rng)

		out.append({
			"angle_offset": angle_offset,
			"speed_scale": speed_scale,
		})

	_shuffle(rng, out)
	return out


static func _sample_clamped_gaussian(rng: RandomNumberGenerator, mean: float, sigma: float, clamp_abs: float) -> float:
	if sigma <= 0.00001:
		return clampf(mean, -clamp_abs, clamp_abs)
	return clampf(rng.randfn(mean, sigma), -clamp_abs, clamp_abs)


static func _speed_scale_for_angle(angle_offset: float, half_cone: float, rng: RandomNumberGenerator) -> float:
	var noise := rng.randfn(0.0, SPEED_JITTER_SIGMA)
	var edge_factor := 0.0
	if half_cone > 0.00001:
		edge_factor = clampf(absf(angle_offset) / (half_cone * HARD_BREAK_MULT), 0.0, 1.0)
	var center_bias := 1.0 - edge_factor * 0.05
	var scale := center_bias + noise
	return clampf(scale, SPEED_MIN_MULT, SPEED_MAX_MULT)


static func _shuffle(rng: RandomNumberGenerator, items: Array) -> void:
	for i in range(items.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = items[i]
		items[i] = items[j]
		items[j] = tmp
