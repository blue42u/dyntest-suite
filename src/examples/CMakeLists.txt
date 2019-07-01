# Some little examples, to provide a very simple sanity check for the test suite

add_executable(exinput ex-main ex-print)

include_directories(
  ${CMAKE_BINARY_DIR}/install/dyninst/include
  ${CMAKE_BINARY_DIR}/install/tbb/include
)
add_executable(exdump exdump.cpp)
target_link_libraries(exdump
  ${CMAKE_BINARY_DIR}/install/dyninst/lib/libsymtabAPI.so
  ${CMAKE_BINARY_DIR}/install/dyninst/lib/libinstructionAPI.so
  ${CMAKE_BINARY_DIR}/install/dyninst/lib/libparseAPI.so
  ${CMAKE_BINARY_DIR}/install/dyninst/lib/libcommon.so
  ${CMAKE_BINARY_DIR}/install/boost/lib/libboost_system.so
  boost_system
  gomp
)
add_dependencies(exdump Dyninst)
