// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy
//--------------------------------------------------------------
//
// Keep the resemblence of a pure C++ header as much as possible
//

@class CMSampleBufferRef;

// Wrap the image into something we can send easily and efficiently to Python
class CameraFrame
{
public:
    CameraFrame(CMSampleBufferRef sampleBuffer);
    void save(std::string path, std::string uti_type, float quality=1.0);
};
