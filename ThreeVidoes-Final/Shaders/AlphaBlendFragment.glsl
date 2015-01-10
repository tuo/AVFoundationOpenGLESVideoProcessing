precision highp float;

varying lowp vec2 srcTexCoordOut1; // New
uniform sampler2D srcTexture1; // New

varying lowp vec2 srcTexCoordOut2; // New
uniform sampler2D srcTexture2; // New

varying lowp vec2 srcTexCoordOut3; // New
uniform sampler2D srcTexture3; // New

uniform float thresholdSensitivity;
uniform float smoothing;
uniform vec3 colorToReplace;

void main(void) {

    vec4 textureColorAlpha = texture2D(srcTexture1, srcTexCoordOut1);//alpha
    vec4 textureColorFX = texture2D(srcTexture2, srcTexCoordOut1); //fx
    vec4 textureColorSrc = texture2D(srcTexture3, srcTexCoordOut1); //src

    gl_FragColor = mix(textureColorFX, textureColorSrc, 1.0 -textureColorAlpha.r);

}