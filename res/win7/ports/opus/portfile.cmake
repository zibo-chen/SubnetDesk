# Opus overrides CMAKE_MSVC_RUNTIME_LIBRARY unless its own switch is enabled.
# Reuse the pinned project port while keeping this change in the Win7 tree.
list(APPEND VCPKG_CMAKE_CONFIGURE_OPTIONS "-DOPUS_STATIC_RUNTIME=ON")
include("${CMAKE_CURRENT_LIST_DIR}/../../../vcpkg/opus/portfile.cmake")
