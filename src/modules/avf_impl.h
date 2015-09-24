// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

class CppAVFCam;
class CameraFrame;

// A basic shim that just passes things to C++ instance
@interface AVCaptureDelegate : NSObject <AVCaptureFileOutputRecordingDelegate,
                                         AVCaptureVideoDataOutputSampleBufferDelegate>
{
    CppAVFCam * m_instance; // What I am delegated for
    dispatch_semaphore_t m_semFile; // used to signal when file recording is done

// Make thes public just for quick checks in avf.m
@public
    AVCaptureSession * m_pSession;
    AVCaptureDevice * m_pDevice;              // Camera device
    AVCaptureDeviceInput * m_pVideoInput;
    AVCaptureMovieFileOutput * m_pVideoFileOutput;
    AVCaptureStillImageOutput * m_pStillImageOutput;
}

- (void)captureFrameWithBlocking:(unsigned int)blocking
  error:(NSError * _Nullable *)error
  completionHandler:(void (^)(CameraFrame & frame))handle;

- (void)stopRecording;
- (void)startRecordingToOutputFileURL:(NSURL *)url
  withDuration:(float)duration
  withBlocking:(unsigned int)blocking;

- (void)setInstance:(CppAVFCam *)pInstance;
- (id)initWithInstance:(CppAVFCam *)pInstance;

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
