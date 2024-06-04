cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "powersync_flutter_libs")
project(${PROJECT_NAME} LANGUAGES CXX)

# This value is used when generating builds using this plugin, so it must
# not be changed.
set(PLUGIN_NAME "powersync_flutter_libs_plugin")

# Define the plugin library target. Its name must not be changed (see comment
# on PLUGIN_NAME above).
#
# Any new source files that you add to the plugin should be added here.
add_library(${PLUGIN_NAME} SHARED
  "powersync_flutter_libs_plugin.cc"
)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)
target_include_directories(${PLUGIN_NAME} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/include")
target_link_libraries(${PLUGIN_NAME} PRIVATE flutter)

# ----------------------------------------------------------------------
# Download and add powersync prebuilt library.

set(POWERSYNC_VERSION 0.1.6)

set(POWERSYNC_ARCH ${CMAKE_SYSTEM_PROCESSOR})
if (${POWERSYNC_ARCH} MATCHES "x86_64" OR ${POWERSYNC_ARCH} MATCHES "AMD64")
    set(POWERSYNC_ARCH x64)
elseif (${POWERSYNC_ARCH} MATCHES "^arm64" OR ${POWERSYNC_ARCH} MATCHES "^armv8")
    set(POWERSYNC_ARCH aarch64)
endif ()

set(POWERSYNC_FILE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/libpowersync.so")

if(NOT EXISTS ${POWERSYNC_FILE_PATH})
  file(DOWNLOAD
    "https://github.com/powersync-ja/powersync-sqlite-core/releases/download/v${POWERSYNC_VERSION}/libpowersync_${POWERSYNC_ARCH}.so"
    ${POWERSYNC_FILE_PATH}
    SHOW_PROGRESS
  )
endif()

# ----------------------------------------------------------------------

# List of absolute paths to libraries that should be bundled with the plugin. 
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(powersync_flutter_libs_bundled_libraries
  "${POWERSYNC_FILE_PATH}"
  PARENT_SCOPE
)
