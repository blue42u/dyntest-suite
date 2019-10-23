#!/bin/bash

if cmp --quiet "$1" failure.txt
then cp failure.txt "$2"
else eval "$3"
fi
