-- luacheck: std lua53, no global (Tup-lua)

BUILD_VALGRIND = 'y'

VALGRIND_CMD = 'VALGRIND_LIB='..tup.getcwd()..'/install/lib/valgrind '
  ..tup.getcwd()..'/install/bin/valgrind'
VALGRIND_MS_PRINT = tup.getcwd()..'/install/bin/ms_print'
