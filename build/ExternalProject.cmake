# Little CMake script to ensure none of the subprojects decide to use
# ExternalProject. Its far too complex for me to pull off in the current setup.

message(FATAL_ERROR "ExternalProject included when it shouldn't be!")
