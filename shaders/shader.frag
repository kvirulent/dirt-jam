#version 450
	
layout(set = 0, binding = 0, std140) uniform UniformBufferObject {
	mat4 MVP;
	float _GradientRotation;
	float _TerrainHeight;
	float _Scale;
	float _Seed;
	vec3 _Offset;
	vec3 _CameraPosition;
};

layout(location = 2) in vec4 a_Color;
layout(location = 3) in vec3 pos;

layout(location = 0) out vec4 frag_color;

#define PI 3.141592653589793238462
		
// UE4's PseudoRandom function
// https://github.com/EpicGames/UnrealEngine/blob/release/Engine/Shaders/Private/Random.ush
float pseudo(vec2 v) {
	v = fract(v/128.)*128. + vec2(-64.340622, -72.465622);
	return fract(dot(v.xyx * v.xyy, vec3(20.390625, 60.703125, 2.4281209)));
}

// Takes our xz positions and turns them into a random number between 0 and 1 using the above pseudo random function
float HashPosition(vec2 pos) {
	return pseudo(pos * vec2(_Seed, _Seed + 4));
}

// Generates a random gradient vector for the perlin noise lattice points, watch my perlin noise video for a more in depth explanation
vec2 RandVector(float seed) {
	float theta = seed * 360 * 2 - 360;
	theta += _GradientRotation;
	theta = theta * PI / 180.0;
	return normalize(vec2(cos(theta), sin(theta)));
}

// Normal smoothstep is cubic -- to avoid discontinuities in the gradient, we use a quintic interpolation instead as explained in my perlin noise video
vec2 quinticInterpolation(vec2 t) {
	return t * t * t * (t * (t * vec2(6) - vec2(15)) + vec2(10));
}

// Derivative of above function
vec2 quinticDerivative(vec2 t) {
	return vec2(30) * t * t * (t * (t - vec2(2)) + vec2(1));
}

// it's perlin noise that returns the noise in the x component and the derivatives in the yz components as explained in my perlin noise video
vec3 perlin_noise2D(vec2 pos) {
	vec2 latticeMin = floor(pos);
	vec2 latticeMax = ceil(pos);

	vec2 remainder = fract(pos);

	// Lattice Corners
	vec2 c00 = latticeMin;
	vec2 c10 = vec2(latticeMax.x, latticeMin.y);
	vec2 c01 = vec2(latticeMin.x, latticeMax.y);
	vec2 c11 = latticeMax;

	// Gradient Vectors assigned to each corner
	vec2 g00 = RandVector(HashPosition(c00));
	vec2 g10 = RandVector(HashPosition(c10));
	vec2 g01 = RandVector(HashPosition(c01));
	vec2 g11 = RandVector(HashPosition(c11));

	// Directions to position from lattice corners
	vec2 p0 = remainder;
	vec2 p1 = p0 - vec2(1.0);

	vec2 p00 = p0;
	vec2 p10 = vec2(p1.x, p0.y);
	vec2 p01 = vec2(p0.x, p1.y);
	vec2 p11 = p1;
	
	vec2 u = quinticInterpolation(remainder);
	vec2 du = quinticDerivative(remainder);

	float a = dot(g00, p00);
	float b = dot(g10, p10);
	float c = dot(g01, p01);
	float d = dot(g11, p11);

	// Expanded interpolation freaks of nature from https://iquilezles.org/articles/gradientnoise/
	float noise = a + u.x * (b - a) + u.y * (c - a) + u.x * u.y * (a - b - c + d);

	vec2 gradient = g00 + u.x * (g10 - g00) + u.y * (g01 - g00) + u.x * u.y * (g00 - g10 - g01 + g11) + du * (u.yx * (a - b - c + d) + vec2(b, c) - a);
	return vec3(noise, gradient);
}

vec3 fbm(vec2 pos) {
	// Exports defined here since I don't want to mess with the UBO
	int octaves = 12;
	vec2 angular_variance = vec2(-15.0, 15);
	int seed = -755;
	float amplitudedecay = 0.439;
	float _NoiseRotation = 36.32;
	vec2 frequency_variance_bounds = vec2(-0.085, 0.115);
	float lacunarity = 1.991;
	

	// Amplitude, height, rotation accumulators
	float amplitude = 0.739;
	float height = 0.0;
	vec2 grad = vec2(0.0);

	float angle_variance = mix(angular_variance.x, angular_variance.y, HashPosition(vec2(seed, 827)));
	float theta = (_NoiseRotation + angle_variance) * PI / 180.0;
	

	// Accumulator for vertex rotation
	mat2 m = mat2(1.0, 0.0,
				  0.0, 1.0);

	// Rotation matrix
	mat2 m2 = mat2(cos(theta), -sin(theta),
			  sin(theta), cos(theta));

	mat2 m2i = inverse(m2);

	// Loop to apply several transforms of decreasing amplitude
	for(int i = 0; i < octaves; ++i) {
		vec3 n = perlin_noise2D(pos);

		height += amplitude * n.x; // Add this transform to the height accumulator scaled by current amplitude
		grad += amplitude * m * n.yz;
		amplitude *= amplitudedecay; // Reduce amplitude for the next iteration of the loop

		angle_variance = mix(angular_variance.x, angular_variance.y, HashPosition(vec2(i * 419, seed)));
		theta = (_NoiseRotation + angle_variance) * PI / 180.0;

		// Reconstruct rotation matrix
		m2 = mat2(cos(theta), -sin(theta),
				 sin(theta), cos(theta));

		m2i = inverse(m2);

		float freq_variance = mix(frequency_variance_bounds.x, frequency_variance_bounds.y, HashPosition(vec2(i * 422, seed)));

		// Apply transform
		pos = (lacunarity + freq_variance) * m2 * pos;
		m = (lacunarity + freq_variance) * m2i * m;	
	}

	return vec3(height, grad);
}
//
void main() {
	// Exports defined here since I don't want to mess with the UBO
	float _SlopeDamping = 0.2;
	vec3 _LightDirection = vec3(200,400,100);
	vec2 _SlopeRange = vec2(0.895, 0.96);
	vec4 _AmbientLight = vec4(0.192, 0.271, 0.3, 1);
	vec4 _HighSlopeColor = vec4(0.366, 0.373, 0.078, 1);
	vec4 _LowSlopeColor = vec4(0.1, 0.058, 0.049, 1);
	vec4 _FarDistanceColor = vec4(0.031, 0.182, 0.25, 1);

	vec3 noise_pos = (pos + vec3(_Offset.x, 0, _Offset.z)) / _Scale;
	vec3 n = _TerrainHeight * fbm(noise_pos.xz);

	vec3 normal = normalize(vec3(-n.y, 1, -n.z));
	vec3 slope_normal = normalize(vec3(-n.y, 1, -n.z) * vec3(_SlopeDamping, 1, _SlopeDamping));
	
	float material_blend_factor = smoothstep(_SlopeRange.x, _SlopeRange.y, 1 - slope_normal.y);
	vec4 albedo = mix(_HighSlopeColor, _LowSlopeColor, vec4(material_blend_factor));
	float dist_blend_factor = smoothstep(30.0, 400.0, distance(_CameraPosition, pos));
	albedo = mix(albedo, _FarDistanceColor, vec4(dist_blend_factor*0.415));
	
	float ndotl = clamp(dot(_LightDirection, normal), 0, 1);
	vec4 direct_light = albedo * ndotl;
	vec4 ambient_light = albedo * _AmbientLight;

	vec4 lit = clamp(direct_light + ambient_light, vec4(0), vec4(1));

	frag_color = pow(lit, vec4(2.2));
}
