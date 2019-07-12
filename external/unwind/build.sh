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

echo "Downloading libUnwind..."
URL=http://download.savannah.nongnu.org/releases/libunwind/libunwind-1.3.1.tar.gz
if which curl > /dev/null; then
  curl -Lso unwind.tar.gz $URL
elif which wget > /dev/null; then
  wget -O unwind.tar.gz $URL
else
  echo "No download program available, abort!" >&2
  exit 1
fi

if which shasum > /dev/null; then
echo "Checking SHAsum..."
shasum -qca 256 - <<'EOF'
43997a3939b6ccdf2f669b50fdb8a4d3205374728c2923ddc2354c65260214f8  unwind.tar.gz
EOF
else
echo "Checking MD5sum..."
md5sum -c --quiet - <<'EOF'
a04f69d66d8e16f8bf3ab72a69112cd6  unwind.tar.gz
EOF
fi

echo "Uncompressing tarball..."
tar xzf unwind.tar.gz --strip-components=1

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
