#!/bin/bash

source ../init.sh ftp://xmlsoft.org/libxml2/libxml2-2.9.9.tar.gz \
  94fb70890143e3c6549f265cee93ec064c80a84c42ad0f23e85ee1fd6540a871 \
  c04a5a0a042eaa157e8e8c9eabe76bd6

# The usual configure-make-install
./configure --prefix="`realpath zzz`" --quiet \
  --without-python > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

# Copy the results back home
tupify cp -r zzz/* "$INSTALL"
