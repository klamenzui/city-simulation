shader_type spatial;
// Separate shoreline-foam overlay. A flat plane over the whole water area that
// reads the scene depth and paints foam on the BEACH (the terrain) wherever the
// ground height is near the current, tide-animated waterline. depth_test_disabled
// so the foam is drawn ON the sand (not occluded by it). As the tide + wash rise
// and fall, the foam line climbs up the beach and pulls back - independent of the
// water plane, which is exactly why it can move with the tide.
render_mode blend_mix, depth_draw_never, depth_test_disabled, cull_disabled, unshaded;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;
uniform sampler2D noise_tex : source_color, repeat_enable, filter_linear_mipmap;
uniform vec4 foam_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

uniform float water_base_y = 0.0;   // flat water level (world Y), set from GDScript
uniform float tide_speed = 0.05;    // slow ebb/flow
uniform float tide_height = 0.6;    // how far the tide raises/lowers the foam line
uniform float wash_speed = 1.1;     // fast lapping run-up
uniform float wash_height = 0.5;    // how high the lapping reaches
uniform float band_up = 0.7;        // foam reach up the beach (world units)
uniform float band_down = 0.5;      // foam reach down toward the water
uniform float foam_clump_scale = 0.1;
uniform float foam_strength = 1.0;

void fragment() {
	// World position of the opaque geometry (terrain) behind this pixel.
	float d = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 ndc = vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	vec4 vpos = INV_PROJECTION_MATRIX * ndc;
	vpos.xyz /= vpos.w;
	vec3 world = (INV_VIEW_MATRIX * vec4(vpos.xyz, 1.0)).xyz;

	// Current waterline height: slow tide + fast lapping wash (per-area phase so
	// the whole coast does not pulse in sync).
	float tide = sin(TIME * tide_speed) * tide_height;
	float wash = (0.5 - 0.5 * cos(TIME * wash_speed + world.x * 0.05 + world.z * 0.043)) * wash_height;
	float line = water_base_y + tide + wash;

	// Foam sits in a band straddling that line on the terrain.
	float h = world.y - line;
	float band = smoothstep(-band_down, 0.0, h) * (1.0 - smoothstep(0.0, band_up, h));

	// Break into clumps (not a solid line).
	vec2 drift = vec2(TIME * 0.05, -TIME * 0.04);
	float n1 = texture(noise_tex, world.xz * foam_clump_scale + drift).r;
	float n2 = texture(noise_tex, world.xz * foam_clump_scale * 2.5 - drift * 1.4).r;
	float clump = smoothstep(0.42, 0.70, n1 * 0.6 + n2 * 0.4);

	float valid = step(d, 0.9999); // no foam on the sky / far plane

	ALBEDO = foam_color.rgb;
	ALPHA = clamp(band * clump * foam_strength, 0.0, 1.0) * foam_color.a * valid;
}
