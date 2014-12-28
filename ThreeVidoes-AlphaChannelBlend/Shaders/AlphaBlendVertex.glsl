attribute vec4 Position;

attribute vec2 srcTexCoordIn1;
attribute vec2 srcTexCoordIn2;
attribute vec2 srcTexCoordIn3;
varying vec2 srcTexCoordOut1;
varying vec2 srcTexCoordOut2;
varying vec2 srcTexCoordOut3;

void main(void) {
    gl_Position = Position;
    srcTexCoordOut1 = srcTexCoordIn1;
    srcTexCoordOut2 = srcTexCoordIn2;
    srcTexCoordOut3 = srcTexCoordIn3;
}
