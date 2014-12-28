//
// Created by Tuo on 12/16/14.
// Copyright (c) 2014 Tuo. All rights reserved.
//

#import "Util.h"


@implementation Util {

}

+ (instancetype)shared
{
    static dispatch_once_t once;
    static Util *sharedInstance;

    dispatch_once(&once, ^
    {
        sharedInstance = [[Util alloc] init];
    });

    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSString *serializationQueueDescription = [NSString stringWithFormat:@"%@ serialization queue", self];

        // Create the main serialization queue.
        self.mainSerializationQueue = dispatch_queue_create([serializationQueueDescription UTF8String], NULL);
        NSString *rwAudioSerializationQueueDescription = [NSString stringWithFormat:@"%@ rw audio serialization queue", self];

        // Create the serialization queue to use for reading and writing the audio data.
        self.rwAudioSerializationQueue = dispatch_queue_create([rwAudioSerializationQueueDescription UTF8String], NULL);
        NSString *rwVideoSerializationQueueDescription = [NSString stringWithFormat:@"%@ rw video serialization queue", self];

        // Create the serialization queue to use for reading and writing the video data.
        self.rwVideoSerializationQueue = dispatch_queue_create([rwVideoSerializationQueueDescription UTF8String], NULL);

        self.dispatchGroup = dispatch_group_create();
    }

    return self;
}


@end