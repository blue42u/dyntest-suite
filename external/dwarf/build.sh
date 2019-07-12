#!/bin/bash

source ../init.sh https://www.prevanders.net/libdwarf-20190529.tar.gz \
  b414c3bff758df211d972de72df1da9f496224da3f649b950b7d7239ec69172c \
  2601496ae97698a7cc9162059341ca7f

# The usual configure-make-install
./configure --prefix="`realpath zzz`" --quiet > /dev/null
make --quiet > /dev/null
make --quiet install > /dev/null

# Copy the outputs back home
tupify cp -r zzz/* "$INSTALL"
