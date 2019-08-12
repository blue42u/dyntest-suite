#!/bin/bash

source ../init.sh

# Xed (and its build system) come from Git. Plop them down here.
git clone -q https://github.com/intelxed/xed.git xed
git clone -q https://github.com/intelxed/mbuild.git mbuild

# Make a build directory to stash everything for now
mkdir build
cd build

# Build and install, and move the output directory to somewhere constant
../xed/mfile.py --extra-flags='-fPIC' > /dev/null
../xed/mfile.py --extra-flags='-fPIC' install > /dev/null
mv kits/* ../install

# Cleanup some oddities and arrange to match what HPCToolkit expects
# NOTE: It feels really wrong to have to do this, someone should fix that.
cd ../install
rmdir bin doc extlib
mv include/xed/* include/
rmdir include/xed

# Copy the results home
tupify cp -r * "$INSTALL"
