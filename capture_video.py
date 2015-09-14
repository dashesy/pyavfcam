#!/usr/bin/python
"""
Created on Sept 7, 2015
@author: dashesy
Purpose: Access AVFoundation as a Cython class

format:
    python capture_video.py <video_name> [-duration <seconds>]
options:
    <video_name>: name of the video to record
    -duration <seconds>: how many seconds to record
"""

import sys
import pyavfcam

duration = 10
video_name = None

parg = None
for arg in sys.argv:
    if parg == '-duration':
        duration = int(arg)
    if parg:
        parg = None
        continue
    if arg == '-duration':
        parg = arg
    elif video_name is None:
        video_name = arg
    else:
        raise ValueError('Unknow argument %s' % arg)

if video_name is None:
    raise ValueError('capture_video.py <video_name> [-duration <seconds>]')

# Open the default video source
video = pyavfcam.AVFCam()
if duration:
    video.record(video_name, duration=duration)

    print "Saved " + video_name + " (Size: " + str(video.shape[0]) + " x " + str(video.shape[1]) + ")"
