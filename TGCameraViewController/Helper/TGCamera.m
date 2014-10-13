//
//  TGCamera.m
//  TGCameraViewController
//
//  Created by Bruno Tortato Furtado on 14/09/14.
//  Copyright (c) 2014 Tudo Gostoso Internet. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import "TGCamera.h"
#import "TGCameraGrid.h"
#import "TGCameraGridView.h"
#import "TGCameraFlash.h"
#import "TGCameraFocus.h"
#import "TGCameraShot.h"
#import "TGCameraToggle.h"

NSMutableDictionary *optionDictionary;

@interface TGCamera ()<AVCaptureVideoDataOutputSampleBufferDelegate>{
    AVCaptureVideoDataOutput*       videoOutput;            //  ビデオ出力デバイス
    dispatch_queue_t                videoOutputQueue;       //  ビデオ出力用スレッド
    UIImage* capImage;
}

@property (strong, nonatomic) AVCaptureSession *session;
@property (strong, nonatomic) AVCaptureVideoPreviewLayer *previewLayer;
@property (strong, nonatomic) AVCaptureStillImageOutput *stillImageOutput;
@property (strong, nonatomic) TGCameraGridView *gridView;

+ (instancetype)newCamera;
+ (void)initOptions;

- (void)setupWithFlashButton:(UIButton *)flashButton;

@end



@implementation TGCamera

/////////////////////////////////////////////////
//      ビデオキャプチャの初期化
//      設定後:captureOutputが呼ばれる
/////////////////////////////////////////////////
-(BOOL)setupVideoCapture{
    //////////////////////////////////
    //    ビデオ出力デバイスの設定
    //////////////////////////////////
    NSDictionary *rgbOutputSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCMPixelFormat_32BGRA)};
    videoOutput = AVCaptureVideoDataOutput.new;
    [videoOutput setVideoSettings:rgbOutputSettings];
    [videoOutput setAlwaysDiscardsLateVideoFrames:YES];     //  NOだとコマ落ちしないが重い処理には向かない
    videoOutputQueue = dispatch_queue_create("VideoData Output Queue", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:self queue:videoOutputQueue];
    
    if(videoOutput){
        if ([_session canAddOutput:videoOutput]){
            [_session addOutput:videoOutput];
            return YES;
        }
    }
    return NO;
}


/////////////////////////////////////////////////////////////////////////////////
//      ビデオキャプチャ時、 新しいフレームが書き込まれた際に通知を受けるデリゲートメソッド
/////////////////////////////////////////////////////////////////////////////////
- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection{
    @autoreleasepool {
        //     キャプチャ画像からUIImageを作成する
        CGImageRef cgImage = [self imageFromSampleBuffer:sampleBuffer];
        capImage = [UIImage imageWithCGImage:cgImage];
        CGImageRelease(cgImage);
    }
}

-(UIImage*)captureImageSilentWithVideoOrientation:(AVCaptureVideoOrientation)videoOrientation{
    return [self rotateImage:capImage angle:videoOrientation];
}
-(UIImage*)rotateImage:(UIImage*)img angle:(AVCaptureVideoOrientation)angle
{
    CGImageRef      imgRef = [img CGImage];
    CGContextRef    context;
    
    switch (angle) {
        case AVCaptureVideoOrientationPortraitUpsideDown:
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(img.size.height, img.size.width), YES, img.scale);
            context = UIGraphicsGetCurrentContext();
            CGContextTranslateCTM(context, img.size.height, img.size.width);
            CGContextScaleCTM(context, 1, -1);
            CGContextRotateCTM(context, M_PI_2);
            break;
        case AVCaptureVideoOrientationLandscapeLeft:
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(img.size.width, img.size.height), YES, img.scale);
            context = UIGraphicsGetCurrentContext();
            CGContextTranslateCTM(context, img.size.width, 0);
            CGContextScaleCTM(context, 1, -1);
            CGContextRotateCTM(context, -M_PI);
            break;
        case AVCaptureVideoOrientationPortrait:
            UIGraphicsBeginImageContextWithOptions(CGSizeMake(img.size.height, img.size.width), YES, img.scale);
            context = UIGraphicsGetCurrentContext();
            CGContextScaleCTM(context, 1, -1);
            CGContextRotateCTM(context, -M_PI_2);
            break;
        default:
            return img;
            break;
    }
    
    CGContextDrawImage(context, CGRectMake(0, 0, img.size.width, img.size.height), imgRef);
    UIImage*    result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}


//////////////////////////////////////////////////////
//      SampleBufferをCGImageRefに変換する
//////////////////////////////////////////////////////
- (CGImageRef) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer,0);        //      バッファをロック
    
    uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef newContext = CGBitmapContextCreate(baseAddress, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGImageRef newImage = CGBitmapContextCreateImage(newContext);
    CGContextRelease(newContext);
    
    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);      //      バッファをアンロック
    
    return newImage;
}

+ (instancetype)cameraWithFlashButton:(UIButton *)flashButton
{
    TGCamera *camera = [TGCamera newCamera];
    [camera setupWithFlashButton:flashButton];
    
    return camera;
}

+ (void)setOption:(NSString *)option value:(id)value
{
    if (optionDictionary == nil) {
        [TGCamera initOptions];
    }
    
    if (option != nil && value != nil) {
        optionDictionary[option] = value;
    }
}

+ (id)getOption:(NSString *)option
{
    if (optionDictionary == nil) {
        [TGCamera initOptions];
    }
    
    if (option != nil) {
        return optionDictionary[option];
    }
    
    return nil;
}

#pragma mark -
#pragma mark - Public methods

- (void)startRunning
{
    [_session startRunning];
}

- (void)stopRunning
{
    [_session stopRunning];
}

- (void)insertSublayerWithCaptureView:(UIView *)captureView atRootView:(UIView *)rootView
{
    _previewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:_session];
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    
    CALayer *rootLayer = [rootView layer];
    rootLayer.masksToBounds = YES;
    
    CGRect frame = captureView.frame;
    _previewLayer.frame = frame;
    
    [rootLayer insertSublayer:_previewLayer atIndex:0];
    
    NSInteger index = [captureView.subviews count]-1;
    [captureView insertSubview:self.gridView atIndex:index];
}

- (void)disPlayGridView
{
    [TGCameraGrid disPlayGridView:self.gridView];
}

- (void)changeFlashModeWithButton:(UIButton *)button
{
    [TGCameraFlash changeModeWithCaptureSession:_session andButton:button];
}

- (void)focusView:(UIView *)focusView inTouchPoint:(CGPoint)touchPoint
{
    [TGCameraFocus focusWithCaptureSession:_session touchPoint:touchPoint inFocusView:focusView];
}

- (void)takePhotoWithCaptureView:(UIView *)captureView effectiveScale:(NSInteger)effectiveScale videoOrientation:(AVCaptureVideoOrientation)videoOrientation completion:(void (^)(UIImage *))completion
{
    [TGCameraShot takePhotoCaptureView:captureView stillImageOutput:_stillImageOutput effectiveScale:effectiveScale videoOrientation:videoOrientation
                            completion:^(UIImage *photo) {
                                completion(photo);
                            }];
}

- (void)toogleWithFlashButton:(UIButton *)flashButton
{
    [TGCameraToggle toogleWithCaptureSession:_session];
    [TGCameraFlash flashModeWithCaptureSession:_session andButton:flashButton];
}

#pragma mark -
#pragma mark - Private methods

+ (instancetype)newCamera
{
    return [super new];
}

- (TGCameraGridView *)gridView
{
    if (_gridView == nil) {
        CGRect frame = _previewLayer.frame;
        frame.origin.x = frame.origin.y = 0;
        
        _gridView = [[TGCameraGridView alloc] initWithFrame:frame];
        _gridView.numberOfColumns = 2;
        _gridView.numberOfRows = 2;
        _gridView.alpha = 0;
    }
    
    return _gridView;
}

- (void)setupWithFlashButton:(UIButton *)flashButton
{
    //
    // create session
    //
    
    _session = [AVCaptureSession new];
    _session.sessionPreset = AVCaptureSessionPresetPhoto;
    
    //
    // setup device
    //
    
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    
    if ([device lockForConfiguration:nil]) {
        if (device.autoFocusRangeRestrictionSupported) {
            device.autoFocusRangeRestriction = AVCaptureAutoFocusRangeRestrictionNear;
        }
        
        if (device.smoothAutoFocusSupported) {
            device.smoothAutoFocusEnabled = YES;
        }
        
        device.focusMode = AVCaptureFocusModeContinuousAutoFocus;
        device.exposureMode = AVCaptureExposureModeContinuousAutoExposure;
        
        [device unlockForConfiguration];
    }
    
    //
    // add device input to session
    //
    
    AVCaptureDeviceInput *deviceInput = [AVCaptureDeviceInput deviceInputWithDevice:device error:nil];
    [_session addInput:deviceInput];
    
    //
    // add output to session
    //
    
    NSDictionary *outputSettings = [NSDictionary dictionaryWithObjectsAndKeys:AVVideoCodecJPEG, AVVideoCodecKey, nil];
    
    _stillImageOutput = [AVCaptureStillImageOutput new];
    _stillImageOutput.outputSettings = outputSettings;
    
    [_session addOutput:_stillImageOutput];
    
    //
    // setup flash button
    //
    
    [TGCameraFlash flashModeWithCaptureSession:_session andButton:flashButton];
    
    // setup
    [self setupVideoCapture];
}

+ (void)initOptions
{
    optionDictionary = [NSMutableDictionary dictionary];
    optionDictionary[kTGCameraOptionSaveImageToDevice] = [NSNumber numberWithBool:YES];
}

@end