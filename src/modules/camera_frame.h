// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy
//--------------------------------------------------------------
//
// Keep the resemblence of a pure C++ header as much as possible
//


#import <Foundation/Foundation.h>

// Wrap the image into something we can send easily and efficiently to Python
class CameraFrame
{
public:
    size_t m_bytesPerRow;
    size_t m_width;
    size_t m_height;
    std::unique_ptr<char[]> m_img;

private:
    CFMutableDictionaryRef m_exif;
public:
    CameraFrame(CMSampleBufferRef sampleBuffer);
    virtual ~CameraFrame();
    void save(std::string path, std::string uti_type, float quality=1.0);
};
