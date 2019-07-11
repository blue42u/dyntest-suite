#!/bin/sh

# Little script to build and install LZMA (to a local directory).
# Installs into the directory lzma/

INSTALL="`pwd`/lzma"
set -e

# Make a temporary directory where we'll stick stuff
TMP="`mktemp -d`"
trap "rm -rf $TMP" EXIT
cd "$TMP"

echo "Downloading LZMA..."
URL=https://tukaani.org/xz/xz-5.2.4.tar.xz
if which curl > /dev/null; then
  curl -Lso lzma.tar.xz $URL
elif which wget > /dev/null; then
  wget -O lzma.tar.xz $URL
else
  echo "No download program available, abort!" >&2
  exit 1
fi

echo "Checking SHAsum..."
shasum -qca 256 - <<'EOF'
9717ae363760dedf573dad241420c5fea86256b65bc21d2cf71b2b12f0544f4b  lzma.tar.xz
EOF

echo "Uncompressing tarball..."
tar xJf lzma.tar.xz --strip-components=1

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
