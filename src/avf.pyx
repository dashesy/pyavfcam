"""
Created on Sept 7, 2015
@author: dashesy
Purpose: Access AVFoundation as a Cython extension class
"""

from avf cimport CppAVFCam, string, PyEval_InitThreads, std_move_avf
cimport cpython.ref as cpy_ref

# the callback may come from a non-python thread
PyEval_InitThreads()


cdef public api void cy_call_func(object self, bint *overridden, char* method, object args, object kwargs) with gil:
    """single point of callback entry from C++ land
    :param overridden: return back to cpp if the method is implemented in Python
    :param method: bound method name to run
    """
    # see if it is implemented in a derived class
    func = getattr(self, method, None)
    if not callable(func):
        overridden[0] = 0
    else:
        overridden[0] = 1
        func(*args, **kwargs)


cdef class AVFCam(object):
    """
    AVFoundation simple camera interface (base class)

    User should derive this class to get the callbacks, we do not provide any default implementations
    """

    # reference to the actual object
    cdef CppAVFCam _ref

    def __init__(self, sinks=None, *args, **kwargs):
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
            if isinstance(sinks, basestring):
                sinks = [sinks]
            if 'file' in sinks:
                sink_file = True
            if 'callback' in sinks:
                sink_callback = True

        # the one and only reference
        self._ref = std_move_avf(CppAVFCam(sink_file, sink_callback, <cpy_ref.PyObject*>self))

    def __dealloc__(self):
        del self._ref
        
    def record(self, video_name, duration=20, blocking=True):
        """record a video
        :param video_name: file path to create (will overwrite if it exists)
        :param duration: duration of video to record (in seconds)
        :param blocking: if should block until recording is done (or error happens)
        """

        cdef string video_name_str = video_name.encode('UTF-8')
        self._ref.record(video_name_str, duration, blocking)

    def stop_recording(self):
        """stop current recording
        """
        self._ref.stop_recording()

    @property
    def shape(self):
        """video shape
        """
        dim = self._ref.get_dimension()
        return tuple(dim)
