# Builds libmain.so — the library SDL dlopen()s on HarmonyOS.
#
# It is deliberately NOT the Cangjie library itself. The Cangjie runtime is started by the
# ArkTS-side loader (requireCJLib), not from native code, so libmain.so is a thin C shim that only
# forwards SDL's entry points into the real Cangjie host library staged in entry/libs/<abi>/ (see
# host_bootstrap.c). It therefore links no Cangjie library — only the C library's dlopen/dlsym.
#
# Shape adapted from PixCap-Cangjie entry/src/main/cpp/CMakeLists.txt (read-only reference); the
# only changes are the project name and the staging-path comment.
cmake_minimum_required(VERSION 3.5.0)
project(textura_host_shim C)

set(CMAKE_C_STANDARD 11)

if(NOT DEFINED OHOS_ARCH)
    set(OHOS_ARCH "arm64-v8a")
endif()

# Where scripts/harmony/stage_libs.sh stages the Cangjie host library and the cross-built SDL
# stack. The shim resolves libtextura_host.so from the runtime loader path, so this is only used to
# document the expected staging location.
set(TEXTURA_LIBS "${CMAKE_CURRENT_SOURCE_DIR}/../../../libs/${OHOS_ARCH}")

add_library(main SHARED host_bootstrap.c)

# TEXTURA-CUI-P05: the ArkTS -> SDL key bridge. A separate NAPI module (`textura_keys`) because the
# page root forwards the keys ArkUI keeps for its own focus traversal (Tab) into SDL's event queue.
# It resolves SDL_PushEvent at run time, so it needs no SDL headers and no link against libSDL3.so;
# libace_napi provides the module registration entry points.
add_library(textura_keys SHARED textura_keys.c)
find_library(ACE_NAPI_LIB ace_napi.z)
if(ACE_NAPI_LIB)
    target_link_libraries(textura_keys PRIVATE ${ACE_NAPI_LIB})
endif()
set_target_properties(textura_keys PROPERTIES
    PREFIX "lib"
    OUTPUT_NAME "textura_keys"
)

# dlopen/dlsym are all the shim needs; the Cangjie runtime is brought up by ArkTS.
target_link_libraries(main PRIVATE dl)

# SDL resolves its entry points out of libmain.so by name.
set_target_properties(main PROPERTIES
    PREFIX "lib"
    OUTPUT_NAME "main"
)
