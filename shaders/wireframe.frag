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

void main() {
	vec3 vert_dist = pos - _CameraPosition;
	float xz_dist_mag = vert_dist.x + vert_dist.z;
	// vertex hegiht scaled 0-1 
	frag_color = vec4(pos.y*0.001,
					  pos.y*0.001,
					  pos.y*0.001,
					  xz_dist_mag*0.001);
}
