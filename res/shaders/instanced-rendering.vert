#version 450 core

struct VertexData {
    mat4 pos;
    vec4 color;
};

layout(std430, binding = 2) readonly buffer SSBO1 {
    VertexData data[];
} ssbo1;

layout(location = 0) in vec2 aPos;
layout(location = 1) in vec3 aColor;

out vec4 vColor;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

void main() {
    VertexData v = ssbo1.data[gl_InstanceID];

    gl_Position = projection * view * v.pos * (vec4(aPos, 0.0, 1.0));
    vColor = vec4(aColor, 1);
}
