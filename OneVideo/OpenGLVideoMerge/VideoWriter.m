//
// Created by Tuo on 11/9/13.
// Copyright (c) 2013 Tuo. All rights reserved.
//


#import "VideoWriter.h"
#import "SVProgressHUD.h"
#import "ContextManager.h"
#import "VideoReader.h"
#import "FrameRenderOutput.h"
#import <AssetsLibrary/ALAssetsLibrary.h>
#import <OpenGLES/ES2/glext.h>
//const NSString* VERTEX_SHADER_FILENAME = @"SmokeVertex";
//const NSString* FRAGMENT_SHADER_FILENAME = @"SmokeFragment";

NSString* VERTEX_SHADER_FILENAME = @"SimpleVertex";
NSString* FRAGMENT_SHADER_FILENAME = @"SimpleFragment";


struct Vector3 {
    GLfloat one;
    GLfloat two;
    GLfloat three;
};
typedef struct Vector3 Vector3;

@interface VideoWriter ()

//AssetWriter
@property(nonatomic) NSURL *outputURL;
@property(nonatomic) CGSize videoSize;
@property(nonatomic) dispatch_queue_t movieWritingQueue;
@property(nonatomic) AVAssetWriter *assetWriter;
@property(nonatomic) AVAssetWriterInput *assetWriterVideoInput;
@property(nonatomic) AVAssetWriterInputPixelBufferAdaptor *assetWriterPixelBufferInput;
@property(nonatomic) ALAssetsLibrary *assetLibrary;

- (void)kickoffProcessing;
@end

@implementation VideoWriter {
//    EAGLContext *_context;
    
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

    CVOpenGLESTextureCacheRef _textureCache;
    CVOpenGLESTextureRef _texture;
    CVPixelBufferRef _pixelBuffer;



    GLuint outputTexture1, outputTexture2;
    CMTime firstFrameTime, secondFrameTime;
    CMTime lastFrameTime;
    BOOL hasReceivedFirstFrame, hasReceivedSecondFrame;
    BOOL alreadyFinishedRecording;

    BOOL videoEncodingIsFinished;

    dispatch_queue_t wQueue;
    
    EmptyBlock semaphore1, semaphore2;
    
    NSMutableArray *writtenFrameTimes;
    
    NSMutableArray *writtenCombined;
}


- (id)init {
    self = [super init];
    if (self) {
        [self setup];

    }

    return self;
}

- (id)initWithEAGLContext:(EAGLContext *)context{
    self = [super init];
    if (self) {
//        _context = context;
//        if (![EAGLContext setCurrentContext:_context]) {
//            NSLog(@"Failed to set current OpenGL context");
//            exit(1);
//        }
        [self setup];
    }

    return self;
}

- (void)setup {
    writtenFrameTimes = [NSMutableArray array];
    writtenCombined = [NSMutableArray array];
    self.videoSize = CGSizeMake(640, 640);

    [self setupOpenGLESTextureCache];
    [self compileShaders];


    [self setupDisplayLink];
}

- (void)startAssetWriter {
    BOOL success = [self.assetWriter startWriting];
    if (!success){
        NSLog(@"asset write start writing failed: %@", self.assetWriter.error);
        return;
    }
    [self.assetWriter startSessionAtSourceTime:kCMTimeZero];
    NSLog(@"asset write is good to write...");
}

- (void)startRecording {
    dispatch_async(UTIL.mainSerializationQueue, ^{
        [self setupAssetWriter];
        [self startAssetWriter];

        // Set up the notification that the dispatch group will send when the audio and video work have both finished.
        dispatch_group_notify(UTIL.dispatchGroup, UTIL.mainSerializationQueue, ^{
            NSLog(@"all set, readers and writer both are ready");

            [self kickoffRecording];
        });
    });
}

- (void)kickoffRecording {
    [self.assetWriterVideoInput requestMediaDataWhenReadyOnQueue:UTIL.rwVideoSerializationQueue usingBlock:^{
        BOOL completedOrFailed = NO;
        // If the task isn't complete yet, make sure that the input is actually ready for more media data.
        while ([self.assetWriterVideoInput isReadyForMoreMediaData] && !completedOrFailed)
        {

            FrameRenderOutput *fxFrameOutput = [self.readerFX renderNextFrame];

            if(!fxFrameOutput.sampleBuffer){
                //reading done
                completedOrFailed = YES;
            } else {
                NSLog(@"------------ready-------recevied both:%d", fxFrameOutput.outputTexture);

                CVPixelBufferLockBaseAddress(_pixelBuffer, 0);

                [[ContextManager shared] useCurrentContext];

                if(_frameBuffer == 0){
                    [self createFrameBufferObject];

                }
                glBindFramebuffer(GL_FRAMEBUFFER, _frameBuffer);

                glClearColor(0.0, 0.0, 0.0, 1.0);
                glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

                glViewport(0, 0, (int)self.videoSize.width, (int)self.videoSize.height);
                //use shader program
                NSAssert(_program, @"Program should be created");
                glUseProgram(_program);


                // This needs to be flipped to write out to video correctly
                static const GLfloat squareVertices[] = {
                        -1.0f, -1.0f,
                        1.0f, -1.0f,
                        -1.0f,  1.0f,
                        1.0f,  1.0f,
                };

                static const GLfloat textureCoordinates[] = {
                        0.0f, 0.0f,
                        1.0f, 0.0f,
                        0.0f, 1.0f,
                        1.0f, 1.0f,
                };
                glVertexAttribPointer(_positionSlot, 2, GL_FLOAT, 0, 0, squareVertices);
                glVertexAttribPointer(_srcTexCoord1Slot, 2, GL_FLOAT, 0, 0, textureCoordinates);

                //bind uniforms
                glUniform1f(_thresholdUniform, 0.4f);
                glUniform1f(_smoothingUniform, 0.1f);

                Vector3 colorToReplaceVec3 = {0.0f, 1.0f, 0.0f};
                glUniform3fv(_colorToReplaceUniform, 1, (GLfloat *)&colorToReplaceVec3);

                glActiveTexture(GL_TEXTURE2);
                glBindTexture(GL_TEXTURE_2D, fxFrameOutput.outputTexture);
                glUniform1i(_srcTexture1Uniform, 2);


                glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
                glFinish();


                //CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);


                CMTime frameTime = fxFrameOutput.frameTime;
                [writtenFrameTimes addObject:[NSValue valueWithCMTime:frameTime]];

                NSLog(@"ready to write video at frame: %@ in seconds: %.2f, valid?: %d, indefinite: %d, last frame: %@ in seconds: %.2f, is same: %d",CMTimeDebug(frameTime), CMTimeGetSeconds(frameTime), CMTIME_IS_VALID(frameTime), CMTIME_IS_INDEFINITE(frameTime), CMTimeDebug(lastFrameTime),CMTimeGetSeconds(lastFrameTime), CMTimeCompare(frameTime, lastFrameTime));


                if(CMTimeCompare(frameTime, lastFrameTime) == NSOrderedSame){
                    NSLog(@"***********************FATAL ERROR, frame times are same");
                }

                //CVPixelBufferLockBaseAddress(_pixelBuffer, 0);

                BOOL writeSucceeded = [self.assetWriterPixelBufferInput appendPixelBuffer:_pixelBuffer withPresentationTime:frameTime];

                CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);

                if(writeSucceeded){
                    NSLog(@"==================dWrote a video frame: %@", CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, frameTime)));
                    lastFrameTime = frameTime;
                }else{
                    //  NSLog(@"pixel buffer pool : %@", assetWriterPixelBufferInput.pixelBufferPool);
                    NSLog(@"Problem appending pixel buffer at time: %@ with error: %@", CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, frameTime)), self.assetWriter.error);

                    lastFrameTime = frameTime;

                    NSLog(@"----------------print all frames");
                    for(NSValue *value in writtenFrameTimes){
                        NSLog(@"\t time: %@", CMTimeDebug(value.CMTimeValue));
                    }
                    exit(0);

                }

                // Flush the CVOpenGLESTexture cache and release the texture
                //CVOpenGLESTextureCacheFlush(_textureCache, 0);

                [self.readerFX cleanupResource:fxFrameOutput];


            }

        }
        if (completedOrFailed)
        {
            NSLog(@"mark as finish");
            // Mark the input as finished, but only if we haven't already done so, and then leave the dispatch group (since the video work has finished).
            [self.assetWriterVideoInput markAsFinished];
            [self.assetWriter finishWritingWithCompletionHandler:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    [SVProgressHUD showWithStatus:@"Write done"];
                    if(self.onWritingFinishedBlock){
                        self.onWritingFinishedBlock(self.outputURL);
                    }
                });
            }];
        }
    }];
}


- (void)setupOpenGLESTextureCache {
    // Create a new CVOpenGLESTexture cache
    //-- Create CVOpenGLESTextureCacheRef for optimal CVImageBufferRef to GLES texture conversion.
#if COREVIDEO_USE_EAGLCONTEXT_CLASS_IN_API
    CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, [ContextManager shared].currentContext, NULL, &_textureCache);
#else
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (__bridge void *)([ContextManager shared].currentContext), NULL, &_textureCache);
    #endif
    if (err) {
        NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
        exit(1);
    }
}



#pragma mark compileShaders
- (void)compileShaders {

    // 1
    GLuint vertexShader = [self compileShader:VERTEX_SHADER_FILENAME withType:GL_VERTEX_SHADER];
    GLuint fragmentShader = [self compileShader:FRAGMENT_SHADER_FILENAME withType:GL_FRAGMENT_SHADER];

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
    _srcTexCoord1Slot = glGetAttribLocation(_program, "srcTexCoordIn1");

    glEnableVertexAttribArray(_positionSlot);
    glEnableVertexAttribArray(_srcTexCoord1Slot);

    _thresholdUniform = glGetUniformLocation(_program, "thresholdSensitivity");
    _smoothingUniform = glGetUniformLocation(_program, "smoothing");
    _colorToReplaceUniform = glGetUniformLocation(_program, "colorToReplace");

    _srcTexture1Uniform = glGetUniformLocation(_program, "srcTexture1");
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

#pragma mark setupAssetWriter

- (void)setupAssetWriter {
    // Do any additional setup after loading the view.

    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
//    NSString *myPathDocs =  [documentsDirectory stringByAppendingPathComponent:@"merge-output.mov"];
    NSString *myPathDocs =  [documentsDirectory stringByAppendingPathComponent:
            [NSString stringWithFormat:@"merge-output-%d.mov",arc4random() % 1000]];
    self.outputURL = [NSURL fileURLWithPath:myPathDocs];

    // If the tracks loaded successfully, make sure that no file exists at the output path for the asset writer.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *localOutputPath = [self.outputURL path];
    if ([fm fileExistsAtPath:localOutputPath]){
        [fm removeItemAtPath:localOutputPath error:nil];
    }



    NSLog(@"setupAssetWriter outputURL: %@", self.outputURL );

    self.movieWritingQueue = dispatch_queue_create("tuo.test.movieWritingQueue", NULL);


    NSError *error;
    self.assetWriter = [AVAssetWriter assetWriterWithURL:self.outputURL
                                           fileType:AVFileTypeQuickTimeMovie error:&error];

    NSParameterAssert(self.assetWriter);



    NSDictionary *videoSettings = @{
            AVVideoCodecKey : AVVideoCodecH264,
            AVVideoWidthKey : @(self.videoSize.width),
            AVVideoHeightKey : @(self.videoSize.height)
    };




    self.assetWriterVideoInput =  [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                outputSettings:videoSettings];

    // You need to use BGRA for the video in order to get realtime encoding. I use a color-swizzling shader to line up glReadPixels' normal RGBA output with the movie input's BGRA.
    NSDictionary *sourcePixelBufferAttributesDictionary = [NSDictionary dictionaryWithObjectsAndKeys: [NSNumber numberWithInt:kCVPixelFormatType_32BGRA], kCVPixelBufferPixelFormatTypeKey,
                                                                                                      [NSNumber numberWithInt:self.videoSize.width], kCVPixelBufferWidthKey,
                                                                                                      [NSNumber numberWithInt:self.videoSize.height], kCVPixelBufferHeightKey,
                                                                                                      nil];

    self.assetWriterPixelBufferInput = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.assetWriterVideoInput
                                                                                                   sourcePixelBufferAttributes:sourcePixelBufferAttributesDictionary];




    NSParameterAssert(self.assetWriterVideoInput);
    NSParameterAssert([self.assetWriter canAddInput:self.assetWriterVideoInput]);
    [self.assetWriter addInput:self.assetWriterVideoInput];


    

//    AVAssetWriterInput *audioInput =  [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
//                                                                         outputSettings:nil];
//
//    NSParameterAssert(audioInput);
//    NSParameterAssert([assetWriter canAddInput:audioInput]);
//    [assetWriter addInput:audioInput];
}

#pragma mark newVideoFrame


#pragma mark FBO initialization -- this only triggered once to improve performance
- (void)createFrameBufferObject {
    //first disable depth test if exists
    glDisable(GL_DEPTH_TEST);
    
    //create FBO
    glGenFramebuffers(1, &_frameBuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBuffer);
    
    
 
    NSAssert([self.assetWriterPixelBufferInput pixelBufferPool], @"pixel pool is nil");
    
    // Code originally sourced from http://allmybrain.com/2011/12/08/rendering-to-a-texture-with-ios-5-texture-cache-api/
    CVPixelBufferPoolCreatePixelBuffer (NULL, [self.assetWriterPixelBufferInput pixelBufferPool], &_pixelBuffer);
   
    
    CVOpenGLESTextureCacheCreateTextureFromImage (kCFAllocatorDefault, _textureCache, _pixelBuffer,
                                                  NULL, // texture attributes
                                                  GL_TEXTURE_2D,
                                                  GL_RGBA, // opengl format
                                                  (int)self.videoSize.width,
                                                  (int)self.videoSize.height,
                                                  GL_BGRA, // native iOS format
                                                  GL_UNSIGNED_BYTE,
                                                  0,
                                                  &_texture);
    
    glBindTexture(CVOpenGLESTextureGetTarget(_texture), CVOpenGLESTextureGetName(_texture));
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, CVOpenGLESTextureGetName(_texture), 0);
    
    GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
    
    NSAssert(status == GL_FRAMEBUFFER_COMPLETE, @"Incomplete filter FBO: %d", status);
   
    
    

    
}

- (void)finish {

    dispatch_async(dispatch_get_main_queue(), ^{
        if(self.onWritingFinishedBlock){
            self.onWritingFinishedBlock(nil);
        }
    });
    if(!alreadyFinishedRecording){
        alreadyFinishedRecording = YES;
        __weak typeof(self) weakSelf = self;
        //dispatch_sync(wQueue, ^{

//            dispatch_sync(movieWritingQueue, ^{
                NSLog(@"finished recording, frame time: %f", CMTimeGetSeconds(firstFrameTime));

                //    [assetWriter endSessionAtSourceTime:firstFrameTime];
                if (self.assetWriter.status == AVAssetWriterStatusCompleted || self.assetWriter.status == AVAssetWriterStatusCancelled || self.assetWriter.status == AVAssetWriterStatusUnknown)
                {
                    return;
                }
                if( self.assetWriter.status == AVAssetWriterStatusWriting  || !videoEncodingIsFinished)
                {
                    videoEncodingIsFinished = YES;
                    [self.assetWriterVideoInput markAsFinished];
                }

                [self.assetWriter finishWritingWithCompletionHandler:^{

                    if (self.assetWriter.error == nil)
                    {
                        NSLog(@"saved ok - writing to lib");
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [SVProgressHUD setStatus:@"writing done, save to camera roll"];
                        });

                        [weakSelf writeMovieToLibrary];
                    } else
                    {
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [SVProgressHUD showErrorWithStatus:@"Writing failed"];
                        });
                        NSLog(@" did not save due to error %@", self.assetWriter.error);
                    }
                }];
           // });
//        });
    }else{

        NSLog(@"already finished, skip");
    }
}



- (void)writeMovieToLibrary {
    NSLog(@"writing %@ to library", self.outputURL);
    if(!self.assetLibrary){
        self.assetLibrary = [[ALAssetsLibrary alloc] init];
    }

    [self.assetLibrary writeVideoAtPathToSavedPhotosAlbum:self.outputURL
                                completionBlock:^(NSURL *assetURL, NSError *error) {
                                    if (error)
                                    {
                                        dispatch_async(dispatch_get_main_queue(), ^{
                                            [SVProgressHUD showErrorWithStatus:@"Saving to camera roll failed"];
                                        });
                                        NSLog(@"Error saving to library%@", [error localizedDescription]);
                                    } else
                                    {
                                        NSLog(@"SAVED to photo lib");
                                        dispatch_async(dispatch_get_main_queue(), ^{
                                            [SVProgressHUD showSuccessWithStatus:@"Done"];
                                        });

                                    }
                                }];
}

- (void)setupDisplayLink {
    CADisplayLink* displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(render:)];
    [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
}

- (void)render:(CADisplayLink*)displayLink {
    
}

- (void)newFrameReadyAtTime:(CMTime)frameTime inputTexture:(GLuint)texture atIndex:(int)index doneFrameCount:(int)doneCount videoName:(NSString*)videoName semaphore:(EmptyBlock)semaphore videoDuration: (CMTime)duration{
    if (hasReceivedFirstFrame && hasReceivedSecondFrame)
    {
        return;
    }
    
    NSLog(@"newFrameReadyAtTime %d frameTime: %@, in total duration: %@, is in: %d, videoName: %@ doneCount: %d", index, CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, frameTime)), CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, duration)), CMTimeCompare(frameTime, duration),  videoName, doneCount);
    
    if(CMTimeCompare(frameTime, duration)){
        
    }
    
    if(index == 1){
        outputTexture1 = texture;
        firstFrameTime = frameTime;
        hasReceivedFirstFrame = YES;
        semaphore1 = semaphore;
        
    }else if(index == 2){
        outputTexture2 = texture;
        secondFrameTime = frameTime;
        hasReceivedSecondFrame = YES;
        semaphore2 = semaphore;
    }
    
    if (hasReceivedFirstFrame && hasReceivedSecondFrame)
    {
        CMTime passOnFrameTime = (!CMTIME_IS_INDEFINITE(firstFrameTime)) ? firstFrameTime : secondFrameTime;
        //        [self renderAtInternalSize];
        //DO NOT USE ASYNC WHICH CAUSE PROBLEM !!!!!
       // dispatch_async(wQueue, ^{
          
            NSLog(@"prepare write video frame at index: %d, videoname: %@, doneCount: %d, first frame: %@, second frame: %@", index, videoName, doneCount, CMTimeDebug(firstFrameTime), CMTimeDebug(secondFrameTime));
        
            NSString *frameString = [NSString stringWithFormat:@"%.2f - %.2f", CMTimeGetSeconds(firstFrameTime), CMTimeGetSeconds(secondFrameTime)];
        
            [writtenCombined addObject:frameString];
            [self renderAtInternalSize];
          
            //NSLog(@"done write video frame, resume queues");
            //resume queue
//            dispatch_resume(self.readFXQueue);
//            dispatch_resume(self.readRawQueue);
       // });
        
    }else{
        if(!hasReceivedFirstFrame && !hasReceivedSecondFrame){
            NSLog(@"Both frame not received yet");
        }else if(!hasReceivedFirstFrame && hasReceivedSecondFrame){
            NSLog(@"Second frame received, waiting for first frame...");
            
            CMTime durationOfFirst= [self.readerFX avReader].asset.duration;
            NSLog(@"duration of first: %@, second frame : %@", CMTimeDebug(durationOfFirst), CMTimeDebug(secondFrameTime));
            if(CMTimeCompare(secondFrameTime, durationOfFirst) != NSOrderedAscending ){
                NSLog(@"---second frame time is over fist dration");
                
                
                            NSLog(@"------complted---------");
                
                semaphore1();
                semaphore2();
                            [self.readerFX.avReader cancelReading];
                            [self.readerRaw.avReader cancelReading];
                            [self finish];
            }
            
        }else if(hasReceivedFirstFrame && !hasReceivedSecondFrame){
            NSLog(@"First frame received, waiting for second frame...");
            
            CMTime durationOfSecond= [self.readerRaw avReader].asset.duration;
            NSLog(@"duration of second: %@, first frame : %@", CMTimeDebug(durationOfSecond), CMTimeDebug(firstFrameTime));
            if(CMTimeCompare(firstFrameTime, durationOfSecond) != NSOrderedAscending ){
                NSLog(@"---first frame time is over secnd dration");
                NSLog(@"------complted---------");
                [self.readerFX.avReader cancelReading];
                [self.readerRaw.avReader cancelReading];
                [self finish];
            }
        }
        
        //        NSLog(@"done--------writing ?");
        NSLog(@"not receving both, check reader status. reader fx: %@ , reader raw: %@", [self statusOfReader:self.readerFX.avReader],  [self statusOfReader:self.readerRaw.avReader]);
        
        
        
        //NSLog(@"write combined: %@", writtenCombined);

        
       

        //frame time
        
//        if(self.readerFX.avReader.status == AVAssetReaderStatusCompleted || self.readerRaw.avReader.status == AVAssetReaderStatusCompleted){
//            NSLog(@"------complted---------");
//            [self.readerFX.avReader cancelReading];
//            [self.readerRaw.avReader cancelReading];
//            [self finish];
//        }
    }
    
    //    if(outputTexture1 != 0 && outputTexture2 != 0){
    
    //    }
    
    //    [self renderAtInternalSize];
    
    //    if(outputTexture1 != 0 && outputTexture2 != 0){
    //        //render it to opengl texture frame buffer
    //        [self renderAtInternalSize];
    //    }
    //    if(outputTexture1 != 0 && outputTexture2 != 0 && (CMTIME_IS_VALID(firstFrameTime)) && (CMTIME_IS_VALID(secondFrameTime))){
    //        //render it to opengl texture frame buffer
    //        [self renderAtInternalSize];
    //    }

}


- (NSString *)statusOfReader:(AVAssetReader *)reader{
    if(reader.status == AVAssetReaderStatusReading){
        return @"reading";
    }else if(reader.status == AVAssetReaderStatusCompleted){
        return @"completed";
    }else if(reader.status == AVAssetReaderStatusFailed){
        return @"failed";
    }else if(reader.status == AVAssetReaderStatusCancelled){
        return @"cancel";
    }
    return @"unknown";
}


- (void)renderAtInternalSize;
{
    CVPixelBufferLockBaseAddress(_pixelBuffer, 0);
   
    [[ContextManager shared] useCurrentContext];

    if(_frameBuffer == 0){
        [self createFrameBufferObject];
        
    }
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBuffer);

    glClearColor(0.0, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    glViewport(0, 0, (int)self.videoSize.width, (int)self.videoSize.height);
    //use shader program
    NSAssert(_program, @"Program should be created");
    glUseProgram(_program);

  
    // This needs to be flipped to write out to video correctly
    static const GLfloat squareVertices[] = {
        -1.0f, -1.0f,
        1.0f, -1.0f,
        -1.0f,  1.0f,
        1.0f,  1.0f,
    };
    
    static const GLfloat textureCoordinates[] = {
        0.0f, 0.0f,
        1.0f, 0.0f,
        0.0f, 1.0f,
        1.0f, 1.0f,
    };
    glVertexAttribPointer(_positionSlot, 2, GL_FLOAT, 0, 0, squareVertices);
    glVertexAttribPointer(_srcTexCoord1Slot, 2, GL_FLOAT, 0, 0, textureCoordinates);


    //bind uniforms
    glUniform1f(_thresholdUniform, 0.4f);
    glUniform1f(_smoothingUniform, 0.1f);

    Vector3 colorToReplaceVec3 = {0.0f, 1.0f, 0.0f};
    glUniform3fv(_colorToReplaceUniform, 1, (GLfloat *)&colorToReplaceVec3);

    glActiveTexture(GL_TEXTURE2);
    glBindTexture(GL_TEXTURE_2D, outputTexture1);
    glUniform1i(_srcTexture1Uniform, 2);

    glActiveTexture(GL_TEXTURE3);
    glBindTexture(GL_TEXTURE_2D, outputTexture2);
    glUniform1i(_srcTexture2Uniform, 3);

    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glFinish();

    
    CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);

    
//    CVPixelBufferPoolCreatePixelBuffer (NULL, [assetWriterPixelBufferInput pixelBufferPool], &_pixelBuffer);
//    
//    NSAssert(assetWriterPixelBufferInput.pixelBufferPool, @"assetWriterPixelBufferInput could not nil");
    //cool let 's get the data back!
  
            CMTime frameTime = firstFrameTime;
            [writtenFrameTimes addObject:[NSValue valueWithCMTime:frameTime]];
        
            NSLog(@"ready to write video at frame: %@ in seconds: %.2f, valid?: %d, indefinite: %d, last frame: %@ in seconds: %.2f, is same: %d",CMTimeDebug(frameTime), CMTimeGetSeconds(frameTime), CMTIME_IS_VALID(frameTime), CMTIME_IS_INDEFINITE(frameTime), CMTimeDebug(lastFrameTime),CMTimeGetSeconds(lastFrameTime), CMTimeCompare(frameTime, lastFrameTime));
    
    
    if(CMTimeCompare(frameTime, lastFrameTime) == NSOrderedSame){
        NSLog(@"***********************FATAL ERROR, frame times are same");
    }
        
        
            while( ! self.assetWriterVideoInput.readyForMoreMediaData && !videoEncodingIsFinished) {
                NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:0.1];
                NSLog(@"video waiting...");
                [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
            }
            if (!self.assetWriterVideoInput.readyForMoreMediaData)
            {
                NSLog(@"2: Had to drop a video frame: %@", CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, frameTime)));
                lastFrameTime = frameTime;
            }
            else if(![self.assetWriterPixelBufferInput appendPixelBuffer:_pixelBuffer withPresentationTime:frameTime])
            {
              //  NSLog(@"pixel buffer pool : %@", assetWriterPixelBufferInput.pixelBufferPool);
                NSLog(@"Problem appending pixel buffer at time: %@ with error: %@", CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, frameTime)), self.assetWriter.error);
                
                lastFrameTime = frameTime;
                
                NSLog(@"----------------print all frames");
                for(NSValue *value in writtenFrameTimes){
                    NSLog(@"\t time: %@", CMTimeDebug(value.CMTimeValue));
                }
                exit(0);
                
            }
            else
            {
               // NSLog(@"pixel buffer pool : %@", assetWriterPixelBufferInput.pixelBufferPool);
                NSLog(@"==================dWrote a video frame: %@", CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, frameTime)));
                lastFrameTime = frameTime;
                
                
                //resume queue
                //NSLog(@"==================done writing, resume queue");
                semaphore1();
                semaphore2();
                
                hasReceivedFirstFrame = NO;
                hasReceivedSecondFrame = NO;
                
            }
                      // CVPixelBufferRelease(_pixelBuffer);
 
//        dispatch_async(movieWritingQueue, write);
 
     
//    glBindBuffer(GL_ARRAY_BUFFER, 0);
    
    // Flush the CVOpenGLESTexture cache and release the texture
    CVOpenGLESTextureCacheFlush(_textureCache, 0);

}

- (void)createDataFBO;
{
    
  
}



@end