#!/usr/bin/python
"""
Created on Sept 7, 2015
@author: dashesy
Purpose: Access AVFoundation as a Cython class
"""

import sys
import pyavfcam

duration = 10

parg = None
for arg in sys.argv:
    if parg == '-duration':
        duration = int(arg)
    if parg:
        parg = None
        continue
    if arg == '-duration':
        parg = arg
    
# Open the default video source
video = pyavfcam.AVFCam()
if duration:
    video.record('test.mov', duration=duration)

    print "Saved test.avi (Size: " + str(video.shape[0]) + " x " + str(video.shape[1]) + ")"
