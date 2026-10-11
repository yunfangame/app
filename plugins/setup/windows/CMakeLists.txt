cmake_minimum_required(VERSION 3.14)
set(PROJECT_NAME "setup")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../buildkit/cmake/buildkit.cmake")
apply_buildkit()

add_dependencies(${BINARY_NAME} setup_buildkit_build)

get_filename_component(PROJECT_ROOT "${CMAKE_SOURCE_DIR}" DIRECTORY)

set(setup_bundled_libraries
  "${PROJECT_ROOT}/libclash/windows/FengWoCore.exe"
  "${PROJECT_ROOT}/libclash/windows/FengWoHelperService.exe"
  "${PROJECT_ROOT}/libclash/windows/manifest.json"
  PARENT_SCOPE
)
