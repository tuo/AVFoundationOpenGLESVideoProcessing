//
// Created by Tuo on 11/14/13.
// Copyright (c) 2013 Tuo. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "FrameRenderOutput.h"
@class VideoWriter;


@interface VideoReader : NSObject 


@property(nonatomic) int targetTextureIndex;

- (id)initWithURL:(NSURL *)pUrl withVideoWriter:(VideoWriter *)pWriter withEAGLContext:(EAGLContext *)context;

- (void)startProcessing;
-(AVAssetReader *)avReader;
-(AVAssetReaderTrackOutput *)avReaderOutput;


@property(nonatomic, assign) dispatch_queue_t writerQueue;

- (FrameRenderOutput *)renderNextFrame;


- (void)cleanupResource:(FrameRenderOutput *)output;
@end