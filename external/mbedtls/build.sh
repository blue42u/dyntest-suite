#!/bin/bash

source ../init.sh https://tls.mbed.org/download/mbedtls-2.16.3-apache.tgz \
  ec1bee6d82090ed6ea2690784ea4b294ab576a65d428da9fe8750f932d2da661 \
  90ce7c7a001d2514410280706b3ab1a7

mkdir zzzbuild zzz
cmake -DENABLE_TESTING=Off -DCMAKE_INSTALL_PREFIX="`realpath zzz`" \
  -S . -B zzzbuild -Wno-dev > /dev/null
make -C zzzbuild --quiet > /dev/null
make -C zzzbuild --quiet install > /dev/null

tupify cp -r zzz/* "$INSTALL"
