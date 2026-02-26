extends SceneTree

func _init():
	for m_variant in ClassDB.class_get_method_list("Engine", true):
		var m := m_variant as Dictionary
		var name := String(m.get("name", ""))
		if name.findn("error") >= 0 or name.findn("warning") >= 0:
			print(name)
	quit()
