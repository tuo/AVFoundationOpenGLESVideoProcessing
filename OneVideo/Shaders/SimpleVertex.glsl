attribute vec4 Position;

attribute vec2 srcTexCoordIn1;
varying vec2 srcTexCoordOut1;

void main(void) {
    gl_Position = Position;
    srcTexCoordOut1 = srcTexCoordIn1;
}
