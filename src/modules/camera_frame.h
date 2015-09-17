// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy
//--------------------------------------------------------------
//
// Keep the resemblence of a pure C++ header as much as possible
//

#include <vector>

#import <Foundation/Foundation.h>
#import <CoreMedia/CoreMedia.h>

// Wrap the image into something we can send easily and efficiently to Python
class CameraFrame
{
public:
    size_t m_bytesPerRow;
    size_t m_width;
    size_t m_height;
    unsigned int m_frameCount;
    std::unique_ptr<char[]> m_img;

private:
    CFMutableDictionaryRef m_exif;

public:
    CameraFrame();
    CameraFrame(CMSampleBufferRef sampleBuffer);
    CameraFrame(CameraFrame &&other) = default;
    CameraFrame & operator= (CameraFrame &&other) = default;
    virtual ~CameraFrame();

    CameraFrame copy();
    char * data();
    
    void save(std::string path, std::string uti_type, float quality=1.0);
    std::vector<unsigned int> get_dimension();
};
