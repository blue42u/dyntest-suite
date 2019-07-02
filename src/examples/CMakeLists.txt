# Some little examples, to provide a very simple sanity check for the test suite

add_executable(exinput ex-main ex-print)

include_directories(
  $<TARGET_PROPERTY:Dyninst,_EP_INSTALL_DIR>/include
  $<TARGET_PROPERTY:TBB,_EP_INSTALL_DIR>/include
)
add_executable(exdump exdump.cpp)
target_link_libraries(exdump
  $<TARGET_PROPERTY:Dyninst,_EP_INSTALL_DIR>/lib/libsymtabAPI.so
  $<TARGET_PROPERTY:Dyninst,_EP_INSTALL_DIR>/lib/libinstructionAPI.so
  $<TARGET_PROPERTY:Dyninst,_EP_INSTALL_DIR>/lib/libparseAPI.so
  $<TARGET_PROPERTY:Dyninst,_EP_INSTALL_DIR>/lib/libcommon.so
  $<TARGET_PROPERTY:Boost,_EP_INSTALL_DIR>/lib/libboost_system.so
  $<TARGET_PROPERTY:TBB,_EP_INSTALL_DIR>/lib/libtbb.so
  boost_system
  gomp
)
add_dependencies(exdump Dyninst)
