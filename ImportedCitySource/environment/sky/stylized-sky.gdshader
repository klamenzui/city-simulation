shader_type sky;
render_mode use_half_res_pass;

// Enhanced Stylized Sky Shader with toggles for all components

group_uniforms clouds;

uniform sampler2D cloud_shape_sampler : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloud_noise_sampler : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D cloud_curves;

uniform int clouds_samples : hint_range(8, 32, 8) = 16;
uniform int shadow_sample : hint_range(1, 4, 1) = 4;

uniform float clouds_density : hint_range(0.0, 1.0, 0.1) = 0.5;
uniform float clouds_scale : hint_range(0.5, 1.5, 0.1) = 1.0;
uniform float clouds_smoothness : hint_range(0.01, 0.1, 0.01) = 0.035;
uniform vec3 clouds_light_color : source_color;
uniform float clouds_shadow_intensity : hint_range(0.1, 10.0, 0.1) = 1.0;

group_uniforms high_clouds;

uniform sampler2D high_clouds_sampler;
uniform float high_clouds_density : hint_range(0.0, 1.0, 0.05) = 0.0;

group_uniforms sky;

uniform vec3 top_color : source_color = vec3(1.0);
uniform vec3 bottom_color : source_color = vec3(1.0);
uniform vec3 sun_scatter : source_color = vec3(1.0);

group_uniforms sun;

uniform bool sun_visible = true;
uniform vec3 sun_direction = vec3(0.0, 0.3, -1.0); // Custom direction vector for sun
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.85);
uniform sampler2D sun_sampler : repeat_disable, filter_linear_mipmap;
uniform float sun_size : hint_range(0.1, 10.0, 0.1) = 3.0;
uniform float sun_intensity : hint_range(1.0, 5.0, 0.1) = 2.0;
uniform float sun_bloom : hint_range(0.0, 2.0, 0.1) = 0.8; // Controls sun bloom/glow effect

group_uniforms moon;

uniform bool moon_visible = false;
uniform vec3 moon_position = vec3(0.0, 0.5, -1.0);
uniform sampler2D moon_sampler : repeat_disable, filter_linear_mipmap;
uniform float moon_size : hint_range(0.1, 10.0, 0.1) = 4.0;
uniform float moon_phase : hint_range(0.0, 1.0, 0.01) = 0.0; // 0=new, 0.5=full
uniform float moon_brightness : hint_range(0.1, 3.0, 0.1) = 1.0;
uniform vec3 moon_tint : source_color = vec3(0.9, 0.9, 1.0); // Slight blue tint for moon

group_uniforms planets;

// Planet 1 (Venus)
uniform bool planet1_visible = false;
uniform vec3 planet1_position = vec3(0.3, 0.4, -1.0);
uniform float planet1_size : hint_range(0.1, 5.0, 0.1) = 2.0;
uniform vec3 planet1_color : source_color = vec3(1.0, 0.95, 0.8);

// Planet 2 (Mars)
uniform bool planet2_visible = false;
uniform vec3 planet2_position = vec3(-0.5, 0.3, -1.0);
uniform float planet2_size : hint_range(0.1, 5.0, 0.1) = 1.5;
uniform vec3 planet2_color : source_color = vec3(1.0, 0.6, 0.4);

// Planet 3 (Jupiter)
uniform bool planet3_visible = false;
uniform vec3 planet3_position = vec3(0.6, 0.2, -1.0);
uniform float planet3_size : hint_range(0.1, 5.0, 0.1) = 3.0;
uniform vec3 planet3_color : source_color = vec3(0.9, 0.85, 0.75);

group_uniforms stars;

uniform float stars_intensity : hint_range(0.0, 5.0, 0.1) = 0.0;
uniform vec3 stars_tint : source_color = vec3(1.0, 1.0, 1.0);
uniform float stars_scintillation : hint_range(0.0, 1.0, 0.1) = 0.5; // How much stars twinkle

group_uniforms shooting_stars;

uniform float shooting_stars_intensity : hint_range(0.0, 0.5, 0.1) = 0.0;
uniform sampler2D shooting_star_sampler : filter_linear, repeat_disable;
uniform vec3 shooting_star_tint : source_color;

float rand(float n) {
    return fract(sin(n) * 43758.5453123);
}

vec3 hash(vec3 x) {
	x = vec3(dot(x, vec3(127.1, 311.7, 74.7)),
			  dot(x, vec3(269.5, 183.3, 246.1)),
			  dot(x, vec3(113.5, 271.9, 124.6)));
	return fract(sin(x) * 43758.5453123);
}

vec3 voronoi(in vec3 x) {
	vec3 p = floor(x);
	vec3 f = fract(x);
	
	float id = 0.0;
	vec2 res = vec2(100.0);
	for(int k = -1; k <= 1; k++)
	for(int j = -1; j <= 1; j++)
	for(int i = -1; i <= 1; i++) {
		vec3 b = vec3(float(i), float(j), float(k));
		vec3 r = vec3(b) - f + hash(p + b);
		float d = dot(r, r);
		if(d < res.x) {
			id = dot(p + b, vec3(1.0, 57.0, 113.0));
			res = vec2(d, res.x);
		} else if(d < res.y) {
			res.y = d;
		}
    }
    return vec3(sqrt(res), abs(id));
}

// Direction to rotation matrix
mat3 direction_to_matrix(vec3 direction) {
	vec3 x_axis = normalize(cross(vec3(0.0, 1.0, 0.0), direction));
	vec3 y_axis = normalize(cross(direction, x_axis));
	return mat3(vec3(x_axis.x, y_axis.x, direction.x),
				vec3(x_axis.y, y_axis.y, direction.y),
				vec3(x_axis.z, y_axis.z, direction.z));
}

// Cloud density function
float cloud_density(vec3 p, float progress) {
	float t_o = TIME * 0.001;
	float t_o_small = TIME * -0.005;
	float noise = texture(cloud_noise_sampler, p.xy * 4.0 + t_o_small).x * 0.1 + 0.9;
	float clouds_shape = texture(cloud_shape_sampler, (p.xy + t_o) * clouds_scale).x;
	float height_curve = texture(cloud_curves, vec2(progress, 0.0)).x;
	float base_density = 1.0 - clouds_density;
	float density = 
	smoothstep(base_density - clouds_smoothness,
	base_density + clouds_smoothness,
	clouds_shape * noise * height_curve
	);
	return density;
}

// Cloud ray marching
vec2 cloud_ray_march(vec3 direction, vec3 sun_dir) {
	float density = 0.0;
	float light = 0.0;
	
	float height = 0.03;
	vec3 sample_point = vec3(0.0, 0.0, 2.0);
	
	int loop_offset = clouds_samples * 3;
	
	for(int i = loop_offset; i < clouds_samples + loop_offset; i++) {
		float progress = float(i) / float(clouds_samples);
		sample_point = direction * height * progress;
		float point_density = cloud_density(sample_point, progress);
		density += point_density;
		
		float point_light = 0.0;
		for(int f = 0; f < shadow_sample; f++) {
			float shadow_progress = float(f) / float(shadow_sample);
			vec3 shadow_offset = sun_dir * height * shadow_progress;
			point_light += cloud_density(sample_point + shadow_offset, progress);
		}
		light += point_light;
	}
	return vec2(clamp(density, 0.0, 1.0), light / float(shadow_sample * clouds_samples));
}

// Random direction generation
vec3 random_direction(float seed) {
	float phi = rand(seed) * PI;
	float costheta = rand(seed + 100.0) * 2.0 - 1.0;
	float theta = acos(costheta);
	return vec3(sin(theta) * cos(phi), (theta) * sin(phi), cos(theta));
}

// Shooting star effect
float get_shooting_star(vec3 eyedir) {
	float shooting_star = 0.0;
	for(int i = 0; i < 1; i++) {
		float base_rand = rand(float(i));
		float time = TIME + base_rand * 2.0;
		float duration = 0.5 + base_rand;
		float seed = floor(time / duration) * duration + base_rand;
		float progress = mod(time, duration) / duration;
		float rand_value = rand(seed + 50.0);
		float rand_scale = base_rand * 2.0;
		float a = rand_value * 0.8;
		mat3 angle = mat3(vec3(cos(a), -sin(a), 0.0), vec3(sin(a), cos(a), 0.0), vec3(0.0, 0.0, 1.0));
		vec3 shooting_dir = direction_to_matrix(random_direction(seed)) * angle * eyedir;
		vec2 shooting_uv = ((shooting_dir.xy + vec2(0.0, progress * 0.4)) * (8.0 + rand_scale)) + vec2(0.5);

		float shooting_mask = ceil(
			clamp(shooting_uv.x * (1.0 - shooting_uv.x), 0.0, 1.0) *
			clamp(shooting_uv.y * (1.0 - shooting_uv.y), 0.0, 1.0)
			) * ceil(shooting_dir.z);
			
		shooting_star = clamp(
			shooting_star + texture(shooting_star_sampler, shooting_uv).x
			* sin(progress * PI)
			* shooting_mask * rand_value,
		0.0, 1.0);
	}
	return clamp(shooting_star, 0.0, 1.0);
}

// Sun rendering with better visibility and bloom
vec4 render_sun(vec3 eyedir) {
    if (!sun_visible) return vec4(0.0);
    
    // Use custom sun direction instead of light direction
    vec3 sun_dir = normalize(sun_visible ? sun_direction : LIGHT0_DIRECTION);
    
    // Get direction to sun
    float dp = dot(sun_dir, normalize(eyedir));
    
    // Skip if not looking towards the sun
    if (dp < 0.99) {
        return vec4(0.0);
    }
    
    // Improved disc size calculation with better falloff
    float sun_disc = smoothstep(0.9990, 0.9999, dp) * sun_size * 0.01;
    
    // Add bloom effect around the sun
    float sun_bloom_effect = smoothstep(0.990, 0.998, dp) * sun_bloom * 0.02;
    
    // Calculate final sun intensity including bloom
    float sun_final = sun_disc + sun_bloom_effect;
    
    // Apply sun texture if available
    vec2 sun_uv = vec2(0.5, 0.5);
    if (dp > 0.99) {
        // Calculate UV based on eye direction relative to sun direction
        vec3 perpendicular = normalize(cross(sun_dir, vec3(0.0, 1.0, 0.0)));
        vec3 up_vector = normalize(cross(perpendicular, sun_dir));
        
        float u = dot(normalize(eyedir), perpendicular);
        float v = dot(normalize(eyedir), up_vector);
        
        // Scale UVs based on how close we're looking to the sun
        float scale = 5.0 * (1.0 - dp);
        sun_uv = vec2(0.5, 0.5) + vec2(u, v) * scale;
    }
    
    vec4 sun_tex_color = texture(sun_sampler, sun_uv);
    
    // Create a more vibrant sun color with improved visibility
    return vec4(sun_color * sun_intensity * sun_tex_color.rgb, sun_final * sun_tex_color.a);
}

// Moon rendering with better texture mapping and phases
vec4 render_moon(vec3 eyedir) {
    if (!moon_visible) return vec4(0.0);
    
    // Get direction to moon
    vec3 normalized_moon_pos = normalize(moon_position);
    vec3 normalized_eyedir = normalize(eyedir);
    float dp = dot(normalized_moon_pos, normalized_eyedir);
    
    // Skip if not looking towards the moon
    if (dp < 0.998) {
        return vec4(0.0);
    }
    
    // Calculate UV coordinates on moon disc - improved mapping
    vec3 moon_right = normalize(cross(vec3(0.0, 1.0, 0.0), normalized_moon_pos));
    vec3 moon_up = normalize(cross(normalized_moon_pos, moon_right));
    
    float u = dot(normalized_eyedir, moon_right);
    float v = dot(normalized_eyedir, moon_up);
    
    // Calculate distance from center, improved radius calculation
    float radius = 0.001 * moon_size;
    float dist = length(vec2(u, v)) / radius;
    
    if (dist > 1.0) {
        return vec4(0.0);
    }
    
    // Map from polar coordinates to UV with better centering
    vec2 moon_uv = vec2(u / radius / 2.0 + 0.5, v / radius / 2.0 + 0.5);
    
    // Sample moon texture with proper filtering
    vec4 moon_color = texture(moon_sampler, moon_uv);
    
    // Apply more accurate moon phase calculation
    float phase_adjusted = abs(moon_phase - 0.5) * 2.0; // 0 = full, 1 = new
    float terminator = u / radius; // Position of day/night terminator
    
    // Better phase model with smoother transition
    float phase_factor = 0.0;
    if (moon_phase < 0.5) {
        // Waxing phase (new to full)
        phase_factor = smoothstep(-phase_adjusted, phase_adjusted, terminator);
    } else {
        // Waning phase (full to new)
        phase_factor = smoothstep(-phase_adjusted, phase_adjusted, -terminator);
    }
    
    // Apply moon tint for more realistic appearance
    vec3 tinted_color = moon_color.rgb * moon_tint;
    
    // Improved brightness falloff near the edges
    float edge_falloff = smoothstep(1.0, 0.8, dist);
    float alpha = edge_falloff * moon_color.a * (phase_factor * 0.8 + 0.2) * moon_brightness;
    
    return vec4(tinted_color, alpha);
}

// Function for rendering a planet with improved appearance
vec4 render_planet(vec3 eyedir, vec3 planet_pos, float planet_size_param, vec3 planet_color, bool is_visible) {
    if (!is_visible) return vec4(0.0);
    
    // Get direction to planet
    float dp = dot(normalize(planet_pos), normalize(eyedir));
    
    // Skip if not looking towards the planet
    if (dp < 0.998) {
        return vec4(0.0);
    }
    
    // Improved disc size calculation
    float disc = smoothstep(0.9995, 0.9999, dp) * planet_size_param * 0.005;
    
    // Add a subtle edge glow for better visibility
    float glow = smoothstep(0.998, 0.9995, dp) * 0.002;
    
    // Set color with simple falloff
    return vec4(planet_color, disc + glow);
}

void sky() {
    float horizon_mask = abs(EYEDIR.y);
    float bottom_mask = smoothstep(0.5, 0.45, SKY_COORDS.y);
    
    // Sky color
    vec3 sky_gradient = mix(bottom_color.rgb, top_color.rgb, clamp(EYEDIR.y, 0.0, 1.0));
    vec3 sunset_color = sun_scatter * (1.0 - horizon_mask);
    vec3 sky_color = clamp(sky_gradient + sunset_color, 0.0, 1.0);
    
    // Stars with improved visibility and twinkling
    if(stars_intensity > 0.0) {
        vec2 stars = voronoi(EYEDIR * 25.0).xz;
        float time_variation = sin(TIME * stars.y * 1.5) * 0.5 + 0.5;
        float star_twinkle = mix(1.0, time_variation, stars_scintillation);
        sky_color += smoothstep(0.025 + (star_twinkle * 0.05), 0.0, stars.x) * stars_intensity * stars_tint;
    }
    
    // Add shooting stars
    if(shooting_stars_intensity > 0.0) {
        sky_color += get_shooting_star(EYEDIR) * shooting_stars_intensity * shooting_star_tint;
    }
    
    // Add moon with improved rendering
    vec4 moon_rgba = render_moon(EYEDIR);
    sky_color = mix(sky_color, moon_rgba.rgb, moon_rgba.a);
    
    // Add planets with improved rendering
    vec4 planet1_rgba = render_planet(EYEDIR, planet1_position, planet1_size, planet1_color, planet1_visible);
    sky_color = mix(sky_color, planet1_rgba.rgb, planet1_rgba.a);
    
    vec4 planet2_rgba = render_planet(EYEDIR, planet2_position, planet2_size, planet2_color, planet2_visible);
    sky_color = mix(sky_color, planet2_rgba.rgb, planet2_rgba.a);
    
    vec4 planet3_rgba = render_planet(EYEDIR, planet3_position, planet3_size, planet3_color, planet3_visible);
    sky_color = mix(sky_color, planet3_rgba.rgb, planet3_rgba.a);
    
    // Add sun with improved visibility
    vec4 sun_rgba = render_sun(EYEDIR);
    sky_color = mix(sky_color, sun_rgba.rgb, sun_rgba.a);
    
    // Add high clouds
    if(high_clouds_density > 0.0) {
        vec2 high_clouds_uv = (EYEDIR.xz / clamp(EYEDIR.y, 0.01, 1.0)) * 0.25 + TIME * 0.001;
        float high_clouds_mask = texture(high_clouds_sampler, high_clouds_uv).x;
        sky_color = mix(sky_color, clouds_light_color, smoothstep(0.0, 1.0, high_clouds_mask) * horizon_mask * bottom_mask * high_clouds_density);
    }
    
    // Main clouds
    if (AT_HALF_RES_PASS) {
        vec3 clouds_direction = vec3(EYEDIR.xz / clamp(EYEDIR.y, 0.01, 1.0), 1.0);
        vec2 clouds = EYEDIR.y > 0.0 ? cloud_ray_march(clouds_direction, sun_visible ? normalize(sun_direction) : LIGHT0_DIRECTION) : vec2(0.0);
        
        COLOR = mix(bottom_color, clouds_light_color, exp(-clouds.y * clouds_shadow_intensity));
        ALPHA = (1.0 - exp(-clouds.x * horizon_mask * bottom_mask * 10.0));
        
    } else {
        COLOR.rgb = mix(sky_color, HALF_RES_COLOR.rgb, HALF_RES_COLOR.a);
    }
}