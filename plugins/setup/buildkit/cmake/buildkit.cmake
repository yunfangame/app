get_filename_component(BUILDKIT_DIR "${CMAKE_CURRENT_LIST_DIR}" DIRECTORY)

function(apply_buildkit)
  if(WIN32)
    set(_launcher "${BUILDKIT_DIR}/run_build_tool.cmd")
  else()
    set(_launcher "${BUILDKIT_DIR}/run_build_tool.sh")
  endif()

  get_filename_component(PROJECT_ROOT "${CMAKE_SOURCE_DIR}" DIRECTORY)

  if(WIN32)
    set(_outputs
      "${PROJECT_ROOT}/libclash/windows/FlClashCore.exe"
      "${PROJECT_ROOT}/libclash/windows/FlClashHelperService.exe"
      "${PROJECT_ROOT}/libclash/windows/manifest.json"
    )
    if(FLUTTER_TARGET_PLATFORM STREQUAL "windows-arm64")
      set(_windows_arch "arm64")
    elseif(FLUTTER_TARGET_PLATFORM STREQUAL "windows-x64")
      set(_windows_arch "amd64")
    elseif(NOT DEFINED FLUTTER_TARGET_PLATFORM AND CMAKE_GENERATOR_PLATFORM STREQUAL "ARM64")
      set(_windows_arch "arm64")
    elseif(NOT DEFINED FLUTTER_TARGET_PLATFORM AND CMAKE_GENERATOR_PLATFORM STREQUAL "x64")
      set(_windows_arch "amd64")
    else()
      message(FATAL_ERROR "Unsupported Windows Flutter target: ${FLUTTER_TARGET_PLATFORM}")
    endif()
    set(_platform_args "windows" "--arch" "${_windows_arch}")
  else()
    set(_outputs "${PROJECT_ROOT}/libclash/linux/FlClashCore")
    set(_platform_args "linux")
  endif()
  set(_phony "${CMAKE_CURRENT_BINARY_DIR}/buildkit_phony")

  set(BUILDKIT_ENV
    "BUILDKIT_CONFIGURATION=$<CONFIG>"
    "PROJECT_DIR=${PROJECT_ROOT}"
  )

  add_custom_command(
    OUTPUT ${_outputs} "${_phony}"
    COMMAND ${CMAKE_COMMAND} -E env ${BUILDKIT_ENV}
    "${_launcher}" ${_platform_args}
    WORKING_DIRECTORY "${PROJECT_ROOT}"
    VERBATIM
  )

  set_source_files_properties("${_phony}" PROPERTIES SYMBOLIC TRUE)
  add_custom_target(setup_buildkit_build ALL DEPENDS ${_outputs})
endfunction()
