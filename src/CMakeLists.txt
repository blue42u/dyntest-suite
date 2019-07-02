# Compile and import bits and bobs from the projects we have the most contact with.

include(ExternalProject)

# Elfutils is used by everyone. DWARF/ELF format parsing and such.
ExternalProject_Add(Elfutils
  SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/elfutils
  BINARY_DIR ${CMAKE_BINARY_DIR}/latest/build/elfutils
  INSTALL_DIR ${CMAKE_BINARY_DIR}/latest/elfutils
  CONFIGURE_COMMAND <SOURCE_DIR>/configure --prefix=<INSTALL_DIR>
    --enable-maintainer-mode
)
ExternalProject_Add_Step(Elfutils preconfigure
  COMMAND autoreconf -i
  DEPENDERS configure
  WORKING_DIRECTORY <SOURCE_DIR>
)
# The elf.h provided by (basically everyone) is out of date.
ExternalProject_Add_Step(Elfutils install_elf_header
  COMMAND ${CMAKE_COMMAND} -E copy <SOURCE_DIR>/libelf/elf.h <INSTALL_DIR>/include
  DEPENDEES install
)

# Dyninst is the main part being tested. Static code analysis.
ExternalProject_Add(Dyninst
  SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/dyninst
  BINARY_DIR ${CMAKE_BINARY_DIR}/latest/build/dyninst
  INSTALL_DIR ${CMAKE_BINARY_DIR}/latest/dyninst
  DEPENDS Elfutils Boost TBB Valgrind
  CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
    -DElfUtils_ROOT_DIR=$<TARGET_PROPERTY:Elfutils,_EP_INSTALL_DIR>
    -DBoost_ROOT_DIR=$<TARGET_PROPERTY:Boost,_EP_INSTALL_DIR>
    -DTBB_ROOT_DIR=$<TARGET_PROPERTY:TBB,_EP_INSTALL_DIR>
)

# A few examples make up the sanity tests
add_subdirectory(examples)

# HPCToolkit is the main test case. Static code analysis dumper.
# However, despite using automake, it doesn't search for any of its dependencies.
# So we have to do most of the work ourselves. Ugh.
find_package(LibIberty REQUIRED)
find_package(LibBFD REQUIRED)
find_package(ZLIB REQUIRED)
find_package(BZip2 REQUIRED)
find_package(LibLZMA REQUIRED)

if(FALSE)
ExternalProject_Add(HPCToolkit
  SOURCE_DIR ${CMAKE_CURRENT_SOURCE_DIR}/hpctoolkit
  BINARY_DIR ${CMAKE_BINARY_DIR}/latest/build/hpctoolkit
  INSTALL_DIR ${CMAKE_BINARY_DIR}/latest/hpctoolkit
  DEPENDS Dyninst Boost TBB Elfutils Xerces
  CONFIGURE_COMMAND <SOURCE_DIR>/configure --prefix=<INSTALL_DIR> --enable-all-static
    --with-dyninst=$<TARGET_PROPERTY:Dyninst,_EP_INSTALL_DIR>
    --with-boost=$<TARGET_PROPERTY:Boost,_EP_INSTALL_DIR>
    --with-tbb=$<TARGET_PROPERTY:TBB,_EP_INSTALL_DIR>
    --with-elfutils=$<TARGET_PROPERTY:Elfutils,_EP_INSTALL_DIR>
    --with-xerces=$<TARGET_PROPERTY:Xerces,_EP_INSTALL_DIR>
    --with-binutils=${LibBFD_INCLUDE_DIR}/..
    --with-zlib=${ZLIB_INCLUDE_DIR}/..
    --with-bzip=${BZIP2_INCLUDE_DIR}/..
    --with-lzma=${LIBLZMA_INCLUDE_DIR}/..
    --with-libiberty=${LibIberty_INCLUDE_DIR}/..
#    --with-libdwarf=
#    --with-libmonitor=
#    --with-libunwind=
#    --with-papi=
#    --with-perfmon=
#    --with-xed=
)
ExternalProject_Add_Step(HPCToolkit preconfigure
  COMMAND autoreconf -i
  DEPENDERS configure
  WORKING_DIRECTORY <SOURCE_DIR>
)
endif()
