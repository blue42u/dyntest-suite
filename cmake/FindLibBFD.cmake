find_path(LibBFD_INCLUDE_DIR NAMES bfd.h)
mark_as_advanced(LibBFD_INCLUDE_DIR)

find_library(LibBFD_LIBRARY NAMES bfd)
mark_as_advanced(LibBFD_LIBRARY)

include(FindPackageHandleStandardArgs)
FIND_PACKAGE_HANDLE_STANDARD_ARGS(LibBFD DEFAULT_MSG
  LibBFD_LIBRARY LibBFD_INCLUDE_DIR)

if(LibBFD_FOUND)
  set(LibBFD_LIBRARIES ${LibBFD_LIBRARY})
  set(LibBFD_INCLUDE_DIRS ${LibBFD_INCLUDE_DIR})
endif()
