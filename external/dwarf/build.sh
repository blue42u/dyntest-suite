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

if which shasum > /dev/null; then
echo "Checking SHAsum..."
shasum -qca 256 - <<'EOF'
b414c3bff758df211d972de72df1da9f496224da3f649b950b7d7239ec69172c  dwarf.tar.gz
EOF
else
echo "Checking MD5sum..."
md5sum -c --quiet - <<'EOF'
2601496ae97698a7cc9162059341ca7f  dwarf.tar.gz
EOF
fi

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
export LD_PRELOAD="$REAL_LD_PRELOAD"
cd "$INSTALL"
cp -r "$TMP"/install/* .
