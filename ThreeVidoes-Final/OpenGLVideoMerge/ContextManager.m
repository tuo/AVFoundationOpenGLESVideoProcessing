//
// Created by Tuo on 11/20/13.
// Copyright (c) 2013 Tuo. All rights reserved.
//


#import "ContextManager.h"


@implementation ContextManager {
    EAGLContext* _context;
    CVOpenGLESTextureCacheRef _videoTextureCache;
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
        [self setupQueues];
    }

    return self;
}

- (void)setupQueues {
    NSString *serializationQueueDescription = [NSString stringWithFormat:@"%@ serialization queue", self];

    // Create the main serialization queue.
    self.mainSerializationQueue = dispatch_queue_create([serializationQueueDescription UTF8String], NULL);
    NSString *rwAudioSerializationQueueDescription = [NSString stringWithFormat:@"%@ rw audio serialization queue", self];

    // Create the serialization queue to use for reading and writing the audio data.
    self.rwAudioSerializationQueue = dispatch_queue_create([rwAudioSerializationQueueDescription UTF8String], NULL);
    NSString *rwVideoSerializationQueueDescription = [NSString stringWithFormat:@"%@ rw video serialization queue", self];

    // Create the serialization queue to use for reading and writing the video data.
    self.rwVideoSerializationQueue = dispatch_queue_create([rwVideoSerializationQueueDescription UTF8String], NULL);

    self.readingAllReadyDispatchGroup = dispatch_group_create();
}


- (CVOpenGLESTextureCacheRef)coreVideoTextureCache {
    if(_videoTextureCache == NULL){
        // Create a new CVOpenGLESTexture cache
        //-- Create CVOpenGLESTextureCacheRef for optimal CVImageBufferRef to GLES texture conversion.
#if COREVIDEO_USE_EAGLCONTEXT_CLASS_IN_API
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, [ContextManager shared].currentContext, NULL, &_videoTextureCache);
#else
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (__bridge void *)([ContextManager shared].currentContext), NULL, &coreVideoTextureCache);
    #endif
        if (err) {
            NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
            exit(1);
        }
    }

    return _videoTextureCache;
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






@end