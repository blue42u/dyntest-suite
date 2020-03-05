# To be sourced into other scripts, do not run directly!

mkdir -p install
INSTALL="`pwd`/install"
set -e

# Hide the temporaries in this script from Tup
REAL_LD_PRELOAD="$LD_PRELOAD"
export LD_PRELOAD=

# Use this function to reenable Tup for specific commands
tupify() {
  env LD_PRELOAD="$REAL_LD_PRELOAD" "$@"
}

# Setup a temporary directory to do things in
trap 'rm -rf "$TMP"' EXIT
TMP="`mktemp -d`"
cd "$TMP"

# Arguments 1, 2 and 3 (if present) are the url, sha256 and md5 of a tarball.
if [ "$1" ]; then

# Download the tarball
if which curl >/dev/null 2>/dev/null
then curl -kLso dl.tar.ball "$1" || echo "curl $1 failed!"
elif which wget >/dev/null 2>/dev/null
then wget --no-check-certificate -O dl.tar.ball "$1" || echo "wget $1 failed!"
else
  echo "Neither curl nor wget is available, cannot download!" >&2
  exit 1
fi

# Check the checksums
CHECKED=
if [ "$#" -gt 1 ]; then
  if which shasum >/dev/null 2>/dev/null; then
    if echo "$2  dl.tar.ball" | shasum -qca 256 -
    then CHECKED=sha
    else shasum -a 256 dl.tar.ball; CHECKED=fail
    fi
  fi
  if which md5sum >/dev/null 2>/dev/null; then
    if echo "$3  dl.tar.ball" | md5sum -c --quiet -
    then CHECKED=md5
    else md5sum dl.tar.ball; CHECKED=fail
    fi
  fi
fi
if [ -z "$CHECKED" ]
then echo "WARNING: No checksum program available, not checking download!"
fi
if [ "$CHECKED" = "fail" ]; then exit 1; fi

# Decompress to right here
tar xaf dl.tar.ball --strip-components=1

fi
