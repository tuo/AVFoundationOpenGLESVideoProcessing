//
// Created by Tuo on 11/14/13.
// Copyright (c) 2013 Tuo. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "FrameRenderOutput.h"
@class VideoWriter;


@interface VideoReader : NSObject 

- (id)initWithURL:(NSURL *)pUrl;
- (void)startProcessing;

-(AVAssetReader *)avReader;
-(AVAssetReaderTrackOutput *)avReaderOutput;

- (FrameRenderOutput *)renderNextFrame;


- (void)cleanupResource:(FrameRenderOutput *)output;

- (AVAssetTrack *)audioTrack;
@end