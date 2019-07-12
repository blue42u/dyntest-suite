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

if test -d "$TMP"/installZZ/lib64; then
  mv "$TMP"/installZZ/lib64/* "$TMP"/installZZ/lib
  rmdir "$TMP"/installZZ/lib64
fi

rm "$TMP"/installZZ/share/info/dir

echo "Copying results..."
export LD_PRELOAD="$REAL_LD_PRELOAD"
cd "$INSTALL"
cp -r "$TMP"/installZZ/* .
