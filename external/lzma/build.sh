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

if which shasum > /dev/null; then
echo "Checking SHAsum..."
shasum -qca 256 - <<'EOF'
9717ae363760dedf573dad241420c5fea86256b65bc21d2cf71b2b12f0544f4b  lzma.tar.xz
EOF
else
echo "Checking MD5sum..."
md5sum -c --quiet - <<'EOF'
003e4d0b1b1899fc6e3000b24feddf7c  lzma.tar.xz
EOF
fi

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
export LD_PRELOAD="$REAL_LD_PRELOAD"
cd "$INSTALL"
cp -r "$TMP"/install/* .
