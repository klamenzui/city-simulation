shader_type spatial;
render_mode blend_mix, unshaded;

uniform vec4 tint_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;

void fragment() {
    vec4 tex = texture(albedo_texture, UV);
    ALBEDO = tex.rgb * tint_color.rgb;
    ALPHA = tex.a * tint_color.a;
}