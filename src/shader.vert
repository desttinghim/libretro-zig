uniform mat4 uMVP;
layout(location=0) attribute vec2 aVertex;
layout(location=1) attribute vec4 aColor;
varying vec4 color;
void main() {
    gl_Position = uMVP * vec4(aVertex, 0.0, 1.0);
    color = aColor;
}
