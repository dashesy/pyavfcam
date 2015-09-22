// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy
//--------------------------------------------------------------
//
// Keep the resemblence of a pure C++ header as much as possible
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

class CppAVFCam;

// A basic shim that just passes things to C++ instance
@interface AVCaptureDelegate : NSObject <AVCaptureFileOutputRecordingDelegate,
                                         AVCaptureVideoDataOutputSampleBufferDelegate>
{
    CppAVFCam * instance; // What I am delegated for
    NSTimer *timer; // Keep-alive timer

@public
    AVCaptureSession * m_pSession;
    AVCaptureDevice * m_pDevice;              // Camera device
    AVCaptureDeviceInput * m_pVideoInput;
    AVCaptureMovieFileOutput * m_pVideoFileOutput;
    AVCaptureStillImageOutput * m_pStillImageOutput;
}

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
