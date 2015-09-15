// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy
//--------------------------------------------------------------
//
// Keep the resemblence of a pure C++ header as much as possible
//

#include <vector>

@class AVCaptureDevice;
@class AVCaptureSession;
@class AVCaptureDelegate;
@class AVCaptureDeviceInput;
@class AVCaptureStillImageOutput;
@class AVCaptureMovieFileOutput;

class CameraFrame;
struct _object;
typedef _object PyObject;

class CppAVFCam
{
private:
    PyObject * m_pObj;  // Python binding
    AVCaptureSession * m_pSession;
    AVCaptureDevice * m_pDevice;              // Camera device
    AVCaptureDelegate * m_pCapture;           // Capture delegate
    AVCaptureDeviceInput * m_pVideoInput;
    AVCaptureMovieFileOutput * m_pVideoFileOutput;
    AVCaptureStillImageOutput * m_pStillImageOutput;

private:
    unsigned int m_videoFrameCount, m_imageFrameCount;

public:
    virtual void file_output_done(bool error);
    virtual void video_output(CameraFrame &frame);
    virtual void image_output(CameraFrame &frame);

public:

    CppAVFCam();
    CppAVFCam(bool sink_file, bool sink_callback, bool sink_image,
              PyObject * pObj=NULL);
    CppAVFCam(CppAVFCam &&other);
    virtual ~CppAVFCam();

    CppAVFCam & operator= (CppAVFCam &&other);

    void set_settings(unsigned int width, unsigned int height, unsigned int fps);
    void record(std::string path, float duration, bool blocking=false);
    void stop_recording();
    void snap_picture(std::string path, bool no_file, bool blocking=false,
                      std::string uti_str="", float quality=1.0);
    void get_device_formats();
    std::vector<unsigned int> get_dimension();
};
