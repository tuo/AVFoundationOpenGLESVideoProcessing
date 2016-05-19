
#import "THMovieAlphaBlendFilter.h"

NSString *const kTHMovieAlphaBlendFragmentShaderString = SHADER_STRING
(
 precision highp float;
 
 varying highp vec2 textureCoordinate;
 varying highp vec2 textureCoordinate2;
 varying highp vec2 textureCoordinate3;
 
 uniform sampler2D inputImageTexture;
 uniform sampler2D inputImageTexture2;
 uniform sampler2D inputImageTexture3;
 
 void main()
 {
     vec4 textureColorAlpha = texture2D(inputImageTexture, textureCoordinate);//alpha
     vec4 textureColorFX = texture2D(inputImageTexture2, textureCoordinate2); //fx
     vec4 textureColorSrc = texture2D(inputImageTexture3, textureCoordinate3); //src
 
     gl_FragColor = mix(textureColorFX, textureColorSrc, 1.0 -textureColorAlpha.r);	     
     
 });


@implementation THMovieAlphaBlendFilter
	
- (id)init;
{
    if (!(self = [super initWithFragmentShaderFromString:kTHMovieAlphaBlendFragmentShaderString]))
    {
        return nil;
    }	    	    
    return self;
}
@end


