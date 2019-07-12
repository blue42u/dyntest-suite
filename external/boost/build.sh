#!/bin/bash

source ../init.sh \
  https://dl.bintray.com/boostorg/release/1.70.0/source/boost_1_70_0.tar.bz2 \
  430ae8354789de4fd19ee52f3b1f739e1fba576f0aded0897c3c2bc00fb38778 \
  242ecc63507711d6706b9b0c0d0c7d4f

# Bootstrap (booststrap?) Boost
./bootstrap.sh --prefix="`realpath zzz`" \
  --with-libraries=atomic,chrono,date_time,filesystem,system,thread,timer \
  > /dev/null

# Build and install
./b2 --ignore-site-config --link=static --runtime-link=static --threading=multi\
  > /dev/null
./b2 install > /dev/null

# Copy the outputs back home
tupify cp -r zzz/* "$INSTALL"
