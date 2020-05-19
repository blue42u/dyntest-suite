#!/bin/bash

# Installs the GCC wrapper script into a Debain setup.
# Should be run in a chroot, as root, after every upgrade.

for exe in g++ gcc cc cpp c++; do
  f="$(realpath "$(which "$exe")")"
  if readelf -h "$f" &> /dev/null; then
    echo "Tweaking $f!"
    mv "$f" "$f".real
    ln /gcc.sh "$f"
  fi
done

mkdir -p /rtldumps
chmod a+rwx /rtldumps
