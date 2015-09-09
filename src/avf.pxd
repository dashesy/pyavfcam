"""
Created on Sept 8, 2015
@author: dashesy
Purpose: CPP wrapper
"""

from libcpp.string cimport string

cdef extern from "modules/avf.h":
    
    cdef cppclass CppAVFCam:
        CppAVFCam()
        CppAVFCam(bool sink_file, bool sink_callback) except +
        void record(string path)
