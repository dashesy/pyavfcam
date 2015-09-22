// pyavfcam
// Simple video capture in OSX using AVFoundation
//
// 2015 dashesy
//--------------------------------------------------------------
//
// Keep the resemblence of a pure C++ header as much as possible
//

#import <Foundation/Foundation.h>

bool str_ends_with(std::string const &full_string, std::string const &ending);
std::string file_extension(std::string file);
std::string file_basename(std::string file);
std::string str_tolower(std::string const & data);


@interface ACWeakProxy : NSProxy {
    id _object;
}

@property(assign) id object;

- (id)initWithObject:(id)object;

@end
