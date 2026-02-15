## shotgun_damage_model.gd
## Shared shotgun hit-to-damage model.
class_name ShotgunDamageModel
extends RefCounted

const DEFAULT_KILL_RATIO := 0.8


static func kill_threshold(total_pellets: int, kill_ratio: float = DEFAULT_KILL_RATIO) -> int:
	var pellets := maxi(total_pellets, 1)
	return maxi(1, ceili(float(pellets) * clampf(kill_ratio, 0.0, 1.0)))


static func is_lethal_hits(hit_pellets: int, total_pellets: int, kill_ratio: float = DEFAULT_KILL_RATIO) -> bool:
	if hit_pellets <= 0:
		return false
	return hit_pellets >= kill_threshold(total_pellets, kill_ratio)


static func damage_for_hits(hit_pellets: int, total_pellets: int, total_shot_damage: float) -> int:
	var pellets := maxi(total_pellets, 1)
	var hits := clampi(hit_pellets, 0, pellets)
	if hits <= 0 or total_shot_damage <= 0.0:
		return 0
	return maxi(int(round((float(hits) / float(pellets)) * total_shot_damage)), 1)
