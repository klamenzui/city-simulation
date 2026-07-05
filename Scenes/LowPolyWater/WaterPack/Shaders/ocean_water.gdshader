shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform sampler2D normal_large : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D normal_small : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D caustics_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D noise_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D flow_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D foam_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D shore_mask : source_color, repeat_disable, filter_linear;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;

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
// Gerstner choppiness: 0 = plain vertical swell, higher = sharper peaks / flatter
// troughs (horizontal pinch). Also drives the whitecap foam via the Jacobian.
uniform float wave_steepness : hint_range(0.0, 1.0) = 0.9;
// Shared wave time (set from GDScript). The buoyancy get_height() uses the SAME
// value so floating objects sit on the exact rendered wave, not a desynced one.
uniform float wave_time = 0.0;

uniform float water_pattern_strength = 0.030;
uniform float water_pattern_scale = 0.0025;
uniform float surface_line_strength = 0.020;
uniform float caustics_strength = 0.022;

uniform vec2 water_center_xz = vec2(0.0, 0.0);
uniform vec2 water_size_xz = vec2(2200.0, 3200.0);
uniform float shore_mask_strength = 1.0;
// Hard cut: discard the water entirely where the shore mask says land. The water
// is simply not drawn over the islands, so it can never poke / bleed through them.
uniform float land_cut = 0.5;
// Mask-independent land clip (the reliable one): uses the real scene depth. Where
// solid terrain right behind the water rises above the water level, there is land
// -> discard. water_base_y is the flat water level, set from GDScript.
uniform float water_base_y = 0.0;
uniform float land_clip_distance = 6.0; // only clip terrain THIS close behind the water
uniform float land_clip_margin = 0.25;  // terrain this far above water level = land
uniform float shore_color_strength = 0.82;
uniform float foam_strength = 0.96;
uniform float foam_noise_scale = 0.016;
uniform float foam_noise_speed = 0.060;

// Contact foam shaping by category (shore_mask.a): sand=1.0, rock=0.7,
// structure=0.45, prop=0.2. Same waterline foam, different density/texture/behavior.
uniform float contact_foam_sand = 1.25;       // density on soft sandy shores
uniform float contact_foam_prop = 0.40;       // density on props/structures
uniform float contact_surge_strength = 1.0;   // rolling wash, mostly on sand
uniform float contact_speckle_strength = 0.9; // tight flecks on hard objects
uniform float contact_speckle_scale = 0.12;
uniform float foam_clump_scale = 0.09;        // shore foam clump size (gaps in the line)

// Whitecap foam on wave crests, from the Gerstner displacement Jacobian (the
// surface folds where the determinant drops). Ported idea from FFT oceans, done
// analytically here. Higher compression than the threshold turns to foam.
uniform float whitecap_strength = 0.8;
uniform float whitecap_threshold = 0.10;
uniform float whitecap_noise_scale = 0.06;

// --- Depth-based water (scene DEPTH_TEXTURE, Forward+) ---
// Real water column depth from the geometry behind the surface. Drives the
// shallow/deep color ("low area" detection + transition) and the foam rim
// around anything sitting in the water (shore, piers, boats) automatically.
uniform float depth_shallow_distance = 2.5;
uniform float depth_deep_distance = 22.0;
uniform float intersection_foam_depth = 1.6;
uniform float intersection_foam_strength = 0.9;
uniform float depth_transparency_strength : hint_range(0.0, 1.0) = 0.5;

// --- Surface texture detail (so the water is not a flat colour fill) ---
uniform float surface_detail_strength = 0.18;
uniform float surface_detail_scale = 0.05;

// --- Dynamic wake foam from moving floating objects ---
// Filled each frame from GDScript (LowPolyWaterPlane.report_disturbance):
// xy = world xz, z = radius, w = strength. count 0 = nothing (no cost).
uniform int disturbance_count = 0;
uniform vec4 disturbances[12];

// --- Tide & shoreline wash ---
// Slow tide raises/lowers the whole water level; the wash makes the shore foam
// run up and pull back rhythmically (waves hitting the coast) instead of a band.
uniform float tide_speed = 0.05;       // ebb/flow rate (rad/sec; ~125 s period)
uniform float tide_height = 0.6;       // real water-level rise/fall (world units)
uniform float wash_depth_range = 3.0;  // depth band the shore wash foam lives in
uniform float wash_speed = 1.1;        // run-up rhythm
uniform float wash_reach = 0.12;       // how far the wash pulls back (0..1 of range)
uniform float wash_width = 0.06;       // foam band thickness (0..1 of range)

uniform float deep_alpha = 0.998;
uniform float shallow_alpha = 0.925;
uniform float land_mask_cut_strength = 1.0;
uniform float fresnel_power = 4.0;
uniform float emission_strength = 0.006;

// --- Stylized open-water pass ---
// Cheap Fresnel sky reflection (no SSR, works in GL Compatibility). Open water
// picks up the sky gradient at grazing angles instead of reading as a flat grey
// sheet. This is the main fix for dull open water seen from a low camera.
uniform vec4 sky_zenith_color : source_color = vec4(0.34, 0.55, 0.76, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.58, 0.74, 0.88, 1.0);
uniform float sky_reflection_strength = 0.45;

// Sun sparkle: high-frequency twinkling glints, brighter at grazing angles.
uniform vec4 sun_glint_color : source_color = vec4(1.0, 0.97, 0.86, 1.0);
uniform float sun_glint_strength = 0.45;
uniform float sun_glint_scale = 0.05;
uniform float sun_glint_sharpness = 6.0;

// --- Low-poly stylization ---
// Faceting: flat per-fragment geometric normals so the wave geometry catches
// light as hard facets instead of a smooth sheet. 0 = smooth, 1 = full facets.
uniform float facet_strength : hint_range(0.0, 1.0) = 1.0;
// Toon color banding of the coastal depth gradient. 0 = smooth, 1 = hard steps.
uniform float band_strength : hint_range(0.0, 1.0) = 0.7;
uniform float color_bands = 4.0;

varying vec3 world_position;
varying vec3 wave_normal;
varying float wave_light;
varying float large_wave_light;
varying float crest_fold;

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
	vec2 flow = (texture(flow_tex, moving_xz * flow_scale + vec2(TIME * 0.0013, -TIME * 0.0011)).rg * 2.0 - 1.0) * flow_strength;

	// Sum several Gerstner octaves coming from DIFFERENT directions so the surface
	// is a natural criss-cross of swells instead of one set of parallel ridges all
	// marching the same way. Directions are the primary direction rotated apart,
	// each with its own wavelength and speed. Total height stays ~master_amp.
	vec2 base_dir = safe_normalize(primary_wave_direction);
	float master_amp = primary_wave_height + secondary_wave_height;
	float wave_angles[4] = float[](0.0, 1.15, -0.75, 2.30);
	float wave_amp[4] = float[](1.0, 0.62, 0.45, 0.28);
	float wave_scl[4] = float[](1.0, 1.8, 2.7, 4.1);
	float wave_spd[4] = float[](1.0, 1.27, 0.82, 1.55);
	float amp_sum = 2.35; // == sum(wave_amp), normalises the total height

	float gy = 0.0;
	float gx = 0.0;
	float gz = 0.0;
	float jxx = 1.0;
	float jzz = 1.0;
	float jxz = 0.0;
	float dHx = 0.0;
	float dHz = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 di = rotate2d(wave_angles[i]) * base_dir;
		float ki = primary_wave_scale * wave_scl[i];
		float ai = master_amp * wave_amp[i] / amp_sum;
		float phi = dot(world_xz, di) * ki + wave_time * primary_wave_speed * wave_spd[i];
		float si = sin(phi);
		float ci = cos(phi);
		gy += si * ai;
		gx += wave_steepness * di.x * ai * ci;
		gz += wave_steepness * di.y * ai * ci;
		jxx += -wave_steepness * ki * ai * di.x * di.x * si;
		jzz += -wave_steepness * ki * ai * di.y * di.y * si;
		jxz += -wave_steepness * ki * ai * di.x * di.y * si;
		dHx += ai * ki * di.x * ci;
		dHz += ai * ki * di.y * ci;
	}

	float n1 = texture(noise_tex, rotate2d(0.35) * moving_xz * 0.008 + flow * TIME * 0.13 + vec2(TIME * 0.006, -TIME * 0.004)).r;
	float n2 = texture(noise_tex, rotate2d(-0.67) * moving_xz * 0.019 - flow.yx * TIME * 0.11 + vec2(-TIME * 0.005, TIME * 0.008)).r;
	float small_wave = ((n1 - 0.5) * 0.55 + (n2 - 0.5) * 0.30) * wave_height;

	// Damp waves near the shore so the steeper open-water waves do not pump up
	// and down through the beach. Uses the same shore mask the fragment reads.
	vec4 shore_v4 = texture(shore_mask, shore_uv_from_world(world_xz));
	float shore_grad_v = clamp(shore_v4.r * shore_mask_strength, 0.0, 1.0);
	float land_v = clamp(shore_v4.b, 0.0, 1.0);
	float wave_damping = mix(1.0, 0.22, smoothstep(0.12, 0.82, shore_grad_v));
	// Flatten the water over land so the taller waves / tide do not poke up through
	// the islands / city. shore_grad is 0 over land too, so it alone would not damp.
	// Aggressive (kills as soon as we approach land) to stop foam bleeding inland.
	wave_damping *= 1.0 - smoothstep(0.05, 0.35, land_v);

	// Smooth analytic wave normal from the summed multi-direction height gradient.
	wave_normal = normalize(vec3(-dHx * wave_damping, 1.0, -dHz * wave_damping));

	VERTEX.x += gx * wave_damping;
	VERTEX.z += gz * wave_damping;
	VERTEX.y += (gy + small_wave) * wave_damping;
	// Real tide: slow uniform rise/fall of the water level. The depth-driven foam
	// and shallow colour follow it, so the shoreline visibly ebbs and flows. Faded
	// out over solid land so it never lifts water up inside the islands / city.
	VERTEX.y += sin(TIME * tide_speed) * tide_height * (1.0 - smoothstep(0.35, 0.75, land_v));
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;

	crest_fold = max(0.0, 1.0 - (jxx * jzz - jxz * jxz));
	wave_light = clamp(small_wave / max(wave_height, 0.001) * 0.5 + 0.5, 0.0, 1.0);
	large_wave_light = clamp(gy / max(primary_wave_height + secondary_wave_height, 0.001) * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	vec2 world_xz = world_position.xz;
	vec2 moving_xz = moving_water_xz(world_xz);
	vec2 flow = (texture(flow_tex, moving_xz * flow_scale + vec2(TIME * 0.0022, -TIME * 0.0016)).rg * 2.0 - 1.0) * flow_strength;

	// Reconstruct the linear distance to the opaque geometry behind the water and
	// subtract the surface distance to get the real water-column depth. Official
	// Godot depth-reconstruction snippet; works on Forward+.
	float scene_depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 depth_ndc = vec4(SCREEN_UV * 2.0 - 1.0, scene_depth_raw, 1.0);
	vec4 depth_view = INV_PROJECTION_MATRIX * depth_ndc;
	depth_view.xyz /= depth_view.w;
	vec3 world_behind = (INV_VIEW_MATRIX * vec4(depth_view.xyz, 1.0)).xyz;

	// VERTICAL water-column depth (surface Y minus seabed/terrain Y). View-independent,
	// so the shallow colour does NOT follow the camera the way an along-ray depth does.
	float water_depth = max(world_position.y - world_behind.y, 0.0);
	// Along-ray distance only for the land-clip proximity gate.
	float view_dist = max(-depth_view.z - (-VERTEX.z), 0.0);

	// Mask-independent land clip: if the opaque geometry right behind this water
	// pixel sits above the water level, there is land here - discard so no water is
	// ever drawn over / through the islands. The distance gate stops far shores and
	// hills from punching holes in the open sea in front of them.
	if (view_dist < land_clip_distance && world_behind.y > water_base_y + land_clip_margin) {
		discard;
	}

	vec2 uv = moving_xz * uv_scale;
	vec2 uv_a = rotate2d(0.19) * uv + flow * TIME * wave_speed + vec2(TIME * 0.010, TIME * 0.004);
	vec2 uv_b = rotate2d(-0.58) * uv * 1.70 - flow.yx * TIME * small_wave_speed + vec2(-TIME * 0.013, TIME * 0.010);

	vec3 n_large = texture(normal_large, uv_a).rgb;
	vec3 n_small = texture(normal_small, uv_b).rgb;
	vec2 normal_xy = (n_large.xy - 0.5) + (n_small.xy - 0.5) * 0.42;
	vec3 final_normal = normalize(vec3(normal_xy * normal_strength, 1.0));
	NORMAL_MAP = final_normal * 0.5 + 0.5;

	// Base shading normal: smooth analytic wave normal for pretty rounded light,
	// with the flat per-facet normal mixed in by facet_strength (0 = smooth,
	// 1 = hard low-poly facets). The fine ripple normal map rides on top.
	vec3 face_world_n = normalize(cross(dFdx(world_position), dFdy(world_position)));
	face_world_n *= sign(face_world_n.y + 0.0001);
	vec3 base_world_n = normalize(mix(normalize(wave_normal), face_world_n, facet_strength));
	NORMAL = normalize((VIEW_MATRIX * vec4(base_world_n, 0.0)).xyz);

	vec4 shore_data = texture(shore_mask, shore_uv_from_world(world_xz));
	float shore_gradient = clamp(shore_data.r * shore_mask_strength, 0.0, 1.0);
	float foam_mask = clamp(shore_data.g * shore_mask_strength, 0.0, 1.0);
	float land_mask = clamp(shore_data.b, 0.0, 1.0);
	// No water under land: discard these fragments outright. This is the robust fix
	// for water showing through the islands - nothing is drawn over land at all.
	if (land_mask > land_cut) {
		discard;
	}
	// Land cut: only strong, solid land kills the water. The shoreline edge is
	// handled by real depth occlusion + the depth fade below, so the tide can flood
	// the beach fringe (the water level actually moves) without the baked mask
	// clipping it.
	float land_fade = smoothstep(0.35, 0.70, land_mask);

	// Contact category from the shore-mask alpha: 1.0 sand, 0.7 rock, 0.45
	// structure (pier/bridge), 0.2 prop (boat/buoy). Drives how the contact foam
	// looks and behaves so different objects foam differently.
	float contact_cat = clamp(shore_data.a, 0.0, 1.0);
	float sand_w = smoothstep(0.55, 1.0, contact_cat);
	float hard_w = 1.0 - smoothstep(0.25, 0.55, contact_cat);
	float foam_density = mix(contact_foam_prop, contact_foam_sand, smoothstep(0.2, 1.0, contact_cat));

	// Toon banding driver: quantize the coastal depth gradient into discrete
	// steps for the color mixes. Foam and alpha keep the smooth gradient.
	float sg = mix(shore_gradient, floor(shore_gradient * color_bands + 0.5) / max(color_bands, 1.0), band_strength);

	// Smooth coastal shallowness from the horizontal shore distance ONLY (no vertical
	// depth -> no razor-sharp ring on the steep underwater cliffs). The pow widens the
	// visible shallow band out from the coast while keeping a soft natural falloff.
	float shallowness = pow(smoothstep(0.0, 1.0, sg), 0.6);
	float shallow_banded = mix(shallowness, floor(shallowness * color_bands + 0.5) / max(color_bands, 1.0), band_strength);

	float patch = soft_water_pattern(world_xz);

	vec3 water_col = mix(deep_color.rgb, mid_color.rgb, smoothstep(0.0, 0.5, shallow_banded));
	water_col = mix(water_col, shallow_color.rgb, smoothstep(0.08, 0.82, shallow_banded) * shore_color_strength);
	water_col = mix(water_col, shore_color.rgb, smoothstep(0.78, 1.0, shallow_banded) * 0.45);

	// Surface texture: mottled detail so the water reads as a textured surface
	// instead of a flat colour fill.
	float detail = texture(noise_tex, world_xz * surface_detail_scale + flow * TIME * 0.05 + vec2(TIME * 0.012, -TIME * 0.009)).r;
	float detail2 = texture(caustics_tex, world_xz * surface_detail_scale * 1.9 - flow.yx * TIME * 0.04 + vec2(-TIME * 0.010, TIME * 0.006)).g;
	water_col *= 1.0 + ((detail * 0.6 + detail2 * 0.4) - 0.5) * surface_detail_strength;

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

	// Shoreline wash: a foam band that rhythmically runs UP toward the shore and
	// pulls back (waves hitting the coast), shifted slowly by the tide. Driven by
	// distance-from-shore so the foam actually MOVES instead of sitting as one line.
	// Distance from the coastline in the WATER (baked shore gradient hugs the coast
	// tightly): 0 right at the water's edge, growing seaward. Keeps the foam on the
	// water edge instead of spreading across shallow lagoons.
	float from_shore = clamp(1.0 - shore_gradient, 0.0, 1.0);
	float run_up = 0.5 - 0.5 * cos(TIME * wash_speed + dot(world_xz, vec2(0.022, 0.019)) + edge_noise * 6.2831);
	float wash_front = mix(wash_reach, 0.0, run_up);
	float wash_bandw = wash_width * mix(0.7, 1.5, sand_w);
	float wash_band = smoothstep(wash_front - wash_bandw, wash_front, from_shore) * (1.0 - smoothstep(wash_front, wash_front + wash_bandw, from_shore));
	// Brightest at the leading edge of the run-up; fades as the wave recedes.
	float wash_foam = wash_band * (0.35 + 0.65 * run_up) * (1.0 - land_fade) * foam_density * mix(0.55, 1.0, edge_noise_2) * contact_surge_strength;

	// Speckle: tight high-frequency flecks clinging to hard contacts (rock, pier,
	// boat) instead of the soft rolling band sand gets.
	float speckle_n = texture(noise_tex, world_xz * contact_speckle_scale + flow * TIME * 0.22 + vec2(TIME * 0.05, -TIME * 0.04)).r;
	float speckle_foam = foam_mask * smoothstep(0.62, 0.93, speckle_n) * hard_w * contact_speckle_strength * (1.0 - land_fade);

	// Whitecaps: foam on open-water crests where the Gerstner surface folds.
	// Two noise octaves break the crest into specks of foam instead of one solid
	// white patch covering the whole wave face.
	float fold = smoothstep(whitecap_threshold, whitecap_threshold + 0.18, crest_fold);
	float whitecap_n = texture(noise_tex, world_xz * whitecap_noise_scale + flow * TIME * 0.2 + vec2(TIME * 0.03, -TIME * 0.02)).r;
	float whitecap_n2 = texture(noise_tex, world_xz * whitecap_noise_scale * 2.7 + flow.yx * TIME * 0.15 + vec2(-TIME * 0.02, TIME * 0.014)).r;
	float whitecap = fold * smoothstep(0.55, 0.92, whitecap_n) * smoothstep(0.40, 0.80, whitecap_n2) * whitecap_strength * (1.0 - land_fade);

	// Intersection foam: white rim where the water meets ANY geometry in contact
	// with it (shore, piers, boats) - from real depth, so it is automatic and
	// dynamic (follows a bobbing boat without a baked mask).
	float depth_foam = (1.0 - smoothstep(0.0, intersection_foam_depth, water_depth)) * intersection_foam_strength;
	depth_foam *= mix(0.6, 1.0, edge_noise);
	// Pulse the contact rim so it reads as water washing against the object and
	// receding, not a static ring sitting around it.
	depth_foam *= mix(0.4, 1.0, 0.5 - 0.5 * cos(TIME * wash_speed + dot(world_xz, vec2(0.05, 0.043))));

	// Break the shoreline + contact foam into irregular clumps with gaps instead
	// of a solid continuous outline (reference look). Two noise octaves carve holes.
	float foam_break = smoothstep(0.30, 0.62,
		texture(foam_tex, world_xz * foam_clump_scale + flow * TIME * 0.05 + vec2(TIME * 0.012, -TIME * 0.009)).a * 0.6 +
		texture(noise_tex, world_xz * foam_clump_scale * 2.3 - flow.yx * TIME * 0.04 + vec2(-TIME * 0.01, TIME * 0.014)).r * 0.4);
	wash_foam *= foam_break;
	depth_foam *= mix(0.30, 1.0, foam_break);

	// Dynamic WAKE foam behind moving boats (points fed from GDScript). Soft blobs
	// broken up by a fast churn noise so it reads as turbulent foam, not a solid
	// white blob dragged behind the boat.
	float dyn_raw = 0.0;
	for (int i = 0; i < 12; i++) {
		if (i >= disturbance_count) { break; }
		vec4 d = disturbances[i];
		float dd = distance(world_xz, d.xy);
		dyn_raw += d.w * (1.0 - smoothstep(d.z * 0.30, d.z, dd));
	}
	float wake_churn = texture(noise_tex, world_xz * 0.15 + flow * TIME * 0.25 + vec2(TIME * 0.09, -TIME * 0.07)).r;
	float wake_churn2 = texture(foam_tex, world_xz * 0.34 - vec2(TIME * 0.05, TIME * 0.04)).a;
	float dyn_foam = clamp(dyn_raw, 0.0, 1.0) * smoothstep(0.33, 0.75, wake_churn * 0.55 + wake_churn2 * 0.45);

	float foam = clamp(wash_foam * 1.20 + speckle_foam * 0.8 + whitecap + depth_foam + dyn_foam * 1.3, 0.0, 1.0) * foam_strength;
	foam *= 1.0 - land_fade; // never any foam over land
	float foam_mix = smoothstep(0.05, 0.16, foam);
	water_col = mix(water_col, foam_color.rgb, foam_mix);

	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);

	// Fresnel sky reflection: grazing-angle water reflects the sky gradient and
	// shimmers with the ripple normal. Suppressed on foam and near land so the
	// shoreline keeps reading correctly.
	vec3 refl_n = normalize(base_world_n + vec3(final_normal.x, 0.0, final_normal.y) * 0.35);
	vec3 view_w = normalize(world_position - CAMERA_POSITION_WORLD);
	vec3 refl = reflect(view_w, refl_n);
	float sky_t = clamp(refl.y * 0.5 + 0.5, 0.0, 1.0);
	vec3 sky_col = mix(sky_horizon_color.rgb, sky_zenith_color.rgb, sky_t);
	water_col = mix(water_col, sky_col, fresnel * sky_reflection_strength * (1.0 - foam_mix) * (1.0 - land_fade));

	// Sun sparkle: high-frequency twinkling glints, stronger at grazing angles,
	// killed on foam/land. Read as light dancing on the moving surface.
	vec2 glint_uv = world_xz * sun_glint_scale;
	float g1 = texture(noise_tex, glint_uv + flow * TIME * 0.40 + vec2(TIME * 0.14, -TIME * 0.10)).r;
	float g2 = texture(noise_tex, glint_uv * 2.30 - vec2(TIME * 0.11, TIME * 0.13)).r;
	float sparkle = pow(clamp(g1 * g2, 0.0, 1.0), sun_glint_sharpness);
	float glint = sparkle * mix(0.25, 1.0, fresnel) * (1.0 - land_fade) * (1.0 - foam_mix);

	float alpha = mix(deep_alpha, shallow_alpha, shore_gradient);
	alpha = clamp(alpha + fresnel * 0.010 + foam_mix * 0.010, 0.0, 0.998);
	alpha *= 1.0 - clamp(land_fade * land_mask_cut_strength, 0.0, 0.999);
	// Shallow water gets more transparent so the seabed/sand shows through and the
	// contact line against geometry softens instead of hard-cutting.
	alpha *= mix(1.0, smoothstep(0.0, depth_shallow_distance, water_depth), depth_transparency_strength);
	alpha = max(alpha, foam_mix * 0.9 * (1.0 - land_fade));

	ALBEDO = water_col;
	ALPHA = alpha;
	ROUGHNESS = 0.32;
	SPECULAR = 0.55;
	METALLIC = 0.0;
	EMISSION = water_col * emission_strength + foam_color.rgb * foam_mix * 0.007
		+ sun_glint_color.rgb * glint * sun_glint_strength;
}
