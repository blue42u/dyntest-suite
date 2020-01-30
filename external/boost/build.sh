#!/bin/bash

source ../init.sh \
  https://dl.bintray.com/boostorg/release/1.71.0/source/boost_1_71_0.tar.bz2 \
  d73a8da01e8bf8c7eda40b4c84915071a8c8a0df4a6734537ddde4a8580524ee \
  4cdf9b5c2dc01fb2b7b733d5af30e558

# Bootstrap (booststrap?) Boost
./bootstrap.sh --prefix="`realpath zzz`" \
  --with-libraries=atomic,chrono,date_time,filesystem,system,thread,timer,graph \
  > /dev/null

# Build and install
./b2 --ignore-site-config --link=static --runtime-link=shared,static --threading=multi > /dev/null
./b2 install > /dev/null

# Copy the outputs back home
tupify cp -r zzz/* "$INSTALL"
