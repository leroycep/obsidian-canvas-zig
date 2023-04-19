#version 330
layout(location=0) in vec3 point_xyz;
layout(location=1) in vec2 point_uv;

uniform mat4 projection;

out vec2 uv;

void main() {
    uv = point_uv;
    gl_Position = projection * vec4(point_xyz, 1.0);
}