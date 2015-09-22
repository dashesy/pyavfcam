// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy

#include <iostream>

#include "avf_impl.h"
#include "avf.h"
#include "camera_frame.h"
#include "util.h"

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

@implementation AVCaptureDelegate

// Keep the thread runloop alive
-(void)keepAlive:(NSTimer *)timer
{
    // Can do some background here
}

// Constructor delegate
-(void)createSession
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    m_pDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (m_pDevice) {
        m_pSession = [[AVCaptureSession alloc] init];
        if (m_pSession) {
            NSError *error = nil;
            m_pVideoInput = [AVCaptureDeviceInput deviceInputWithDevice:m_pDevice error:&error];
            if (m_pVideoInput)
                [m_pSession addInput:m_pVideoInput];
            if (m_instance->isSinkFileSet())
                m_pVideoFileOutput = [[AVCaptureMovieFileOutput alloc] init];
            if (m_pVideoFileOutput)
                [m_pSession addOutput:m_pVideoFileOutput];
            if (m_instance->isSinkImageSet())
                m_pStillImageOutput = [[AVCaptureStillImageOutput alloc] init];

            if (m_pStillImageOutput) {
                [m_pSession addOutput:m_pStillImageOutput];
                // If outputSettings is not set no iamge is returned
                NSString* key = (NSString*)kCVPixelBufferPixelFormatTypeKey;
                NSNumber* value = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
                NSDictionary* outputSettings = [NSDictionary dictionaryWithObject:value forKey:key];

                [m_pStillImageOutput setOutputSettings:outputSettings];
            }
    //        if (m_instance->m_sink_callback) {
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
}

- (void)startRecordingToOutputFileURL:(NSURL *)url
  withDuration:(float)duration
  withBlocking:(unsigned int)blocking
{
    // Set the duration of the video, pretend fps is 600, be a nice sheep
    if (duration > 0)
        [m_pVideoFileOutput setMaxRecordedDuration:CMTimeMakeWithSeconds((unsigned int)duration, 600)];

    if (m_semFile) {
        dispatch_release(m_semFile);
        m_semFile = nil;
    }

//        dispatch_queue_t queue = dispatch_queue_create("pyavfcam.fileQueue", NULL);
//        dispatch_sync(queue, ^(void){

    std::cout << " cur " << CFRunLoopGetCurrent()<< " main " << CFRunLoopGetMain() << std::endl;

    if (blocking)
        m_semFile = dispatch_semaphore_create(0);

    // BUG: ref count of self is increased but unfortunately it seems it is not a weak reference, so later it is not reclaimed !!
    //  The workarond is to use a proxy to force it being used as a weak reference: http://stackoverflow.com/a/3618797/311567
    ACWeakProxy * proxy = [[ACWeakProxy alloc] initWithObject:self];
    // Start recordign the video and let me know when it is done
    [m_pVideoFileOutput startRecordingToOutputFileURL:url recordingDelegate:(AVCaptureDelegate *)proxy];
    [proxy release];

    // std::cout << " 2  m_pCapture " << CFGetRetainCount((__bridge CFTypeRef)m_pCapture) << std::endl;

    // Block on file output, time out in more than the expected time!
    if (m_semFile) {
        dispatch_time_t timout = dispatch_time(DISPATCH_TIME_NOW,
                                               (uint64_t) (blocking + (unsigned int)duration) * NSEC_PER_SEC );
        dispatch_semaphore_wait(m_semFile, timout);
//        float wait = blocking + duration;
//        std::cout << " wait " << wait << std::endl;
//        int err;
//        while ((err = dispatch_semaphore_wait(m_m_semFile, DISPATCH_TIME_NOW))) {
//            CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.05, YES);
//            wait -= 0.05;
//            if (wait <= 0)
//                break;
//        }
//        std::cout << "err " << err << " wait " << wait << std::endl;
//
        dispatch_release(m_semFile);
        m_semFile = NULL;

        // Manually stop recording
        [m_pVideoFileOutput stopRecording];
    }

//        });
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
  didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
  fromConnection:(AVCaptureConnection *)connection
{
    if (!m_instance)
        return;

    CameraFrame frame(sampleBuffer);
    m_instance->video_output(frame);

}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
  didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
  fromConnections:(NSArray *)connections
  error:(NSError *)error
{
    if (m_semFile)
        dispatch_semaphore_signal(m_semFile);

    if (!m_instance)
        return;

    m_instance->file_output_done(error != NULL);
}

- (void)captureOutput:(AVCaptureFileOutput *)captureOutput
  didStartRecordingToOutputFileAtURL:(NSURL *)outputFileURL
  fromConnections:(NSArray *)connections
{
    // We can notify
}

- (id)init
{
    return [self initWithInstance:NULL];
}

// Thread life
- (void)runThread
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    ACWeakProxy * proxy = [[ACWeakProxy alloc] initWithObject:self];
    m_timer = [NSTimer scheduledTimerWithTimeInterval:1
                                               target:proxy
                                             selector:@selector(keepAlive:)
                                             userInfo:nil repeats:YES];
    [proxy release];

    // Actually go on and create the session but in this thread
    [self createSession];

    std::cout << "before thread cur " << CFRunLoopGetCurrent() << std::endl;
    // Start the run loop
    CFRunLoopRun();
    std::cout << "after thread cur " << CFRunLoopGetCurrent() << std::endl;

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

    [pool drain];
}

- (id)initWithInstance:(CppAVFCam *)pInstance
{
    self = [super init];
    if(self) {
        m_semFile = nil;
        m_instance = pInstance;

        m_timer = nil;
        m_pSession = nil;
        m_pDevice = nil;
        m_pVideoInput = nil;
        m_pVideoFileOutput = nil;
        m_pStillImageOutput = nil;

        m_thread =  [[NSThread alloc] initWithTarget:self selector:@selector(runThread) object:nil];
        [m_thread start];
    }
    return self;
}

// Change the c++ instance I am delegated to
- (void)setInstance:(CppAVFCam *)pInstance
{
    m_instance = pInstance;
}

- (void)stopThread
{
    // this should darin the runloop
    [m_timer invalidate];
    // Make sure I stop
    CRunLoopStop(CFRunLoopGetCurrent());
}

// Destructor
-(void)dealloc
{
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];


    [self performSelector:@selector(stopThread)
                 onThread:m_thread
               withObject:self
            waitUntilDone:NO];

    [m_thread release];
    m_thread = nil;

    [pool release];

    [super dealloc];
}

@end
