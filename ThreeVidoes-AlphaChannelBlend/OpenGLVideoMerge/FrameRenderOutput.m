//
// Created by Tuo on 12/16/14.
// Copyright (c) 2014 Tuo. All rights reserved.
//

#import "FrameRenderOutput.h"


@implementation FrameRenderOutput {

}

- (NSString *)description {
    NSMutableString *description = [NSMutableString stringWithFormat:@"<%@: ", NSStringFromClass([self class])];
    [description appendFormat:@"self.outputTexture=%u", self.outputTexture];
    [description appendFormat:@", self.frameTime.value=%@", CMTimeDebug(self.frameTime)];
    [description appendString:@">"];
    return description;
}


@end