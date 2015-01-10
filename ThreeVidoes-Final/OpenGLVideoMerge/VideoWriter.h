//
// Created by Tuo on 11/9/13.
// Copyright (c) 2013 Tuo. All rights reserved.
//


#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@class VideoReader;

typedef void (^VideoFinishBlock) ();

@interface VideoWriter : NSObject

//TODO: this should be some protocol rather than hardcode here, but for now, just for quick test
@property(nonatomic, weak) VideoReader *readerFX;

@property(nonatomic, weak) VideoReader *readerRaw;

@property(nonatomic, copy) VideoFinishBlock onWritingFinishedBlock;

@property(nonatomic, strong) VideoReader *readerAlpha;

- (void)startRecording;

- (id)initWithTargetVideoSize:(CGSize)size;

- (id)initWithOutputURL:(NSURL *)url size:(CGSize)size;
@end