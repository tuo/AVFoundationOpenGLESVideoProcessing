attribute vec4 Position;

attribute vec2 srcTexCoordIn1;
attribute vec2 srcTexCoordIn2;
varying vec2 srcTexCoordOut1;
varying vec2 srcTexCoordOut2;

void main(void) {
    gl_Position = Position;
    srcTexCoordOut1 = srcTexCoordIn1;
    srcTexCoordOut2 = srcTexCoordIn2;
}
