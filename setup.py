#!/usr/bin/python

from __future__ import print_function
import os
import sys
from os.path import join, dirname
from setuptools import Extension, find_packages, setup
from distutils.command import build_ext as _build_ext
try:
    # we use Cython if possible then resort to pre-build intermediate files
    # noinspection PyPackageRequirements
    from Cython.Distutils import build_ext
except ImportError:
    build_ext = None

# change directory to this module path
try:
    this_file = __file__
except NameError:
    this_file = sys.argv[0]
this_file = os.path.abspath(this_file)
if os.path.dirname(this_file):
    os.chdir(os.path.dirname(this_file))
script_dir = os.getcwd()


def readme(fname):
    """Read text out of a file in the same directory as setup.py.
    """
    return open(join(dirname(__file__), fname), 'rt').read()

if build_ext:
    avf_module = Extension(
        'pyavfcam',
        ['src/avf.pyx',
         'src/modules/avf.m',
         'src/modules/camera_frame.m',
         'src/modules/utils.m',
         'src/modules/avf_impl.m',
         ],
        extra_link_args=['-framework', 'AVFoundation',
                         '-framework', 'Foundation',
                         ],
        extra_compile_args=['-ObjC++', '-std=c++11', '-stdlib=libc++','-mmacosx-version-min=10.7'],
        language="c++",
    )
else:
    avf_module = Extension(
        'pyavfcam',
        ['src/avf.cpp',
         'src/modules/avf.m',
         'src/modules/camera_frame.m',
         'src/modules/utils.m',
         'src/modules/avf_impl.m',
         ],
        extra_link_args=['-framework', 'AVFoundation',
                         '-framework', 'Foundation',
                         ],
        extra_compile_args=['-ObjC++', '-std=c++11', '-stdlib=libc++'],
        language="c++",
    )

    # noinspection PyPep8Naming
    class build_ext(_build_ext.build_ext):

        def run(self):
            print("""
            --> Cython is not installed. Can not compile .pyx files. <--
            If the pre-built sources did not work you'll have to do it yourself
            and run this command again,
            if you want to recompile your .pyx files.

            `pip install cython` should suffice.

            ------------------------------------------------------------
            """)
            assert os.path.exists(
                os.path.join(script_dir, 'src', 'avf.cpp')), \
                'Source file not found!'
            return _build_ext.build_ext.run(self)

setup(
    name="pyavfcam",
    version="0.0.1",
    author="dashesy",
    author_email="dashesy@gmail.com",
    url='https://github.com/dashesy/pyavfcam',
    description="Simple camera video capture in OSX using AVFoundation",
    long_description=readme('README.md'),
    packages=find_packages(),
    license="BSD",
    cmdclass={
        'build_ext': build_ext,
    },
    classifiers=[
        'Intended Audience :: Developers',
        'Operating System :: MacOS :: MacOS X',
        "License :: OSI Approved :: BSD License",
        "Programming Language :: Objective C++",
        "Programming Language :: Cython",
        "Programming Language :: Python",
        'Topic :: Software Development',
    ],
    ext_modules=[
        avf_module
    ]
)
