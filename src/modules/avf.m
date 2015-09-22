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
#include "camera_frame.h"
#include "utils.h"
#include "../avf_api.h"


// A basic shim that just passes things to C++ instance
@interface AVCaptureDelegate : NSObject <AVCaptureFileOutputRecordingDelegate,
                                         AVCaptureVideoDataOutputSampleBufferDelegate>
{
    CppAVFCam * instance; // What I am delegated for
    NSTimer *timer; // Keep-alive timer
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
  didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
  fromConnection:(AVCaptureConnection *)connection;

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
  didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
  fromConnections:(NSArray *)connections
  error:(NSError *)error;

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
  didStartRecordingToOutputFileAtURL:(NSURL *)outputFileURL
  fromConnections:(NSArray *)connections;
  
@end


@implementation AVCaptureDelegate

- (id)init
{
    return [self initWithInstance:NULL];
}

- (id)initWithInstance:(CppAVFCam *)pInstance
{
    self = [super init];
    if(self) {
        instance = pInstance;
        ACWeakProxy * proxy = [[ACWeakProxy alloc] initWithObject:self];
        timer = [NSTimer scheduledTimerWithTimeInterval:1
                         target:proxy
                         selector:@selector(keepAlive:)
                         userInfo:nil repeats:YES];
        [proxy release];
    }
    return self;
}

- (void)setInstance:(CppAVFCam *)pInstance
{
    instance = pInstance;
}

-(void)dealloc
{
    // BUG: It seems this is not called because AVFoundation retains a strong reference of this object somewhere !!
    //      the workaround is to use a ACWeakProxy
    // std::cout << "dealloc" << std::endl;
    [timer invalidate];
    [super dealloc];
}

-(void)keepAlive:(NSTimer *)timer
{
    // Can do some background here
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
  didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
  fromConnection:(AVCaptureConnection *)connection
{
    if (!instance)
        return;

    CameraFrame frame(sampleBuffer);
    instance->video_output(frame);

}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
  didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
  fromConnections:(NSArray *)connections
  error:(NSError *)error
{
    if (!instance)
        return;

    instance->file_output_done(error != NULL);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
  didStartRecordingToOutputFileAtURL:(NSURL *)outputFileURL
  fromConnections:(NSArray *)connections
{
    // We can notify
}

@end

// Default constructor
CppAVFCam::CppAVFCam()
    : m_pObj(NULL),
      m_pSession(NULL), m_pDevice(NULL), m_pCapture(NULL),
      m_pVideoInput(NULL), m_pVideoFileOutput(NULL), m_pStillImageOutput(NULL),
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

    //AVCaptureVideoDataOutput *video_buffer_output = NULL

    // TODO: option to select among cameras
    m_pDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (m_pDevice && m_pCapture) {
        m_pSession = [[AVCaptureSession alloc] init];
        if (m_pSession) {
            NSError *error = nil;
            m_pVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:m_pDevice error:&error];
            if (m_pVideoInput)
                [m_pSession addInput:m_pVideoInput];
            if (sink_file)
                m_pVideoFileOutput = [[AVCaptureMovieFileOutput alloc] init];
            if (m_pVideoFileOutput)
                [m_pSession addOutput:m_pVideoFileOutput];
            if (sink_image)
                m_pStillImageOutput = [[AVCaptureStillImageOutput alloc] init];

            if (m_pStillImageOutput) {
                [m_pSession addOutput:m_pStillImageOutput];
                // If outputSettings is not set no iamge is returned
                NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
                NSNumber* value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
                NSDictionary* outputSettings = [NSDictionary dictionaryWithObject:value forKey:key];

                [m_pStillImageOutput setOutputSettings:outputSettings];
            }
    //        if (sink_callback) {
    //            video_buffer_output = [[AVCaptureVideoDataOutput alloc] init];
    //            dispatch_queue_t videoQueue = dispatch_queue_create("videoQueue", NULL);
    //            [video_buffer_output setSampleBufferDelegate:self queue:videoQueue];
    //
    //            video_buffer_output.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    //            video_buffer_output.alwaysDiscardsLateCameraFrames=YES;
    //        }
    //        if (video_buffer_output)
    //            [m_pSession addOutput:video_buffer_output];

            // Start the AV session
            [m_pSession startRunning];

            if (m_pVideoFileOutput) {
                // Set movie to 30fps by default
                AVCaptureConnection *videoConnection = [m_pVideoFileOutput connectionWithMediaType:AVMediaTypeVideo];
                if (videoConnection) {
                    if (videoConnection.isVideoMinFrameDurationSupported)
                        videoConnection.videoMinFrameDuration = CMTimeMake(1, 30);
                    if (videoConnection.isVideoMaxFrameDurationSupported)
                        videoConnection.videoMaxFrameDuration = CMTimeMake(1, 30);
                }
            }                
        }
    }
    [pool drain];

    // Now raise if error detected above for RAII
    if (!m_pDevice)
        throw std::runtime_error("cannot access the webcam video source");
    if (!m_pCapture || !m_pSession)
        throw std::runtime_error("cannot create multimedia session (perhaps memory error)");
    if (sink_file && !m_pVideoFileOutput)
        throw std::runtime_error("cannot create file video sink");
    if (sink_image && !m_pStillImageOutput)
        throw std::runtime_error("cannot create image sink");
}

// Destructor
CppAVFCam::~CppAVFCam()
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    std::cout << "dest cur " << CFRunLoopGetCurrent()<< " dest main " << CFRunLoopGetMain() << std::endl;
    
    // BUG: AVFoundation causes segfaults if release some of these, 
    //      this is only evident if object lives in a non-main thread.
    //      potential for memory leak is annoying but I cannot find a safe way to deallocate.  

    if (m_pSession) {
        std::cout << "   m_pSession " << CFGetRetainCount((__bridge CFTypeRef)m_pSession) << std::endl;
//         [m_pSession stopRunning];
        // Remove the connections so the library might clean up
        for (AVCaptureInput *input1 in m_pSession.inputs)
            [m_pSession removeInput:input1];
        for (AVCaptureOutput *output1 in m_pSession.outputs)
            [m_pSession removeOutput:output1];
        std::cout << "bob" << std::endl;
        [m_pSession stopRunning];
        std::cout << "   m_pSession " << CFGetRetainCount((__bridge CFTypeRef)m_pSession) << std::endl;
        [m_pSession release];
        m_pSession = NULL;
    }

    if (m_pVideoInput) {
        std::cout << "   m_pVideoInput " << CFGetRetainCount((__bridge CFTypeRef)m_pVideoInput) << std::endl;
        //[m_pVideoInput release];
        m_pVideoInput = NULL;
    }

    if (m_pVideoFileOutput) {
        std::cout << "   m_pVideoFileOutput " << CFGetRetainCount((__bridge CFTypeRef)m_pVideoFileOutput) << std::endl;
        //[m_pVideoFileOutput release];
        m_pVideoFileOutput = NULL;
     }

    if (m_pStillImageOutput) {
        std::cout << "   m_pStillImageOutput " << CFGetRetainCount((__bridge CFTypeRef)m_pStillImageOutput) << std::endl;
        //[m_pStillImageOutput release];
        m_pStillImageOutput = NULL;
     }

    if (m_pDevice) {
        std::cout << "   m_pDevice " << CFGetRetainCount((__bridge CFTypeRef)m_pDevice) << std::endl;
        //[m_pDevice release];
        m_pDevice = NULL;
    }

    if (m_pCapture) {
        std::cout << "   m_pCapture " << CFGetRetainCount((__bridge CFTypeRef)m_pCapture) << std::endl;
        [m_pCapture release];
        m_pCapture = NULL;
    }

    std::cout << " b 1" << std::endl;
    [pool drain];
    std::cout << " b 2" << std::endl;

    // decrease refcount of the Python binding
    Py_XDECREF(m_pObj);
    m_pObj = NULL;
}

// Move assignment operator
CppAVFCam & CppAVFCam::operator= (CppAVFCam && other)
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    m_pObj = other.m_pObj;
    m_pSession = other.m_pSession;
    m_pDevice = other.m_pDevice;
    m_pVideoInput = other.m_pVideoInput;
    m_pVideoFileOutput = other.m_pVideoFileOutput;
    m_pStillImageOutput = other.m_pStillImageOutput;
    m_pCapture = other.m_pCapture;
    if (m_pCapture)
        [m_pCapture setInstance:this];

    // Ownership of other is moved to this
    other.m_pObj = NULL;
    other.m_pSession = NULL;
    other.m_pDevice = NULL;
    other.m_pVideoInput = NULL;
    other.m_pVideoFileOutput = NULL;
    other.m_pStillImageOutput = NULL;
    other.m_pCapture = NULL;
    
    [pool drain];

    return *this;
}

// File output callback to Python
void CppAVFCam::file_output_done(bool error)
{
    // BUG: If duration is given to AVFoundation it seems as opposed to Apple docs, this is not called !!

    std::cout << "file output\n" << std::endl;
    std::cout << "f cur " << CFRunLoopGetCurrent()<< " f main " << CFRunLoopGetMain() << std::endl;

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
    if (!m_pDevice)
        return;

    if (fps == 0)
        fps = 1;

    if ( [m_pDevice lockForConfiguration:NULL] == YES ) {
        // should set these properties after output is added to session or it may be lost
        [m_pDevice setActiveVideoMinFrameDuration:CMTimeMake(1, fps)];
        [m_pDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, fps)];
        [m_pDevice unlockForConfiguration];
    }

    // TODO: set width and height settings
}

// Record to file video sink at given file path
void CppAVFCam::record(std::string path, float duration, unsigned int blocking)
{
    if (!m_pCapture || !m_pSession)
        throw std::invalid_argument( "session not initialized" );
    if (!m_pVideoFileOutput)
        throw std::invalid_argument( "file video sink not initialized" );

    if (duration < 1)
        duration = 1;

    bool no_duration = (duration == std::numeric_limits<float>::infinity() || std::isnan(duration));
    if (no_duration && blocking) {
        std::cout << "blocking non-stop recording turned into non-blocking!" << std::endl;
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

        // Set the duration of the video, pretend fps is 600, be a nice sheep
        if (!no_duration)
            [m_pVideoFileOutput setMaxRecordedDuration:CMTimeMakeWithSeconds((unsigned int)duration, 600)];

//        if (m_semFile) {
//            dispatch_release(m_semFile);
//            m_semFile = NULL;
//        }

//        dispatch_queue_t queue = dispatch_queue_create("pyavfcam.fileQueue", NULL);
//        dispatch_sync(queue, ^(void){

        std::cout << "q cur " << CFRunLoopGetCurrent()<< " q main " << CFRunLoopGetMain() << std::endl;
        // Request for signaling when output done
//        if (blocking)
//            m_semFile = dispatch_semaphore_create(0);

        // BUG: ref count of m_pCapture is increased but unfortunately it seems it is not a weak reference, so later it is not reclaimed !!
        //  The workarond is to use a proxy to force it being used as a weak reference: http://stackoverflow.com/a/3618797/311567
        ACWeakProxy * proxy = [[ACWeakProxy alloc] initWithObject:m_pCapture];
        // Start recordign the video and let me know when it is done
        [m_pVideoFileOutput startRecordingToOutputFileURL:url recordingDelegate:proxy];
        [proxy release];

        // std::cout << " 2  m_pCapture " << CFGetRetainCount((__bridge CFTypeRef)m_pCapture) << std::endl;

        // Block on file output, time out in more than the expected time!
//        if (m_semFile) {
////                dispatch_time_t timout = dispatch_time(DISPATCH_TIME_NOW, (uint64_t) (blocking + (unsigned int)duration) * NSEC_PER_SEC );
////                dispatch_semaphore_wait(m_semFile, timout);
//            float wait = blocking + duration;
//            std::cout << " wait " << wait << std::endl;
//            int err;
//            while ((err = dispatch_semaphore_wait(m_semFile, DISPATCH_TIME_NOW))) {
//                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, YES);
//                wait -= 0.05;
//                if (wait <= 0)
//                    break;
//            }
//            std::cout << "err " << err << " wait " << wait << std::endl;
//
//            dispatch_release(m_semFile);
//            m_semFile = NULL;
//            [m_pVideoFileOutput stopRecording];
//        }

//        });
    }

    [pool drain];

    if (file_error)
        throw std::invalid_argument( "invalid or inaccessable file path" );
}

// Stop recording to file if recording in progress
void CppAVFCam::stop_recording()
{
    if (!m_pCapture || !m_pSession)
        throw std::invalid_argument( "session not initialized" );
    if (!m_pVideoFileOutput)
        throw std::invalid_argument( "file video sink not initialized" );

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    [m_pVideoFileOutput stopRecording];

    // Note that some samples will be flushed in the backgrouns and the callback will know when the file is ready

    [pool drain];
}

// Record to still image sink at given file path
PyObject * CppAVFCam::snap_picture(std::string path, unsigned int blocking,
                                   std::string uti_str, float quality)
{
    if (!m_pCapture || !m_pSession)
        throw std::invalid_argument( "session not initialized" );
    if (!m_pStillImageOutput)
        throw std::invalid_argument( "image video sink not initialized" );
        
    m_bBlockingImage = blocking > 0;

    bool no_file = path.length() == 0;
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    NSError *file_error = nil;
    if (! no_file) {
        // Get the string and expand it to a file URL
        NSString* path_str = [[NSString stringWithUTF8String:path.c_str()] stringByExpandingTildeInPath];
        NSURL *url = [NSURL fileURLWithPath:path_str];

        // AVFoundation will not overwrite but we do, remove the file if it exists
        [[NSFileManager defaultManager] removeItemAtURL:url error:&file_error];
    }

    AVCaptureConnection *videoConnection = nil;
    // The only accepted file error is if file does not exist yet
    if (!file_error || file_error.code == NSFileNoSuchFileError) {
        file_error = nil;
        for (AVCaptureConnection *connection in m_pStillImageOutput.connections) {
            for (AVCaptureInputPort *port in [connection inputPorts]) {
                if ([[port mediaType] isEqual:AVMediaTypeVideo] ) {
                    videoConnection = connection;
                    break;
                }
            }
            if (videoConnection)
                break;
        }
    }
    __block PyObject * pObj = NULL;
    if (videoConnection) {

        // FIXME: Make sure all the internals to the lambda are kept by value, or are weak references

        __block dispatch_semaphore_t sem = NULL;
        if (blocking)
            sem = dispatch_semaphore_create(0);
        [m_pStillImageOutput captureStillImageAsynchronouslyFromConnection:videoConnection
                             completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
                
                if (error) {
                    // TODO: take care of error handling by reporting it if blocking
                    NSLog(@"err %@", error);
                } else {
                    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                    CameraFrame frame(imageSampleBuffer);
                    if (!no_file)
                        frame.save(path, uti_str, quality);
                    // Callback at the end
                    pObj = image_output(frame);
                    if (pObj == NULL && blocking)
                        pObj = cy_get_frame(frame);
                    if (sem) {
                        dispatch_semaphore_signal(sem);
                        //std::cout << "signal" << std::endl;
                    }

                    [pool drain];
                }
        }];
        if (sem) {
            //std::cout << " wait for signal" << std::endl;
            // This is blocking call so wait at most handful of seconds for the signal
            float wait = blocking;
            int err;
            while ((err = dispatch_semaphore_wait(sem, DISPATCH_TIME_NOW))) {
                CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, YES);
                wait -= 0.05;
                if (wait <= 0)
                    break;
            }

            //std::cout << " done waiting for " << wait << "err " << err << std::endl;
            // dispatch_semaphore_wait(sem, timeout);
            dispatch_release(sem);
            sem = NULL;
        }
    }


    [pool drain];

    if (file_error)
        throw std::invalid_argument( "invalid or inaccessable file path" );
    if (!videoConnection)
        throw std::runtime_error( "connection error" );

    if (pObj == NULL) {
        Py_INCREF(Py_None);
        pObj = Py_None;
    }
    return pObj;
}

// Return a list with items that can be passed to a set_format method
void CppAVFCam::get_device_formats()
{
    if (!m_pDevice)
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
    if (!m_pVideoInput)
        return dim;
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    NSArray* ports = m_pVideoInput.ports;
    CMFormatDescriptionRef format = [[ports objectAtIndex:0] formatDescription];
    CGSize s1 = CMVideoFormatDescriptionGetPresentationDimensions(format, YES, YES);

    dim.push_back((unsigned int)s1.height);
    dim.push_back((unsigned int)s1.width);

    [pool drain];

    return dim;
}

