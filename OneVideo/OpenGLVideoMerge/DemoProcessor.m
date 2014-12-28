//
//  DemoProcessor.m
//  OpenGLVideoMerge
//
//  Created by Tuo on 11/23/13.
//  Copyright (c) 2013 Tuo. All rights reserved.
//

#import "DemoProcessor.h"
#import <OpenGLES/ES2/glext.h>
// This needs to be flipped to write out to video correctly
typedef struct {
    float Position[3];
} Vertex;

const Vertex Vertices[] = {
    {1, -1, 0},
    {1, 1, 0},
    {-1, 1, 0},
    {-1, -1, 0}
};

const GLubyte Indices[] = {
    0, 1, 2,
    2, 3, 0
};

struct Vector3 {
    GLfloat one;
    GLfloat two;
    GLfloat three;
};
typedef struct Vector3 Vector3;
@implementation DemoProcessor  {
    EAGLContext *_context;
    GLuint _positionSlot;
    GLuint _srcTexCoord1Slot;
    GLuint _srcTexCoord2Slot;
    GLuint _srcTexture1Uniform;
    GLuint _srcTexture2Uniform;
    
    GLuint _thresholdUniform;
    GLuint _smoothingUniform;
    GLuint _colorToReplaceUniform;
    
    GLuint _program;
    
    GLuint _frameBuffer;
    
    CVOpenGLESTextureRef outputTexture1;
    CVOpenGLESTextureRef outputTexture2;
    
    CVOpenGLESTextureCacheRef _textureCache;
    CVOpenGLESTextureRef _texture;
    CVPixelBufferRef _pixelBuffer;
    CVPixelBufferRef _pb;
    
    //AssetWriter
    NSURL *outputURL;
    CGSize videoSize;
    dispatch_queue_t movieWritingQueue;
 
    int width, height;
}

- (id)init {
    self = [super init];
    if (self) {
        [self setup];
    }
    
    return self;
}

- (void)setup {
    width = 640;
    height = 640;
    videoSize = CGSizeMake(width, height);
    
    [self setupContext];
//    [self setupOpenGLESTextureCache];
    [self compileShaders];
    
}



- (void)setupContext {
    EAGLRenderingAPI api = kEAGLRenderingAPIOpenGLES2;
    _context = [[EAGLContext alloc] initWithAPI:api];
    if (!_context) {
        NSLog(@"Failed to initialize OpenGLES 2.0 context");
        exit(1);
    }
    
    if (![EAGLContext setCurrentContext:_context]) {
        NSLog(@"Failed to set current OpenGL context");
        exit(1);
    }
}
#pragma mark setupOpenGLESTextureCache
- (void)setupOpenGLESTextureCache {
    // Create a new CVOpenGLESTexture cache
    //-- Create CVOpenGLESTextureCacheRef for optimal CVImageBufferRef to GLES texture conversion.
#if COREVIDEO_USE_EAGLCONTEXT_CLASS_IN_API
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _context, NULL, &_textureCache);
#else
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (__bridge void *)_context, NULL, &_textureCache);
#endif
    if (err) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        exit(1);
    }
}
#pragma mark compileShaders
#pragma mark compileShaders
- (void)compileShaders {
    
    // 1
    GLuint vertexShader = [self compileShader:@"SmokeVertex" withType:GL_VERTEX_SHADER];
    GLuint fragmentShader = [self compileShader:@"SmokeFragment" withType:GL_FRAGMENT_SHADER];
    
    // 2
    _program = glCreateProgram();
    glAttachShader(_program, vertexShader);
    glAttachShader(_program, fragmentShader);
    glLinkProgram(_program);
    
    // 3
    GLint linkSuccess;
    glGetProgramiv(_program, GL_LINK_STATUS, &linkSuccess);
    if (linkSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetProgramInfoLog(_program, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSLog(@"%@", messageString);
        exit(1);
    }
    
    // 4
    _positionSlot = glGetAttribLocation(_program, "Position");
    
    glEnableVertexAttribArray(_positionSlot);
 
}

- (GLuint)compileShader:(NSString*)shaderName withType:(GLenum)shaderType {
    
    // 1
    NSString* shaderPath = [[NSBundle mainBundle] pathForResource:shaderName ofType:@"glsl"];
    NSError* error;
    NSString* shaderString = [NSString stringWithContentsOfFile:shaderPath encoding:NSUTF8StringEncoding error:&error];
    if (!shaderString) {
        NSLog(@"Error loading shader: %@", error.localizedDescription);
        exit(1);
    }
    
    // 2
    GLuint shaderHandle = glCreateShader(shaderType);
    
    // 3
    const char * shaderStringUTF8 = [shaderString UTF8String];
    int shaderStringLength = [shaderString length];
    glShaderSource(shaderHandle, 1, &shaderStringUTF8, &shaderStringLength);
    
    // 4
    glCompileShader(shaderHandle);
    
    // 5
    GLint compileSuccess;
    glGetShaderiv(shaderHandle, GL_COMPILE_STATUS, &compileSuccess);
    if (compileSuccess == GL_FALSE) {
        GLchar messages[256];
        glGetShaderInfoLog(shaderHandle, sizeof(messages), 0, &messages[0]);
        NSString *messageString = [NSString stringWithUTF8String:messages];
        NSLog(@"%@", messageString);
        exit(1);
    }
    
    return shaderHandle;
    
}




- (void)startProcessing {
    
    
    UIImage *rawImg = [UIImage imageNamed:@"video"];
    for(int i =0; i < 6; i++){
        UIImage *boomiImage = [UIImage imageNamed:[NSString stringWithFormat:@"boomi%d",i]];
        //        [self testConvertingWithImg:rawImg boomiImg: boomiImage index: i];
        [self processWithImg:rawImg boomiImg: boomiImage index: i];
        
    }
    
}

- (void)testConvertingWithImg:(UIImage *)rawImg boomiImg:(UIImage *)bImg index:(int)index {

    CVImageBufferRef rawPixelBuffer = [self pixelBufferFromCGImage:[rawImg CGImage]];
    CVImageBufferRef boomiPixelBuffer = [self pixelBufferFromCGImage:[bImg CGImage]];
   
    /*We display the result on the image view (We need to change the orientation of the image so that the video is displayed correctly)*/
    
    UIImage *image = [self imageFromSampleBuffer:rawPixelBuffer];
    NSString *fileName = [NSString stringWithFormat:@"Documents/output%d.png", index];
    // Create paths to output images
    NSString  *pngPath = [NSHomeDirectory() stringByAppendingPathComponent:fileName];
    // Write image to PNG
    [UIImagePNGRepresentation(image) writeToFile:pngPath atomically:YES];
}

- (void)processWithImg:(UIImage *)rawImg boomiImg:(UIImage *)bImg index:(int)index {
    NSLog(@"processing i: %d", index);
    [EAGLContext setCurrentContext:_context];
//    CVImageBufferRef rawPixelBuffer = [self pixelBufferFromCGImage:[rawImg CGImage]];
    CVImageBufferRef boomiPixelBuffer = [self pixelBufferFromCGImage:[bImg CGImage]];
//
//    size_t width = CVPixelBufferGetWidth(rawPixelBuffer);
//    size_t height = CVPixelBufferGetHeight(rawPixelBuffer);
//    
//    size_t width1 = CVPixelBufferGetWidth(boomiPixelBuffer);
//    size_t height1 = CVPixelBufferGetHeight(boomiPixelBuffer);
//    //    NSLog(@"_pixel buffer: %@", _pixelBuffer);
    
    if(_frameBuffer == 0){ //0 means detached, so if it is 0, means it not initialized
          glDisable(GL_DEPTH_TEST);
        //create FBO
        glGenFramebuffers(1, &_frameBuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, _frameBuffer);

        [self setupOpenGLESTextureCache];
        
       
        CFDictionaryRef empty; // empty value for attr value.
        CFMutableDictionaryRef attrs;
        empty = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); // our empty IOSurface properties dictionary
        attrs = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(attrs, kCVPixelBufferIOSurfacePropertiesKey, empty);
        
        CVReturn err = CVPixelBufferCreate(kCFAllocatorDefault, (int)width, (int)height, kCVPixelFormatType_32BGRA, attrs, &_pb);
        if (err)
        {
            NSLog(@"FBO size: %d, %d", width, height);
            NSAssert(NO, @"Error at CVPixelBufferCreate %d", err);
        }
        
        CVOpenGLESTextureCacheCreateTextureFromImage (kCFAllocatorDefault,
                                                      _textureCache,
                                                      _pb,
                                                      NULL, // texture attributes
                                                      GL_TEXTURE_2D,
                                                      GL_RGBA, // opengl format
                                                      (int)videoSize.width,
                                                      (int)videoSize.height,
                                                      GL_BGRA, // native iOS format
                                                      GL_UNSIGNED_BYTE,
                                                      0,
                                                      &_texture);
        
        if (err)
        {
            NSAssert(NO, @"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        
        CFRelease(attrs);
        CFRelease(empty);
        glBindTexture(CVOpenGLESTextureGetTarget(_texture), CVOpenGLESTextureGetName(_texture));
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, CVOpenGLESTextureGetName(_texture), 0);
        
        
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        NSAssert(status == GL_FRAMEBUFFER_COMPLETE, @"Failed to create frame buffer object : %d", status);
        

    }
  
    //double sure it bind to our frame buffer
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBuffer);
    
    glClearColor(0.0, 0, 0,  0.0);
    glClear(GL_COLOR_BUFFER_BIT);
    glViewport(0, 0, (int)videoSize.width, (int)videoSize.height);
   
    
    //use shader program
    NSAssert(_program, @"Program should be created");
    glUseProgram(_program);
    
    static const GLfloat squareVertices[] = {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };
    glVertexAttribPointer(_positionSlot, 2, GL_FLOAT, 0, 0, squareVertices);
    glEnableVertexAttribArray(_positionSlot);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
//    glFinish();
    
    
    UIImage *image = [self imageFromSampleBuffer:_pb];
//    UIImage *image = [self getGLScreenshot];
    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil);
    NSString *fileName = [NSString stringWithFormat:@"Documents/output%d.png", index];
    // Create paths to output images
    NSString  *pngPath = [NSHomeDirectory() stringByAppendingPathComponent:fileName];
    // Write image to PNG
    [UIImagePNGRepresentation(image) writeToFile:pngPath atomically:YES];

    
    CVOpenGLESTextureCacheFlush(_textureCache, 0);
//    glBindTexture(CVOpenGLESTextureGetTarget(outputTexture1), 0);
//    glBindTexture(CVOpenGLESTextureGetTarget(outputTexture2), 0);
//    
    // Flush the CVOpenGLESTexture cache and release the texture
   
//    CFRelease(outputTexture1);
//    CFRelease(outputTexture2);
//    
}

-(UIImage*) getGLScreenshot {
    NSInteger myDataLength = width * height * 4;
    
    // allocate array and read pixels into it.
    GLubyte *buffer = (GLubyte *) malloc(myDataLength);
    glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, buffer);
    
    // gl renders "upside down" so swap top to bottom into new array.
    // there's gotta be a better way, but this works.
    GLubyte *buffer2 = (GLubyte *) malloc(myDataLength);
    for(int y = 0; y < height; y++)
    {
        for(int x = 0; x < width * 4; x++)
        {
            buffer2[(height -1  - y) * width * 4 + x] = buffer[y * 4 * width + x];
        }
    }
    
    // make data provider with data.
    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, buffer2, myDataLength, NULL);
    
    // prep the ingredients
    int bitsPerComponent = 8;
    int bitsPerPixel = 32;
    int bytesPerRow = 4 * width;
    CGColorSpaceRef colorSpaceRef = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
    CGColorRenderingIntent renderingIntent = kCGRenderingIntentDefault;
    
    // make the cgimage
    CGImageRef imageRef = CGImageCreate(width, height, bitsPerComponent, bitsPerPixel, bytesPerRow, colorSpaceRef, bitmapInfo, provider, NULL, NO, renderingIntent);
    
    // then make the uiimage from that
    UIImage *myImage = [UIImage imageWithCGImage:imageRef];
    return myImage;
}

- (void)saveGLScreenshotToPhotosAlbum {
    UIImageWriteToSavedPhotosAlbum([self getGLScreenshot], nil, nil, nil);
}


#pragma mark FBO initialization -- this only triggered once to improve performance
- (void)createFrameBufferObject {
    //first disable depth test if exists
    CFDictionaryRef empty; // empty value for attr value.
    CFMutableDictionaryRef attrs;
    empty = CFDictionaryCreate(kCFAllocatorDefault, // our empty IOSurface properties dictionary
                               NULL,
                               NULL,
                               0,
                               &kCFTypeDictionaryKeyCallBacks,
                               &kCFTypeDictionaryValueCallBacks);
    attrs = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                      1,
                                      &kCFTypeDictionaryKeyCallBacks,
                                      &kCFTypeDictionaryValueCallBacks);
    
    CFDictionarySetValue(attrs,
                         kCVPixelBufferIOSurfacePropertiesKey,
                         empty);
    
    
    // for simplicity, lets just say the image is 640x480
    CVReturn pbStatus = CVPixelBufferCreate(kCFAllocatorDefault, videoSize.width, videoSize.height,
                        kCVPixelFormatType_32BGRA,
                        attrs,
                        &_pixelBuffer);
    // in real life check the error return value of course.
    NSParameterAssert(pbStatus == kCVReturnSuccess && _pixelBuffer != NULL);
    
    //create FBO
    glGenFramebuffers(1, &_frameBuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBuffer);
    
    //setup the texture object
    //setup the
    NSAssert(_textureCache, @"Error at CVOpenGLESTextureCacheCreate, not be created");
    
    //for performance reason
    //    CVPixelBufferPoolCreatePixelBuffer(NULL, [assetWriterPixelBufferInput pixelBufferPool], &_pixelBuffer);

    CVOpenGLESTextureCacheCreateTextureFromImage (kCFAllocatorDefault, _textureCache,
                                                  _pixelBuffer, //note this _pixel buffer should be populated from CMSampleBuffer and we will retrieve its value after drawing
                                                  NULL, // texture attributes
                                                  GL_TEXTURE_2D,
                                                  GL_RGBA, // opengl format
                                                  (int)videoSize.width,
                                                  (int)videoSize.height,
                                                  GL_BGRA, // native iOS format
                                                  GL_UNSIGNED_BYTE,
                                                  0,
                                                  &_texture);
    // set the texture up like any other texture
    glBindTexture(CVOpenGLESTextureGetTarget(_texture), CVOpenGLESTextureGetName(_texture));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // bind the texture to the framebuffer you're going to render to
    // (boilerplate code to make a framebuffer not shown)
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                           GL_TEXTURE_2D, CVOpenGLESTextureGetName(_texture), 0);
    
    
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    NSAssert(status == GL_FRAMEBUFFER_COMPLETE, @"Failed to create frame buffer object : %d", status);
}


- (CVPixelBufferRef) pixelBufferFromCGImage: (CGImageRef) image
{
    
    CGSize frameSize = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
//    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
//                             [NSNumber numberWithBool:NO], kCVPixelBufferCGImageCompatibilityKey,
//                             [NSNumber numberWithBool:NO], kCVPixelBufferCGBitmapContextCompatibilityKey,
//                             nil];
        NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                                 [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                                 [NSNumber numberWithBool:YES], kCVPixelBufferOpenGLCompatibilityKey,
        nil];
    
    CVPixelBufferRef pxbuffer = NULL;
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, frameSize.width,
                                          frameSize.height,  kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef) options,
                                          &pxbuffer);
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    //    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
    ////                         [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
    ////                         [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
    ////                         [NSNumber numberWithBool:YES], kCVPixelBufferOpenGLCompatibilityKey,
    //            nil];
    //    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault, videoSize.width,
    //            videoSize.height, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef) options,
    //            &_pixelBuffer);
    //    NSParameterAssert(status == kCVReturnSuccess && _pixelBuffer != NULL);
    
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pxdata, frameSize.width,
                                                 frameSize.height, 8, 4*frameSize.width, rgbColorSpace,
                                                 kCGImageAlphaNoneSkipLast);
    
    CGContextDrawImage(context, CGRectMake(0, 0, CGImageGetWidth(image),
                                           CGImageGetHeight(image)), image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}

- (UIImage *)imageFromSampleBuffer:(CVPixelBufferRef) imageBuffer
{
    if (kCVReturnSuccess == CVPixelBufferLockBaseAddress(imageBuffer,
                                                         kCVPixelBufferLock_ReadOnly)) {
        
        
        // Get the number of bytes per row for the pixel buffer
        void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
        
        // Get the number of bytes per row for the pixel buffer
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        // Get the pixel buffer width and height
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        
        // Create a device-dependent RGB color space
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        
        
        // Create a bitmap graphics context with the sample buffer data
        CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                     bytesPerRow, colorSpace, kCGImageAlphaNoneSkipLast);
        
        // Create a Quartz image from the pixel data in the bitmap graphics context
        CGImageRef quartzImage = CGBitmapContextCreateImage(context);
        // Unlock the pixel buffer
        CVPixelBufferUnlockBaseAddress(imageBuffer,kCVPixelBufferLock_ReadOnly);
        
        // Free up the context and color space
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);
        
        // Create an image object from the Quartz image
        UIImage *image = [UIImage imageWithCGImage:quartzImage];
        
        // Release the Quartz image
        CGImageRelease(quartzImage);
        
        return (image);
 
    }
    return nil;
 }



@end
