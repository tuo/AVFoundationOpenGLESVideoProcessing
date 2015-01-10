//
// Created by Tuo on 11/20/13.
// Copyright (c) 2013 Tuo. All rights reserved.
//


#import <Foundation/Foundation.h>


@interface ContextManager : NSObject

@property (nonatomic, strong, readonly) EAGLContext* currentContext;

+(ContextManager *)shared;

- (void)useCurrentContext;

@property(readonly) CVOpenGLESTextureCacheRef coreVideoTextureCache;


@property(nonatomic) dispatch_queue_t mainSerializationQueue;

@property(nonatomic) dispatch_queue_t rwAudioSerializationQueue;

@property(nonatomic) dispatch_queue_t rwVideoSerializationQueue;

@property(nonatomic) dispatch_group_t readingAllReadyDispatchGroup;


@end