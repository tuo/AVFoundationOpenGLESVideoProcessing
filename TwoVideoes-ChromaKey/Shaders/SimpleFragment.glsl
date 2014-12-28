precision highp float;

varying lowp vec2 srcTexCoordOut1; // New
uniform sampler2D srcTexture1; // New

varying lowp vec2 srcTexCoordOut2; // New
uniform sampler2D srcTexture2; // New

uniform float thresholdSensitivity;
uniform float smoothing;
uniform vec3 colorToReplace;

void main(void) {
    //gl_FragColor = texture2D(srcTexture1, srcTexCoordOut1); // New
    //gl_FragColor = vec4(1.0,0.0,0.0,1.0); //set it red for testing

    vec4 textureColor = texture2D(srcTexture1, srcTexCoordOut1); //movie fx video

    //vec4 textureColor1 = vec4(1.0,0.0,0.0,1.0);     //raw video
    vec4 textureColor1 = texture2D(srcTexture2, srcTexCoordOut2);

    float maskY = 0.2989 * colorToReplace.r + 0.5866 * colorToReplace.g + 0.1145 * colorToReplace.b;
    float maskCr = 0.7132 * (colorToReplace.r - maskY);
    float maskCb = 0.5647 * (colorToReplace.b - maskY);

    float Y = 0.2989 * textureColor.r + 0.5866 * textureColor.g + 0.1145 * textureColor.b;
    float Cr = 0.7132 * (textureColor.r - Y);
    float Cb = 0.5647 * (textureColor.b - Y);

    //     float blendValue = 1.0 - smoothstep(thresholdSensitivity - smoothing, thresholdSensitivity , abs(Cr - maskCr) + abs(Cb - maskCb));
    float blendValue = 1.0 - smoothstep(thresholdSensitivity, thresholdSensitivity + smoothing, distance(vec2(Cr, Cb), vec2(maskCr, maskCb)));
    //gl_FragColor = textureColor; //set it red for testing
    gl_FragColor = mix(textureColor, textureColor1, blendValue);

}