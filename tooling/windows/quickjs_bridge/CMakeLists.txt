cmake_minimum_required(VERSION 3.15)
project(fengwo_arm64_javascript LANGUAGES C CXX)

if(NOT WIN32 OR NOT CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64")
  message(FATAL_ERROR "This bridge requires the Windows ARM64 MSVC target")
endif()
if(NOT MSVC)
  message(FATAL_ERROR "This bridge requires MSVC")
endif()
if(NOT EXISTS "${QUICKJS_SOURCE_DIR}/quickjs.c" OR NOT EXISTS "${QUICKJS_RUNTIME_SOURCE}")
  message(FATAL_ERROR "Pinned QuickJS sources are missing")
endif()

file(STRINGS "${QUICKJS_SOURCE_DIR}/VERSION" QUICKJS_VERSION)
add_library(fengwo_quickjs_engine STATIC
  "${QUICKJS_SOURCE_DIR}/cutils.c"
  "${QUICKJS_SOURCE_DIR}/libregexp.c"
  "${QUICKJS_SOURCE_DIR}/libunicode.c"
  "${QUICKJS_SOURCE_DIR}/quickjs.c"
)
target_compile_definitions(fengwo_quickjs_engine PRIVATE "CONFIG_VERSION=\"${QUICKJS_VERSION}\"")
target_compile_options(fengwo_quickjs_engine PRIVATE /utf-8)

file(TO_CMAKE_PATH "${QUICKJS_RUNTIME_SOURCE}" QUICKJS_RUNTIME_INCLUDE)
configure_file(runtime_compat.cpp.in "${CMAKE_CURRENT_BINARY_DIR}/runtime_compat.cpp" @ONLY)
add_library(quickjs_c_bridge SHARED "${CMAKE_CURRENT_BINARY_DIR}/runtime_compat.cpp" memory_limit.cpp)
target_compile_features(quickjs_c_bridge PRIVATE cxx_std_17)
target_compile_options(quickjs_c_bridge PRIVATE /utf-8)
get_filename_component(QUICKJS_PARENT_DIR "${QUICKJS_SOURCE_DIR}" DIRECTORY)
target_include_directories(quickjs_c_bridge PRIVATE "${QUICKJS_PARENT_DIR}")
target_link_libraries(quickjs_c_bridge PRIVATE fengwo_quickjs_engine)

add_executable(quickjs_bridge_smoke smoke.cpp)
target_compile_features(quickjs_bridge_smoke PRIVATE cxx_std_17)
target_compile_options(quickjs_bridge_smoke PRIVATE /utf-8 /W4 /WX)
enable_testing()
add_test(NAME quickjs_bridge_smoke COMMAND quickjs_bridge_smoke
  "$<TARGET_FILE:quickjs_c_bridge>" "${QUICKJS_REQUIRED_SYMBOLS}")
set_tests_properties(quickjs_bridge_smoke PROPERTIES TIMEOUT 15)
