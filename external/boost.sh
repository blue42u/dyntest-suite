#!/bin/sh

# Little script to build and install boost (to a local directory).
# Installs into the directory boost/

INSTALL="`pwd`/boost"
set -e

# Make a temporary directory where we'll stick stuff
TMP="`mktemp -d`"
trap "rm -rf $TMP" EXIT
cd "$TMP"

echo "Downloading Boost..."
URL=https://dl.bintray.com/boostorg/release/1.70.0/source/boost_1_70_0.tar.bz2
if which curl > /dev/null; then
  curl -Lso boost.tar.bz2 $URL
elif which wget > /dev/null; then
  wget -O boost.tar.bz2 $URL
else
  echo "No download program available, abort!" >&2
  exit 1
fi

echo "Checking SHAsum..."
shasum -qca 256 - <<'EOF'
430ae8354789de4fd19ee52f3b1f739e1fba576f0aded0897c3c2bc00fb38778  boost.tar.bz2
EOF

echo "Uncompressing tarball..."
tar xjf boost.tar.bz2 --strip-components=1

echo "Running bootstrap script..."  # Or is it a booststrap script?
./bootstrap.sh --prefix="$TMP"/install \
  --with-libraries=atomic,chrono,date_time,filesystem,system,thread,timer \
  > /dev/null

echo "Building..."
./b2 --ignore-site-config --link=static --runtime-link=static --threading=multi\
  > /dev/null

echo "Installing..."
./b2 install > /dev/null

echo "Copying results..."
cd "$INSTALL"
cp -r "$TMP"/install/* .
