#!/bin/sh

# Little script to build and install LZMA (to a local directory).
# Installs into the directory lzma/

INSTALL="`pwd`/xed"
set -e

# Make a temporary directory where we'll stick stuff
TMP="`mktemp -d`"
trap "rm -rf $TMP" EXIT
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
rmdir ../install/bin

echo "Copying results..."
cd "$INSTALL"
cp -r "$TMP"/install/* .
