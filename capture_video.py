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
for arg_idx, arg in enumerate(sys.argv):
    if arg_idx == 0:
        continue
    if parg == '-duration':
        duration = float(arg)
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
cam = pyavfcam.AVFCam()
if duration:
    cam.record(video_name, duration=duration)

    print "Saved " + video_name + " (Size: " + str(cam.shape[0]) + " x " + str(cam.shape[1]) + ")"
