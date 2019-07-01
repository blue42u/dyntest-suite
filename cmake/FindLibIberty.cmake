find_path(LibIberty_INCLUDE_DIR NAMES libiberty.h PATH_SUFFIXES libiberty)
mark_as_advanced(LibIberty_INCLUDE_DIR)

find_library(LibIberty_LIBRARY NAMES iberty)
mark_as_advanced(LibIberty_LIBRARY)

include(FindPackageHandleStandardArgs)
FIND_PACKAGE_HANDLE_STANDARD_ARGS(LibIberty DEFAULT_MSG
  LibIberty_LIBRARY LibIberty_INCLUDE_DIR)

if(LibIberty_FOUND)
  set(LibIberty_LIBRARIES ${LibIberty_LIBRARY})
  set(LibIberty_INCLUDE_DIRS ${LibIberty_INCLUDE_DIR})
endif()
