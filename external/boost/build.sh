#!/bin/bash

source ../init.sh \
  https://dl.bintray.com/boostorg/release/1.72.0/source/boost_1_72_0.tar.bz2 \
  59c9b274bc451cf91a9ba1dd2c7fdcaf5d60b1b3aa83f2c9fa143417cc660722 \
  cb40943d2a2cb8ce08d42bc48b0f84f0

# Bootstrap (booststrap?) Boost
./bootstrap.sh --prefix="`realpath zzz`" \
  --with-libraries=atomic,chrono,date_time,filesystem,system,thread,timer,graph,program_options \
  > /dev/null

# Build and install
./b2 visibility=global link=shared runtime-link=shared threading=multi \
  variant=release install > /dev/null

# Fix internal boost links via RUNPATHing everything
for f in zzz/lib/*.so; do
  "$INSTALL"/../../patchelf/install/bin/patchelf --set-rpath '$ORIGIN' "$f"
done

# Copy the outputs back home
tupify cp -r zzz/* "$INSTALL"
