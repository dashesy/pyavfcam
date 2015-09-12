// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

#include <stdexcept>
#include <iostream>
#include "avf.h"
#include "../avf_api.h"


// Wrap the image into something we can send easily and efficiently to Python
class VideoFrame
{
public:
    VideoFrame(CMSampleBufferRef sampleBuffer) {
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
    }
};

// A basic shim that just passes things to C++ instance
@interface AVCaptureDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate,
                                         AVCaptureFileOutputRecordingDelegate>
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

@end


@implementation AVCaptureDelegate

- (id)init
{
    return [self initWithInstance:NULL];
}

- (id)initWithInstance:(CppAVFCam *)pInstance
{
    std::cout << "   initWithInstance CppAVFCam at " << pInstance << std::endl;
    self = [super init];
    if(self) {
        NSLog(@"done");
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

- (void)blockFileOutput:(uint64_t)seconds
{
    if (!m_semFile)
        return;
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, seconds);
    dispatch_semaphore_wait(m_semFile, timeout);
}

-(void)dealloc
{
    std::cout << "   cap dealoc sem " << m_semFile  << " instance " << m_pInstance << std::endl;

    if (m_semFile) {
        NSLog(@"had sem");
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

    VideoFrame frame = VideoFrame(sampleBuffer);
    m_pInstance->video_output(frame);

}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
  didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
  fromConnections:(NSArray *)connections
  error:(NSError *)error
{
    if (!m_pInstance)
        return;

    m_pInstance->file_output_done(error != NULL);
    if (m_semFile) {
        dispatch_semaphore_signal(m_semFile);
    }
}

@end

// Default constructor
CppAVFCam::CppAVFCam()
    : m_pObj(NULL),
      m_pSession(NULL), m_pDevice(NULL), m_pCapture(NULL),
      m_pVideoInput(NULL), m_pVideoFileOutput(NULL)
{
    std::cout << "   C++: creating default CppAVFCam at " << this << std::endl;
}

// copy-constructor
CppAVFCam::CppAVFCam(const CppAVFCam& other)
    : m_pObj(NULL),
      m_pSession(NULL), m_pDevice(NULL), m_pCapture(NULL),
      m_pVideoInput(NULL), m_pVideoFileOutput(NULL)
{
    std::cout << "   C++: copy constructing CppAVFCam at " << this  << " from " << &other << std::endl;

    // Shallow copy the member pointers
    m_pObj = other.m_pObj;
    m_pSession = other.m_pSession;
    m_pDevice = other.m_pDevice;
    m_pVideoInput = other.m_pVideoInput;
    m_pVideoFileOutput = other.m_pVideoFileOutput;

    m_pCapture = other.m_pCapture;
    if (m_pCapture)
        [m_pCapture setInstance:this];
}

// designated constructor
CppAVFCam::CppAVFCam(bool sink_file, bool sink_callback, PyObject * pObj)
    : m_pObj(pObj),
      m_pSession(NULL), m_pDevice(NULL), m_pCapture(NULL),
      m_pVideoInput(NULL), m_pVideoFileOutput(NULL)
{
    std::cout << "   C++: creating CppAVFCam at " << this << std::endl;

    if (m_pObj) {
        if (import_pyavfcam()) {
            std::cerr << "[c+]  error in import_avf!\n";
            Py_XDECREF(m_pObj);
            m_pObj = NULL;
        } else {
            Py_XINCREF(m_pObj);
        }
    }

    NSLog(@"start      0");
    // Connect this class with NSObject
    m_pCapture = [[AVCaptureDelegate alloc] initWithInstance: this];
    NSLog(@"start      100");

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    //AVCaptureVideoDataOutput *video_buffer_output = NULL

    // TODO: option to select among cameras
    m_pDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (m_pDevice && m_pCapture) {
        m_pSession = [[AVCaptureSession alloc] init];
        if (m_pSession) {
            NSError *error = nil;
            m_pVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:m_pDevice error:&error];
            NSLog(@"start      1");
            if (m_pVideoInput)
                [m_pSession addInput:m_pVideoInput];
            NSLog(@"start      2");
            if (sink_file)
                m_pVideoFileOutput = [[AVCaptureMovieFileOutput alloc] init];
            NSLog(@"start      3");
            if (m_pVideoFileOutput)
                [m_pSession addOutput:m_pVideoFileOutput];
            NSLog(@"start      4");
    //        if (sink_callback) {
    //            video_buffer_output = [[AVCaptureVideoDataOutput alloc] init];
    //            dispatch_queue_t videoQueue = dispatch_queue_create("videoQueue", NULL);
    //            [video_buffer_output setSampleBufferDelegate:self queue:videoQueue];
    //
    //            video_buffer_output.videoSettings = @{(id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    //            video_buffer_output.alwaysDiscardsLateVideoFrames=YES;
    //        }
    //        if (video_buffer_output)
    //            [m_pSession addOutput:video_buffer_output];

            // Start the AV session
            [m_pSession startRunning];
            NSLog(@"start      5");
        }
    }
    [pool drain];
    NSLog(@"start      6");

    // Now raise if error detected above for RAII
    if (!m_pDevice)
        throw std::runtime_error("cannot access the webcam video source");
    if (!m_pCapture || !m_pSession)
        throw std::runtime_error("cannot create multimedia session (perhaps memory error)");
    if (sink_file && !m_pVideoFileOutput)
        throw std::runtime_error("cannot create file video sink");

    std::cout << "   C++: created CppAVFCam at " << this << std::endl;
}

// Destructor
CppAVFCam::~CppAVFCam()
{
    std::cout << "   C++: destroying CppAVFCam at " << this << std::endl;
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    if (m_pSession) {
        [m_pSession beginConfiguration];
        for(AVCaptureInput *input1 in m_pSession.inputs) {
            [m_pSession removeInput:input1];
        }

        for(AVCaptureOutput *output1 in m_pSession.outputs) {
            [m_pSession removeOutput:output1];
        }
        [m_pSession commitConfiguration];

        [m_pSession stopRunning];
        [m_pSession release];
        m_pSession = NULL;

        NSLog(@"stop      1");
    }


    if (m_pVideoInput) {
        [m_pVideoInput release];
        m_pVideoInput = NULL;
        NSLog(@"stop      2");
    }

    if (m_pVideoFileOutput) {
        [m_pVideoFileOutput release];
        m_pVideoFileOutput = NULL;
        NSLog(@"stop      3");
    }

    if (m_pCapture) {
        [m_pCapture release];
        m_pCapture = NULL;
        NSLog(@"stop      4");
    }

    // Deallocate device at the end
    if (m_pDevice) {
        [m_pDevice release];
        m_pDevice = NULL;
        NSLog(@"stop      5");
    }

    [pool drain];
    NSLog(@"stop      6");

    // decrease refcount of the Python binding
    Py_XDECREF(m_pObj);
    m_pObj = NULL;
    NSLog(@"stop      7");
}

// Move assignment operator
CppAVFCam & CppAVFCam::operator= (CppAVFCam && other)
{
    std::cout << "   move " << &other << " to " << this << std::endl;

    m_pObj = other.m_pObj;
    m_pSession = other.m_pSession;
    m_pDevice = other.m_pDevice;
    m_pVideoInput = other.m_pVideoInput;
    m_pVideoFileOutput = other.m_pVideoFileOutput;
    m_pCapture = other.m_pCapture;
    if (m_pCapture)
        [m_pCapture setInstance:this];

    // Ownership of other is moved to this
    other.m_pObj = NULL;
    other.m_pSession = NULL;
    other.m_pDevice = NULL;
    other.m_pVideoInput = NULL;
    other.m_pVideoFileOutput = NULL;
    other.m_pCapture = NULL;

    return *this;
}

// File output callback to Python
void CppAVFCam::file_output_done(bool error)
{
    if (!m_pObj)
        return;
    std::cout << "   file output " << this << std::endl;

    int overridden;
    PyObject * kwargs = Py_BuildValue("{}");
    PyObject * args = Py_BuildValue("(i)", error);

    // Call a virtual overload, if it exists
    cy_call_func(m_pObj, &overridden, (char*)__func__, args, kwargs);
    if (!overridden) {
        if (error)
            std::cout << "   error recording " << this << std::endl;
        else
            std::cout << "   done recording " << this << std::endl;

    }
}

// Video frame callback to Python
void CppAVFCam::video_output(VideoFrame &frame)
{
    if (!m_pObj)
        return;

    // TODO: implement callback using numpy array

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
void CppAVFCam::record(std::string path, unsigned int duration, bool blocking)
{
    if (!m_pCapture || !m_pSession)
        throw std::invalid_argument( "session not initialized" );
    if (!m_pVideoFileOutput)
        throw std::invalid_argument( "file video sink not initialized" );

    if (duration == 0)
        duration = 1;

    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

    // Get the string and expand it to a file URL
    NSString* path_str = [[NSString stringWithUTF8String:path.c_str()] stringByExpandingTildeInPath];
    NSURL *url = [NSURL fileURLWithPath:path_str];

    NSLog(@"file url      %@", url);

    NSError *file_error = nil;
    // AVFoundation will not overwrite but we do, remove the file if it exists
    [[NSFileManager defaultManager] removeItemAtURL:url error:&file_error];

    // The only accepted file error is if file does not exist yet
    if (!file_error || file_error.code == NSFileNoSuchFileError) {
        file_error = nil;

        // Set the duration of the video, pretend fps is 600, be a nice sheep
        [m_pVideoFileOutput setMaxRecordedDuration:CMTimeMakeWithSeconds(duration, 600)];

        // Request for signaling when output done
        if (blocking)
            [m_pCapture signalFileOutput];

        // Start recordign the video and let me know when it is done
        [m_pVideoFileOutput startRecordingToOutputFileURL:url recordingDelegate:m_pCapture];

        // Block on file output, time out in twice the expected time!
        if (blocking)
            [m_pCapture blockFileOutput:(uint64_t)(2 * duration * NSEC_PER_SEC)];
    }

    [pool drain];

    if (file_error)
        throw std::invalid_argument( "invalid or inaccessable path (error)" );
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

void CppAVFCam::get_device_formats()
{
    if (!m_pDevice)
        throw std::invalid_argument( "webcam video source not initialized" );

    for(AVCaptureDeviceFormat *vFormat in [m_pDevice formats] )
    {
        CMFormatDescriptionRef description= vFormat.formatDescription;
        float max_fps = ((AVFrameRateRange*)[vFormat.videoSupportedFrameRateRanges objectAtIndex:0]).maxFrameRate;
        int format = CMFormatDescriptionGetMediaSubType(description);
    }

    // TODO: return a list with items that can be passed to a set_format method
}

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

