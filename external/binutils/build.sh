#!/bin/sh

INSTALL="`pwd`"
set -e

# Make a temporary directory where we'll stick stuff
TMP="`mktemp -d`"
trap "rm -rf $TMP" EXIT
cd "$TMP"

echo "Downloading Binutils..."
URL=https://ftpmirror.gnu.org/binutils/binutils-2.32.tar.xz
if which curl > /dev/null; then
  curl -Lso binutils.tar.xz $URL
elif which wget > /dev/null; then
  wget -O binutils.tar.xz $URL
else
  echo "No download program available, abort!" >&2
  exit 1
fi

if which shasum > /dev/null; then
echo "Checking SHAsum..."
shasum -qca 256 - <<'EOF'
0ab6c55dd86a92ed561972ba15b9b70a8b9f75557f896446c82e8b36e473ee04  binutils.tar.xz
EOF
else
echo "Checking MD5sum..."
md5sum -c --quiet - <<'EOF'
0d174cdaf85721c5723bf52355be41e6  binutils.tar.xz
EOF
fi

echo "Uncompressing tarball..."
tar xJf binutils.tar.xz --strip-components=1

echo "Configuring..."
./configure --prefix="$TMP"/installZZ --enable-lto --enable-install-libiberty \
  > /dev/null

echo "Building..."
make > /dev/null

echo "Installing..."
make install > /dev/null

echo "Copying results..."
cd "$INSTALL"
cp -r "$TMP"/installZZ/* .
