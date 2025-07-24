#version 450

layout(set = 0, binding = 0, std140) uniform UniformBufferObject {
	mat4 MVP;
	float _GradientRotation;
	float _TerrainHeight;
	float _Scale;
	float _Seed;
	vec3 _Offset;
};

layout(location = 2) in vec4 a_Color;
layout(location = 0) out vec4 frag_color;

void main() {
	frag_color = a_Color;
}
