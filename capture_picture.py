#!/usr/bin/python
"""
Created on Sept 13, 2015
@author: dashesy
Purpose: Access AVFoundation as a Cython class
"""

import pyavfcam

# Open the default video source
cam = pyavfcam.AVFCam(sinks='image')
cam.snap_picture('test.jpg')

print( "Saved test.jpg (Size: " + str(cam.shape[0]) + " x " + str(cam.shape[1]) + ")")
