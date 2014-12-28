//
// Created by Tuo on 11/20/13.
// Copyright (c) 2013 Tuo. All rights reserved.
//


#import <Foundation/Foundation.h>


@interface ContextManager : NSObject

@property (nonatomic, strong, readonly) EAGLContext* currentContext;

+(ContextManager *)shared;

- (dispatch_queue_t) contextQueue;

- (void)useCurrentContext;

@end