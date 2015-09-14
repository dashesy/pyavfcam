// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy

#import <Foundation/Foundation.h>

#include <stdexcept>
#include <iostream>
#include "camera_frame.h"
#include "utils.h"


// Input is a frame reference, make a solid object from it
CameraFrame::CameraFrame(CMSampleBufferRef sampleBuffer)
    : m_bytesPerRow(0), m_width(0), m_height(0),
      m_exif(NULL)
{
    //NSLog(@" sampleBuffer %@", sampleBuffer);
    // Get a bitmap representation of the frame using CoreImage and Cocoa calls

    // Pass an actual reference to a custom Frame class up

    // Take exif to re-attach if need to save as image
    CFDictionaryRef exifAttachments = (CFDictionaryRef)CMGetAttachment(sampleBuffer, kCGImagePropertyExifDictionary, NULL);
    if (exifAttachments) {
        NSLog(@"attachements: %@", exifAttachments);
        // Replace the previous copy (if any)
        if (m_exif)
            CFRelease(m_exif);
        m_exif = CFDictionaryCreateMutableCopy(nil, 0, exifAttachments);
    }

    // Take the bitmap
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // NSLog(@" imageBuffer %@", imageBuffer);
    CVPixelBufferLockBaseAddress(imageBuffer,0);

    m_bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    m_width = CVPixelBufferGetWidth(imageBuffer);
    m_height = CVPixelBufferGetHeight(imageBuffer);
    const char * src_buff = (const char *)CVPixelBufferGetBaseAddress(imageBuffer);
    char * dst_buf = new char[m_bytesPerRow * m_height];
    std::memcpy(dst_buf, src_buff, m_bytesPerRow * m_height);
    m_img = std::unique_ptr<char[]>(dst_buf);

    CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    
    std::cout << " size " <<  m_bytesPerRow << " " << m_height << " x " << m_width << std::endl;
}

// Destructor
CameraFrame::~CameraFrame()
{
    if (m_exif) {
        CFRelease(m_exif);
        m_exif = NULL;
    }
}

// Save the frame to an image file
void CameraFrame::save(std::string path, std::string uti_str, float quality)
{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

        bool found_uti = true;
        CFStringRef uti_type = (CFStringRef)@"public.png";
        if (uti_str.length() == 0) {
            found_uti = false;
            std::string ext = str_tolower(file_extension(path));
            if (ext == ".jpeg" || ext == ".jpg") {
                uti_type = (CFStringRef)@"public.jpeg";
                found_uti = true;
            } else if (ext == ".png") {
                found_uti = true;
            }
        }
        
        // Get the string and expand it to a file URL
        NSString* path_str = [[NSString stringWithUTF8String:path.c_str()] stringByExpandingTildeInPath];

        CFStringRef uti = NULL;
        if (!found_uti) {
            // Infere the uti
            uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)[path_str pathExtension], NULL);
            // If not known assume png
            if (uti)
                uti_type = uti;
        }

        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

        CGContextRef newContext = CGBitmapContextCreate((CGImageRef) m_img.get(),
                                                        m_width, m_height, 8, m_bytesPerRow, colorSpace,
                                                        kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

        if (!newContext) {
            std::cerr << "[c+]  error in CGBitmapContextCreate!\n";
        } else {
            CGImageRef newImageRef = CGBitmapContextCreateImage(newContext); // It does a COW

            if (!newImageRef) {
                std::cerr << "[c+]  error in CGBitmapContextCreateImage!\n";
            } else {
                CGColorSpaceRelease(colorSpace);

                CFMutableDictionaryRef mSaveMetaAndOpts = NULL;
                if (m_exif)
                    mSaveMetaAndOpts = CFDictionaryCreateMutableCopy(nil, 0, m_exif);
                else
                    mSaveMetaAndOpts = CFDictionaryCreateMutable(nil, 0, &kCFTypeDictionaryKeyCallBacks,  &kCFTypeDictionaryValueCallBacks);

                // Set the image quality
                CFDictionarySetValue(mSaveMetaAndOpts, kCGImageDestinationLossyCompressionQuality, [NSNumber numberWithFloat:quality]);

                NSURL *url = [NSURL fileURLWithPath:path_str];
                CGImageDestinationRef dr = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, uti_type, 1, NULL);

                CGImageDestinationAddImage(dr, newImageRef, mSaveMetaAndOpts);
                CGImageDestinationFinalize(dr);

                if (mSaveMetaAndOpts)
                    CFRelease(mSaveMetaAndOpts);

                CFRelease(newImageRef);
            }
            CGContextRelease(newContext);
        }

        if (uti)
            CFRelease(uti);
        [pool drain];
}
