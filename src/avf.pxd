"""
Created on Sept 8, 2015
@author: dashesy
Purpose: CPP wrapper
"""

from libcpp.string cimport string
from libcpp.vector cimport vector
cimport cpython.ref as cpy_ref

cdef extern from "Python.h":
	# noinspection PyPep8Naming
    void PyEval_InitThreads()

cdef extern from "modules/camera_frame.h":

    # noinspection PyPep8Naming
    cdef cppclass CameraFrame:
        unsigned int m_width, m_height
        CameraFrame()
        void save(string path, string uti_type, float quality) except +
        vector[unsigned int] get_dimension()

cdef extern from "modules/avf.h":

    # noinspection PyPep8Naming
    cdef cppclass CppAVFCam:
        CppAVFCam()
        CppAVFCam(bint sink_file, bint sink_callback, bint sink_image,
                  cpy_ref.PyObject *obj) except +
        void record(string path, float duration, bint blocking) except +
        void snap_picture(string path, bint no_file, bint blocking, string uti_str, float quality) except +
        void stop_recording() except +
        vector[unsigned int] get_dimension()

cdef extern from "<utility>" namespace "std":
    cppclass shared_ptr[T]:
        T* get()
        void reset()
        
    cdef CppAVFCam std_move_avf "std::move" (CppAVFCam) nogil
    cdef shared_ptr[CppAVFCam] std_make_shared_avf "std::make_shared" [CppAVFCam](CppAVFCam) nogil
    
