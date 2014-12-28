//
// Created by Tuo on 12/16/14.
// Copyright (c) 2014 Tuo. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@interface FrameRenderOutput : NSObject

@property (nonatomic) GLuint outputTexture;
@property (nonatomic) CMTime frameTime;

@property(nonatomic) CMSampleBufferRef sampleBuffer;

@property(nonatomic) CVOpenGLESTextureRef inputTexture;

- (NSString *)description;


@end