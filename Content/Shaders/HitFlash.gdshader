// HitFlash · 受击闪白共享 Shader（M8 引入）
// 适用于 AnimatedSprite2D / Sprite2D / Sprite3D（CanvasItem）
//
// 用法（CanvasItemMaterial 形式）：
//   var mat := ShaderMaterial.new()
//   mat.shader = preload("res://Content/Shaders/HitFlash.gdshader")
//   sprite.material = mat
//   # 闪白瞬间：
//   mat.set_shader_parameter("flash_strength", 1.0)
//   tween.tween_property(mat, "shader_parameter/flash_strength", 0.0, 0.08)
//
// 兼容 2D。M9 切 3D 时另写 HitFlash3D.gdshader（shader_type spatial），公共
// 接口（uniform flash_strength + flash_color）一致，HitFlashController 内
// 部按父节点类型选 material 即可。

shader_type canvas_item;

uniform vec4 flash_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float flash_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	// 把原色与 flash_color 按 flash_strength 混合，保留 alpha
	vec3 mixed = mix(base.rgb, flash_color.rgb, flash_strength);
	COLOR = vec4(mixed, base.a);
}
