#!/bin/sh

# Little script to build and install Xerces (to a local directory).
# Installs into the directory xerces/

INSTALL="`pwd`/xerces"
set -e

# Make a temporary directory where we'll stick stuff
TMP="`mktemp -d`"
trap "rm -rf $TMP" EXIT
cd "$TMP"

echo "Downloading Xerces..."
URL=http://mirror.cogentco.com/pub/apache//xerces/c/3/sources/xerces-c-3.2.2.tar.xz
if which curl > /dev/null; then
  curl -Lso xerces.tar.xz $URL
elif which wget > /dev/null; then
  wget -O xerces.tar.xz $URL
else
  echo "No download program available, abort!" >&2
  exit 1
fi

echo "Checking SHAsum..."
shasum -qca 256 - <<'EOF'
6daca3b23364d8d883dc77a73f681242f69389e3564543287ed3d073007e0a8e  xerces.tar.xz
EOF

echo "Uncompressing tarball..."
tar xJf xerces.tar.xz --strip-components=1

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
