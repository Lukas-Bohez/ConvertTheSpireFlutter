# Project-level configuration.
cmake_minimum_required(VERSION 3.13)
project(runner LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "convert_the_spire_reborn")
# The unique GTK application identifier for this application. See:
# https://wiki.gnome.org/HowDoI/ChooseApplicationID
set(APPLICATION_ID "com.example.convert_the_spire_reborn")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(SET CMP0063 NEW)

# Load bundled libraries from the lib/ directory relative to the binary.
set(CMAKE_INSTALL_RPATH "$ORIGIN/lib")

# Root filesystem for cross-building.
if(FLUTTER_TARGET_PLATFORM_SYSROOT)
  set(CMAKE_SYSROOT ${FLUTTER_TARGET_PLATFORM_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH ${CMAKE_SYSROOT})
  set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
  set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
  set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
endif()

# Define build configuration options.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
  set(CMAKE_BUILD_TYPE "Debug" CACHE
    STRING "Flutter build mode" FORCE)
  set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
    "Debug" "Profile" "Release")
endif()

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_14)
  target_compile_options(${TARGET} PRIVATE -Wall -Werror)
  target_compile_options(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:-O3>")
  target_compile_definitions(${TARGET} PRIVATE "$<$<NOT:$<CONFIG:Debug>>:NDEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# System-level dependencies.
find_package(PkgConfig REQUIRED)
pkg_check_modules(GTK REQUIRED IMPORTED_TARGET gtk+-3.0)

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Run the Flutter tool portions of the build. This must not be removed.
add_dependencies(${BINARY_NAME} flutter_assemble)

# Only the install-generated bundle's copy of the executable will launch
# correctly, since the resources must in the right relative locations. To avoid
# people trying to run the unbundled copy, put it in a subdirectory instead of
# the default top-level location.
set_target_properties(${BINARY_NAME}
  PROPERTIES
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/intermediates_do_not_run"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# By default, "installing" just makes a relocatable bundle in the build
# directory.
set(BUILD_BUNDLE_DIR "${PROJECT_BINARY_DIR}/bundle")
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

# Start with a clean build bundle directory every time.
install(CODE "
  file(REMOVE_RECURSE \"${BUILD_BUNDLE_DIR}/\")
  " COMPONENT Runtime)

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}/lib")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

foreach(bundled_library ${PLUGIN_BUNDLED_LIBRARIES})
  install(FILES "${bundled_library}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endforeach(bundled_library)

# Ensure plugin shared libraries built under the build plugins folder are copied
# into the bundle lib directory so the runtime can load them from $ORIGIN/lib.
install(CODE "
  file(GLOB plugin_libs \"${PROJECT_BINARY_DIR}/plugins/*/*.so\")
  foreach(p ${plugin_libs})
    file(COPY ${p} DESTINATION \"${INSTALL_BUNDLE_LIB_DIR}\")
  endforeach()
" COMPONENT Runtime)

# ── Bundle runtime libs so the app works on older distros ──────────────────

# Locate libstdc++ and libgcc_s from the build machine's GCC toolchain
execute_process(
  COMMAND ${CMAKE_CXX_COMPILER} -print-file-name=libstdc++.so.6
  OUTPUT_VARIABLE LIBSTDCPP_PATH OUTPUT_STRIP_TRAILING_WHITESPACE)

execute_process(
  COMMAND ${CMAKE_CXX_COMPILER} -print-file-name=libgcc_s.so.1
  OUTPUT_VARIABLE LIBGCC_PATH OUTPUT_STRIP_TRAILING_WHITESPACE)

# Resolve symlinks to get the real versioned file
get_filename_component(LIBSTDCPP_REAL "${LIBSTDCPP_PATH}" REALPATH)
get_filename_component(LIBGCC_REAL    "${LIBGCC_PATH}"    REALPATH)

if(LIBSTDCPP_REAL AND EXISTS "${LIBSTDCPP_REAL}")
  message(STATUS "Bundling libstdc++: ${LIBSTDCPP_REAL}")
  install(FILES "${LIBSTDCPP_REAL}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
          RENAME libstdc++.so.6)
endif()
if(LIBGCC_REAL AND EXISTS "${LIBGCC_REAL}")
  message(STATUS "Bundling libgcc: ${LIBGCC_REAL}")
  install(FILES "${LIBGCC_REAL}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
          RENAME libgcc_s.so.1)
endif()

# Make the app binary look in its own lib/ dir first (before system libs)
set_target_properties(${BINARY_NAME} PROPERTIES
  INSTALL_RPATH "\$ORIGIN/lib"
  BUILD_WITH_INSTALL_RPATH TRUE)

# Locate and bundle libmpv (required by media_kit)
find_library(LIBMPV_PATH mpv)
if(LIBMPV_PATH)
  get_filename_component(LIBMPV_REAL "${LIBMPV_PATH}" REALPATH)
  if(EXISTS "${LIBMPV_REAL}")
    get_filename_component(LIBMPV_BASENAME "${LIBMPV_REAL}" NAME)
    message(STATUS "Bundling libmpv: ${LIBMPV_REAL} (installed as ${LIBMPV_BASENAME})")
    install(FILES "${LIBMPV_REAL}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
            RENAME "${LIBMPV_BASENAME}")
  endif()
else()
  message(WARNING "libmpv not found — install libmpv-dev on the build machine")
endif()

# Also bundle libass if available (media_kit may depend on it)
find_library(LIBASS_PATH ass)
if(LIBASS_PATH)
  get_filename_component(LIBASS_REAL "${LIBASS_PATH}" REALPATH)
  if(EXISTS "${LIBASS_REAL}")
    get_filename_component(LIBASS_BASENAME "${LIBASS_REAL}" NAME)
    message(STATUS "Bundling libass: ${LIBASS_REAL} (installed as ${LIBASS_BASENAME})")
    install(FILES "${LIBASS_REAL}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
            RENAME "${LIBASS_BASENAME}")
  endif()
endif()

# Copy the native assets provided by the build.dart from all packages.
set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/linux/")
install(DIRECTORY "${NATIVE_ASSETS_DIR}"
   DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
   COMPONENT Runtime)

# Fully re-copy the assets directory on each build to avoid having stale files
# from a previous install.
set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

# Install the AOT library on non-Debug builds only.
if(NOT CMAKE_BUILD_TYPE MATCHES "Debug")
  install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()
