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

cdef extern from "modules/avf.h":

    # noinspection PyPep8Naming
    cdef cppclass CppAVFCam:
        CppAVFCam()
        CppAVFCam(bint sink_file, bint sink_callback, cpy_ref.PyObject *obj) except +
        void record(string path, unsigned int duration, bint blocking) except +
        void stop_recording() except +
        vector[unsigned int] get_dimension()

cdef extern from "<utility>" namespace "std":
    cdef CppAVFCam std_move_avf "std::move" (CppAVFCam) nogil
