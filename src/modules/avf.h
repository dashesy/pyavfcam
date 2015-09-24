// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy
//--------------------------------------------------------------
//
// Keep the resemblence of a pure C++ header as much as possible
//

#include <vector>
#include <string>

@class AVCaptureDelegate;

class CameraFrame;
struct _object;
typedef _object PyObject;

class CppAVFCam
{
private:
    PyObject * m_pObj;               // Python binding
    bool m_sink_file, m_sink_callback, m_sink_image; // video sinks
    AVCaptureDelegate * m_pCapture;  // Capture delegate (pImpl for ObjC bits)

private:
    PyObject * m_pLastImage;
    bool m_bBlockingImage;

private:
    unsigned int m_videoFrameCount, m_imageFrameCount;
    bool m_haveImageCallback, m_haveVideoCallback, m_haveMovieCallback;

public:
    virtual void file_output_done(bool error);
    virtual void video_output(CameraFrame &frame);
    virtual void image_output(CameraFrame &frame);

public:
    // simple accessors
    bool isSinkFileSet() {return m_sink_file;}
    bool isSinkCallbackSet() {return m_sink_callback;}
    bool isSinkImageSet() {return m_sink_image;}

public:

    CppAVFCam();
    CppAVFCam(bool sink_file, bool sink_callback, bool sink_image,
              PyObject * pObj=NULL);
    CppAVFCam(CppAVFCam &&other);
    virtual ~CppAVFCam();

    CppAVFCam & operator= (CppAVFCam &&other);

    void set_settings(unsigned int width, unsigned int height, unsigned int fps);
    void record(std::string path, float duration, unsigned int blocking=4);
    void stop_recording();
    PyObject * snap_picture(std::string path, unsigned int blocking=10,
                            std::string uti_str="", float quality=1.0);
    void get_device_formats();
    std::vector<unsigned int> get_dimension();
};
