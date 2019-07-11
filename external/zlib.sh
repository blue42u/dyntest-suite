#!/bin/sh

# Little script to build and install Binutils (to a local directory).
# Installs into the directory binutils/

INSTALL="`pwd`/zlib"
set -e

# Make a temporary directory where we'll stick stuff
TMP="`mktemp -d`"
trap "rm -rf $TMP" EXIT
cd "$TMP"

echo "Downloading Zlib..."
URL=https://www.zlib.net/zlib-1.2.11.tar.xz
if which curl > /dev/null; then
  curl -Lso zlib.tar.xz $URL
elif which wget > /dev/null; then
  wget -O zlib.tar.xz $URL
else
  echo "No download program available, abort!" >&2
  exit 1
fi

echo "Checking SHAsum..."
shasum -qca 256 - <<'EOF'
4ff941449631ace0d4d203e3483be9dbc9da454084111f97ea0a2114e19bf066  zlib.tar.xz
EOF

echo "Uncompressing tarball..."
tar xJf zlib.tar.xz --strip-components=1

echo "Configuring..."
./configure --prefix="$TMP"/install \
  > /dev/null

echo "Building..."
make > /dev/null

echo "Installing..."
make install > /dev/null

echo "Copying results..."
cd "$INSTALL"
cp -r "$TMP"/install/* .
