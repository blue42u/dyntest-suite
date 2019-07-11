#!/bin/sh

# Little script to build and install LibDwarf (to a local directory).
# Installs into the directory dwarf/

INSTALL="`pwd`/dwarf"
set -e

# Make a temporary directory where we'll stick stuff
TMP="`mktemp -d`"
trap "rm -rf $TMP" EXIT
cd "$TMP"

echo "Downloading Dwarf..."
URL=https://www.prevanders.net/libdwarf-20190529.tar.gz
if which curl > /dev/null; then
  curl -Lso dwarf.tar.gz $URL
elif which wget > /dev/null; then
  wget -O dwarf.tar.gz $URL
else
  echo "No download program available, abort!" >&2
  exit 1
fi

echo "Checking SHAsum..."
shasum -qca 256 - <<'EOF'
b414c3bff758df211d972de72df1da9f496224da3f649b950b7d7239ec69172c  dwarf.tar.gz
EOF

echo "Uncompressing tarball..."
tar xzf dwarf.tar.gz --strip-components=1

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
