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

echo "Downloading PAPI..."
URL=http://icl.utk.edu/projects/papi/downloads/papi-5.7.0.tar.gz
if which curl > /dev/null; then
  curl -Lso papi.tar.gz $URL
elif which wget > /dev/null; then
  wget -O papi.tar.gz $URL
else
  echo "No download program available, abort!" >&2
  exit 1
fi

if which shasum > /dev/null; then
echo "Checking SHAsum..."
shasum -qca 256 - <<'EOF'
d1a3bb848e292c805bc9f29e09c27870e2ff4cda6c2fba3b7da8b4bba6547589  papi.tar.gz
EOF
else
echo "Checking MD5sum..."
md5sum -c --quiet - <<'EOF'
0e7468d61c279614ff6f39488ac3600d  papi.tar.gz
EOF
fi

echo "Uncompressing tarball..."
tar xzf papi.tar.gz --strip-components=1
cd src

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
