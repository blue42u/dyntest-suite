# Bits and bobs for things that aren't actually part of the project, but we still need.

include(ExternalProject)

# Boost is a major component of Dyninst and HPCToolkit (to my personal dismay).
# We do it up here because a) Dyninst doesn't do it right, and b) to save time.
ExternalProject_Add(Boost
  URL https://dl.bintray.com/boostorg/release/1.70.0/source/boost_1_70_0.tar.bz2
  URL_HASH SHA256=430ae8354789de4fd19ee52f3b1f739e1fba576f0aded0897c3c2bc00fb38778

  DOWNLOAD_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/boost/dl
  TMP_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/boost/tmp
  STAMP_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/boost/stamp
  SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/boost/src
  BUILD_IN_SOURCE 1
  INSTALL_DIR ${CMAKE_CURRENT_BINARY_DIR}/boost

  CONFIGURE_COMMAND ./bootstrap.sh --prefix=<INSTALL_DIR>
    --with-libraries=atomic,chrono,date_time,filesystem,system,thread,timer
  BUILD_COMMAND ./b2 --ignore-site-config
    --link=static --runtime-link=static
    --threading=multi
  INSTALL_COMMAND ./b2 install
)

# TBB is used by Dyninst and HPCToolkit for various helpful parallel classes.
# The compilation process is complex. We basically skip around it.
ExternalProject_Add(TBB
  URL https://github.com/intel/tbb/archive/2019_U8.tar.gz
  URL_HASH SHA256=7b1fd8caea14be72ae4175896510bf99c809cd7031306a1917565e6de7382fba

  DOWNLOAD_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/tbb/dl
  TMP_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/tbb/tmp
  STAMP_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/tbb/stamp
  SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/tbb/src
  BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/tbb/build
  INSTALL_DIR ${CMAKE_CURRENT_BINARY_DIR}/tbb

  CONFIGURE_COMMAND ""  # This version needs no configuration.
  # This is kind of a hack, to casually jump around TBB's weird build system.
  # We always build debug versions because we can.
  BUILD_COMMAND $(MAKE) -C <BINARY_DIR> -r -f <SOURCE_DIR>/build/Makefile.tbb
    tbb_root=<SOURCE_DIR> cfg=release
  INSTALL_COMMAND
    ${CMAKE_COMMAND} -E copy_if_different <BINARY_DIR>/libtbb.so.2 <INSTALL_DIR>/lib
)
ExternalProject_Add_Step(TBB build_malloc
  DEPENDEES build
  COMMAND $(MAKE) -C <BINARY_DIR> -r -f <SOURCE_DIR>/build/Makefile.tbbmalloc malloc
    tbb_root=<SOURCE_DIR> cfg=release
)
ExternalProject_Add_Step(TBB install_malloc
  DEPENDEES build_malloc
  COMMAND
    ${CMAKE_COMMAND} -E copy_if_different <BINARY_DIR>/libtbbmalloc.so.2 <INSTALL_DIR>/lib
)
ExternalProject_Add_Step(TBB build_proxy
  DEPENDEES build
  COMMAND $(MAKE) -C <BINARY_DIR> -r -f <SOURCE_DIR>/build/Makefile.tbbproxy tbbproxy
    tbb_root=<SOURCE_DIR> cfg=release
)
ExternalProject_Add_Step(TBB install_proxy
  DEPENDEES build_proxy
  COMMAND
    ${CMAKE_COMMAND} -E copy_if_different <BINARY_DIR>/libtbbmalloc_proxy.so.2 <INSTALL_DIR>/lib
)
ExternalProject_Add_Step(TBB build_preview
  DEPENDEES build
  COMMAND $(MAKE) -C <BINARY_DIR> -r -f <SOURCE_DIR>/build/Makefile.tbb
    tbb_root=<SOURCE_DIR> cfg=preview tbb_cpf=1
)
ExternalProject_Add_Step(TBB install_preview
  DEPENDEES build_preview
  COMMAND
    ${CMAKE_COMMAND} -E copy_if_different <BINARY_DIR>/libtbb_preview.so.2 <INSTALL_DIR>/lib
)
ExternalProject_Add_Step(TBB install_headers
  DEPENDEES configure
  COMMAND ${CMAKE_COMMAND} -E copy_directory <SOURCE_DIR>/include/tbb <INSTALL_DIR>/include/tbb
)
ExternalProject_Add_Step(TBB mkdirs
  DEPENDERS install install_headers install_malloc install_proxy install_preview
  COMMAND ${CMAKE_COMMAND} -E make_directory <INSTALL_DIR>/include/tbb <INSTALL_DIR>/lib
)
ExternalProject_Add_Step(TBB symlink
  DEPENDEES install
  COMMAND
    ${CMAKE_COMMAND} -E create_symlink <INSTALL_DIR>/lib/libtbb.so.2 <INSTALL_DIR>/lib/libtbb.so
)
ExternalProject_Add_Step(TBB symlink_malloc
  DEPENDEES install_malloc
  COMMAND
    ${CMAKE_COMMAND} -E create_symlink <INSTALL_DIR>/lib/libtbbmalloc.so.2 <INSTALL_DIR>/lib/libtbbmalloc.so
)
ExternalProject_Add_Step(TBB symlink_proxy
  DEPENDEES install_proxy
  COMMAND
    ${CMAKE_COMMAND} -E create_symlink <INSTALL_DIR>/lib/libtbbmalloc_proxy.so.2 <INSTALL_DIR>/lib/libtbbmalloc_proxy.so
)
ExternalProject_Add_Step(TBB symlink_preview
  DEPENDEES install_preview
  COMMAND
    ${CMAKE_COMMAND} -E create_symlink <INSTALL_DIR>/lib/libtbb_preview.so.2 <INSTALL_DIR>/lib/libtbb_preview.so
)

# Valgrind is the core of the testing framework, it does most of the heavy lifting.
ExternalProject_Add(Valgrind
  URL https://sourceware.org/pub/valgrind/valgrind-3.15.0.tar.bz2
  URL_HASH MD5=46e5fbdcbc3502a5976a317a0860a975

  DOWNLOAD_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/valgrind/dl
  TMP_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/valgrind/tmp
  STAMP_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/valgrind/stamp
  SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/valgrind/src
  BUILD_IN_SOURCE 1
  INSTALL_DIR ${CMAKE_CURRENT_BINARY_DIR}/valgrind

  CONFIGURE_COMMAND <SOURCE_DIR>/configure --prefix=<INSTALL_DIR>
)

# Xerces is an XML parsing library. Only HPCToolit uses it.
ExternalProject_Add(Xerces
  URL http://mirror.metrocast.net/apache//xerces/c/3/sources/xerces-c-3.2.2.tar.bz2
  URL_HASH SHA256=1f2a4d1dbd0086ce0f52b718ac0fa4af3dc1ce7a7ff73a581a05fbe78a82bce0

  DOWNLOAD_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/xerces/dl
  TMP_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/xerces/tmp
  STAMP_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/xerces/stamp
  SOURCE_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/xerces/src
  BINARY_DIR ${CMAKE_CURRENT_BINARY_DIR}/cmake/xerces/build
  INSTALL_DIR ${CMAKE_CURRENT_BINARY_DIR}/xerces

  CMAKE_ARGS -DCMAKE_INSTALL_PREFIX=<INSTALL_DIR>
)
