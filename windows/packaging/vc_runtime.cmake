set(CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP TRUE)
set(CMAKE_INSTALL_DEBUG_LIBRARIES FALSE)
unset(MSVC_REDIST_DIR CACHE)
unset(MSVC_REDIST_DIR)
include(InstallRequiredSystemLibraries)

foreach(runtime_name IN ITEMS vcruntime140.dll vcruntime140_1.dll msvcp140.dll)
  set(runtime_found FALSE)
  foreach(runtime_path IN LISTS CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS)
    get_filename_component(runtime_filename "${runtime_path}" NAME)
    if(runtime_filename STREQUAL runtime_name AND EXISTS "${runtime_path}")
      set(runtime_found TRUE)
    endif()
  endforeach()
  if(NOT runtime_found)
    message(FATAL_ERROR "Missing MSVC redistributable ${runtime_name}; install the Visual Studio C++ build tools before packaging")
  endif()
endforeach()

install(FILES ${CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS}
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  CONFIGURATIONS Profile Release
  COMPONENT Runtime)

set(vc_runtime_source "${CMAKE_CURRENT_LIST_DIR}/../../.dart_tool/windows_runtime/${CMAKE_MSVC_ARCH}")
install(FILES
  "${vc_runtime_source}/vc_redist.exe"
  "${vc_runtime_source}/vc_runtime.iss"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/prerequisites"
  CONFIGURATIONS Profile Release
  COMPONENT Runtime
  OPTIONAL)
install(FILES "${CMAKE_CURRENT_LIST_DIR}/exe/vc_runtime_code.iss"
  DESTINATION "${INSTALL_BUNDLE_LIB_DIR}/prerequisites"
  CONFIGURATIONS Profile Release
  COMPONENT Runtime)
