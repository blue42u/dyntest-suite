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

echo "Downloading libMonitor..."
git clone https://github.com/hpctoolkit/libmonitor.git monitor
cd monitor

echo "Configuring..."
./configure --prefix="$TMP"/install \
  > /dev/null

echo "Building..."
make > /dev/null

echo "Installing..."
make install > /dev/null

echo "Copying results..."
export LD_PRELOAD="$REAL_LD_PRELOAD"
cd "$INSTALL"
cp -r "$TMP"/install/* .
