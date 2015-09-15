"""
Created on Sept 7, 2015
@author: dashesy
Purpose: Access camera through AVFoundation as a Cython extension class

To keep dependencies to minimum, do not depend on numpy, instead return memoryviews
"""

from avf cimport CppAVFCam, CameraFrame
from avf cimport string, PyEval_InitThreads
from avf cimport std_move_avf, std_make_shared_avf, shared_ptr, std_move_frame, std_make_shared_frame
cimport cpython.ref as cpy_ref

# the callback may come from a non-python thread
PyEval_InitThreads()

cdef public api object cy_get_frame(CameraFrame & cframe) with gil:
    """Create a Frame from CameraFrame
    """
    frame = Frame()
    frame._ref = std_make_shared_frame(std_move_frame(frame))

    return frame

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

cdef class Frame(object):
    """CameraFrame wrapper with memoryview interface for the image
    """
    # reference to the actual object
    cdef shared_ptr[CameraFrame] _ref

    def __repr__(self):
        """represent what I am
        """
        return "Frame({frame_count}, shape={shape})".format(
            frame_count=self.frame_count,
            shape=self.shape
        )

    def __dealloc__(self):
        """called when last reference is claimed
        """
        self._ref.reset()

    def save(self, name, uti_type='', quality=1.0):
        """save an image
        :param name: file path to create (will overwrite if it exists)
        :param uti_type: OSX uti/mime type string (will try to find the right one if not given)
        :param quality: if compressed format this is the compression quality
        """

        cdef string name_str = name.encode('UTF-8')
        cdef string uti_str = uti_type.encode('UTF-8')
        ref = self._ref.get()
        if ref == NULL:
            raise RuntimeError("Invalid frame!")
        ref.save(name_str, uti_str, quality)

    @property
    def image(self):
        """memoryview to the image buffer
        """
        if len(self.shape) == 0:
            return None

    @property
    def shape(self):
        """image shape (height, width)
        """
        ref = self._ref.get()
        if ref == NULL:
            return ()
        dim = ref.get_dimension()
        return tuple(dim)

    @property
    def width(self):
        """image width
        """
        return self._ref.get().m_width

    @property
    def height(self):
        """image height
        """
        return self._ref.get().m_height

    @property
    def frame_count(self):
        """frame counter
        """
        ref = self._ref.get()
        if ref == NULL:
            return -1
        return ref.m_frameCount


cdef class AVFCam(object):
    """
    AVFoundation simple camera interface (base class)

    User should derive this class to get the callbacks, we do not provide any default implementations
    These are current callback methods that can be implemented in a subclass:
        'def file_output_done(self, error:bool)'
        'def video_output(self, frame:Frame)'
        'def image_output(self, frame:Frame)'
    """

    # reference to the actual object
    cdef shared_ptr[CppAVFCam] _ref

    def __cinit__(self, sinks=None, *args, **kwargs):
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

        self._sinks = sinks

    def __repr__(self):
        """represent what I am
        """
        return "AVFCam({sinks}, shape={shape})".format(
            sinks=self._sinks,
            shape=self.shape
        )

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
        ref = self._ref.get()
        if ref == NULL:
            raise RuntimeError("Camera reference not valid!")
        ref.record(name_str, duration, blocking)

    def snap_picture(self, name='', blocking=True, uti_type='', quality=1.0):
        """take and save an image and call image_output
        :param name: file path to create (will overwrite if it exists), if no name given only receives callback
        :param blocking: if should block until image is taken (or error happens)
        :param uti_type: OSX uti/mime type string (will try to find the right one if not given)
        :param quality: if compressed format this is the compression quality
        """

        cdef bint no_file = len(name) == 0
        cdef string name_str = name.encode('UTF-8')
        cdef string uti_str = uti_type.encode('UTF-8')
        ref = self._ref.get()
        if ref == NULL:
            raise RuntimeError("Camera reference not valid!")
        ref.snap_picture(name_str, no_file, blocking, uti_str, quality)

    def stop_recording(self):
        """stop current recording
        """
        ref = self._ref.get()
        if ref == NULL:
            raise RuntimeError("Camera reference not valid!")
        ref.stop_recording()

    @property
    def shape(self):
        """video shape (height, width)
        """
        ref = self._ref.get()
        if ref == NULL:
            return ()
        dim = ref.get_dimension()
        return tuple(dim)
