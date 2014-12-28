precision highp float;

varying lowp vec2 srcTexCoordOut1; // New
uniform sampler2D srcTexture1; // New

void main(void) {
    vec4 textureColor = texture2D(srcTexture1, srcTexCoordOut1); //movie fx video

    gl_FragColor = vec4(textureColor.r,0, textureColor.b, textureColor.a);

}