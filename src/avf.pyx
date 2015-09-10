"""
Created on Sept 7, 2015
@author: dashesy
Purpose: Access AVFoundation as a Cython class
"""

from avf cimport CppAVFCam, string
cimport cpython.ref as cpy_ref

cdef class AVFCam(object):
    """
    AVFoundation simple camera interface

    User should derive this class to get the callbacks
    """

    # reference to the actual object
    cdef CppAVFCam _ref

    def __cinit__(self, sinks=None):
        """
        :param sinks: list of video sinks
            'file': File output (default)
            'callback': Decompressed video frame callback
        """
        cdef bint sink_file = False
        cdef bint sink_callback = False
        if sinks is None:
            sink_file = True
        else:
            assert isinstance(sinks, list)
            if 'file' in sinks:
                sink_file = True
            if 'callback' in sinks:
                sink_callback = True

        # the one and only reference
        self._ref = CppAVFCam(sink_file, sink_callback, <cpy_ref.PyObject*>self)

    def record(self, video_name, duration=20):
        """record a video
        :param video_name: file path to create (will overwrite if it exists)
        :param duration: duration of video to record (in seconds)
        """
        cdef string video_name_str = video_name.encode('UTF-8')
        self._ref.record(video_name_str, duration)

cdef public api void cy_call_func(object self, bint *overridden, char* method, object args, object kwargs):
    # see if it is derived
    func = getattr(self, method, None)
    if not callable(func):
        overridden[0] = 0
    else:
        overridden[0] = 1
        func(*args, **kwargs)
