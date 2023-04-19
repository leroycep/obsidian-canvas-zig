#version 330

in vec2 uv;
in vec4 tint;

uniform sampler2D texture_handle;

out vec4 color;

void main() {
    color = tint * texture(texture_handle, uv);
}
