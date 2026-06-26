shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D normal_large : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_small : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D caustics_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D flow_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D foam_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D shore_mask : source_color, repeat_disable, filter_linear;

uniform vec4 deep_color : source_color = vec4(0.010, 0.110, 0.275, 0.96);
uniform vec4 mid_color : source_color = vec4(0.022, 0.340, 0.605, 0.86);
uniform vec4 shallow_color : source_color = vec4(0.045, 0.520, 0.580, 0.88);
uniform vec4 shore_color : source_color = vec4(0.100, 0.620, 0.600, 0.82);
uniform vec4 highlight_color : source_color = vec4(0.760, 0.980, 0.950, 1.0);
uniform vec4 foam_color : source_color = vec4(0.992, 0.996, 0.994, 1.0);

// Fake depth colors for low-poly coastal water.
uniform vec4 fake_deep_color : source_color = vec4(0.010, 0.115, 0.245, 1.0);
uniform vec4 fake_mid_color : source_color = vec4(0.020, 0.320, 0.400, 1.0);
uniform vec4 fake_shallow_color : source_color = vec4(0.060, 0.470, 0.485, 1.0);
uniform vec4 fake_sand_edge_color : source_color = vec4(0.105, 0.585, 0.545, 1.0);

uniform float uv_scale = 0.0105;
uniform float flow_scale = 0.0028;
uniform float flow_strength = 0.024;
uniform float wave_speed = 0.032;
uniform float small_wave_speed = 0.052;
uniform float normal_strength = 0.075;
uniform float wave_height = 0.024;
// Very subtle travelling swell. This is spatial, so the whole ocean does not rise/fall at once.
uniform float swell_height = 0.055;
uniform float swell_scale = 0.006;
uniform float swell_speed = 0.32;

uniform vec2 current_direction = vec2(0.82, 0.36);
uniform float current_speed = 2.7;
uniform vec2 primary_wave_direction = vec2(0.84, 0.31);
uniform vec2 secondary_wave_direction = vec2(-0.38, 0.93);
uniform float primary_wave_height = 0.078;
uniform float secondary_wave_height = 0.034;
uniform float primary_wave_scale = 0.022;
uniform float secondary_wave_scale = 0.036;
uniform float primary_wave_speed = 0.62;
uniform float secondary_wave_speed = 0.88;
uniform float surface_drift_strength = 1.0;

uniform float water_pattern_strength = 0.014;
uniform float water_pattern_scale = 0.0025;
uniform float surface_line_strength = 0.009;
uniform float caustics_strength = 0.010;

uniform vec2 water_center_xz = vec2(0.0, 0.0);
uniform vec2 water_size_xz = vec2(2200.0, 3200.0);
uniform float shore_mask_strength = 1.0;
uniform float shore_color_strength = 0.68;
uniform float foam_strength = 0.82;
uniform float foam_noise_scale = 0.010;
uniform float foam_noise_speed = 0.038;
uniform float foam_streak_strength = 0.105;
uniform float foam_streak_length_scale = 0.026;
uniform float foam_streak_width_scale = 0.285;
uniform float foam_streak_speed = 0.13;

uniform float deep_alpha = 0.985;
uniform float shallow_alpha = 0.92;
uniform float land_mask_cut_strength = 1.0;
uniform float fresnel_power = 4.6;
uniform float emission_strength = 0.0015;

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

float soft_water_pattern(vec2 world_xz) {
	vec2 moving_xz = moving_water_xz(world_xz);
	float a = texture(noise_tex, rotate2d(0.41) * moving_xz * water_pattern_scale + vec2(TIME * 0.0010, -TIME * 0.0007)).r;
	float b = texture(noise_tex, rotate2d(-0.77) * moving_xz * water_pattern_scale * 2.15 + vec2(-TIME * 0.0014, TIME * 0.0010)).r;
	float c = texture(flow_tex, rotate2d(1.10) * moving_xz * water_pattern_scale * 0.72 + vec2(TIME * 0.0006, TIME * 0.0004)).b;
	return a * 0.42 + b * 0.33 + c * 0.25;
}

float foam_noise(vec2 world_xz, vec2 flow) {
	float a = texture(foam_tex, rotate2d(-0.18) * world_xz * foam_noise_scale + flow * TIME * 0.08 + vec2(TIME * foam_noise_speed, -TIME * foam_noise_speed * 0.33)).a;
	float b = texture(noise_tex, rotate2d(0.57) * world_xz * foam_noise_scale * 1.4 - flow.yx * TIME * 0.05).r;
	return smoothstep(0.30, 0.84, a * 0.62 + b * 0.38);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 world_xz = world.xz;
	vec2 moving_xz = moving_water_xz(world_xz);
	vec2 d1 = safe_normalize(primary_wave_direction);
	vec2 d2 = safe_normalize(secondary_wave_direction);
	vec2 flow = (texture(flow_tex, moving_xz * flow_scale + vec2(TIME * 0.0013, -TIME * 0.0011)).rg * 2.0 - 1.0) * flow_strength;
	vec4 shore_vertex_data = texture(shore_mask, shore_uv_from_world(world_xz));
	float shore_gradient_v = clamp(shore_vertex_data.r * shore_mask_strength, 0.0, 1.0);
	float edge_proximity_v = clamp(shore_vertex_data.g * shore_mask_strength, 0.0, 1.0);
	float wave_damping = mix(1.0, 0.48, smoothstep(0.08, 0.86, shore_gradient_v));
	wave_damping *= mix(1.0, 0.16, smoothstep(0.35, 0.98, edge_proximity_v));

	float long_wave_a = sin(dot(world_xz, d1) * primary_wave_scale + TIME * primary_wave_speed) * primary_wave_height;
	float long_wave_b = sin(dot(world_xz, d2) * secondary_wave_scale + TIME * secondary_wave_speed) * secondary_wave_height;
	float n1 = texture(noise_tex, rotate2d(0.35) * moving_xz * 0.008 + flow * TIME * 0.13 + vec2(TIME * 0.006, -TIME * 0.004)).r;
	float n2 = texture(noise_tex, rotate2d(-0.67) * moving_xz * 0.019 - flow.yx * TIME * 0.11 + vec2(-TIME * 0.005, TIME * 0.008)).r;
	float small_wave = ((n1 - 0.5) * 0.55 + (n2 - 0.5) * 0.30) * wave_height;

	// Wide low-poly swell: different parts of the plane move at different phases.
	// Near the shoreline it is damped, so the water does not visibly pump through the beach.
	float swell_a = sin(dot(world_xz, safe_normalize(current_direction)) * swell_scale + TIME * swell_speed) * swell_height;
	float swell_b = sin(dot(world_xz, safe_normalize(secondary_wave_direction)) * swell_scale * 0.68 + TIME * swell_speed * 0.73 + 1.8) * swell_height * 0.35;
	float swell_damping = mix(1.0, 0.28, smoothstep(0.25, 0.95, edge_proximity_v));
	float swell = (swell_a + swell_b) * swell_damping;

	float wave = (long_wave_a + long_wave_b + small_wave) * wave_damping + swell;

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
	float edge_proximity = clamp(shore_data.g * shore_mask_strength, 0.0, 1.0); // 1 near shore, 0 away
	float land_mask = clamp(shore_data.b, 0.0, 1.0);
	float shore_softness = clamp(shore_data.a, 0.0, 1.0); // 0 rock, 1 sand
	float land_fade = smoothstep(0.12, 0.70, land_mask);
	float edge_distance = 1.0 - edge_proximity;

	float patch = soft_water_pattern(world_xz);
	float patch_soft = smoothstep(0.20, 0.88, patch);

	// Fake depth: softer coastal falloff. Deep water stays readable, shallow color only near actual shore.
	float depth_mid = smoothstep(0.16, 0.74, shore_gradient);
	float depth_shallow = smoothstep(0.58, 0.96, shore_gradient);
	float sand_edge = pow(edge_proximity, 2.65) * smoothstep(0.58, 0.96, shore_softness);
	vec3 fake_depth_col = mix(fake_deep_color.rgb, fake_mid_color.rgb, depth_mid);
	fake_depth_col = mix(fake_depth_col, fake_shallow_color.rgb, depth_shallow * 0.72);
	fake_depth_col = mix(fake_depth_col, fake_sand_edge_color.rgb, sand_edge * 0.28);

	vec3 base_col = mix(deep_color.rgb, mid_color.rgb, patch_soft * 0.12);
	vec3 water_col = mix(base_col, fake_depth_col, 0.82);
	water_col += (patch - 0.5) * water_pattern_strength * vec3(0.018, 0.040, 0.045);
	water_col += (wave_light - 0.5) * 0.006;
	water_col += (large_wave_light - 0.5) * 0.012;

	float line_a = texture(caustics_tex, rotate2d(0.18) * uv * 0.36 + flow * TIME * 0.16 + vec2(TIME * 0.006, -TIME * 0.003)).g;
	float line_b = texture(caustics_tex, rotate2d(-0.72) * uv * 0.64 - flow.yx * TIME * 0.12 + vec2(-TIME * 0.005, TIME * 0.006)).g;
	float surface_lines = smoothstep(0.41, 0.58, max(line_a, line_b * 0.82));
	water_col += highlight_color.rgb * surface_lines * surface_line_strength * 0.78;

	float caust = smoothstep(0.38, 0.56, texture(caustics_tex, rotate2d(0.51) * uv * 0.27 + flow * TIME * 0.16).g);
	water_col += highlight_color.rgb * caust * caustics_strength * (0.10 + shore_gradient * 0.55);

	float n = foam_noise(moving_xz, flow);
	float sand_weight = smoothstep(0.55, 0.92, shore_softness);
	float decor_weight = smoothstep(0.18, 0.23, shore_softness) * (1.0 - smoothstep(0.31, 0.38, shore_softness));

	// Break the shoreline foam into natural short segments.
	// The distance mask defines where foam can be; these noises only remove parts of the line.
	float gap_a = texture(noise_tex, rotate2d(0.21) * world_xz * 0.006 + vec2(TIME * 0.003, -TIME * 0.002)).r;
	float gap_b = texture(noise_tex, rotate2d(-0.77) * world_xz * 0.018 + vec2(-TIME * 0.010, TIME * 0.006)).r;
	float broken_segments = smoothstep(0.39, 0.69, gap_a * 0.62 + gap_b * 0.38);
	float tiny_fragments = smoothstep(0.55, 0.86, gap_b * 0.45 + n * 0.55);
	float foam_visibility = mix(0.10, 0.92, broken_segments);
	foam_visibility = mix(foam_visibility, mix(0.22, 1.0, broken_segments), sand_weight);
	foam_visibility = mix(foam_visibility, tiny_fragments * 0.42, decor_weight);

	float contact_width = mix(0.048, 0.112, sand_weight);
	contact_width = mix(contact_width, 0.014, decor_weight);
	float contact_strength = mix(0.62, 0.90, sand_weight);
	contact_strength = mix(contact_strength, 0.14, decor_weight);
	float contact_foam = smoothstep(1.0 - contact_width, 1.0 - contact_width * 0.30, edge_proximity);
	contact_foam *= mix(0.70, 1.0, n) * contact_strength * foam_visibility;
	contact_foam *= (1.0 - land_fade);

	// Tide foam: distance-based, not texture-islands. Very thin/minimal near pier/tree/decor, wider on sand.
	float tide_phase = 0.5 - 0.5 * cos(TIME * 0.84 + dot(world_xz, safe_normalize(current_direction)) * 0.018);
	float tide_reach = mix(0.10, 0.34, sand_weight);
	tide_reach = mix(tide_reach, 0.030, decor_weight);
	float tide_width = mix(0.022, 0.062, sand_weight);
	tide_width = mix(tide_width, 0.010, decor_weight);
	float tide_center = mix(0.025, tide_reach, tide_phase);
	float tide_band = smoothstep(tide_center - tide_width, tide_center, edge_distance) * (1.0 - smoothstep(tide_center, tide_center + tide_width, edge_distance));
	float tide_strength = mix(0.38, 0.70, sand_weight);
	tide_strength = mix(tide_strength, 0.06, decor_weight);
	float tide_foam = tide_band * mix(0.70, 1.0, n) * edge_proximity * tide_strength;
	tide_foam *= mix(0.20, 1.0, broken_segments) * (1.0 - land_fade);

	// Small stretched foam streaks. They follow current_direction and only appear near shore water, not as big islands.
	vec2 flow_dir = safe_normalize(current_direction);
	vec2 flow_side = vec2(-flow_dir.y, flow_dir.x);
	float along_flow = dot(world_xz, flow_dir);
	float across_flow = dot(world_xz, flow_side);
	vec2 streak_uv = vec2(along_flow * foam_streak_length_scale - TIME * foam_streak_speed, across_flow * foam_streak_width_scale + TIME * 0.018);
	float streak_noise_a = texture(noise_tex, streak_uv).r;
	float streak_noise_b = texture(foam_tex, streak_uv * vec2(1.85, 0.72) + vec2(TIME * 0.035, -TIME * 0.012)).a;
	float streak_shape = smoothstep(0.82, 0.95, streak_noise_a) * smoothstep(0.54, 0.82, streak_noise_b);
	float streak_zone = smoothstep(0.070, 0.18, edge_distance) * (1.0 - smoothstep(0.30, 0.48, edge_distance));
	streak_zone *= smoothstep(0.12, 0.72, shore_gradient) * (1.0 - land_fade);
	streak_zone *= (1.0 - decor_weight * 0.95);
	float foam_streaks = streak_shape * streak_zone * foam_streak_strength;

	float foam = clamp(contact_foam * 0.90 + tide_foam * 0.56 + foam_streaks, 0.0, 1.0) * foam_strength;
	float foam_mix = smoothstep(0.09, 0.32, foam);
	water_col = mix(water_col, foam_color.rgb, foam_mix);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	float alpha = mix(deep_alpha, shallow_alpha, shore_gradient);
	alpha = clamp(alpha + fresnel * 0.010 + foam_mix * 0.012, 0.0, 0.998);
	alpha *= 1.0 - clamp(land_fade * land_mask_cut_strength, 0.0, 0.999);

	ALBEDO = water_col;
	ALPHA = alpha;
	ROUGHNESS = 0.42;
	SPECULAR = 0.28;
	METALLIC = 0.0;
	EMISSION = water_col * emission_strength + foam_color.rgb * foam_mix * 0.003;
}
