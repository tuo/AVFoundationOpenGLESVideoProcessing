//
//  ViewController.m
//  OpenGLVideoMerge
//
//  Created by Tuo on 11/9/13.
//  Copyright (c) 2013 Tuo. All rights reserved.
//

#import "ViewController.h"
#import "VideoWriter.h"
#import "SVProgressHUD.h"
#import "VideoReader.h"
#import "DemoProcessor.h"
#import "ContextManager.h"


#import <GPUImageView.h>
#import <GPUImageMovie.h>
#import <GPUImageChromaKeyBlendFilter.h>
#import <GPUImageMovieWriter.h>

#import <AssetsLibrary/ALAsset.h>
#import <AssetsLibrary/ALAssetsLibrary.h>
#import <AssetsLibrary/ALAssetRepresentation.h>

@interface ViewController ()
@property (strong, nonatomic) IBOutlet UIButton *startMergeBtn;
@property (weak, nonatomic) IBOutlet UILabel *gpuResultLabel;
@property (weak, nonatomic) IBOutlet UILabel *customResultLabel;


@property (nonatomic, strong) GPUImageMovie *gpuMovieFX;
@property (nonatomic, strong) GPUImageMovie *gpuMovieA;
@property (nonatomic, strong) GPUImageMovieWriter *movieWriter;
@property (nonatomic, strong) GPUImageChromaKeyBlendFilter *filter;
@property (nonatomic, strong) ALAssetsLibrary *library;

@property(nonatomic) NSDate *startDate;
@end

@implementation ViewController {
    VideoWriter *videoWriter;
    VideoReader *videoReaderFX, *videoReaderRaw;
//    DemoProcessor *demoProcessor;
    
    NSURL *fxURL,*rawVideoURL, *outputURL;

}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    fxURL = [[NSBundle mainBundle] URLForResource:@"FXSample" withExtension:@"mov"];
    rawVideoURL = [[NSBundle mainBundle] URLForResource:@"video" withExtension:@"mp4"];

}


- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}
- (IBAction)onGPUMerge:(id)sender {
    [self gpuimageProcess];
}

- (IBAction)onCustomMerge:(id)sender {
    [self customProcess];
}

- (void)gpuimageProcess{
    [SVProgressHUD showWithStatus:@"processing..."];
    self.startDate = [NSDate date];
    self.gpuMovieA = [[GPUImageMovie alloc] initWithURL:rawVideoURL];
    
    self.gpuMovieFX = [[GPUImageMovie alloc] initWithURL:fxURL];
  
    
    self.filter = [[GPUImageChromaKeyBlendFilter alloc] init];
    //[self.filter forceProcessingAtSize:CGSizeMake(640, 640)];
    
    [self.gpuMovieFX addTarget:self.filter];
    [self.gpuMovieA addTarget:self.filter];
    
    
    //setup writer
    NSString *pathToMovie = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/gpu_output.mov"];
    unlink([pathToMovie UTF8String]); // If a file already exists, AVAssetWriter won't let you record new frames, so delete the old movie
    outputURL = [NSURL fileURLWithPath:pathToMovie];
    self.movieWriter =  [[GPUImageMovieWriter alloc] initWithMovieURL:outputURL size:CGSizeMake(640.0, 640.0)];

    [self.filter addTarget:self.movieWriter];
   
    [self.movieWriter startRecording];
    [self.gpuMovieA startProcessing];
    [self.gpuMovieFX startProcessing];
    
    __weak typeof(self) sself = self;
    
    [self.movieWriter setCompletionBlock:^{

        [sself.gpuMovieFX endProcessing];
        [sself.gpuMovieA endProcessing];
        [sself.movieWriter finishRecording];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [SVProgressHUD showSuccessWithStatus:@"Done"];
            NSString *time = [NSString stringWithFormat:@"GPU: %f seconds.",  -([sself.startDate timeIntervalSinceNow])];
            
            sself.gpuResultLabel.text = time;

            
            [sself writeToAlbum:outputURL];
        });
    }];
}


- (void)customProcess{
    [SVProgressHUD showWithStatus:@"processing custom..."];
    self.startDate = [NSDate date];
    
    EAGLRenderingAPI api = kEAGLRenderingAPIOpenGLES2;
    EAGLContext *writeContext = [ContextManager shared].currentContext;
    if (!writeContext) {
        NSLog(@"Failed to initialize OpenGLES 2.0 context");
        exit(1);
    }

    __weak typeof(self) sself = self;

    
    videoWriter = [[VideoWriter alloc] initWithEAGLContext:writeContext];
    videoWriter.onWritingFinishedBlock = ^(NSURL *outputURL){
        NSString *time = [NSString stringWithFormat:@"Custom: %f seconds.",  -([sself.startDate timeIntervalSinceNow])];

        sself.customResultLabel.text = time;

        [sself writeToAlbum:outputURL];
    };
    videoReaderFX = [[VideoReader alloc] initWithURL:fxURL withVideoWriter:videoWriter withEAGLContext:writeContext];
    videoReaderRaw = [[VideoReader alloc] initWithURL:rawVideoURL withVideoWriter:videoWriter withEAGLContext:writeContext];
    
    videoWriter.readerFX = videoReaderFX;
    videoWriter.readerRaw = videoReaderRaw;
    
    videoReaderFX.targetTextureIndex = 1;
    videoReaderRaw.targetTextureIndex = 2;
    

    [videoReaderFX startProcessing];
    [videoReaderRaw startProcessing];
    [videoWriter startRecording];
}

- (void)writeToAlbum:(NSURL *)outputFileURL{
    self.library = [[ALAssetsLibrary alloc] init];
    if ([_library videoAtPathIsCompatibleWithSavedPhotosAlbum:outputFileURL])
    {
        [_library writeVideoAtPathToSavedPhotosAlbum:outputFileURL
                                     completionBlock:^(NSURL *assetURL, NSError *error)
         {
             if (error)
             {
                 dispatch_async(dispatch_get_main_queue(), ^{
                     [SVProgressHUD showErrorWithStatus:@"failed"];
                 });
                 NSLog(@"fail to saved: %@", error);
             }else{
                 NSLog(@"saved");
                 dispatch_async(dispatch_get_main_queue(), ^{
                     [SVProgressHUD showSuccessWithStatus:@"saved"];
                 });
             }
         }];
    }
}




@end
