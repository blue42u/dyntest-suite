#!/bin/sh

INSTALL="`pwd`"
set -e

# Hide from Tup for a bit, we know what we're doing
REAL_LD_PRELOAD="$LD_PRELOAD"
export LD_PRELOAD=

# Make a temporary directory where we'll stick stuff
TMP="`realpath zzztmp`"
trap "rm -rf $TMP" EXIT
rm -rf zzztmp
mkdir zzztmp
cd "$TMP"

echo "Downloading Xed..."
git clone -q https://github.com/intelxed/xed.git xed

echo "Downloading Mbuild..."
git clone -q https://github.com/intelxed/mbuild.git mbuild

mkdir build
cd build

echo "Building..."
../xed/mfile.py > /dev/null

echo "Installing..."
../xed/mfile.py install > /dev/null
mv kits/* ../install

echo "Cleaning up oddities and arranging for HPCToolkit..."
cd ../install
rmdir bin
mv include/xed/* include/
rmdir include/xed

echo "Copying results..."
export LD_PRELOAD="$REAL_LD_PRELOAD"
cd "$INSTALL"
cp -r "$TMP"/install/* .
