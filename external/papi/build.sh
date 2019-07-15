#!/bin/bash

source ../init.sh http://icl.utk.edu/projects/papi/downloads/papi-5.7.0.tar.gz \
  d1a3bb848e292c805bc9f29e09c27870e2ff4cda6c2fba3b7da8b4bba6547589 \
  0e7468d61c279614ff6f39488ac3600d

cd src
./configure --prefix="`realpath zzz`" >/dev/null
make --quiet >/dev/null
make --quiet install >/dev/null

tupify cp -r zzz/* "$INSTALL"
