//
// Created by Tuo on 12/16/14.
// Copyright (c) 2014 Tuo. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface Util : NSObject

@property(nonatomic) dispatch_queue_t mainSerializationQueue;

@property(nonatomic) dispatch_queue_t rwAudioSerializationQueue;

@property(nonatomic) dispatch_queue_t rwVideoSerializationQueue;

@property(nonatomic) dispatch_group_t dispatchGroup;

+ (instancetype)shared;
@end