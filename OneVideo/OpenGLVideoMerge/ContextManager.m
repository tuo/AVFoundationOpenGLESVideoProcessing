//
// Created by Tuo on 11/20/13.
// Copyright (c) 2013 Tuo. All rights reserved.
//


#import "ContextManager.h"


@implementation ContextManager {
    EAGLContext* _context;
    dispatch_queue_t drawQueue;
}
+ (ContextManager *)shared {
    static ContextManager *shared = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        shared = [[ContextManager alloc] init];
        // Do any other initialisation stuff here
    });
    return shared;
}

- (id)init {
    self = [super init];
    if (self) {
       [self setupContext];
        drawQueue = dispatch_queue_create("info.tuohuang.openGLESContextQueue", DISPATCH_QUEUE_SERIAL);
    }

    return self;
}

- (void)setupContext {
    EAGLRenderingAPI api = kEAGLRenderingAPIOpenGLES2;
    _context = [[EAGLContext alloc] initWithAPI:api];
    if (!_context) {
        NSLog(@"Failed to initialize OpenGLES 2.0 context");
        exit(1);
    }

    if (![EAGLContext setCurrentContext:_context]) {
        NSLog(@"Failed to set current OpenGL context");
        exit(1);
    }
}

- (void)useCurrentContext{
    if (![EAGLContext setCurrentContext:[self currentContext]]) {
        NSLog(@"Failed to set current OpenGL context");
        exit(1);
    }
}

- (EAGLContext *)currentContext {
    NSAssert(_context, @"Context must be created");
    return _context;
}

- (dispatch_queue_t) contextQueue{
    return drawQueue;
}





@end