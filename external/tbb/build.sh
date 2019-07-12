#!/bin/sh

INSTALL="`pwd`"
set -e

# Make a temporary directory where we'll stick stuff
TMP="`mktemp -d`"
trap "rm -rf $TMP" EXIT
cd "$TMP"

echo "Downloading TBB..."
URL=https://github.com/intel/tbb/archive/2019_U8.tar.gz
if which curl > /dev/null; then
  curl -Lso tbb.tar.gz $URL
elif which wget > /dev/null; then
  wget -O tbb.tar.gz $URL
else
  echo "No download program available, abort!" >&2
  exit 1
fi

if which shasum > /dev/null; then
echo "Checking SHAsum..."
shasum -qca 256 - <<'EOF'
7b1fd8caea14be72ae4175896510bf99c809cd7031306a1917565e6de7382fba  tbb.tar.gz
EOF
else
echo "Checking MD5sum..."
md5sum -c --quiet - <<'EOF'
7c371d0f62726154d2c568a85697a0ad  tbb.tar.gz
EOF
fi

echo "Uncompressing tarball..."
tar xzf tbb.tar.gz --strip-components=1

echo "Building components..."
make -C "$TMP" -rf "$TMP"/build/Makefile.tbb tbb_root="$TMP" cfg=release \
  >/dev/null
make -C "$TMP" -rf "$TMP"/build/Makefile.tbbmalloc tbb_root="$TMP" cfg=release \
  malloc >/dev/null
make -C "$TMP" -rf "$TMP"/build/Makefile.tbbproxy tbb_root="$TMP" cfg=release \
  tbbproxy >/dev/null
make -C "$TMP" -rf "$TMP"/build/Makefile.tbb tbb_root="$TMP" cfg=preview \
  tbb_cpf=1 >/dev/null

echo "Copying built components..."
cp "$TMP"/libtbb.so.2 "$INSTALL"/lib
cp "$TMP"/libtbbmalloc.so.2 "$INSTALL"/lib
cp "$TMP"/libtbbmalloc_proxy.so.2 "$INSTALL"/lib
cp "$TMP"/libtbb_preview.so.2 "$INSTALL"/lib

echo "Copying headers..."
cp -r "$TMP"/include/tbb "$INSTALL"/include

echo "Adding library symlinks..."
ln -s libtbb.so.2 "$INSTALL"/lib/libtbb.so
ln -s libtbbmalloc.so.2 "$INSTALL"/lib/libtbbmalloc.so
ln -s libtbbmalloc_proxy.so.2 "$INSTALL"/lib/libtbbmalloc_proxy.so
ln -s libtbb_preview.so.2 "$INSTALL"/lib/libtbb_preview.so
