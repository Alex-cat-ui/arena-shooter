shader_type canvas_item;
uniform vec4 tint_color : source_color = vec4(1.0, 0.0, 0.0, 1.0);
void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	float a = tex.a;
	COLOR = vec4(tint_color.rgb, tint_color.a * a);
}
