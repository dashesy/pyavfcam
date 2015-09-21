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
    -qthread: run recording in a QThread
"""

import sys
import pyavfcam

threaded = False
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
    elif arg == '-qthread':
        threaded = True
    elif video_name is None:
        video_name = arg
    else:
        raise ValueError('Unknow argument %s' % arg)

if video_name is None:
    raise ValueError('capture_video.py <video_name> [-duration <seconds>]')


BaseClass = object
if threaded:
    try:
        # noinspection PyPackageRequirements
        from PySide import QtCore
    except ImportError:
        # noinspection PyPackageRequirements
        from PyQt4 import QtCore
        # noinspection PyUnresolvedReferences
        QtCore.Signal = QtCore.pyqtSignal
        # noinspection PyUnresolvedReferences
        QtCore.Slot = QtCore.pyqtSlot
    BaseClass = QtCore.QObject


class Worker(BaseClass):

    # Task done with list of bpm results
    taskDone = QtCore.Signal(list)

    def __init__(self):
        """run an app job in a thread
        """
        super(Worker, self).__init__()

        self.t = None
        if threaded:
            self.t = QtCore.QThread(objectName='record_thread')
            self.moveToThread(self.t)
            self.t.start()
            # noinspection PyUnresolvedReferences
            self.t.started.connect(self.task)

    def task(self):
        if self.t:
            thread_name = QtCore.QThread.currentThread().objectName()
            print '[%s] recording' % thread_name

        # Open the default video source and record
        cam = pyavfcam.AVFCam()
        if not duration:
            return
        cam.record(video_name, duration=duration)
        print "Saved " + video_name + " (Size: " + str(cam.shape[0]) + " x " + str(cam.shape[1]) + ")"


w = Worker()
if not threaded:
    w.task()
