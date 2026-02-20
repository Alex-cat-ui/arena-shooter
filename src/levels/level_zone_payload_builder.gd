extends RefCounted
class_name LevelZonePayloadBuilder


static func build_zone_payload(navigation_service: Node) -> Array:
	var zone_config: Array[Dictionary] = []
	var zone_edges: Array[Array] = []
	if not navigation_service or not navigation_service.has_method("build_zone_config_from_layout"):
		return [zone_config, zone_edges]

	var raw_payload: Variant = navigation_service.call("build_zone_config_from_layout")
	if not (raw_payload is Array):
		return [zone_config, zone_edges]
	var payload := raw_payload as Array
	if payload.size() < 2:
		return [zone_config, zone_edges]

	for zone_variant in (payload[0] as Array):
		var zone := zone_variant as Dictionary
		if zone.is_empty():
			continue
		zone_config.append(zone.duplicate(true))

	for edge_variant in (payload[1] as Array):
		var edge := edge_variant as Array
		if edge.size() < 2:
			continue
		zone_edges.append([int(edge[0]), int(edge[1])])
	return [zone_config, zone_edges]
