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
#include "../avf_api.h"

// A basic shim that just passes things to C++ instance
@interface AVCaptureDelegate : NSObject <AVCaptureFileOutputRecordingDelegate,
                                         AVCaptureVideoDataOutputSampleBufferDelegate>
{
    CppAVFCam * m_pInstance; // What I am delegated for
    dispatch_semaphore_t m_semFile;  // Semaphore for blocking file video sink
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
        m_pInstance = pInstance;
        m_semFile = NULL;
    }
    return self;
}

- (void)setInstance:(CppAVFCam *)pInstance
{
    m_pInstance = pInstance;
}

- (void)signalFileOutput
{
    // Remove any possible leftovers
    if (m_semFile)
        dispatch_release(m_semFile);

    m_semFile = dispatch_semaphore_create(0);
}

- (void)blockFileOutput:(uint64_t)nseconds
{
    if (!m_semFile)
        return;
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, nseconds);
    dispatch_semaphore_wait(m_semFile, timeout);
}

-(void)dealloc
{
    // BUG: It seems this is not called because AVFoundation retains a strong reference of this object somewhere !!
    // std::cout << "dealloc" << std::endl;
    if (m_semFile) {
        dispatch_release(m_semFile);
        m_semFile = NULL;
    }
    [super dealloc];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
  didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
  fromConnection:(AVCaptureConnection *)connection
{
    if (!m_pInstance)
        return;

    CameraFrame frame(sampleBuffer);
    m_pInstance->video_output(frame);

}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
  didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
  fromConnections:(NSArray *)connections
  error:(NSError *)error
{
    // BUG: It seems didFinishRecordingToOutputFileAtURL is not called if duration is given  !!
    if (!m_pInstance)
        return;

    m_pInstance->file_output_done(error != NULL);
    if (m_semFile) {
        dispatch_semaphore_signal(m_semFile);
    }
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
  didStartRecordingToOutputFileAtURL:(NSURL *)outputFileURL
  fromConnections:(NSArray *)connections
{
    // We can notify
}

@end

@interface ACWeakProxy : NSProxy {
    id _object;
}

@property(assign) id object;

- (id)initWithObject:(id)object;

@end

@implementation ACWeakProxy

@synthesize object = _object;

- (id)initWithObject:(id)object {
    // no init method in superclass
    _object = object;
    return self;
}

- (BOOL)isKindOfClass:(Class)aClass {
    return [super isKindOfClass:aClass] || [_object isKindOfClass:aClass];
}

- (void)forwardInvocation:(NSInvocation *)invocation {
    [invocation setTarget:_object];
    [invocation invoke];
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    return [_object methodSignatureForSelector:sel];
}

@end

// Default constructor
CppAVFCam::CppAVFCam()
    : m_pObj(NULL),
      m_pSession(NULL), m_pDevice(NULL), m_pCapture(NULL),
      m_pVideoInput(NULL), m_pVideoFileOutput(NULL), m_pStillImageOutput(NULL),
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

    if (m_pSession) {
        [m_pSession stopRunning];
        [m_pSession release];
        m_pSession = NULL;
    }

    if (m_pVideoInput) {
        [m_pVideoInput release];
        m_pVideoInput = NULL;
    }

    if (m_pVideoFileOutput) {
        [m_pVideoFileOutput release];
        m_pVideoFileOutput = NULL;
     }

    if (m_pStillImageOutput) {
        [m_pStillImageOutput release];
        m_pStillImageOutput = NULL;
     }

    if (m_pDevice) {
        [m_pDevice release];
        m_pDevice = NULL;
    }

    if (m_pCapture) {
        // std::cout << "   m_pCapture " << CFGetRetainCount((__bridge CFTypeRef)m_pCapture) << std::endl;
        [m_pCapture release];
        m_pCapture = NULL;
    }

    [pool drain];

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

    if (!m_pObj || !m_haveMovieCallback)
        return;

    int overridden = 0;
    PyObject * kwargs = Py_BuildValue("{}");
    PyObject * args = Py_BuildValue("(i)", error);

    // Call a virtual overload, if it exists
    cy_call_func(m_pObj, &overridden, (char*)__func__, args, kwargs);
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
bool CppAVFCam::image_output(CameraFrame &frame)
{
    frame.m_frameCount = m_imageFrameCount++;
    if (!m_pObj || !m_haveImageCallback)
        return false;

    int overridden = 0;
    PyObject * kwargs = Py_BuildValue("{}");
    PyObject * pObj = cy_get_frame(frame);
    PyObject * args = Py_BuildValue("(O)", pObj);

    // Call a virtual overload, if it exists
    cy_call_func(m_pObj, &overridden, (char*)__func__, args, kwargs);
    if (!overridden)
        m_haveImageCallback = false;

    return true
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

        // Request for signaling when output done
        if (blocking)
            [m_pCapture signalFileOutput];

        // BUG: ref count of m_pCapture is increased but unfortunately it seems it is not a weak reference, so later it is not reclaimed !!
        //  The workarond is to use a proxy to force it being used as a weak reference: http://stackoverflow.com/a/3618797/311567
        ACWeakProxy * proxy = [[ACWeakProxy alloc] initWithObject:m_pCapture];
        // Start recordign the video and let me know when it is done
        [m_pVideoFileOutput startRecordingToOutputFileURL:url recordingDelegate:proxy];
        [proxy release];

        // std::cout << " 2  m_pCapture " << CFGetRetainCount((__bridge CFTypeRef)m_pCapture) << std::endl;

        // Block on file output, time out in more than the expected time!
        if (blocking) {
            uint64_t timeout = blocking + (unsigned int)duration;
            [m_pCapture blockFileOutput:(uint64_t)(timeout * NSEC_PER_SEC)];
            [m_pVideoFileOutput stopRecording];
        }
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
void CppAVFCam::snap_picture(std::string path, bool no_file, unsigned int blocking,
                             std::string uti_str, float quality)
{
    if (!m_pCapture || !m_pSession)
        throw std::invalid_argument( "session not initialized" );
    if (!m_pStillImageOutput)
        throw std::invalid_argument( "image video sink not initialized" );

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
    if (videoConnection) {

        // FIXME: Make sure all the internals to the lambda are kept by value, or are weak references

        dispatch_semaphore_t sem = NULL;
        if (blocking)
            sem = dispatch_semaphore_create(0);
        [m_pStillImageOutput captureStillImageAsynchronouslyFromConnection:videoConnection
                             completionHandler: ^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
                
                // TODO: take care of error handling
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                CameraFrame frame(imageSampleBuffer);
                if (!no_file)
                    frame.save(path, uti_str, quality);
                // Callback at the end
                image_output(frame);
                if (sem)
                    dispatch_semaphore_signal(sem);

                [pool drain];
        }];
        if (sem) {
            // This is blocking call so wait at most handful of seconds for the signal
            dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (uint64_t)(blocking * NSEC_PER_SEC));
            dispatch_semaphore_wait(sem, timeout);
            dispatch_release(sem);
        }
    }


    [pool drain];

    if (file_error)
        throw std::invalid_argument( "invalid or inaccessable file path" );
    if (!videoConnection)
        throw std::runtime_error( "connection error" );
}

// Return a list with items that can be passed to a set_format method
void CppAVFCam::get_device_formats()
{
    if (!m_pDevice)
        throw std::invalid_argument( "webcam video source not initialized" );

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

