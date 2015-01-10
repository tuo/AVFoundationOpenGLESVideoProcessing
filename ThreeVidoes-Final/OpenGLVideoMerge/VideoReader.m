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
@property(nonatomic) AVAsset *asset;
@property(nonatomic) AVAssetReader *assetReader;
@property(nonatomic) AVAssetReaderTrackOutput *assetReaderOutput;
@end

@implementation VideoReader {
    GLuint outputTexture;
    CVOpenGLESTextureRef texture;
    GLuint framebuffer;
}

-(AVAssetReader *)avReader{
    return self.assetReader;
}

-(AVAssetReaderTrackOutput *)avReaderOutput{
    return self.assetReaderOutput;
}


- (id)initWithURL:(NSURL *)pUrl {
    self = [super init]; 
    if (self) {
        self.url = pUrl;
    }

    return self;
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

- (AVAssetTrack *)audioTrack{
    NSAssert(self.asset, @"Asset should be inited before access");
    NSArray *audioTracks = [self.asset tracksWithMediaType:AVMediaTypeAudio];
    return audioTracks.firstObject;
}

- (void)startProcessing{
    dispatch_group_enter([ContextManager shared].readingAllReadyDispatchGroup);
    self.asset = [AVAsset assetWithURL:_url];
    CMTime duration = self.asset.duration;
    CGFloat durationInSeconds = (CGFloat) CMTimeGetSeconds(duration);
    __weak typeof(self) weakSelf = self;
    [self.asset loadValuesAsynchronouslyForKeys:@[@"tracks"] completionHandler:^{
        // Once the tracks have finished loading, dispatch the work to the main serialization queue.
        dispatch_async([ContextManager shared].mainSerializationQueue, ^{
            BOOL success = YES;
            NSError *localError = nil;
            // Check for success of loading the assets tracks.
            success = ([weakSelf.asset statusOfValueForKey:@"tracks" error:&localError] == AVKeyValueStatusLoaded);
            if (success)
            {
                NSLog(@"check audio track count: %d for asset: %@", [weakSelf.asset tracksWithMediaType:AVMediaTypeAudio].count, self.url.lastPathComponent);
            }

            if (success){
                [weakSelf setupAssetReader];
            }
            if (success){
                [weakSelf startAssetReader];
            }

            dispatch_group_leave([ContextManager shared].readingAllReadyDispatchGroup);
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
            [ContextManager shared].coreVideoTextureCache,
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
    if(texture != NULL){
        CFRelease(texture);
        texture = NULL;
    }
    CVOpenGLESTextureCacheFlush([ContextManager shared].coreVideoTextureCache, 0);

    NSLog(@"clean up resources: %@", self.url.lastPathComponent);
    if(output.sampleBuffer != NULL){
        CMSampleBufferInvalidate(output.sampleBuffer);
        CFRelease(output.sampleBuffer);
        output.sampleBuffer = NULL;
    }

    outputTexture = 0;
}

@end