//
// Created by Tuo on 11/14/13.
// Copyright (c) 2013 Tuo. All rights reserved.
//


#import "VideoReader.h"

#import "ViewController.h"

#import "SVProgressHUD.h"
#import "VideoWriter.h"
#import "ContextManager.h"
#import "Util.h"
#import "FrameRenderOutput.h"
#import <OpenGLES/ES2/glext.h>

@interface VideoReader ()
@property(nonatomic, strong) NSURL *url;
@property(nonatomic, strong) VideoWriter *videoWriter;

@property(nonatomic) AVAsset *asset;
@property(nonatomic) AVAssetReader *assetReader;
@property(nonatomic) AVAssetReaderTrackOutput *assetReaderOutput;
@property(nonatomic) NSString *videoName;
@end

@implementation VideoReader {


    CVPixelBufferRef _boomiPixelBuffer;
    GLuint outputTexture;
    CVOpenGLESTextureRef texture;
    CVOpenGLESTextureCacheRef coreVideoTextureCache;

    GLuint framebuffer;
//    EAGLContext *_context;
    dispatch_queue_t rQueue;
    
    int processedFrameCount;
}

-(AVAssetReader *)avReader{
    return self.assetReader;
}

-(AVAssetReaderTrackOutput *)avReaderOutput{
    return self.assetReaderOutput;
}


- (id)initWithURL:(NSURL *)pUrl withVideoWriter:(VideoWriter *)pWriter withEAGLContext:(EAGLContext *)context {
    self = [super init]; 
    if (self) {
//        _context = context;
//        if (![EAGLContext setCurrentContext:_context]) {
//            NSLog(@"Failed to set current OpenGL context");
//            exit(1);
//        }
        self.url = pUrl;
        self.videoWriter = pWriter;
        self.videoName = [[pUrl relativePath] lastPathComponent];
        [self setup];
    }

    return self;
}

- (void)setup {
    [self setupOpenGLESTextureCache];
    //_boomiPixelBuffer = [self pixelBufferFromCGImage:[[UIImage imageNamed:@"boomi5"] CGImage]];
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

- (void)setupOpenGLESTextureCache {
    // Create a new CVOpenGLESTexture cache
    //-- Create CVOpenGLESTextureCacheRef for optimal CVImageBufferRef to GLES texture conversion.
#if COREVIDEO_USE_EAGLCONTEXT_CLASS_IN_API
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, [ContextManager shared].currentContext, NULL, &coreVideoTextureCache);
#else
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (__bridge void *)([ContextManager shared].currentContext), NULL, &coreVideoTextureCache);
    #endif
    if (err) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        exit(1);
    }
}



- (void)teardown{

}

- (void)setupAssetReader {
   
    NSError* error;
    self.assetReader = [AVAssetReader assetReaderWithAsset:self.asset error:&error];
    NSParameterAssert(self.assetReader);


    NSDictionary *outputSettings = @{
            (id)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA)
    };

    NSArray *videoTracks = [self.asset tracksWithMediaType:AVMediaTypeVideo];
    AVAssetTrack *videoTrack = [videoTracks objectAtIndex:0];

    self.assetReaderOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:videoTrack
                                                                     outputSettings:outputSettings];

    //
    NSParameterAssert(self.assetReaderOutput);
    NSParameterAssert([self.assetReader canAddOutput:self.assetReaderOutput]);
    [self.assetReader addOutput:self.assetReaderOutput];
    
}


- (void)startProcessing{
    dispatch_group_enter(UTIL.dispatchGroup);
    self.asset = [AVAsset assetWithURL:_url];
    CMTime duration = self.asset.duration;
    CGFloat durationInSeconds = (CGFloat) CMTimeGetSeconds(duration);
    __weak typeof(self) weakSelf = self;
    [self.asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        // Once the tracks have finished loading, dispatch the work to the main serialization queue.
        dispatch_async(UTIL.mainSerializationQueue, ^{
            BOOL success = YES;
            NSError *localError = nil;
            // Check for success of loading the assets tracks.
            success = ([self.asset statusOfValueForKey:@"tracks" error:&localError] == AVKeyValueStatusLoaded);
            if (success)
            {
                // If the tracks loaded successfully, make sure that no file exists at the output path for the asset writer.
//                NSFileManager *fm = [NSFileManager defaultManager];
//                NSString *localOutputPath = [self.outputURL path];
//                if ([fm fileExistsAtPath:localOutputPath])
//                    success = [fm removeItemAtPath:localOutputPath error:&localError];
            }
            if (success){
                [self setupAssetReader];
            }
            if (success){
                [self startAssetReader];
            }

            dispatch_group_leave(UTIL.dispatchGroup);
//            if (!success)
//                [self readingAndWritingDidFinishSuccessfully:success withError:localError];
        });
    }];
}
- (void)startAssetReader {
    __weak typeof(self) weakSelf = self;
    if (![self.assetReader startReading])
    {
        NSLog(@"Error reading from file at URL: %@", self.url);
        return;
    }

    NSLog(@"asset %@ is good to read...", self.url);
}

//- (void)processMovieFrame:(CVPixelBufferRef)movieFrame withSampleTime:(CMTime)currentSampleTime
- (void)processMovieFrame:(CMSampleBufferRef)movieSampleBuffer;
{
    
    CMTime currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(movieSampleBuffer);
    CVImageBufferRef movieFrame = CMSampleBufferGetImageBuffer(movieSampleBuffer);
    
    
    [[ContextManager shared] useCurrentContext];
    
    CVPixelBufferLockBaseAddress(movieFrame, 0);
    
    int bufferHeight = CVPixelBufferGetHeight(movieFrame);
    int bufferWidth = CVPixelBufferGetWidth(movieFrame);

    if(!framebuffer){
        glGenFramebuffers(1, &framebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);



    CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
            coreVideoTextureCache,
            movieFrame,
            NULL,
            GL_TEXTURE_2D,
            GL_RGBA,
            bufferWidth,
            bufferHeight,
            GL_BGRA,
            GL_UNSIGNED_BYTE,
            0,
            &texture);

    if (!texture || err) {
        NSLog(@"Movie CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err);
        NSAssert(NO, @"Camera failure");
        return;
    }

    outputTexture = CVOpenGLESTextureGetName(texture);
    //        glBindTexture(CVOpenGLESTextureGetTarget(texture), outputTexture);
    glBindTexture(GL_TEXTURE_2D, outputTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, CVOpenGLESTextureGetName(texture), 0);

//    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
//    NSAssert(status == GL_FRAMEBUFFER_COMPLETE, @"Incomplete filter FBO: %d", status);

//    NSLog(@"videoName: %@ output texture: %d", videoName, outputTexture);
//    [currentTarget setInputSize:CGSizeMake(bufferWidth, bufferHeight) atIndex:_targetTextureIndex];
//    [currentTarget setInputTexture:outputTexture atIndex:_targetTextureIndex];
//    [currentTarget setTextureDelegate:self atIndex:_targetTextureIndex];
//    [currentTarget newFrameReadyAtTime:currentSampleTime atIndex:_targetTextureIndex];
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    NSLog(@"video name: %@, prepare for upload frame to writer: %d", self.videoName, processedFrameCount);
    
    
    dispatch_async(self.writerQueue, ^{
        [_videoWriter newFrameReadyAtTime:currentSampleTime inputTexture:outputTexture atIndex:_targetTextureIndex doneFrameCount: processedFrameCount videoName:self.videoName semaphore:^{
            dispatch_semaphore_signal(semaphore);
        } videoDuration: self.asset.duration];
    });
    
 
    
    
    
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
        NSLog(@"==video name: %@, finished upload frame to writer: %d", self.videoName, processedFrameCount);
        CVPixelBufferUnlockBaseAddress(movieFrame, 0);
        CVOpenGLESTextureCacheFlush(coreVideoTextureCache, 0);
        CFRelease(texture);
        
        outputTexture = 0;
        
        NSLog(@"invalidate and release buffer for index: %d", self.targetTextureIndex);
        CMSampleBufferInvalidate(movieSampleBuffer);
        CFRelease(movieSampleBuffer);
        
        
      //  dispatch_resume(rQueue);
        
   
    
    
    //stop here
  
    
    
//    if (outputTexture)
//    {
//        glDeleteTextures(1, &outputTexture);
//        outputTexture = 0;
//    }
//    if(texture){
//        CFRelease(texture);
//    }

}


- (FrameRenderOutput *)renderNextFrame{

    CMSampleBufferRef sampleBuffer = [self.avReaderOutput copyNextSampleBuffer];
    NSLog(@"%@, sampleBuffer: %d, reader status: %d", self.url.lastPathComponent, sampleBuffer != nil, self.assetReader.status);

    if(sampleBuffer == nil){
        NSLog(@"%@ ----- reading done", self.url.lastPathComponent);
        FrameRenderOutput *frameRenderOutput = [[FrameRenderOutput alloc] init];
        frameRenderOutput.sampleBuffer = nil;
        return frameRenderOutput;
    }


    CMTime currentSampleTime = CMSampleBufferGetOutputPresentationTimeStamp(sampleBuffer);
    CVImageBufferRef movieFrame = CMSampleBufferGetImageBuffer(sampleBuffer);


    [[ContextManager shared] useCurrentContext];

    CVPixelBufferLockBaseAddress(movieFrame, 0);

    int bufferHeight = CVPixelBufferGetHeight(movieFrame);
    int bufferWidth = CVPixelBufferGetWidth(movieFrame);

    if(!framebuffer){
        glGenFramebuffers(1, &framebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    }
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);



    CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
            coreVideoTextureCache,
            movieFrame,
            NULL,
            GL_TEXTURE_2D,
            GL_RGBA,
            bufferWidth,
            bufferHeight,
            GL_BGRA,
            GL_UNSIGNED_BYTE,
            0,
            &texture);

    if (!texture || err) {
        NSLog(@"Movie CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err);
        NSAssert(NO, @"Camera failure");
        return nil;
    }

    outputTexture = CVOpenGLESTextureGetName(texture);
    //        glBindTexture(CVOpenGLESTextureGetTarget(texture), outputTexture);
    glBindTexture(GL_TEXTURE_2D, outputTexture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, CVOpenGLESTextureGetName(texture), 0);


    FrameRenderOutput *frameRenderOutput = [[FrameRenderOutput alloc] init];
    frameRenderOutput.outputTexture = outputTexture;
    frameRenderOutput.inputTexture = texture;
    frameRenderOutput.frameTime = currentSampleTime;
    frameRenderOutput.sampleBuffer = sampleBuffer;

    NSLog(@"%@, frameRenderOutput: %@", self.url.lastPathComponent, frameRenderOutput);
    return frameRenderOutput;
}

- (void)cleanupResource:(FrameRenderOutput *)output {
    CVOpenGLESTextureCacheFlush(coreVideoTextureCache, 0);
    CFRelease(texture);

    NSLog(@"clean up resources: %@", self.url.lastPathComponent);
    CMSampleBufferInvalidate(output.sampleBuffer);
    CFRelease(output.sampleBuffer);
    output.sampleBuffer = NULL;

    outputTexture = 0;

}

@end