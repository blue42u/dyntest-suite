-- luacheck: std lua53, no global (Tup-lua)

io.popen 'cc -o external/gotcha/dummy/lib/libgotcha.so -shared -x c - < /dev/null':close()

BUILD_GOTCHA = 'y'
