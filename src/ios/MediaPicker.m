/********* MediaPicker.m Cordova Plugin Implementation *******/

#import <Cordova/CDV.h>
#import "DmcPickerViewController.h"
@interface AdvancedImagePicker : CDVPlugin <DmcPickerDelegate>{
    // Member variables go here.
    NSString* callbackId;
    NSInteger photoWidth;
    NSInteger photoHeight;
}

- (void)present:(CDVInvokedUrlCommand*)command;
- (void)takePhoto:(CDVInvokedUrlCommand*)command;
- (void)extractThumbnail:(CDVInvokedUrlCommand*)command;

@end

@implementation AdvancedImagePicker

NSDictionary *currentOptions;

- (void)present:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    currentOptions = [command.arguments objectAtIndex: 0];
    DmcPickerViewController * dmc=[[DmcPickerViewController alloc] init];
    @try{
        dmc.selectMode=100;
    }@catch (NSException *exception) {
        NSLog(@"Exception: %@", exception);
    }
    @try{
        dmc.maxSelectCount=[[currentOptions objectForKey:@"max"]integerValue];
    }@catch (NSException *exception) {
        NSLog(@"Exception: %@", exception);
    }
    @try{
        photoWidth = [[currentOptions objectForKey:@"width"]integerValue];
    }@catch (NSException *exception) {
        photoWidth = 0;
    }
    
    @try{
        photoHeight = [[currentOptions objectForKey:@"height"]integerValue];
    }@catch (NSException *exception) {
        photoHeight = 0;
    }
    
    dmc.modalPresentationStyle = 0;
    if (@available(iOS 13.0, *)) {
        dmc.modalInPresentation = true;
    }
    dmc._delegate=self;
    [self.viewController presentViewController:[[UINavigationController alloc]initWithRootViewController:dmc] animated:YES completion:nil];
}

-(void) resultPicker:(NSMutableArray*) selectArray
{
    
    NSString * tmpDir = NSTemporaryDirectory();
    NSString *dmcPickerPath = [tmpDir stringByAppendingPathComponent:@"dmcPicker"];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if(![fileManager fileExistsAtPath:dmcPickerPath ]){
        [fileManager createDirectoryAtPath:dmcPickerPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    NSMutableArray * aListArray=[[NSMutableArray alloc] init];
    if([selectArray count]<=0){
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
        return;
    }
    
    dispatch_async(dispatch_get_global_queue (DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        int index=0;
        for(PHAsset *asset in selectArray){
            @autoreleasepool {
                if(asset.mediaType==PHAssetMediaTypeImage){
                    [self imageToSandbox:asset dmcPickerPath:dmcPickerPath aListArray:aListArray selectArray:selectArray index:index];
                }else{
                    [self videoToSandboxCompress:asset dmcPickerPath:dmcPickerPath aListArray:aListArray selectArray:selectArray index:index];
                }
            }
            index++;
        }
    });
    
}

-(UIImage*)processImage:(UIImage*)image {
    
    
    if(photoWidth != 0 && photoHeight != 0) {
        CGSize imgSize = image.size;
        
        CGFloat widthRatio = (CGFloat)photoWidth / imgSize.width;
        CGFloat heightRatio = (CGFloat)photoHeight / imgSize.height;
        
        CGSize newSize;
        if(widthRatio > heightRatio) {
            newSize = CGSizeMake(imgSize.width * heightRatio, imgSize.height * heightRatio);
        } else {
            newSize = CGSizeMake(imgSize.width * widthRatio, imgSize.height * widthRatio);
        }
        
        CGRect rect = CGRectMake(0, 0, newSize.width, newSize.height);
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0f);
        CGContextRef context = UIGraphicsGetCurrentContext();
        
        //CGContextTranslateCTM(context, 0, newSize.height);
        //CGContextScaleCTM(context, 1.0, -1.0);
        
        UIGraphicsPushContext(context);
        [image drawInRect:rect]; // UIImage will handle all especial cases!
        UIGraphicsPopContext();
        
        // CGContextDrawImage(context, rect, imageRef);
        /*
         switch(orientationData) {
         case kCGImagePropertyOrientationUp:
         break;
         case kCGImagePropertyOrientationDown:
         CGContextRotateCTM(context,180.f);
         break;
         case kCGImagePropertyOrientationLeft:
         CGContextRotateCTM(context,90);
         break;
         case kCGImagePropertyOrientationRight:
         CGContextRotateCTM(context,270);
         break;
         case kCGImagePropertyOrientationUpMirrored:
         CGContextScaleCTM(context, -1.f, -1.f);
         break;
         case kCGImagePropertyOrientationDownMirrored:
         CGContextScaleCTM(context, 1.f, -1.f);
         break;
         case kCGImagePropertyOrientationLeftMirrored:
         CGContextRotateCTM(context,90);
         break;
         case kCGImagePropertyOrientationRightMirrored:
         CGContextScaleCTM(context, -1.f, 1.f);
         break;
         }
         */
        
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
    }
    
    return image;
}
-(void)imageToSandbox:(PHAsset *)asset dmcPickerPath:(NSString*)dmcPickerPath aListArray:(NSMutableArray*)aListArray selectArray:(NSMutableArray*)selectArray index:(int)index{
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.synchronous = NO;
    options.networkAccessAllowed = YES;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    options.version = PHImageRequestOptionsVersionCurrent;
    options.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        NSString *compressCompletedjs = [NSString stringWithFormat:@"MediaPicker.icloudDownloadEvent(%f,%i)", progress,index];
        [self.commandDelegate evalJs:compressCompletedjs];
    };
    [[PHImageManager defaultManager] requestImageDataForAsset:asset  options:options resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, UIImageOrientation orientation, NSDictionary * _Nullable info) {
        if(imageData != nil) {
            NSString *filename=[asset valueForKey:@"filename"];
            
            float quality = 0.8;
            
            @try{
                quality=[[currentOptions objectForKey:@"quality"]integerValue]/100;
            }@catch (NSException *exception) {
                NSLog(@"Exception: %@", exception);
            }
            
            if ([filename hasSuffix:@".HEIC"]) {
                imageData = UIImageJPEGRepresentation([UIImage imageWithData:imageData], quality);
                filename = [filename stringByReplacingOccurrencesOfString:@".HEIC" withString:@".JPG"];
            }
            
            imageData = UIImageJPEGRepresentation([self processImage:[UIImage imageWithData:imageData]], quality);
            
            NSString *fullpath=[NSString stringWithFormat:@"%@/%@%@", dmcPickerPath,[[NSProcessInfo processInfo] globallyUniqueString], filename];
            NSNumber *size=[NSNumber numberWithLong:imageData.length];
            
            NSError *error = nil;
            
            bool asBase64 = false;
            @try{
                asBase64=[[currentOptions objectForKey:@"asBase64"]boolValue];
            }@catch (NSException *exception) {
                NSLog(@"Exception: %@", exception);
            }
            
            
            if(!asBase64){
                if (![imageData writeToFile:fullpath options:NSAtomicWrite error:&error]) {
                    NSLog(@"%@", [error localizedDescription]);
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:callbackId];
                } else {
                    
                    NSDictionary *dict=[NSDictionary dictionaryWithObjectsAndKeys:fullpath,@"path",[[NSURL fileURLWithPath:fullpath] absoluteString],@"uri",@"image",@"mediaType",size,@"size",[NSNumber numberWithInt:index],@"index", nil];
                    [aListArray addObject:dict];
                    if([aListArray count]==[selectArray count]){
                        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
                    }
                }
            } else {
                NSNumber *size=[NSNumber numberWithLong:imageData.length];
                NSDictionary *dict=[NSDictionary dictionaryWithObjectsAndKeys:[NSString stringWithFormat:@"%@%@", @"data:image/jpeg;base64,", [imageData base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength] ],@"src",@"image",@"mediaType",@"true",@"isBase64",size,@"size",[NSNumber numberWithInt:index],@"index", nil];
                [aListArray addObject:dict];
                if([aListArray count]==[selectArray count]){
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
                }
            }
        } else {
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:NSLocalizedString(@"photo_download_failed", nil)] callbackId:callbackId];
        }
    }];
}

- (void)getExifForKey:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSString *path= [command.arguments objectAtIndex: 0];
    NSString *key  = [command.arguments objectAtIndex: 1];
    
    NSData *imageData = [NSData dataWithContentsOfFile:path];
    //UIImage * image= [[UIImage alloc] initWithContentsOfFile:[options objectForKey:@"path"] ];
    CGImageSourceRef imageRef=CGImageSourceCreateWithData((CFDataRef)imageData, NULL);
    
    CFDictionaryRef imageInfo = CGImageSourceCopyPropertiesAtIndex(imageRef, 0,NULL);
    
    NSDictionary  *nsdic = (__bridge_transfer  NSDictionary*)imageInfo;
    NSString* orientation=[nsdic objectForKey:key];
    
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:orientation] callbackId:callbackId];
    
    
}


-(void)videoToSandbox:(PHAsset *)asset dmcPickerPath:(NSString*)dmcPickerPath aListArray:(NSMutableArray*)aListArray selectArray:(NSMutableArray*)selectArray index:(int)index{
    PHImageRequestOptions *options = [[PHImageRequestOptions alloc] init];
    options.networkAccessAllowed = YES;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    options.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        NSString *compressCompletedjs = [NSString stringWithFormat:@"MediaPicker.icloudDownloadEvent(%f,%i)", progress,index];
        [self.commandDelegate evalJs:compressCompletedjs];
    };
    [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:options resultHandler:^(AVAsset *avsset, AVAudioMix *audioMix, NSDictionary *info) {
        if ([avsset isKindOfClass:[AVURLAsset class]]) {
            NSString *filename = [asset valueForKey:@"filename"];
            AVURLAsset* urlAsset = (AVURLAsset*)avsset;
            
            NSString *fullpath=[NSString stringWithFormat:@"%@/%@", dmcPickerPath,filename];
            NSLog(@"%@", urlAsset.URL);
            NSData *data = [NSData dataWithContentsOfURL:urlAsset.URL options:NSDataReadingUncached error:nil];
            
            NSNumber* size=[NSNumber numberWithLong: data.length];
            NSError *error = nil;
            if (![data writeToFile:fullpath options:NSAtomicWrite error:&error]) {
                NSLog(@"%@", [error localizedDescription]);
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:callbackId];
            } else {
                
                NSDictionary *dict=[NSDictionary dictionaryWithObjectsAndKeys:fullpath,@"path",[[NSURL fileURLWithPath:fullpath] absoluteString],@"uri",size,@"size",@"video",@"mediaType" ,[NSNumber numberWithInt:index],@"index", nil];
                [aListArray addObject:dict];
                if([aListArray count]==[selectArray count]){
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
                }
            }
            
        }
    }];
    
}

-(void)videoToSandboxCompress:(PHAsset *)asset dmcPickerPath:(NSString*)dmcPickerPath aListArray:(NSMutableArray*)aListArray selectArray:(NSMutableArray*)selectArray index:(int)index{
    NSString *compressStartjs = [NSString stringWithFormat:@"MediaPicker.compressEvent('%@',%i)", @"start",index];
    [self.commandDelegate evalJs:compressStartjs];
    [[PHImageManager defaultManager] requestExportSessionForVideo:asset options:nil exportPreset:AVAssetExportPresetMediumQuality resultHandler:^(AVAssetExportSession *exportSession, NSDictionary *info) {
        
        
        NSString *fullpath=[NSString stringWithFormat:@"%@/%@.%@", dmcPickerPath,[[NSProcessInfo processInfo] globallyUniqueString], @"mp4"];
        NSURL *outputURL = [NSURL fileURLWithPath:fullpath];
        
        NSLog(@"this is the final path %@",outputURL);
        
        exportSession.outputFileType=AVFileTypeMPEG4;
        
        exportSession.outputURL=outputURL;
        
        [exportSession exportAsynchronouslyWithCompletionHandler:^{
            
            if (exportSession.status == AVAssetExportSessionStatusFailed) {
                NSString * errorString = [NSString stringWithFormat:@"videoToSandboxCompress failed %@",exportSession.error];
                [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:errorString] callbackId:callbackId];
                NSLog(@"failed");
                
            } else if(exportSession.status == AVAssetExportSessionStatusCompleted){
                
                NSLog(@"completed!");
                NSString *compressCompletedjs = [NSString stringWithFormat:@"MediaPicker.compressEvent('%@',%i)", @"completed",index];
                [self.commandDelegate evalJs:compressCompletedjs];
                NSDictionary *dict=[NSDictionary dictionaryWithObjectsAndKeys:fullpath,@"path",[[NSURL fileURLWithPath:fullpath] absoluteString],@"uri",@"video",@"mediaType" ,[NSNumber numberWithInt:index],@"index", nil];
                [aListArray addObject:dict];
                if([aListArray count]==[selectArray count]){
                    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArray:aListArray] callbackId:callbackId];
                }
            }
            
        }];
        
    }];
}



-(NSString*)thumbnailVideo:(NSString*)path quality:(NSInteger)quality {
    UIImage *shotImage;
    //视频路径URL
    NSURL *fileURL = [NSURL fileURLWithPath:path];
    
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:fileURL options:nil];
    
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    
    gen.appliesPreferredTrackTransform = YES;
    
    CMTime time = CMTimeMakeWithSeconds(0.0, 600);
    
    NSError *error = nil;
    
    CMTime actualTime;
    
    CGImageRef image = [gen copyCGImageAtTime:time actualTime:&actualTime error:&error];
    
    shotImage = [[UIImage alloc] initWithCGImage:image];
    
    CGImageRelease(image);
    CGFloat q=quality/100.0f;
    NSString *thumbnail=[UIImageJPEGRepresentation(shotImage,q) base64EncodedStringWithOptions:0];
    return thumbnail;
}

- (void)takePhoto:(CDVInvokedUrlCommand*)command
{
    
    
}

-(UIImage*)getThumbnailImage:(NSString*)path type:(NSString*)mtype{
    UIImage *result;
    if([@"image" isEqualToString: mtype]){
        result= [[UIImage alloc] initWithContentsOfFile:path];
    }else{
        NSURL *fileURL = [NSURL fileURLWithPath:path];
        
        AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:fileURL options:nil];
        
        AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        
        gen.appliesPreferredTrackTransform = YES;
        
        CMTime time = CMTimeMakeWithSeconds(0.0, 600);
        
        NSError *error = nil;
        
        CMTime actualTime;
        
        CGImageRef image = [gen copyCGImageAtTime:time actualTime:&actualTime error:&error];
        
        result = [[UIImage alloc] initWithCGImage:image];
    }
    return result;
}

-(NSString*)thumbnailImage:(UIImage*)result quality:(NSInteger)quality{
    NSInteger qu = quality>0?quality:3;
    CGFloat q=qu/100.0f;
    NSString *thumbnail=[UIImageJPEGRepresentation(result,q) base64EncodedStringWithOptions:0];
    return thumbnail;
}

- (void)extractThumbnail:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSMutableDictionary *options = [command.arguments objectAtIndex: 0];
    UIImage * image=[self getThumbnailImage:[options objectForKey:@"path"] type:[options objectForKey:@"mediaType"]];
    NSString *thumbnail=[self thumbnailImage:image quality:[[options objectForKey:@"thumbnailQuality"] integerValue]];
    
    [options setObject:thumbnail forKey:@"thumbnailBase64"];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options] callbackId:callbackId];
}

- (void)compressImage:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSMutableDictionary *options = [command.arguments objectAtIndex: 0];
    
    NSInteger quality=[[options objectForKey:@"quality"] integerValue];
    if(quality<100&&[@"image" isEqualToString: [options objectForKey:@"mediaType"]]){
        UIImage *result = [[UIImage alloc] initWithContentsOfFile: [options objectForKey:@"path"]];
        NSInteger qu = quality>0?quality:3;
        CGFloat q=qu/100.0f;
        NSData *data =UIImageJPEGRepresentation(result,q);
        NSString *dmcPickerPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"dmcPicker"];
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if(![fileManager fileExistsAtPath:dmcPickerPath ]){
            [fileManager createDirectoryAtPath:dmcPickerPath withIntermediateDirectories:YES attributes:nil error:nil];
        }
        NSString *filename=[NSString stringWithFormat:@"%@%@%@",@"dmcMediaPickerCompress", [self currentTimeStr],@".jpg"];
        NSString *fullpath=[NSString stringWithFormat:@"%@/%@", dmcPickerPath,filename];
        NSNumber* size=[NSNumber numberWithLong: data.length];
        NSError *error = nil;
        if (![data writeToFile:fullpath options:NSAtomicWrite error:&error]) {
            NSLog(@"%@", [error localizedDescription]);
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:callbackId];
        } else {
            [options setObject:fullpath forKey:@"path"];
            [options setObject:[[NSURL fileURLWithPath:fullpath] absoluteString] forKey:@"uri"];
            [options setObject:size forKey:@"size"];
            [options setObject:filename forKey:@"name"];
            [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options] callbackId:callbackId];
        }
        
    }else{
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options] callbackId:callbackId];
    }
}

//获取当前时间戳
- (NSString *)currentTimeStr{
    NSDate* date = [NSDate dateWithTimeIntervalSinceNow:0];//获取当前时间0秒后的时间
    NSTimeInterval time=[date timeIntervalSince1970]*1000;// *1000 是精确到毫秒，不乘就是精确到秒
    NSString *timeString = [NSString stringWithFormat:@"%.0f", time];
    return timeString;
}


-(void)fileToBlob:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSData *result =[NSData dataWithContentsOfFile:[command.arguments objectAtIndex: 0]];
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsArrayBuffer:result]callbackId:command.callbackId];
}

- (void)getFileInfo:(CDVInvokedUrlCommand*)command
{
    callbackId=command.callbackId;
    NSString *type= [command.arguments objectAtIndex: 1];
    NSURL *url;
    NSString *path;
    if([type isEqualToString:@"uri"]){
        NSString *str=[command.arguments objectAtIndex: 0];
        url = [NSURL URLWithString:str];
        path= url.path;
    }else{
        path= [command.arguments objectAtIndex: 0];
        url =  [NSURL fileURLWithPath:path];
    }
    NSMutableDictionary *options = [NSMutableDictionary dictionaryWithCapacity:5];
    [options setObject:path forKey:@"path"];
    [options setObject:url.absoluteString forKey:@"uri"];
    
    NSNumber * size = [NSNumber numberWithUnsignedLongLong:[[[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil] fileSize]];
    [options setObject:size forKey:@"size"];
    NSString *fileName = [[NSFileManager defaultManager] displayNameAtPath:path];
    [options setObject:fileName forKey:@"name"];
    if([[self getMIMETypeURLRequestAtPath:path] containsString:@"video"]){
        [options setObject:@"video" forKey:@"mediaType"];
    }else{
        [options setObject:@"image" forKey:@"mediaType"];
    }
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:options] callbackId:callbackId];
}


-(NSString *)getMIMETypeURLRequestAtPath:(NSString*)path
{
    //1.确定请求路径
    NSURL *url = [NSURL fileURLWithPath:path];
    
    //2.创建可变的请求对象
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    
    //3.发送请求
    NSHTTPURLResponse *response = nil;
    [NSURLConnection sendSynchronousRequest:request returningResponse:&response error:nil];
    
    NSString *mimeType = response.MIMEType;
    return mimeType;
}


@end
