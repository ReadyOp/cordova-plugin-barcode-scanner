/*
 * PhoneGap is available under *either* the terms of the modified BSD license *or* the
 * MIT License (2008). See http://opensource.org/licenses/alphabetical for full text.
 *
 * Copyright 2011 Matt Kane. All rights reserved.
 * Copyright (c) 2011, IBM Corporation
 */

#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <Cordova/CDVPlugin.h>


//------------------------------------------------------------------------------
// Delegate to handle orientation functions
//------------------------------------------------------------------------------
@protocol CDVBarcodeScannerOrientationDelegate <NSObject>

- (NSUInteger)supportedInterfaceOrientations;
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation;
- (BOOL)shouldAutorotate;

@end

//------------------------------------------------------------------------------
@class CDVbcsProcessor;
@class CDVbcsViewController;

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@interface CDVBarcodeScanner : CDVPlugin {}
- (NSString*)isScanNotPossible;
- (void)startScan: (CDVInvokedUrlCommand *)command;
- (void)returnSuccess:(NSString*)scannedText format:(u_long)format callback:(NSString*)callback;
- (void)returnError:(NSString*)message callback:(NSString*)callback;
@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@interface CDVbcsProcessor : NSObject <AVCaptureMetadataOutputObjectsDelegate> {}
@property (nonatomic, retain) CDVBarcodeScanner*           plugin;
@property (nonatomic, retain) NSString*                   callback;
@property (nonatomic, retain) UIViewController*           parentViewController;
@property (nonatomic, retain) CDVbcsViewController*        viewController;
@property (nonatomic, retain) AVCaptureSession*           captureSession;
@property (nonatomic, retain) AVCaptureVideoPreviewLayer* previewLayer;
@property (nonatomic, retain) NSMutableArray*             results;
@property (nonatomic, retain) NSString*                   detectorType;
@property (nonatomic)         u_long                      formats;
@property (nonatomic)         BOOL                        capturing;
@property (nonatomic)         BOOL                        useFrontCamera;
@property (nonatomic)         BOOL                        showFlipCameraButton;
@property (nonatomic)         BOOL                        showTorchButton;
@property (nonatomic)         BOOL                        isFlipped;
@property (nonatomic)         BOOL                        beepOnSuccess;
@property (nonatomic)         BOOL                        vibrateOnSuccess;

- (id)initWithPlugin:(CDVBarcodeScanner*)plugin callback:(NSString*)callback parentViewController:(UIViewController*)parentViewController;
- (void)startProcessor;
- (void)barcodeScanSucceeded:(NSString*)text format:(u_long)format;
- (void)barcodeScanFailed:(NSString*)message;
- (void)barcodeScanCancelled;
- (NSString*)setUpCaptureSession;
@end

//------------------------------------------------------------------------------
// view controller for the ui
//------------------------------------------------------------------------------
@interface CDVbcsViewController : UIViewController <CDVBarcodeScannerOrientationDelegate> {}
    @property (nonatomic, retain) CDVbcsProcessor *processor;
    @property (nonatomic, retain) IBOutlet UIView *overlayView;
    @property (nonatomic, retain) UILabel *reticleView;
    // unsafe_unretained is equivalent to assign - used to prevent retain cycles in the property below
    @property (nonatomic, unsafe_unretained) id orientationDelegate;

    - (id)initWithProcessor: (CDVbcsProcessor*)processor;
    - (void)addOverlayView;
    - (void)addReticleToView: (UIView *)overlayView;
    - (IBAction)cancelButtonPressed: (id)sender;
    - (IBAction)flipCameraButtonPressed: (id)sender;
    - (IBAction)torchButtonPressed: (id)sender;
@end

//------------------------------------------------------------------------------
// plugin class
//------------------------------------------------------------------------------
@implementation CDVBarcodeScanner

//--------------------------------------------------------------------------
- (NSString*)isScanNotPossible {
    NSString* result = nil;

    Class aClass = NSClassFromString(@"AVCaptureSession");
    if (aClass == nil) {
        return @"AVFoundation Framework not available";
    }

    return result;
}

-(BOOL)notHasPermission
{
    AVAuthorizationStatus authStatus = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
    return (authStatus == AVAuthorizationStatusDenied ||
            authStatus == AVAuthorizationStatusRestricted);
}

-(BOOL)isUsageDescriptionSet
{
  NSDictionary * plist = [[NSBundle mainBundle] infoDictionary];
  if ([plist objectForKey:@"NSCameraUsageDescription" ] ||
      [[NSBundle mainBundle] localizedStringForKey: @"NSCameraUsageDescription" value: nil table: @"InfoPlist"]) {
    return YES;
  }
  return NO;
}

//--------------------------------------------------------------------------
-(void)startScan: (CDVInvokedUrlCommand *)command
{
    NSString *callback = command.callbackId;

    NSDictionary *options;
    if (command.arguments.count == 0) {
        options = [NSDictionary dictionary];
    } else {
        options = command.arguments[0];
    }

    BOOL showFlipCameraButton = [options[@"showFlipCameraButton"] boolValue];
    BOOL showTorchButton = [options[@"showTorchButton"] boolValue];

    NSString *capabilityError = [self isScanNotPossible];
    if (capabilityError) {
        [self returnError:capabilityError callback: callback];
        return;
    } else if ([self notHasPermission]) {
        NSString * error = NSLocalizedString(@"Access to the camera has been prohibited; please enable it in the Settings app to continue.",nil);
        [self returnError:error callback: callback];
        return;
    } else if (![self isUsageDescriptionSet]) {
        NSString * error = NSLocalizedString(@"NSCameraUsageDescription is not set in the info.plist", nil);
        [self returnError:error callback :callback];
        return;
    }

    CDVbcsProcessor *processor = [[CDVbcsProcessor alloc] initWithPlugin: self callback: callback parentViewController: self.viewController];
    processor.beepOnSuccess = [options[@"beepOnSuccess"] boolValue];
    processor.formats = [options[@"formats"] unsignedLongValue];

    processor.detectorType = nil;
    if ([options[@"detectorType"] isKindOfClass: [NSString class]]) {
        NSArray *types = @[
            @"default",
            @"card",
        ];
        processor.detectorType = options[@"detectorType"];

        if (![types containsObject: processor.detectorType]) {
            NSString * error = NSLocalizedString(@"Invalid config detectorType specified.", nil);
            return [self returnError:error callback: callback];
        }
    }
    if (showFlipCameraButton) {
        processor.showFlipCameraButton = true;
    }
    if (showTorchButton) {
        processor.showTorchButton = true;
    }
    processor.useFrontCamera = false;
    processor.vibrateOnSuccess = [options[@"vibrateOnSuccess"] boolValue];

    [processor startProcessor];
}

//--------------------------------------------------------------------------
- (void)returnSuccess:(NSString*)scannedText format:(u_long)format callback:(NSString*)callback {
    NSArray *resultArray = @[
        scannedText,
        [NSNumber numberWithUnsignedLong: format],
    ];

    CDVPluginResult *result = [CDVPluginResult resultWithStatus: CDVCommandStatus_OK messageAsArray: resultArray];
    [self.commandDelegate sendPluginResult:result callbackId:callback];
}

//--------------------------------------------------------------------------
- (void)returnError:(NSString*)message callback:(NSString*)callback {
    NSArray *resultArray = @[
        message,
    ];

    CDVPluginResult *result = [CDVPluginResult resultWithStatus: CDVCommandStatus_ERROR messageAsArray: resultArray];
    [self.commandDelegate sendPluginResult:result callbackId:callback];
}

@end

//------------------------------------------------------------------------------
// class that does the grunt work
//------------------------------------------------------------------------------
@implementation CDVbcsProcessor

@synthesize plugin               = _plugin;
@synthesize callback             = _callback;
@synthesize parentViewController = _parentViewController;
@synthesize viewController       = _viewController;
@synthesize captureSession       = _captureSession;
@synthesize previewLayer         = _previewLayer;
@synthesize capturing            = _capturing;
@synthesize results              = _results;

SystemSoundID _soundFileObject;

//--------------------------------------------------------------------------
- (id)initWithPlugin:(CDVBarcodeScanner*)plugin
            callback:(NSString*)callback
parentViewController:(UIViewController*)parentViewController {
    self = [super init];
    if (!self) return self;

    self.plugin               = plugin;
    self.callback             = callback;
    self.parentViewController = parentViewController;

    self.capturing = NO;
    self.results = [NSMutableArray new];

    CFURLRef soundFileURLRef  = CFBundleCopyResourceURL(CFBundleGetMainBundle(), CFSTR("CDVBarcodeScanner.bundle/beep"), CFSTR ("caf"), NULL);
    AudioServicesCreateSystemSoundID(soundFileURLRef, &_soundFileObject);

    return self;
}

//--------------------------------------------------------------------------
- (void)dealloc {
    self.plugin = nil;
    self.callback = nil;
    self.parentViewController = nil;
    self.viewController = nil;
    self.captureSession = nil;
    self.previewLayer = nil;
    self.results = nil;

    self.capturing = NO;

    AudioServicesRemoveSystemSoundCompletion(_soundFileObject);
    AudioServicesDisposeSystemSoundID(_soundFileObject);
}

//--------------------------------------------------------------------------
- (void)startProcessor
{
    NSString *errorMessage = [self setUpCaptureSession];
    if (errorMessage) {
        return [self barcodeScanFailed: errorMessage];
    }
    if (self.capturing) {
        return [self barcodeScanFailed: @"SCANNER_OPEN"];
    }

    self.viewController = [[CDVbcsViewController alloc] initWithProcessor: self];
    // here we set the orientation delegate to the MainViewController of the app (orientation controlled in the Project Settings)
    self.viewController.orientationDelegate = self.plugin.viewController;

    // Show the scanner view
    [self.parentViewController presentViewController:self.viewController animated:YES completion: ^{
        [self updateRectOfInterest: self.viewController.reticleView.frame];
    }];
}


//--------------------------------------------------------------------------
- (void)barcodeScanDone:(void (^)(void))callbackBlock {
    self.capturing = NO;
    [self.captureSession stopRunning];
    [self.parentViewController dismissViewControllerAnimated:YES completion:callbackBlock];

    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    [device lockForConfiguration:nil];
    if([device isAutoFocusRangeRestrictionSupported]) {
        [device setAutoFocusRangeRestriction:AVCaptureAutoFocusRangeRestrictionNone];
    }
    [device unlockForConfiguration];

    // viewcontroller holding onto a reference to us, release them so they
    // will release us
    self.viewController = nil;
}

//--------------------------------------------------------------------------
- (BOOL)checkResult:(NSString *)result {
    [self.results addObject:result];

    NSInteger treshold = 7;

    if (self.results.count > treshold) {
        [self.results removeObjectAtIndex:0];
    }

    if (self.results.count < treshold)
    {
        return NO;
    }

    BOOL allEqual = YES;
    NSString *compareString = self.results[0];

    for (NSString *aResult in self.results)
    {
        if (![compareString isEqualToString:aResult])
        {
            allEqual = NO;
            //NSLog(@"Did not fit: %@",self.results);
            break;
        }
    }

    return allEqual;
}

//--------------------------------------------------------------------------
- (void)barcodeScanSucceeded:(NSString*)text format:(u_long)format {
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (self.beepOnSuccess) {
            AudioServicesPlaySystemSound(_soundFileObject);
        }
        if (self.vibrateOnSuccess) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        }
        [self barcodeScanDone:^{
            [self.plugin returnSuccess:text format:format callback:self.callback];
        }];
    });
}

//--------------------------------------------------------------------------
- (void)barcodeScanFailed:(NSString*)message {
    dispatch_block_t block = ^{
        [self barcodeScanDone:^{
            [self.plugin returnError:message callback:self.callback];
        }];
    };
    if ([NSThread isMainThread]) {
        block();
    } else {
        dispatch_sync(dispatch_get_main_queue(), block);
    }
}

//--------------------------------------------------------------------------
- (void)barcodeScanCancelled {
    [self barcodeScanDone:^{
        [self.plugin returnError: @"USER_CANCELLED" callback:self.callback];
    }];
    if (self.isFlipped) {
        self.isFlipped = NO;
    }
}

- (void)flipCamera {
    self.isFlipped = YES;
    self.useFrontCamera = !self.useFrontCamera;
    [self barcodeScanDone:^{
        if (self.isFlipped) {
            self.isFlipped = NO;
        }
    [self performSelector:@selector(startProcessor) withObject:nil afterDelay:0.1];
    }];
}

- (void)toggleTorch: (id)sender
{
    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCapturePhotoSettings *photoSettings = [AVCapturePhotoSettings photoSettings];

    if ([device hasTorch] && [device hasFlash]) {
        [device lockForConfiguration:nil];

        if ([device torchMode] != AVCaptureTorchModeOff) {
            [device setTorchMode:AVCaptureTorchModeOff];
            [photoSettings setFlashMode: AVCaptureFlashModeOff];

            [(UIButton *)sender setBackgroundColor: [UIColor colorWithWhite: 1.0f alpha: 0.25f]];
        } else {
            [device setTorchModeOnWithLevel: AVCaptureMaxAvailableTorchLevel error:nil];
            [photoSettings setFlashMode: AVCaptureFlashModeOn];

            [(UIButton *)sender setBackgroundColor: [UIColor colorWithWhite: 1.0f alpha: 1.0f]];
        }
        [device unlockForConfiguration];
    }
}

//--------------------------------------------------------------------------
- (NSString *)setUpCaptureSession
{
    AVCaptureDevice *__block device = nil;
    AVCaptureDevicePosition position = AVCaptureDevicePositionBack;
    if (self.useFrontCamera) {
        position = AVCaptureDevicePositionFront;
    }

    AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeBuiltInWideAngleCamera] mediaType:AVMediaTypeVideo position: position];
    NSArray *devices = [discovery devices];
    if ([devices count]) {
        device = [[discovery devices] objectAtIndex: 0];
    }
    if (!device) {
        return @"unable to obtain video capture device";
    }

    // Configure focus options
    NSError *error = nil;
    [device lockForConfiguration: &error];
    if (error == nil) {
        if([device isFocusModeSupported:AVCaptureFocusModeContinuousAutoFocus]) {
            [device setFocusMode:AVCaptureFocusModeContinuousAutoFocus];
        }
        if([device isAutoFocusRangeRestrictionSupported]) {
            [device setAutoFocusRangeRestriction:AVCaptureAutoFocusRangeRestrictionNear];
        }
    }
    [device unlockForConfiguration];

    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&error];
    if (!input) {
        return @"unable to obtain video capture device input";
    }

    AVCaptureMetadataOutput *output = [[AVCaptureMetadataOutput alloc] init];
    if (!output) {
        return @"unable to obtain video capture output";
    }

    self.captureSession = [[AVCaptureSession alloc] init];
    if ([device supportsAVCaptureSessionPreset: AVCaptureSessionPreset3840x2160]) {
        [self.captureSession setSessionPreset: AVCaptureSessionPreset3840x2160];
    } else if ([device supportsAVCaptureSessionPreset: AVCaptureSessionPresetHigh]) {
        [self.captureSession setSessionPreset: AVCaptureSessionPresetHigh];
    } else if ([device supportsAVCaptureSessionPreset: AVCaptureSessionPresetMedium]) {
        [self.captureSession setSessionPreset: AVCaptureSessionPresetMedium];
    } else {
      return @"unable to preset high nor medium quality video capture";
    }

    if ([self.captureSession canAddInput: input]) {
        [self.captureSession addInput: input];
    } else {
        return @"unable to add video capture device input to session";
    }

    if ([self.captureSession canAddOutput: output]) {
        [self.captureSession addOutput: output];
    } else {
        return @"unable to add video capture output to session";
    }
    [output setMetadataObjectsDelegate: self queue: dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0)];
    [output setMetadataObjectTypes: [self formatObjectTypes]];

    // Setup the preview layer
    self.previewLayer = [AVCaptureVideoPreviewLayer layerWithSession: self.captureSession];
    self.previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    [self.captureSession startRunning];

    return nil;
}

- (void)captureOutput: (AVCaptureOutput*)captureOutput didOutputMetadataObjects: (NSArray *)metadataObjects fromConnection: (AVCaptureConnection*)connection
{
    if (!self.capturing) {
        return;
    }

    try {
        // This will bring in multiple entities if there are multiple 2D codes in frame.
        for (AVMetadataObject *metaData in metadataObjects) {
            AVMetadataMachineReadableCodeObject* code = (AVMetadataMachineReadableCodeObject*)[self.previewLayer transformedMetadataObjectForMetadataObject:(AVMetadataMachineReadableCodeObject*)metaData];

            if ([self checkResult: code.stringValue]) {
                [self barcodeScanSucceeded: code.stringValue format: [self formatFromMetadata: code]];
            }
        }
    }
    catch (...) {
        //            NSLog(@"decoding: unknown exception");
        //            [self barcodeScanFailed:@"unknown exception decoding barcode"];
    }
}

- (u_long)formatFromMetadata: (AVMetadataMachineReadableCodeObject*)format
{
    if (format.type == AVMetadataObjectTypeCode128Code) {
        return 1;
    }
    if (format.type == AVMetadataObjectTypeCode39Code) {
        return 2;
    }
    if (format.type == AVMetadataObjectTypeCode93Code) {
        return 4;
    }
    if (format.type == AVMetadataObjectTypeDataMatrixCode) {
        return 16;
    }
    // According to Apple documentation, UPC_A is EAN13 with a leading 0.
    if (format.type == AVMetadataObjectTypeEAN13Code && [format.stringValue characterAtIndex: 0] != '0') {
        return 32;
    }
    if (format.type == AVMetadataObjectTypeEAN8Code) {
        return 64;
    }
    if (format.type == AVMetadataObjectTypeInterleaved2of5Code) {
        return 128;
    }
    if (format.type == AVMetadataObjectTypeQRCode) {
        return 256;
    }
    if (format.type == AVMetadataObjectTypeEAN13Code) { // UPC_A
        return 512;
    }
    if (format.type == AVMetadataObjectTypeUPCECode) {
        return 1024;
    }
    if (format.type == AVMetadataObjectTypePDF417Code) {
        return 2048;
    }
    if (format.type == AVMetadataObjectTypeAztecCode) {
        return 4096;
    }

    return 0;
}

- (NSArray *)formatObjectTypes
{
    NSMutableArray<AVMetadataObjectType> * formatObjectTypes = [NSMutableArray array];

    if (self.formats & 1) [formatObjectTypes addObject:AVMetadataObjectTypeCode128Code];
    if (self.formats & 2) [formatObjectTypes addObject:AVMetadataObjectTypeCode39Code];
    if (self.formats & 4) [formatObjectTypes addObject:AVMetadataObjectTypeCode93Code];
    if (self.formats & 16) [formatObjectTypes addObject:AVMetadataObjectTypeDataMatrixCode];
    if (self.formats & 32) [formatObjectTypes addObject:AVMetadataObjectTypeEAN13Code];
    if (self.formats & 64) [formatObjectTypes addObject:AVMetadataObjectTypeEAN8Code];
    if (self.formats & 128) [formatObjectTypes addObject:AVMetadataObjectTypeInterleaved2of5Code];
    if (self.formats & 256) [formatObjectTypes addObject:AVMetadataObjectTypeQRCode];
    if (self.formats & 1024) [formatObjectTypes addObject:AVMetadataObjectTypeUPCECode];
    if (self.formats & 2048) [formatObjectTypes addObject:AVMetadataObjectTypePDF417Code];
    if (self.formats & 4096) [formatObjectTypes addObject:AVMetadataObjectTypeAztecCode];

    return formatObjectTypes;
}

- (CGRect)convertRectOfInterest: (CGRect)rect
{
    CGRect overlayRect = self.previewLayer.bounds;
    CGSize overlaySize = overlayRect.size;

    CGFloat x = 1 / (overlaySize.width / rect.origin.x);
    CGFloat y = 1 / (overlaySize.height / rect.origin.y);
    CGFloat w = 1 / (overlaySize.width / rect.size.width);
    CGFloat h = 1 / (overlaySize.height / rect.size.height);

    AVCaptureVideoOrientation orientation = [[self.previewLayer connection] videoOrientation];
    if (orientation == AVCaptureVideoOrientationPortrait || orientation == AVCaptureVideoOrientationPortraitUpsideDown) {
        return CGRectMake(y, x, h, w);
    }
    return CGRectMake(x, y, w, h);
}

- (void)updateRectOfInterest: (CGRect)rect {
    AVCaptureMetadataOutput *output = [[self.captureSession outputs] firstObject];
    [output setRectOfInterest: [self convertRectOfInterest: rect]];
}

@end


/**
 * UI View Controller
 */
@implementation CDVbcsViewController
@synthesize processor      = _processor;
@synthesize overlayView    = _overlayView;

-(id)initWithProcessor: (CDVbcsProcessor *)processor
{
    self = [super init];
    if (!self) {
        return self;
    }

    self.processor = processor;
    self.overlayView = nil;
    return self;
}

-(void)dealloc
{
    self.view = nil;
    self.processor = nil;
    self.overlayView = nil;
}

- (void)loadView
{
    self.view = [[UIView alloc] initWithFrame: self.processor.parentViewController.view.frame];
}

-(void)viewWillAppear: (BOOL)animated
{
    // set video orientation to what the camera sees
    [[self.processor.previewLayer connection] setVideoOrientation: [self interfaceOrientationToVideoOrientation: [UIApplication sharedApplication].statusBarOrientation]];

    // this fixes the bug when the statusbar is landscape, and the preview layer
    // starts up in portrait (not filling the whole view)
    [self.processor.previewLayer setFrame: self.view.bounds];
}

- (void)viewDidAppear: (BOOL)animated
{
    AVCaptureVideoPreviewLayer *previewLayer = self.processor.previewLayer;
    [previewLayer setFrame: self.view.bounds];
    [previewLayer setVideoGravity: AVLayerVideoGravityResizeAspectFill];

    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    if ([previewLayer.connection isVideoOrientationSupported]) {
        [[previewLayer connection] setVideoOrientation: [self interfaceOrientationToVideoOrientation: orientation]];
    }
    [self.view.layer addSublayer: previewLayer];

    [self addOverlayView];
    self.processor.capturing = YES;

    [super viewDidAppear:animated];
}


- (AVCaptureVideoOrientation)interfaceOrientationToVideoOrientation:(UIInterfaceOrientation)orientation {
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
            return AVCaptureVideoOrientationPortrait;
        case UIInterfaceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
        case UIInterfaceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeLeft;
        case UIInterfaceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeRight;
        default:
            return AVCaptureVideoOrientationPortrait;
   }
}

- (void)cancelButtonPressed: (id)sender
{
    [self.processor performSelector:@selector(barcodeScanCancelled) withObject:nil afterDelay:0];
}

- (IBAction)flipCameraButtonPressed: (id)sender
{
    [self.processor performSelector:@selector(flipCamera) withObject:nil afterDelay:0];
}

- (IBAction)torchButtonPressed: (id)sender
{
    [self.processor performSelector:@selector(toggleTorch:) withObject: sender afterDelay:0];
}

-(void)addOverlayView
{
    CGRect bounds = self.view.frame;
    bounds = CGRectMake(0, 0, bounds.size.width, bounds.size.height);

    UIView *overlayView = [[UIView alloc] initWithFrame: bounds];
    overlayView.autoresizesSubviews = YES;
    overlayView.autoresizingMask    = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlayView.opaque              = NO;

    CGFloat buttonSize = 45.0;
    CGFloat buttonOffset = buttonSize / 2;

    // Cancel button
    NSURL *cancelImageUrl = [NSURL URLWithString: @"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAQAAABpN6lAAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAAmJLR0QAAKqNIzIAAAAJcEhZcwAADdcAAA3XAUIom3gAAAAHdElNRQfhCxMVEyaNvw4TAAADNElEQVR42u2dv1LqQBSHv1DwBjY0FjyAA7wCtna2ttrwLr6GY4PWKfQBJGNtb2PDMFQ2ewvmDheBC0l295zjYVO6Cb/vC4b82c0p+Lf1GDNkwAVfzKh4oyRguxWMGTFgyBnvVMwo+dzd8Y4F4cfyQl+aoFXr87LFtOCW4mfHc8qtjqtlyWS7u4lWMGG5h6rkfBN/vqfjapnSlaap3bpM/8s0Xyso9u799fJkTEGXp4NM5d9v9t3BrtYUHIMfCNwC9HYc+mwrOBY/sKAHN0d2tqLgePxA4Abua3TXr6AefuAeXmutoFtBXfzAKwd+AC0pqI8fmMNH7ZV0KmiCH/iAhwar6VPQDD/w0KFq9IFXPCpS0OWRq0ZrVnDZyJymb0HTvR8IXEKx43rJkoI2+C+rk+H+3msm/Qra4C/Xl/qTxhuRVdAGPzBZb6g4cOmoU0E7/OnmXY52G5NQED2xLQVJ0tpRkCypDQVJU+pXkDyhbgVZ0ulVkC2ZTgVZU+lTkD2RLgUiafQoEEuiQ4FoCnkF4glkA4jjy4ZQgS8XRA2+TBhV+PkDqcPPG0olfr5gavHzhFONnz6gevy0IU3gpwtqBj9NWFP48QObw48b2iR+vOBm8eOEN40fQ4Fx/PYKzONLKVCEL6FAGX5uBQrxcypQip9LgWL8HAqU46dWYAA/pQIj+KkUGMJPocAYfmwFBvFjKjCKH0uBYfwYCpLjd6QN/e7m/F/A+UHQ+c+g8xMh56fCzi+GnF8OO78h4vyWmPObos5vizt/MOL80Zjzh6POH487HyDhfIiM80FSzofJOR8o6XyorPPB0s6HyzufMOF8yozzSVPOp805nzjpfOqs88nTzqfPiwfw/v4I0RQ68MWS6MEXSaMLP3siffhZU+nEz5ZML36WdLrxkyfUj580pQ38ZEnt4CdJaws/emL3r9Z2/nJ156/Xd19gwXmJjQ6jhh/7zDXf0uwAfHPNc8N1R+7L7JwKLZ1KbTkvtla30pSeQ9+uVv9wWJ0KLp5Kbrovunoqu4v7wssrBa5Lb6+6uyy+vrlve4wZMuCCL2ZUvFESpBlatoIxIwYMOeOdihkln+s//wFFdoCM42fEswAAACV0RVh0ZGF0ZTpjcmVhdGUAMjAxNy0xMS0xOVQyMToxOTozOCswMTowMPNH2M8AAAAldEVYdGRhdGU6bW9kaWZ5ADIwMTctMTEtMTlUMjE6MTk6MzgrMDE6MDCCGmBzAAAAGXRFWHRTb2Z0d2FyZQB3d3cuaW5rc2NhcGUub3Jnm+48GgAAAABJRU5ErkJggg=="];
    NSData *cancelImageData = [NSData dataWithContentsOfURL: cancelImageUrl];
    UIImage *cancelIcon = [UIImage imageWithData: cancelImageData];

    UIButton *buttonCancel = [[UIButton alloc] initWithFrame: CGRectMake(buttonOffset, bounds.size.height - buttonSize - buttonOffset, buttonSize, buttonSize)];
    [buttonCancel addTarget: self action: @selector(cancelButtonPressed:) forControlEvents: UIControlEventTouchUpInside];
    [buttonCancel setImage: cancelIcon forState: UIControlStateNormal];
    [buttonCancel setBackgroundColor: [UIColor colorWithWhite: 1.0f alpha: 0.25f]];
    [buttonCancel setTransform: CGAffineTransformMakeRotation(M_PI / 2)];
    [[buttonCancel layer] setCornerRadius: (buttonSize / 2)];
    [buttonCancel setContentEdgeInsets: UIEdgeInsetsMake(15, 15, 15, 15)];
    [overlayView addSubview: buttonCancel];

    // Torch button
    if (_processor.showTorchButton && !_processor.useFrontCamera) {
        AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType: AVMediaTypeVideo];
        if ([device hasTorch] && [device hasFlash]) {
            NSURL *torchImageUrl = [NSURL URLWithString: @"data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAIAAAACACAQAAABpN6lAAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAAmJLR0QAAKqNIzIAAAAJcEhZcwAADdcAAA3XAUIom3gAAAAHdElNRQfhCxMVAzOqoPipAAADM0lEQVR42u2dv2sTcRyG38RWzGYHhxYHp+B+Lk7iIlhFXZvdPeAouOuS1X/AVCiiCBU6OjgIOffG+gvEgCIqlsQi9JxEbC/XJt8fz136eTJecve+T+6Su8t9czX5oqmWEiVa9DbHfAZKlaqrfuDlTERNbQ2VRXwM1VaNrv2v/nrU8n8f62VR0EbqZ8rUpqtLUjPyyv//htB0jV93FrCiBia/oRYv4BxWX5IS1xm4f4x8Cv7FV8RAS7SADKzvoYH7JlBxTAAdgMYE0AFoTAAdwDAMwzAMo7q8ws4IZsr0wjW++57gFqrfeenuAt6YAJLXvADbBFABJVgDPmobrP+DF5BpAxPwyH0WPk6IPKmyAB8/MJ/UZ80D9T/ojPtMfKwB3/UcqO/l/fd1TvAxIuAhstRclrQT/ShgzU/0Y17m8lMLOh9V+UjX3L8CfbKgr1Hf/zt04f3EvFLorU7QdfdzXFuR6v/SRbpsPjci1b9MFx3P7eD1d3SFLlnM3cD1r9IFD+Z+wJW/AvWluh4EqT/UJbraYZnTmvf627pA12IV3KQrTa7gqcf6z+g603BKXzzV/+Z6NSjFiicB9+gi07PhRcBZusb0XPdQ3/nXP5J5D58Dt8JGDHuZ3G8Pp60C//AS+jrBl85zeBc24FxgAe/HTulrVT2lkhIlao0d/RNYQGhO527Xu+rsGWnUUEe7uc+tOPXc+su5z13OVVB59lfqjH1u5ygI2CwYZtfQZmwB8a8WX9Vo7LSRurHjxBfQK5yaRs8TnL2rdPEow8XZ3wRKRnwBicPUmRBQPNY4uoDwlPxrML6AI78jZLvC5ToYCv83JOMqHPZwOHBCTkBJEtqOEB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgTQAWhMAB2AxgQEX8IAfHUpBLgNhg0+lDa8gJ7Tq2dgLLHLbXk93Fa3DEz/d6ttOrofpr01d2lure1DwaQ3Z492c/V4jptqKVFy4F2KB0qVqqt+nFh/ADjJgLiaxweIAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDE3LTExLTE5VDIxOjAzOjUxKzAxOjAwdhzbkgAAACV0RVh0ZGF0ZTptb2RpZnkAMjAxNy0xMS0xOVQyMTowMzo1MSswMTowMAdBYy4AAAAZdEVYdFNvZnR3YXJlAHd3dy5pbmtzY2FwZS5vcmeb7jwaAAAAAElFTkSuQmCCconv"];
            NSData *torchImageData = [NSData dataWithContentsOfURL: torchImageUrl];
            UIImage *torchIcon = [UIImage imageWithData: torchImageData];

            UIButton *buttonTorch = [[UIButton alloc] initWithFrame: CGRectMake(bounds.size.width - buttonSize - buttonOffset, bounds.size.height - buttonSize - buttonOffset, buttonSize, buttonSize)];
            [buttonTorch addTarget: self action: @selector(torchButtonPressed:) forControlEvents: UIControlEventTouchUpInside];
            [buttonTorch setImage: torchIcon forState: UIControlStateNormal];
            [buttonTorch setBackgroundColor: [UIColor colorWithWhite: 1.0f alpha: 0.25f]];
            [[buttonTorch layer] setCornerRadius: (buttonSize / 2)];
            [buttonTorch setContentEdgeInsets: UIEdgeInsetsMake(15, 15, 15, 15)];
            [overlayView addSubview: buttonTorch];
        }
    }

    [self addReticleToView: overlayView];
    [self.view addSubview: overlayView];
}

-(void)addReticleToView: (UIView *)overlayView
{
    BOOL isCard = (self.processor.detectorType != nil && [self.processor.detectorType isEqualToString: @"card"]);

    CGFloat height = overlayView.frame.size.height;
    CGFloat width = overlayView.frame.size.width;
    CGFloat diameterW = (float)(width * (isCard ? 0.85 : .75));
    if (diameterW > 350) {
        diameterW = 350;
    }
    CGFloat diameterH = (float)(diameterW * (isCard ? 0.60 : 1));

    CGFloat left = width / 2 - diameterW / 2;
    CGFloat top = height / 2 - diameterH / 2;

    self.reticleView = [[UILabel alloc] init];
    self.reticleView.frame = CGRectMake(left, top, diameterW, diameterH);
    self.reticleView.layer.masksToBounds = NO;
    self.reticleView.layer.cornerRadius = 20;
    self.reticleView.userInteractionEnabled = NO;
    self.reticleView.layer.borderColor = [UIColor whiteColor].CGColor;
    self.reticleView.layer.borderWidth = 3.0;

    // Add the reticle line
    CAShapeLayer *line = [[CAShapeLayer alloc] init];
    [line setPath: [UIBezierPath bezierPathWithRect: CGRectMake(3, (diameterH / 2) - 1.5, diameterW - 6, 3)].CGPath];
    [line setFillColor: [UIColor colorWithRed: 1.0f green: 0.0f blue: 0.0f alpha: 0.40f].CGColor];
    [[self.reticleView layer] addSublayer: line];

    [overlayView addSubview: self.reticleView];
}

#pragma mark CDVBarcodeScannerOrientationDelegate

-(BOOL)shouldAutorotate
{
    return YES;
}

-(UIInterfaceOrientation)preferredInterfaceOrientationForPresentation
{
    return [[UIApplication sharedApplication] statusBarOrientation];
}

-(NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationMaskAll;
}

-(BOOL)shouldAutorotateToInterfaceOrientation: (UIInterfaceOrientation)interfaceOrientation
{
    if ((self.orientationDelegate != nil) && [self.orientationDelegate respondsToSelector: @selector(shouldAutorotateToInterfaceOrientation:)]) {
        return [self.orientationDelegate shouldAutorotateToInterfaceOrientation: interfaceOrientation];
    }

    return YES;
}

-(void)updateLayoutForNewOrientation: (UIInterfaceOrientation)orientation
{
    AVCaptureVideoPreviewLayer *previewLayer = self.processor.previewLayer;
    [previewLayer.connection setVideoOrientation: [self interfaceOrientationToVideoOrientation: orientation]];
    [previewLayer setFrame: self.view.bounds];
    [previewLayer setVideoGravity: AVLayerVideoGravityResizeAspectFill];

    // Center the reticle view
    self.reticleView.center = CGPointMake(self.view.center.x, self.view.center.y);
    [self.processor updateRectOfInterest: self.reticleView.frame];
}
@end
