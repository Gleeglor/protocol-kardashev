#version 450 core

layout(std430, binding = 0) readonly buffer SSBO1 {
    vec2 pos[];
} ssbo1;

layout(std430, binding = 1) readonly buffer SSBO2 {
    float angle[];
} ssbo2;

layout(std430, binding = 2) readonly buffer SSBO3 {
    uint type[];
} ssbo3;

// layout(std430, binding = 3) readonly buffer SSBO4 {
//     float scale[];
// } ssbo4;

// layout(std430, binding = 4) readonly buffer SSBO5 {
//     vec4 color[];
// } ssbo5;

layout(location = 0) in vec2 vertPos;

out vec4 vertColor;

uniform mat4 projection;
uniform mat4 view;
uniform mat4 model;

void main() {
    vec2 bebe = ssbo1.pos[gl_InstanceID];
    float angle = ssbo2.angle[gl_InstanceID];
    uint type = ssbo3.type[gl_InstanceID];
    // float scale = ssbo2.scale[v.type];
    // vec4 color = ssbo3.color[v.type];

    float s = sin(-angle);
    float c = cos(-angle);
    vec2 localPos = vec2(
            c * vertPos.x - s * vertPos.y,
            s * vertPos.x + c * vertPos.y
        );
    vec2 pos = bebe + localPos * 1;

    gl_Position = projection * view * (vec4(pos, 0.0, 1.0));
    vertColor = vec4(1, 1, 1, 1);
}
