#!/bin/bash

HERE="`pwd`"
source ../init.sh

# Tup comes from a git repo, clone it here
git clone https://github.com/gittup/tup.git tup
cd tup

# Apply the hotfixes to fix the little issues that arise.
git apply "$HERE"/hotfixes.patch

# Just use the oneshot script to build it, not worth the trouble.
TUP_SERVER=ldpreload ./build.sh

# Copy everything back home
tupify cp build/tup "$INSTALL"
tupify cp build/tup-ldpreload.so "$INSTALL"
