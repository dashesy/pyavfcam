// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#include <stdexcept>
#include <iostream>
#include <limits>
#include <cmath>
#include "avf.h"
#include "avf_impl.h"
#include "camera_frame.h"
#include "utils.h"
#include "../avf_api.h"


// Default constructor
CppAVFCam::CppAVFCam()
    : m_pObj(NULL),
      m_sink_file(false), m_sink_callback(false), m_sink_image(false),
      m_pCapture(NULL),
      m_bBlockingImage(false),
      m_videoFrameCount(0), m_imageFrameCount(0),
      m_haveImageCallback(true), m_haveVideoCallback(true), m_haveMovieCallback(true)
{
}

// move-constructor
CppAVFCam::CppAVFCam(CppAVFCam&& other)
    : CppAVFCam()
{
    *this = std::move(other);
}

// designated constructor
CppAVFCam::CppAVFCam(bool sink_file, bool sink_callback, bool sink_image, PyObject * pObj)
    : CppAVFCam()
{
    // Keep the requested sinks
    m_sink_file = sink_file;
    m_sink_callback = sink_callback;
    m_sink_image = sink_image;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    if (pObj) {
        m_pObj = PyWeakref_NewRef(pObj, NULL);

        if (import_pyavfcam()) {
            std::cerr << "[c+]  error in import_pyavfcam!\n";
            Py_XDECREF(m_pObj);
            m_pObj = NULL;
        } else {
            Py_XINCREF(m_pObj);
        }
    }
    std::cout << "const cur " << CFRunLoopGetCurrent()<< " const main " << CFRunLoopGetMain() << std::endl;

    // Connect this class with NSObject
    m_pCapture = [[AVCaptureDelegate alloc] initWithInstance: this];

    [pool drain];

    // Now raise if error detected above for RAII
    if (m_pCapture && !m_pCapture->m_pDevice)
        throw std::runtime_error("cannot access the webcam video source");
    if (!m_pCapture || !m_pCapture->m_pSession)
        throw std::runtime_error("cannot create multimedia session (perhaps memory error)");
    if (sink_file && !m_pCapture->m_pVideoFileOutput)
        throw std::runtime_error("cannot create file video sink");
    if (sink_image && !m_pCapture->m_pStillImageOutput)
        throw std::runtime_error("cannot create image sink");
}

// Destructor
CppAVFCam::~CppAVFCam()
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    std::cout << "dest cur " << CFRunLoopGetCurrent()<< " dest main " << CFRunLoopGetMain() << std::endl;
    

    if (m_pCapture) {
        std::cout << "   m_pCapture " << CFGetRetainCount((__bridge CFTypeRef)m_pCapture) << std::endl;
        [m_pCapture release];
        m_pCapture = NULL;
    }

    [pool drain];

    // decrease refcount of the Python binding
    Py_XDECREF(m_pObj);
    m_pObj = NULL;
    std::cout << " dest end " << std::endl;
}

// Move assignment operator
CppAVFCam & CppAVFCam::operator= (CppAVFCam && other)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    m_pObj = other.m_pObj;
    m_sink_file = other.m_sink_file;
    m_sink_callback = other.m_sink_callback;
    m_sink_image = other.m_sink_image;

    m_pCapture = other.m_pCapture;
    if (m_pCapture)
        [m_pCapture setInstance:this];

    // Ownership of other is moved to this
    other.m_pObj = NULL;
    m_sink_file = false;
    m_sink_callback = false;
    m_sink_image = false;
    other.m_pCapture = NULL;
    
    [pool drain];

    return *this;
}

// File output callback to Python
void CppAVFCam::file_output_done(bool error)
{
    // BUG: If duration is given to AVFoundation it seems as opposed to Apple docs, this is not called !!

    std::cout << "file output" << " cur " << CFRunLoopGetCurrent()<< " f main " << CFRunLoopGetMain() << std::endl;

    if (!m_pObj || !m_haveMovieCallback)
        return;

    int overridden = 0;
    PyObject * kwargs = Py_BuildValue("{}");
    PyObject * args = Py_BuildValue("(i)", error);

    PyGILState_STATE gstate = PyGILState_Ensure();

    // Call a virtual overload, if it exists
    cy_call_func(m_pObj, &overridden, (char*)__func__, args, kwargs);

    PyGILState_Release(gstate);
    
    if (!overridden)
        m_haveMovieCallback = false;
}

// Video frame callback to Python
void CppAVFCam::video_output(CameraFrame &frame)
{
    frame.m_frameCount = m_videoFrameCount++;
    if (!m_pObj || !m_haveVideoCallback)
        return;

    int overridden = 0;
    PyObject * kwargs = Py_BuildValue("{}");
    PyObject * pObj = cy_get_frame(frame);
    PyObject * args = Py_BuildValue("(O)", pObj);

    // Call a virtual overload, if it exists
    cy_call_func(m_pObj, &overridden, (char*)__func__, args, kwargs);

    if (!overridden)
        m_haveVideoCallback = false;
}

// Video frame callback to Python
PyObject * CppAVFCam::image_output(CameraFrame &frame)
{
    frame.m_frameCount = m_imageFrameCount++;
    if (!m_pObj || !m_haveImageCallback)
        return NULL;

    int overridden = 0;
    PyObject * kwargs = Py_BuildValue("{}");
    PyObject * pObj = cy_get_frame(frame);
    PyObject * args = Py_BuildValue("(O)", pObj);

    // If non-blocking it is from a foreign thread make sure gil is aquired
    PyGILState_STATE gstate;
    if (!m_bBlockingImage)
        gstate = PyGILState_Ensure();

    // Call a virtual overload, if it exists
    cy_call_func(m_pObj, &overridden, (char*)__func__, args, kwargs);

    if (!m_bBlockingImage)
        PyGILState_Release(gstate);
        
    if (!overridden)
        m_haveImageCallback = false;

    return pObj;
}

void CppAVFCam::set_settings(unsigned int width, unsigned int height, unsigned int fps)
{
    if (!m_pCapture || !m_pCapture->m_pSession)
        throw std::invalid_argument( "session not initialized" );

    if (fps == 0)
        fps = 1;

//    if ( [m_pDevice lockForConfiguration:NULL] == YES ) {
//        // should set these properties after output is added to session or it may be lost
//        [m_pDevice setActiveVideoMinFrameDuration:CMTimeMake(1, fps)];
//        [m_pDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, fps)];
//        [m_pDevice unlockForConfiguration];
//    }

    // TODO: set width and height settings
}

// Record to file video sink at given file path
void CppAVFCam::record(std::string path, float duration, unsigned int blocking)
{
    if (!m_pCapture || !m_pCapture->m_pSession)
        throw std::invalid_argument( "session not initialized" );
    if (!m_pCapture->m_pVideoFileOutput)
        throw std::invalid_argument( "file video sink not initialized" );

    if (duration < 1)
        duration = 1;

    bool no_duration = (duration == std::numeric_limits<float>::infinity() || std::isnan(duration));
    if (no_duration)
        duration = 0;

    if (no_duration && blocking) {
        std::cerr << "blocking non-stop recording turned into non-blocking!" << std::endl;
        blocking = 0;
    }

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    // Get the string and expand it to a file URL
    NSString* path_str = [[NSString stringWithUTF8String:path.c_str()] stringByExpandingTildeInPath];
    NSURL *url = [NSURL fileURLWithPath:path_str];

    NSError *file_error = nil;
    // AVFoundation will not overwrite but we do, remove the file if it exists
    [[NSFileManager defaultManager] removeItemAtURL:url error:&file_error];

    // The only accepted file error is if file does not exist yet
    if (!file_error || file_error.code == NSFileNoSuchFileError) {
        file_error = nil;
        [m_pCapture startRecordingToOutputFileURL:url
                                     withDuration:duration
                                     withBlocking:blocking];
    }

    [pool drain];

    if (file_error)
        throw std::invalid_argument( "invalid or inaccessable file path" );
}

// Stop recording to file if recording in progress
void CppAVFCam::stop_recording()
{
    if (!m_pCapture || !m_pCapture->m_pSession)
        throw std::invalid_argument( "session not initialized" );
    if (!m_pCapture->m_pVideoFileOutput)
        throw std::invalid_argument( "file video sink not initialized" );

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    //[m_pVideoFileOutput stopRecording];

    // Note that some samples will be flushed in the backgrouns and the callback will know when the file is ready

    [pool drain];
}

// Record to still image sink at given file path
PyObject * CppAVFCam::snap_picture(std::string path, unsigned int blocking,
                                   std::string uti_str, float quality)
{
    if (!m_pCapture || !m_pCapture->m_pSession)
        throw std::invalid_argument( "session not initialized" );
    if (!m_pCapture->m_pStillImageOutput)
        throw std::invalid_argument( "image video sink not initialized" );
        
//    m_bBlockingImage = blocking > 0;
//
//    bool no_file = path.length() == 0;
//    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
//
//    NSError *file_error = nil;
//    if (! no_file) {
//        // Get the string and expand it to a file URL
//        NSString* path_str = [[NSString stringWithUTF8String:path.c_str()] stringByExpandingTildeInPath];
//        NSURL *url = [NSURL fileURLWithPath:path_str];
//
//        // AVFoundation will not overwrite but we do, remove the file if it exists
//        [[NSFileManager defaultManager] removeItemAtURL:url error:&file_error];
//    }
//
//    AVCaptureConnection *videoConnection = nil;
//    // The only accepted file error is if file does not exist yet
//    if (!file_error || file_error.code == NSFileNoSuchFileError) {
//        file_error = nil;
//        for (AVCaptureConnection *connection in m_pStillImageOutput.connections) {
//            for (AVCaptureInputPort *port in [connection inputPorts]) {
//                if ([[port mediaType] isEqual:AVMediaTypeVideo] ) {
//                    videoConnection = connection;
//                    break;
//                }
//            }
//            if (videoConnection)
//                break;
//        }
//    }
    __block PyObject * pObj = NULL;
//    if (videoConnection) {
//
//        // FIXME: Make sure all the internals to the lambda are kept by value, or are weak references
//
//        __block dispatch_semaphore_t sem = NULL;
//        if (blocking)
//            sem = dispatch_semaphore_create(0);
//        [m_pStillImageOutput captureStillImageAsynchronouslyFromConnection:videoConnection
//                             completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
//
//                if (error) {
//                    // TODO: take care of error handling by reporting it if blocking
//                    NSLog(@"err %@", error);
//                } else {
//                    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
//                    CameraFrame frame(imageSampleBuffer);
//                    if (!no_file)
//                        frame.save(path, uti_str, quality);
//                    // Callback at the end
//                    pObj = image_output(frame);
//                    if (pObj == NULL && blocking)
//                        pObj = cy_get_frame(frame);
//                    if (sem) {
//                        dispatch_semaphore_signal(sem);
//                        //std::cout << "signal" << std::endl;
//                    }
//
//                    [pool drain];
//                }
//        }];
//        if (sem) {
//            //std::cout << " wait for signal" << std::endl;
//            // This is blocking call so wait at most handful of seconds for the signal
//            float wait = blocking;
//            int err;
//            while ((err = dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW))) {
//                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, YES);
//                wait -= 0.05;
//                if (wait <= 0)
//                    break;
//            }
//
//            //std::cout << " done waiting for " << wait << "err " << err << std::endl;
//            // dispatch_semaphore_wait(sem, timeout);
//            dispatch_release(sem);
//            sem = NULL;
//        }
//    }
//
//
//    [pool drain];
//
//    if (file_error)
//        throw std::invalid_argument( "invalid or inaccessable file path" );
//    if (!videoConnection)
//        throw std::runtime_error( "connection error" );
//
    if (pObj == NULL) {
        Py_INCREF(Py_None);
        pObj = Py_None;
    }
    return pObj;
}

// Return a list with items that can be passed to a set_format method
void CppAVFCam::get_device_formats()
{
    if (!m_pCapture || !m_pCapture->m_pSession)
        throw std::invalid_argument( "session not initialized" );
    if (!m_pCapture->m_pDevice)
        throw std::invalid_argument( "webcam video source not initialized" );

//        devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
//        for (AVCaptureDevice *device in devices) {
//            const char *name = [[device localizedName] UTF8String];
//            int index  = [devices indexOfObject:device];
//        }

//    for(AVCaptureDeviceFormat *vFormat in [m_pDevice formats] )
//    {
//        CMFormatDescriptionRef description= vFormat.formatDescription;
//        float max_fps = ((AVFrameRateRange*)[vFormat.videoSupportedFrameRateRanges objectAtIndex:0]).maxFrameRate;
//        int format = CMFormatDescriptionGetMediaSubType(description);
//    }

    // TODO: return a list with items that can be passed to a set_format method
}

// Get width and height of the frames in the sink
std::vector<unsigned int> CppAVFCam::get_dimension()
{
    std::vector<unsigned int> dim;
    if (!m_pCapture || !m_pCapture->m_pVideoInput)
        return dim;
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    NSArray* ports = m_pCapture->m_pVideoInput.ports;
    CMFormatDescriptionRef format = [[ports objectAtIndex:0] formatDescription];
    CGSize s1 = CMVideoFormatDescriptionGetPresentationDimensions(format, YES, YES);

    dim.push_back((unsigned int)s1.height);
    dim.push_back((unsigned int)s1.width);

    [pool drain];

    return dim;
}

