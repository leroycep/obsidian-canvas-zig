#version 330

in vec2 uv;

uniform sampler2D font_texture;

out vec4 color;

void main() {
    color = texture(font_texture, uv);
}
