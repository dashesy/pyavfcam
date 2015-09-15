"""
Created on Sept 7, 2015
@author: dashesy
Purpose: Access camera through AVFoundation as a Cython extension class
"""

from avf cimport CppAVFCam, string, PyEval_InitThreads, std_move_avf, std_make_shared_avf, shared_ptr
cimport cpython.ref as cpy_ref

# the callback may come from a non-python thread
PyEval_InitThreads()


cdef public api void cy_call_func(object self, bint *overridden, char* method, object args, object kwargs) with gil:
    """single point of callback entry from C++ land
    :param overridden: return back to cpp if the method is implemented in Python
    :param method: bound method name to run
    :param args: positional arguments to pass to the bound method
    :param kwargs: keyword arguments to pass to the bound method
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
    These are current callback methods that can be implemented in a subclass:
        'def file_output_done(self, error)'
        'def video_output(self, frame_buf, frame_count)'
        'def image_output(self, frame_buf, exif=None)'
    """

    # reference to the actual object
    cdef shared_ptr[CppAVFCam] _ref

    def __init__(self, sinks=None, *args, **kwargs):
        """
        :param sinks: list of video sinks
            'file': File output (default)
            'callback': Decompressed video frame callback
        """
        cdef bint sink_file = False
        cdef bint sink_callback = False
        cdef bint sink_image = False
        if sinks is None:
            sink_file = True
        else:
            if isinstance(sinks, basestring):
                sinks = [sinks]
            if 'file' in sinks:
                sink_file = True
            if 'callback' in sinks:
                sink_callback = True
            if 'image' in sinks:
                sink_image = True

        # the one and only reference
        self._ref = std_make_shared_avf(std_move_avf(CppAVFCam(sink_file, sink_callback, sink_image,
                                                               <cpy_ref.PyObject*>self)))

    def __dealloc__(self):
        """called when last reference is claimed
        """
        self._ref.reset()
        
    def record(self, name, duration=20, blocking=True):
        """record a video and call file_output_done
        :param name: file path to create (will overwrite if it exists)
        :param duration: duration of video to record (in seconds), can be inf/nan to record with no duration
        :param blocking: if should block until recording is done (or error happens)
        """

        cdef string name_str = name.encode('UTF-8')
        self._ref.get().record(name_str, duration, blocking)

    def snap_picture(self, name='', blocking=True, uti_type='', quality=1.0):
        """record an image and call image_output
        :param name: file path to create (will overwrite if it exists), if no name given only receives callback
        :param blocking: if should block until image is taken (or error happens)
        :param uti_type: OSX uti/mime type string (will try to find the right one if not given)
        :param quality: if compressed format this is the compression quality
        """

        cdef bint no_file = len(name) == 0
        cdef string name_str = name.encode('UTF-8')
        cdef string uti_str = uti_type.encode('UTF-8')
        self._ref.get().snap_picture(name_str, no_file, blocking, uti_str, quality)

    def stop_recording(self):
        """stop current recording
        """
        self._ref.get().stop_recording()

    @property
    def shape(self):
        """video shape
        """
        dim = self._ref.get().get_dimension()
        return tuple(dim)
