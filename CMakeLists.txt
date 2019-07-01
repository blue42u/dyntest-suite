# Just a temp file till I figure out what I'm doing here

project(DynTest)
cmake_minimum_required(VERSION 3.5)  # TODO: Find a good version boundary

set(CMAKE_MODULE_PATH ${CMAKE_MODULE_PATH} "${CMAKE_SOURCE_DIR}/cmake")

# For compatibility on NOTS. Accept CPATH/LD_LIBRARY_PATH on the search paths.
string(REPLACE ":" ";" INC_PATH $ENV{CPATH})
set(CMAKE_INCLUDE_PATH ${CMAKE_INCLUDE_PATH} ${INC_PATH})
#message(STATUS "CMake include search path: ${CMAKE_INCLUDE_PATH}")

string(REPLACE ":" ";" LIB_PATH $ENV{LD_LIBRARY_PATH})
set(CMAKE_LIBRARY_PATH ${CMAKE_LIBRARY_PATH} ${LIB_PATH})
#message(STATUS "CMake library search path: ${CMAKE_LIBRARY_PATH}")

add_subdirectory(external)
add_subdirectory(src)
