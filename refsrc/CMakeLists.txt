# Compile and import bits from the stable versions of what we wanted to test.

include(ExternalProject)

# Elfutils is used by everyone. DWARF/ELF format parsing and such.
ExternalProject_Add(Elfutils_Ref
  SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/elfutils
  BINARY_DIR ${CMAKE_BINARY_DIR}/reference/build/elfutils
  INSTALL_DIR ${CMAKE_BINARY_DIR}/reference/elfutils
  CONFIGURE_COMMAND <SOURCE_DIR>/configure --prefix=<INSTALL_DIR>
    --enable-maintainer-mode
)
ExternalProject_Add_Step(Elfutils_Ref preconfigure
  COMMAND autoreconf -i
  DEPENDERS configure
  WORKING_DIRECTORY <SOURCE_DIR>
)
# The elf.h provided by (basically everyone) is out of date.
ExternalProject_Add_Step(Elfutils_Ref install_elf_header
  COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/libelf/elf.h <INSTALL_DIR>/include
  DEPENDEES install
)

# Dyninst is the main part being tested. Static code analysis.
ExternalProject_Add(Dyninst_Ref
  SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/dyninst
  BINARY_DIR ${CMAKE_BINARY_DIR}/reference/build/dyninst
  INSTALL_DIR ${CMAKE_BINARY_DIR}/reference/dyninst
  DEPENDS Elfutils_Ref Boost TBB Valgrind
  CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
    -DElfUtils_ROOT_DIR=$<TARGET_PROPERTY:Elfutils_Ref,_EP_INSTALL_DIR>
    -DBoost_ROOT_DIR=$<TARGET_PROPERTY:Boost,_EP_INSTALL_DIR>
    -DTBB_ROOT_DIR=$<TARGET_PROPERTY:TBB,_EP_INSTALL_DIR>
    -DUSE_OpenMP=OFF
)

# Example dumping thing, reference version
include_directories(
  $<TARGET_PROPERTY:Dyninst_Ref,_EP_INSTALL_DIR>/include
  $<TARGET_PROPERTY:TBB,_EP_INSTALL_DIR>/include
)
add_executable(exdump_Ref exdump.cpp)
target_link_libraries(exdump_Ref
  $<TARGET_PROPERTY:Dyninst_Ref,_EP_INSTALL_DIR>/lib/libsymtabAPI.so
  $<TARGET_PROPERTY:Dyninst_Ref,_EP_INSTALL_DIR>/lib/libinstructionAPI.so
  $<TARGET_PROPERTY:Dyninst_Ref,_EP_INSTALL_DIR>/lib/libparseAPI.so
  $<TARGET_PROPERTY:Dyninst_Ref,_EP_INSTALL_DIR>/lib/libcommon.so
  $<TARGET_PROPERTY:Boost,_EP_INSTALL_DIR>/lib/libboost_system.so
  $<TARGET_PROPERTY:TBB,_EP_INSTALL_DIR>/lib/libtbb.so
  boost_system
  gomp
)
add_dependencies(exdump_Ref Dyninst_Ref)
