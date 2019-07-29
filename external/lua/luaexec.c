// Reduced version of lua's interpreter that requires less dependencies, only
// for running scripts.

#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
#include <stdio.h>

int msgh(lua_State* L) {
  luaL_traceback(L, L, luaL_tolstring(L, -1, NULL), 2);
  return 1;
}

int main(int argc, const char** argv) {
  if(argc < 2) return 2;
  lua_State* L = luaL_newstate();
  if(L == NULL) return 2;
  luaL_openlibs(L);

  lua_pushcfunction(L, msgh);

  if(luaL_loadfile(L, argv[1]) != LUA_OK) {
    fprintf(stderr, "Unable to load file %s!\n", argv[1]);
    lua_close(L);
    return 1;
  }

  for(int i=2; i<argc; i++) lua_pushstring(L, argv[i]);

  if(lua_pcall(L, argc-2, 0, 1) != LUA_OK) {
    fprintf(stderr, "%s\n", lua_tostring(L, -1));
    lua_close(L);
    return 1;
  }
  lua_close(L);
  return 0;
}
