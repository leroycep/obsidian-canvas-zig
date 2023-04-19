#version 330
layout(location=0) in vec3 point_xyz;
layout(location=1) in vec2 point_uv;
layout(location=2) in vec4 point_tint;

uniform mat4 projection;

out vec2 uv;
out vec4 tint;

void main() {
    uv = point_uv;
    tint = point_tint;
    gl_Position = projection * vec4(point_xyz, 1.0);
}