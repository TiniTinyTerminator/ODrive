#!/usr/bin/env python3
"""Setup file for ODrive packaging and release."""

import sys

try:
    from setuptools import find_packages, setup
except ImportError:
    print("Error: 'setuptools' is required to run setup.py directly.", file=sys.stderr)
    print("Install it via: sudo pacman -S python-setuptools  (or pip install setuptools)", file=sys.stderr)
    sys.exit(1)

setup(
    name="odrive",
    version="1.0.0",
    description="Unified Cloud Drive Manager for Omarchy Linux",
    long_description=open("README.md", "r", encoding="utf-8").read(),
    long_description_content_type="text/markdown",
    author="TiniTinyTerminator",
    license="MIT",
    url="https://github.com/TiniTinyTerminator/ODrive",
    package_dir={"": "lib"},
    packages=find_packages(where="lib"),
    entry_points={
        "console_scripts": [
            "odrive=odrive.cli:main",
        ],
    },
    python_requires=">=3.9",
    classifiers=[
        "License :: OSI Approved :: MIT License",
        "Operating System :: POSIX :: Linux",
        "Programming Language :: Python :: 3",
        "Topic :: System :: Filesystems",
    ],
)

