
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
      "${PROJECT_ROOT}/libclash/windows/FengWoCore.exe"
      "${PROJECT_ROOT}/libclash/windows/manifest.json"
    )
    set(_platform_args "windows")
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
