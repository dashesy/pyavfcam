// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy

#import <Foundation/Foundation.h>

#include <stdexcept>
#include <iostream>
#include "camera_frame.h"
#include "utils.h"


CameraFrame::CameraFrame(CMSampleBufferRef sampleBuffer)
{
    // Get a bitmap representation of the frame using CoreImage and Cocoa calls

    // Pass an actual reference to a custom Frame class up

//    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(source);
//    CVPixelBufferLockBaseAddress(imageBuffer,0);
//
//    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
//    size_t width = CVPixelBufferGetWidth(imageBuffer);
//    size_t height = CVPixelBufferGetHeight(imageBuffer);
//    void *src_buff = CVPixelBufferGetBaseAddress(imageBuffer);
//
//    NSData *data = [NSData dataWithBytes:src_buff length:bytesPerRow * height];
//
//    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
//        UIImage * img = [[UIImage alloc] initWithData:d];
}

void CameraFrame::save(std::string path, std::string uti_str, float quality)
{
        CFStringRef uti_type = (CFStringRef)@"public.png";
        if (uti_str.length() == 0) {
            std::string ext = str_tolower(file_extension(path));
            if (ext == ".jpeg" || ext == ".jpg")
                uti_type = (CFStringRef)@"public.jpeg";
            // TODO: Can infere more uti mime
        }
        // Get the string and expand it to a file URL
        NSString* path_str = [[NSString stringWithUTF8String:path.c_str()] stringByExpandingTildeInPath];
        NSURL *url = [NSURL fileURLWithPath:path_str];

//        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
//        //
//        jpeg = ... is ext jpg
//        CGImageRef imageRef = ...
//        CFMutableDictionaryRef mSaveMetaAndOpts = NULL;
//        CFStringRef uti_type = (CFStringRef)@"public.png";
//        if (jpeg) {
//            mSaveMetaAndOpts = CFDictionaryCreateMutable(nil, 0, &kCFTypeDictionaryKeyCallBacks,  &kCFTypeDictionaryValueCallBacks);
//            CFDictionarySetValue(mSaveMetaAndOpts, kCGImageDestinationLossyCompressionQuality,
//                                 [NSNumber numberWithFloat:quality]);
//            uti_type = (CFStringRef)@"public.jpeg"
//        }
//
//        CGImageDestinationRef dr = CGImageDestinationCreateWithURL((CFURLRef)outURL, uti_type, 1, NULL);
//        CGImageDestinationAddImage(dr, imageRef, mSaveMetaAndOpts);
//        CGImageDestinationFinalize(dr);
//        [pool drain];
}
