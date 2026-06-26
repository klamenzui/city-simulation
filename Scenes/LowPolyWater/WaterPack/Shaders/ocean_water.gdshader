shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D normal_large : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_small : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D caustics_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D flow_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D foam_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D shore_mask : source_color, repeat_disable, filter_linear;

uniform vec4 deep_color : source_color = vec4(0.010, 0.110, 0.275, 0.96);
uniform vec4 mid_color : source_color = vec4(0.022, 0.340, 0.605, 0.86);
uniform vec4 shallow_color : source_color = vec4(0.082, 0.745, 0.845, 0.58);
uniform vec4 shore_color : source_color = vec4(0.390, 0.935, 0.905, 0.50);
uniform vec4 highlight_color : source_color = vec4(0.760, 0.980, 0.950, 1.0);
uniform vec4 foam_color : source_color = vec4(0.992, 0.996, 0.994, 1.0);

uniform float uv_scale = 0.0105;
uniform float flow_scale = 0.0028;
uniform float flow_strength = 0.072;
uniform float wave_speed = 0.040;
uniform float small_wave_speed = 0.066;
uniform float normal_strength = 0.135;
uniform float wave_height = 0.052;

uniform vec2 current_direction = vec2(0.82, 0.36);
uniform float current_speed = 13.0;
uniform vec2 primary_wave_direction = vec2(0.84, 0.31);
uniform vec2 secondary_wave_direction = vec2(-0.38, 0.93);
uniform float primary_wave_height = 0.135;
uniform float secondary_wave_height = 0.065;
uniform float primary_wave_scale = 0.022;
uniform float secondary_wave_scale = 0.036;
uniform float primary_wave_speed = 0.92;
uniform float secondary_wave_speed = 1.32;
uniform float surface_drift_strength = 1.0;

uniform float water_pattern_strength = 0.030;
uniform float water_pattern_scale = 0.0025;
uniform float surface_line_strength = 0.020;
uniform float caustics_strength = 0.022;

uniform vec2 water_center_xz = vec2(0.0, 0.0);
uniform vec2 water_size_xz = vec2(2200.0, 3200.0);
uniform float shore_mask_strength = 1.0;
uniform float shore_color_strength = 0.82;
uniform float foam_strength = 0.96;
uniform float foam_noise_scale = 0.016;
uniform float foam_noise_speed = 0.060;

uniform float deep_alpha = 0.998;
uniform float shallow_alpha = 0.925;
uniform float land_mask_cut_strength = 1.0;
uniform float fresnel_power = 4.0;
uniform float emission_strength = 0.006;

varying vec3 world_position;
varying float wave_light;
varying float large_wave_light;

mat2 rotate2d(float a) {
	float s = sin(a);
	float c = cos(a);
	return mat2(vec2(c, -s), vec2(s, c));
}

vec2 safe_normalize(vec2 v) {
	float l = max(length(v), 0.001);
	return v / l;
}

vec2 shore_uv_from_world(vec2 world_xz) {
	return clamp((world_xz - water_center_xz) / max(water_size_xz, vec2(0.001)) + vec2(0.5), vec2(0.001), vec2(0.999));
}

vec2 moving_water_xz(vec2 world_xz) {
	return world_xz + safe_normalize(current_direction) * TIME * current_speed * surface_drift_strength;
}

float foam_breakup(vec2 world_xz, vec2 flow) {
	float a = texture(foam_tex, world_xz * foam_noise_scale + flow * TIME * 0.36 + vec2(TIME * foam_noise_speed, -TIME * foam_noise_speed * 0.35)).a;
	float b = texture(caustics_tex, rotate2d(0.62) * world_xz * foam_noise_scale * 0.62 - flow.yx * TIME * 0.25 + vec2(-TIME * 0.020, TIME * 0.013)).g;
	float c = texture(noise_tex, rotate2d(-0.38) * world_xz * foam_noise_scale * 0.35 + vec2(TIME * 0.008, TIME * 0.006)).r;
	return smoothstep(0.34, 0.82, a * 0.50 + b * 0.35 + c * 0.15);
}

float soft_water_pattern(vec2 world_xz) {
	vec2 moving_xz = moving_water_xz(world_xz);
	float a = texture(noise_tex, rotate2d(0.41) * moving_xz * water_pattern_scale + vec2(TIME * 0.0010, -TIME * 0.0007)).r;
	float b = texture(noise_tex, rotate2d(-0.77) * moving_xz * water_pattern_scale * 2.15 + vec2(-TIME * 0.0014, TIME * 0.0010)).r;
	float c = texture(flow_tex, rotate2d(1.10) * moving_xz * water_pattern_scale * 0.72 + vec2(TIME * 0.0006, TIME * 0.0004)).b;
	float d = texture(caustics_tex, rotate2d(-0.22) * moving_xz * water_pattern_scale * 1.36 + vec2(-TIME * 0.0012, -TIME * 0.0005)).g;
	return a * 0.38 + b * 0.27 + c * 0.20 + d * 0.15;
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 world_xz = world.xz;
	vec2 moving_xz = moving_water_xz(world_xz);
	vec2 d1 = safe_normalize(primary_wave_direction);
	vec2 d2 = safe_normalize(secondary_wave_direction);
	vec2 flow = (texture(flow_tex, moving_xz * flow_scale + vec2(TIME * 0.0013, -TIME * 0.0011)).rg * 2.0 - 1.0) * flow_strength;

	float long_wave_a = sin(dot(world_xz, d1) * primary_wave_scale + TIME * primary_wave_speed) * primary_wave_height;
	float long_wave_b = sin(dot(world_xz, d2) * secondary_wave_scale + TIME * secondary_wave_speed) * secondary_wave_height;
	float n1 = texture(noise_tex, rotate2d(0.35) * moving_xz * 0.008 + flow * TIME * 0.13 + vec2(TIME * 0.006, -TIME * 0.004)).r;
	float n2 = texture(noise_tex, rotate2d(-0.67) * moving_xz * 0.019 - flow.yx * TIME * 0.11 + vec2(-TIME * 0.005, TIME * 0.008)).r;
	float small_wave = ((n1 - 0.5) * 0.55 + (n2 - 0.5) * 0.30) * wave_height;
	float wave = long_wave_a + long_wave_b + small_wave;

	VERTEX.y += wave;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wave_light = clamp(small_wave / max(wave_height, 0.001) * 0.5 + 0.5, 0.0, 1.0);
	large_wave_light = clamp((long_wave_a + long_wave_b) / max(primary_wave_height + secondary_wave_height, 0.001) * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	vec2 world_xz = world_position.xz;
	vec2 moving_xz = moving_water_xz(world_xz);
	vec2 flow = (texture(flow_tex, moving_xz * flow_scale + vec2(TIME * 0.0022, -TIME * 0.0016)).rg * 2.0 - 1.0) * flow_strength;

	vec2 uv = moving_xz * uv_scale;
	vec2 uv_a = rotate2d(0.19) * uv + flow * TIME * wave_speed + vec2(TIME * 0.010, TIME * 0.004);
	vec2 uv_b = rotate2d(-0.58) * uv * 1.70 - flow.yx * TIME * small_wave_speed + vec2(-TIME * 0.013, TIME * 0.010);

	vec3 n_large = texture(normal_large, uv_a).rgb;
	vec3 n_small = texture(normal_small, uv_b).rgb;
	vec2 normal_xy = (n_large.xy - 0.5) + (n_small.xy - 0.5) * 0.42;
	vec3 final_normal = normalize(vec3(normal_xy * normal_strength, 1.0));
	NORMAL_MAP = final_normal * 0.5 + 0.5;

	vec4 shore_data = texture(shore_mask, shore_uv_from_world(world_xz));
	float shore_gradient = clamp(shore_data.r * shore_mask_strength, 0.0, 1.0);
	float foam_mask = clamp(shore_data.g * shore_mask_strength, 0.0, 1.0);
	float land_mask = clamp(shore_data.b, 0.0, 1.0);
	float land_fade = smoothstep(0.12, 0.70, land_mask);

	float patch = soft_water_pattern(world_xz);
	float patch_soft = smoothstep(0.20, 0.88, patch);

	vec3 water_col = mix(deep_color.rgb, mid_color.rgb, patch_soft * 0.30);
	water_col = mix(water_col, mid_color.rgb, shore_gradient * 0.16);
	water_col = mix(water_col, shallow_color.rgb, shore_gradient * shore_color_strength);
	water_col = mix(water_col, shore_color.rgb, pow(shore_gradient, 1.75) * 0.14);
	water_col += (patch - 0.5) * water_pattern_strength * vec3(0.04, 0.10, 0.11);
	water_col += (wave_light - 0.5) * 0.010;
	water_col += (large_wave_light - 0.5) * 0.020;

	float line_a = texture(caustics_tex, rotate2d(0.18) * uv * 0.36 + flow * TIME * 0.16 + vec2(TIME * 0.006, -TIME * 0.003)).g;
	float line_b = texture(caustics_tex, rotate2d(-0.72) * uv * 0.64 - flow.yx * TIME * 0.12 + vec2(-TIME * 0.005, TIME * 0.006)).g;
	float surface_lines = smoothstep(0.41, 0.58, max(line_a, line_b * 0.82));
	water_col += highlight_color.rgb * surface_lines * surface_line_strength;

	float caust = smoothstep(0.38, 0.56, texture(caustics_tex, rotate2d(0.51) * uv * 0.27 + flow * TIME * 0.16).g);
	water_col += highlight_color.rgb * caust * caustics_strength * (0.16 + shore_gradient * 0.80);

	float edge_noise = foam_breakup(moving_xz, flow);
	float edge_noise_2 = texture(noise_tex, rotate2d(0.35) * moving_xz * 0.020 + flow * TIME * 0.12 + vec2(TIME * 0.010, -TIME * 0.007)).r;
	float edge_phase = 0.5 + 0.5 * sin(TIME * 1.55 + world_xz.x * 0.040 - world_xz.y * 0.031 + edge_noise * 3.2);

	float edge_foam = foam_mask;
	edge_foam *= mix(0.84, 1.0, edge_noise);
	edge_foam *= mix(0.90, 1.0, edge_noise_2);
	edge_foam *= (1.0 - land_fade);

	float wash_noise_a = texture(foam_tex, rotate2d(-0.26) * moving_xz * 0.011 - flow.yx * TIME * 0.17 + vec2(-TIME * 0.012, TIME * 0.009)).r;
	float wash_noise_b = texture(noise_tex, rotate2d(0.81) * moving_xz * 0.015 + flow * TIME * 0.09 + vec2(TIME * 0.006, TIME * 0.005)).r;
	float shore_push = 0.5 + 0.5 * sin(TIME * 1.35 + world_xz.x * 0.024 + world_xz.y * 0.020 + wash_noise_a * 3.0);
	float surge_center = mix(0.955, 0.992, shore_push);
	float surge_half = 0.016;
	float wash_band = smoothstep(surge_center - surge_half, surge_center, shore_gradient) * (1.0 - smoothstep(surge_center, surge_center + surge_half, shore_gradient));
	float wash_shape = smoothstep(0.70, 0.88, wash_noise_a * 0.58 + wash_noise_b * 0.42);
	float surge_foam = wash_band * wash_shape * (1.0 - land_fade);

	float contact_foam = edge_foam * mix(0.45, 1.00, shore_push);
	float foam = clamp(contact_foam * 1.05 + surge_foam * 0.82, 0.0, 1.0) * foam_strength;
	float foam_mix = smoothstep(0.05, 0.16, foam);
	water_col = mix(water_col, foam_color.rgb, foam_mix);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float alpha = mix(deep_alpha, shallow_alpha, shore_gradient);
	alpha = clamp(alpha + fresnel * 0.010 + foam_mix * 0.010, 0.0, 0.998);
	alpha *= 1.0 - clamp(land_fade * land_mask_cut_strength, 0.0, 0.999);

	ALBEDO = water_col;
	ALPHA = alpha;
	ROUGHNESS = 0.32;
	SPECULAR = 0.55;
	METALLIC = 0.0;
	EMISSION = water_col * emission_strength + foam_color.rgb * foam_mix * 0.007;
}
