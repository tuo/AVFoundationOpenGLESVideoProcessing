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

NSString* VERTEX_SHADER_FILENAME = @"AlphaBlendVertex";
NSString* FRAGMENT_SHADER_FILENAME = @"AlphaBlendFragment";

struct Vector3 {
    GLfloat one;
    GLfloat two;
    GLfloat three;
};
typedef struct Vector3 Vector3;

typedef struct {
    GLfloat position[2];
    GLfloat texcoord[2];
} Vertex;

const Vertex Vertices[] = {
        {{-1, -1}, {0, 0}}, //bottom left
        {{1, -1}, {1, 0}},  //bottom right
        {{-1, 1}, {0, 1}}, //top left
        {{1, 1}, {1, 1}}   //top right
};

const GLubyte Indices[] = {
        0, 1, 2,
        2, 1, 3
};



@interface VideoWriter ()

//AssetWriter
@property(nonatomic) NSURL *outputURL;
@property(nonatomic) CGSize videoSize;
@property(nonatomic) AVAssetWriter *assetWriter;
@property(nonatomic) AVAssetWriterInput *assetWriterVideoInput;
@property(nonatomic) AVAssetWriterInputPixelBufferAdaptor *assetWriterPixelBufferInput;
@property(nonatomic, strong) AVAssetReader *assetAudioReader;
@property(nonatomic, strong) AVAssetReaderAudioMixOutput *assetAudioReaderTrackOutput;
@property(nonatomic, strong) AVAssetWriterInput *assetWriterAudioInput;
@property(nonatomic) BOOL audioFinished, videoFinished;
@property(nonatomic) dispatch_group_t recordingDispatchGroup;
- (void)kickoffRecording;
@end

@implementation VideoWriter {
//    EAGLContext *_context;
    
    GLuint _positionSlot;
    GLuint _srcTexCoord1Slot;
    GLuint _srcTexCoord2Slot;
    GLuint _srcTexCoord3Slot;
    GLuint _srcTexture1Uniform;
    GLuint _srcTexture2Uniform;
    GLuint _srcTexture3Uniform;


    GLuint _program;

    GLuint _frameBuffer;

    CVOpenGLESTextureCacheRef _textureCache;
    CVOpenGLESTextureRef _texture;
    CVPixelBufferRef _pixelBuffer;

    GLuint    vertextArrayObject;
    GLuint    vertexBuffer;
    GLuint    indexBuffer;
}

- (id)initWithOutputURL:(NSURL *)url size:(CGSize)size {
    self = [super init];
    if (self) {
        self.videoSize = size;
        self.outputURL = url;
        [self setup];
    }

    return self;
}



- (void)setup {
    [self setupOpenGLESTextureCache];
    [self compileShaders];
    [self setupOpenGLES];
}



- (void)setupOpenGLES {
    [self setupVAO];
}

//setup vertex array object for better performance as the position/texcoordiates are same
- (void)setupVAO {

    //create and bind a vao
    glGenVertexArraysOES(1, &vertextArrayObject);
    glBindVertexArrayOES(vertextArrayObject);

    //create and bind a BO for vertex data
    glGenBuffers(1, &vertexBuffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertexBuffer);

    // copy data into the buffer object
    glBufferData(GL_ARRAY_BUFFER, sizeof(Vertices), Vertices, GL_STATIC_DRAW);

    // set up vertex attributes
    glEnableVertexAttribArray(_positionSlot);
    glVertexAttribPointer(_positionSlot, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex, position));
    glEnableVertexAttribArray(_srcTexCoord1Slot);
    glVertexAttribPointer(_srcTexCoord1Slot, 2, GL_FLOAT, GL_FALSE, sizeof(Vertex), (void*)offsetof(Vertex, texcoord));


    // Create and bind a BO for index data
    glGenBuffers(1, &indexBuffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, indexBuffer);

    // copy data into the buffer object
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(Indices), Indices, GL_STATIC_DRAW);


    glBindVertexArrayOES(0);
}

- (void)startAssetWriter {
    BOOL aduioReaderStartSuccess = [self.assetAudioReader startReading];
    if(!aduioReaderStartSuccess){
        NSLog(@"asset audio reader start reading failed: %@", self.assetAudioReader.error);
        return;
    }
    BOOL success = [self.assetWriter startWriting];
    if (!success){
        NSLog(@"asset write start writing failed: %@", self.assetWriter.error);
        return;
    }
    [self.assetWriter startSessionAtSourceTime:kCMTimeZero];
    NSLog(@"asset write is good to write...");
}

- (void)startRecording {
    dispatch_async([ContextManager shared].mainSerializationQueue, ^{
        [self setupAssetWriterVideo];
        // Set up the notification that the dispatch group will send when the audio and video work have both finished.
        dispatch_group_notify([ContextManager shared].readingAllReadyDispatchGroup, [ContextManager shared].mainSerializationQueue, ^{
            NSLog(@"all set, readers and writer both are ready");
            [self setupAssetAudioReaderAndWriter];
            [self startAssetWriter];
            [self kickoffRecording];
        });
    });
}


- (void)kickoffRecording {

    // If the asset reader and writer both started successfully, create the dispatch group where the reencoding will take place and start a sample-writing session.
    self.recordingDispatchGroup = dispatch_group_create();
    self.audioFinished = NO;
    self.videoFinished = NO;


    [self kickOffAudioWriting];

    [self kickOffVideoWriting];


    // Set up the notification that the dispatch group will send when the audio and video work have both finished.
    dispatch_group_notify(self.recordingDispatchGroup, [ContextManager shared].mainSerializationQueue, ^{
        self.videoFinished = NO;
        self.audioFinished = NO;
        [self.assetWriter finishWritingWithCompletionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                if(self.onWritingFinishedBlock){
                    self.onWritingFinishedBlock();
                }
            });
        }];
    });
}

- (void)tearDown {

    [EAGLContext setCurrentContext:nil];

    glDeleteBuffers(1, &vertextArrayObject);
    glDeleteBuffers(1, &vertexBuffer);
    glDeleteBuffers(1, &indexBuffer);

    if (_program) {
        glDeleteProgram(_program);
        _program = 0;
    }
}

- (void)kickOffVideoWriting {
    NSAssert(self.recordingDispatchGroup, @"Recording dispatch group should be inited to sync audio/video writing");
    // If there is video to reencode, enter the dispatch group before beginning the work.
    dispatch_group_enter(self.recordingDispatchGroup);

    [self.assetWriterVideoInput requestMediaDataWhenReadyOnQueue:[ContextManager shared].rwVideoSerializationQueue usingBlock:^{
        if (self.videoFinished)
            return;
        BOOL completedOrFailed = NO;
        // If the task isn't complete yet, make sure that the input is actually ready for more media data.
        while ([self.assetWriterVideoInput isReadyForMoreMediaData] && !completedOrFailed) {
            // Get the next video sample buffer, and append it to the output file.
            dispatch_group_t downloadGroup = dispatch_group_create(); // 2

            __block FrameRenderOutput *alphaFrameOutput;
            dispatch_group_async(downloadGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                alphaFrameOutput = [self.readerAlpha renderNextFrame];
            });

            __block FrameRenderOutput *fxFrameOutput;

            dispatch_group_async(downloadGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                fxFrameOutput = [self.readerFX renderNextFrame];
            });

            __block FrameRenderOutput *rawFrameOutput;
            dispatch_group_async(downloadGroup, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                rawFrameOutput = [self.readerRaw renderNextFrame];
            });


            NSLog(@"wait is starting");
            dispatch_group_wait(downloadGroup, DISPATCH_TIME_FOREVER); // 5
            NSLog(@"wait is done");
            if (!fxFrameOutput.sampleBuffer || !rawFrameOutput.sampleBuffer || !alphaFrameOutput.sampleBuffer) {
                //reading done
                completedOrFailed = YES;
            } else {
                CVPixelBufferLockBaseAddress(_pixelBuffer, 0);

                [[ContextManager shared] useCurrentContext];

                if (_frameBuffer == 0) {
                    NSLog(@"create frame buffer object");
                    [self createFrameBufferObject];


                    glClearColor(0.0, 0.0, 0.0, 1.0);
                    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

                    glViewport(0, 0, (int) self.videoSize.width, (int) self.videoSize.height);
                    //use shader program
                    NSAssert(_program, @"Program should be created");
                    glUseProgram(_program);

                }
                glBindFramebuffer(GL_FRAMEBUFFER, _frameBuffer);

                // This is it. Binding the VAO again restores all buffer
                // bindings and attribute settings that were previously set up
                glBindVertexArrayOES(vertextArrayObject);


                glActiveTexture(GL_TEXTURE2);
                glBindTexture(GL_TEXTURE_2D, alphaFrameOutput.outputTexture);
                glUniform1i(_srcTexture1Uniform, 2);

                glActiveTexture(GL_TEXTURE3);
                glBindTexture(GL_TEXTURE_2D, fxFrameOutput.outputTexture);
                glUniform1i(_srcTexture2Uniform, 3);

                glActiveTexture(GL_TEXTURE4);
                glBindTexture(GL_TEXTURE_2D, rawFrameOutput.outputTexture);
                glUniform1i(_srcTexture3Uniform, 4);

                glDrawElements(GL_TRIANGLES, sizeof(Indices) / sizeof(GLubyte), GL_UNSIGNED_BYTE, (void *) 0);
                glFinish();


                CMTime frameTime = fxFrameOutput.frameTime;
                BOOL writeSucceeded = [self.assetWriterPixelBufferInput appendPixelBuffer:_pixelBuffer withPresentationTime:frameTime];

                CVPixelBufferUnlockBaseAddress(_pixelBuffer, 0);

                if (writeSucceeded) {
                    NSLog(@"==================dWrote a video frame: %@", CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, frameTime)));
                } else {
                    //  NSLog(@"pixel buffer pool : %@", assetWriterPixelBufferInput.pixelBufferPool);
                    NSLog(@"Problem appending pixel buffer at time: %@ with error: %@", CFBridgingRelease(CMTimeCopyDescription(kCFAllocatorDefault, frameTime)), self.assetWriter.error);
                }

                [self.readerAlpha cleanupResource:alphaFrameOutput];
                [self.readerFX cleanupResource:fxFrameOutput];
                [self.readerRaw cleanupResource:rawFrameOutput];
            }

        }
        if (completedOrFailed) {
            NSLog(@"mark as finish");
            // Mark the input as finished, but only if we haven't already done so, and then leave the dispatch group (since the video work has finished).
            BOOL oldFinished = self.videoFinished;
            self.videoFinished = YES;
            if (!oldFinished) {
                [self.assetWriterVideoInput markAsFinished];
            }
            dispatch_group_leave(self.recordingDispatchGroup);
        }
    }];
}

- (void)kickOffAudioWriting {
    NSAssert(self.recordingDispatchGroup, @"Recording dispatch group should be inited to sync audio/video writing");
    // If there is audio to reencode, enter the dispatch group before beginning the work.
    dispatch_group_enter(self.recordingDispatchGroup);
    // Specify the block to execute when the asset writer is ready for audio media data, and specify the queue to call it on.
    [self.assetWriterAudioInput requestMediaDataWhenReadyOnQueue:[ContextManager shared].rwAudioSerializationQueue usingBlock:^{
        // Because the block is called asynchronously, check to see whether its task is complete.
        if (self.audioFinished)
            return;

        BOOL completedOrFailed = NO;
        // If the task isn't complete yet, make sure that the input is actually ready for more media data.
        while ([self.assetWriterAudioInput isReadyForMoreMediaData] && !completedOrFailed) {
            // Get the next audio sample buffer, and append it to the output file.
            CMSampleBufferRef sampleBuffer = [self.assetAudioReaderTrackOutput copyNextSampleBuffer];
            if (sampleBuffer != NULL) {
                BOOL success = [self.assetWriterAudioInput appendSampleBuffer:sampleBuffer];
                if (success) {
                    NSLog(@"append audio buffer success");
                } else {
                    NSLog(@"append audio buffer failed");
                }
                CFRelease(sampleBuffer);
                sampleBuffer = NULL;
                completedOrFailed = !success;
            }
            else {
                completedOrFailed = YES;
            }


        }//end of loop

        if (completedOrFailed) {
            NSLog(@"audio wrint done");
            // Mark the input as finished, but only if we haven't already done so, and then leave the dispatch group (since the audio work has finished).
            BOOL oldFinished = self.audioFinished;
            self.audioFinished = YES;
            if (!oldFinished) {
                [self.assetWriterAudioInput markAsFinished];
                dispatch_group_leave(self.recordingDispatchGroup);
            };
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
    _srcTexCoord2Slot = glGetAttribLocation(_program, "srcTexCoordIn2");
    _srcTexCoord3Slot = glGetAttribLocation(_program, "srcTexCoordIn3");

    glEnableVertexAttribArray(_positionSlot);
    glEnableVertexAttribArray(_srcTexCoord1Slot);
    glEnableVertexAttribArray(_srcTexCoord2Slot);
    glEnableVertexAttribArray(_srcTexCoord3Slot);

    _srcTexture1Uniform = glGetUniformLocation(_program, "srcTexture1");
    _srcTexture2Uniform = glGetUniformLocation(_program, "srcTexture2");
    _srcTexture3Uniform = glGetUniformLocation(_program, "srcTexture3");
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
- (void)setupAssetAudioReaderAndWriter {
    NSArray *audioTracks = [@[self.readerFX, self.readerRaw, self.readerAlpha] valueForKey:@"audioTrack"];
    NSLog(@"audioTracks: %@", audioTracks);

    AVMutableComposition* mixComposition = [AVMutableComposition composition];

    for(AVAssetTrack *track in audioTracks){
        if(![track isKindOfClass:[NSNull class]]){
            NSLog(@"track url: %@ duration: %.2f", track.asset, CMTimeGetSeconds(track.asset.duration));
            AVMutableCompositionTrack *compositionCommentaryTrack = [mixComposition addMutableTrackWithMediaType:AVMediaTypeAudio

                                                                                                preferredTrackID:kCMPersistentTrackID_Invalid];
            [compositionCommentaryTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, track.asset.duration)
                                                ofTrack:track
                                                 atTime:kCMTimeZero error:nil];
        }
    }

    self.assetAudioReader = [AVAssetReader assetReaderWithAsset:mixComposition error:nil];
    self.assetAudioReaderTrackOutput =
            [[AVAssetReaderAudioMixOutput alloc] initWithAudioTracks:[mixComposition tracksWithMediaType:AVMediaTypeAudio]
                                                       audioSettings:nil];

    [self.assetAudioReader addOutput:self.assetAudioReaderTrackOutput];

    NSAssert(self.assetWriter, @"Writer should be inited");

    //Use default audio outputsettings

    //http://stackoverflow.com/questions/4149963/this-code-to-write-videoaudio-through-avassetwriter-and-avassetwriterinputs-is
    // Add the audio input
    AudioChannelLayout acl;
    bzero( &acl, sizeof(acl));
    acl.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;

    NSDictionary *audioOutputSettings = [ NSDictionary dictionaryWithObjectsAndKeys:
            [ NSNumber numberWithInt: kAudioFormatAppleLossless ], AVFormatIDKey,
            [ NSNumber numberWithInt: 16 ], AVEncoderBitDepthHintKey,
            [ NSNumber numberWithFloat: 44100.0 ], AVSampleRateKey,
            [ NSNumber numberWithInt: 1 ], AVNumberOfChannelsKey,
            [ NSData dataWithBytes: &acl length: sizeof( acl ) ], AVChannelLayoutKey,
                    nil ];

    self.assetWriterAudioInput =  [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio
                                                                         outputSettings:audioOutputSettings];

    self.assetWriterAudioInput.expectsMediaDataInRealTime = YES;

    NSParameterAssert(self.assetWriterAudioInput);
    NSParameterAssert([self.assetWriter canAddInput:self.assetWriterAudioInput]);
    [self.assetWriter addInput:self.assetWriterAudioInput];
}


- (void)setupAssetWriterVideo {
    // Do any additional setup after loading the view.

    // If the tracks loaded successfully, make sure that no file exists at the output path for the asset writer.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *localOutputPath = [self.outputURL path];
    NSAssert(![fm fileExistsAtPath:localOutputPath], @"Video writer output file exist already: %@", localOutputPath);

    NSLog(@"setupAssetWriterVideo outputURL: %@", self.outputURL );
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
    self.assetWriterVideoInput.expectsMediaDataInRealTime = YES;

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


@end