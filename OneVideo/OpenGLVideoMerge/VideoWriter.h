//
// Created by Tuo on 11/9/13.
// Copyright (c) 2013 Tuo. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@class VideoReader;

typedef void (^VideoFinishBlock) (NSURL *outputURL);

@interface VideoWriter : NSObject

@property(nonatomic, strong) NSArray *readerQueues;

@property(nonatomic, assign) dispatch_queue_t readRawQueue;

@property(nonatomic, assign) dispatch_queue_t readFXQueue;

@property(nonatomic, weak) VideoReader *readerFX;

@property(nonatomic, weak) VideoReader *readerRaw;

@property(nonatomic, copy) VideoFinishBlock onWritingFinishedBlock;

- (void)finish;

- (id)initWithEAGLContext:(EAGLContext *)context;

- (void)newFrameReadyAtTime:(CMTime)time inputTexture:(GLuint)texture atIndex:(int)index;

- (void)newFrameReadyAtTime:(CMTime)time inputTexture:(GLuint)texture atIndex:(int)index doneFrameCount:(int)doneCount videoName:(NSString*)videoName semaphore:(EmptyBlock)semaphoreBlock videoDuration: (CMTime)duration;

- (void)startRecording;
@end