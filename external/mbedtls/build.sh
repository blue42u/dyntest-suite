#!/bin/bash

source ../init.sh https://tls.mbed.org/download/mbedtls-2.16.5-apache.tgz \
  65b4c6cec83e048fd1c675e9a29a394ea30ad0371d37b5742453f74084e7b04d \
  339f0505323b29851ef3128a53d2de20

mkdir zzzbuild zzz
cmake -DENABLE_TESTING=Off -DCMAKE_INSTALL_PREFIX="`realpath zzz`" \
  -S . -B zzzbuild -Wno-dev -DCMAKE_C_FLAGS=-fPIC > /dev/null
make -C zzzbuild --quiet > /dev/null
make -C zzzbuild --quiet install > /dev/null

tupify cp -r zzz/* "$INSTALL"
