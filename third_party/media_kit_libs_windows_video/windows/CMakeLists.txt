# This file is a part of media_kit (https://github.com/media-kit/media-kit).
#
# Copyright © 2021 & onwards, Hitesh Kumar Saini <saini123hitesh@gmail.com>.
# All rights reserved.
# Use of this source code is governed by MIT license that can be found in the LICENSE file.

cmake_minimum_required(VERSION 3.14)

cmake_policy(VERSION 3.14...3.25)

# This option is read by the other packages which are part of package:media_kit.
option(MEDIA_KIT_LIBS_AVAILABLE "package:media_kit libraries are available." ON)

set(PROJECT_NAME "media_kit_libs_windows_video")
project(${PROJECT_NAME} LANGUAGES CXX)

# Deal with MSVC incompatibility
add_compile_definitions(_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR)

# ------------------------------------------------------------------------------
function(download_and_verify url md5 locationForArchive)
  # Check if the archive exists.
  if(EXISTS "${locationForArchive}")
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    # If MD5 doesn't match, delete the archive to download again.
    if(NOT md5 STREQUAL ARCHIVE_MD5)
      file(REMOVE "${locationForArchive}")
      message(STATUS "MD5 mismatch. File deleted.")
    endif()
  endif()

  # Download the archive if it doesn't exist.
  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(DOWNLOAD "${url}" "${locationForArchive}")
    message(STATUS "Downloaded archive to ${locationForArchive}.")

    # Verify MD5 of the newly downloaded file.
    file(MD5 "${locationForArchive}" ARCHIVE_MD5)

    if(md5 STREQUAL ARCHIVE_MD5)
      message(STATUS "${locationForArchive} Verification successful.")
    else()
      message(FATAL_ERROR "${locationForArchive} Integrity check failed, please try to re-build project again.")
    endif()
  endif()
endfunction()

function(download_and_verify_sha256 url sha256 locationForArchive)
  if(EXISTS "${locationForArchive}")
    file(SHA256 "${locationForArchive}" ARCHIVE_SHA256)
    if(NOT "${sha256}" STREQUAL "${ARCHIVE_SHA256}")
      file(REMOVE "${locationForArchive}")
      message(STATUS "SHA-256 mismatch. File deleted.")
    endif()
  endif()

  if(NOT EXISTS "${locationForArchive}")
    message(STATUS "Downloading archive from ${url}...")
    file(
      DOWNLOAD
      "${url}"
      "${locationForArchive}"
      EXPECTED_HASH "SHA256=${sha256}"
      STATUS DOWNLOAD_STATUS
      TLS_VERIFY ON
      TIMEOUT 1800
      INACTIVITY_TIMEOUT 300
    )
    list(GET DOWNLOAD_STATUS 0 DOWNLOAD_STATUS_CODE)
    list(GET DOWNLOAD_STATUS 1 DOWNLOAD_STATUS_MESSAGE)
    if(NOT DOWNLOAD_STATUS_CODE EQUAL 0)
      file(REMOVE "${locationForArchive}")
      message(
        FATAL_ERROR
        "Failed to download ${url}: ${DOWNLOAD_STATUS_MESSAGE}"
      )
    endif()
  endif()

  file(SHA256 "${locationForArchive}" ARCHIVE_SHA256)
  if(NOT "${sha256}" STREQUAL "${ARCHIVE_SHA256}")
    message(
      FATAL_ERROR
      "${locationForArchive} SHA-256 verification failed."
    )
  endif()
endfunction()

find_program(SEVENZ_EXECUTABLE NAMES 7z 7za)

# Fall back to the project's bundled 7-Zip under tools/ if not on PATH.
# Use absolute fallback paths instead of CMAKE_CURRENT_LIST_DIR-based ones,
# because CMake does not resolve Windows directory symlinks.
if(NOT SEVENZ_EXECUTABLE)
  foreach(_sevenz_candidate
      "D:/project/dart_simple_live-master/tools/7zip/7z.exe"
      "C:/project/dart_simple_live-master/tools/7zip/7z.exe")
    if(EXISTS "${_sevenz_candidate}")
      set(SEVENZ_EXECUTABLE "${_sevenz_candidate}")
      break()
    endif()
  endforeach()
endif()

# WinRAR can also extract 7z archives.
find_program(WINRAR_EXECUTABLE NAMES winrar unrar)
# Common non-PATH install locations on Windows.
if(NOT WINRAR_EXECUTABLE)
  foreach(_candidate
      "D:/Program Files/WinRAR/UnRAR.exe"
      "C:/Program Files/WinRAR/UnRAR.exe"
      "C:/Program Files (x86)/WinRAR/UnRAR.exe"
      "D:/winrar/UnRAR.exe")
    if(EXISTS "${_candidate}")
      set(WINRAR_EXECUTABLE "${_candidate}")
      break()
    endif()
  endforeach()
endif()

# Pre-staged CppWinRT package for permission_handler_windows.
# If a pre-staged packages dir exists and contains the required version,
# skip the nuget install step entirely (avoids NuGet lock / network issues).
set(CPPWINRT_VERSION "2.0.210806.1")
set(CPPWINRT_STAGED_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../tools/cppwinrt-staged/packages")
if(EXISTS "${CPPWINRT_STAGED_DIR}/Microsoft.Windows.CppWinRT.${CPPWINRT_VERSION}/bin/cppwinrt.exe")
  set(CPPWINRT_STAGED TRUE)
  message(STATUS "Reusing staged CppWinRT ${CPPWINRT_VERSION} package: ${CPPWINRT_STAGED_DIR}")
else()
  set(CPPWINRT_STAGED FALSE)
endif()

function(extract_archive archive destDir)
  # Prefer 7-Zip: it handles .7z natively.
  if(SEVENZ_EXECUTABLE)
    execute_process(
      COMMAND "${SEVENZ_EXECUTABLE}" x "${archive}" "-o${destDir}" "-y"
      RESULT_VARIABLE EXTRACT_RESULT
    )
    if(EXTRACT_RESULT EQUAL 0)
      return()
    endif()
    message(STATUS "7-Zip failed, trying WinRAR...")
  endif()
  # WinRAR only works for .rar (not .7z).
  if(WINRAR_EXECUTABLE)
    execute_process(
      COMMAND "${WINRAR_EXECUTABLE}" x -y "${archive}" "${destDir}\""
      RESULT_VARIABLE EXTRACT_RESULT
    )
    if(EXTRACT_RESULT EQUAL 0)
      return()
    endif()
  endif()
  message(FATAL_ERROR "Could not extract ${archive}. Install 7-Zip.")
endfunction()

function(check_directory_exists_and_not_empty dir result_var)
  if(EXISTS "${dir}")
    file(GLOB dir_contents "${dir}/*")
    if(dir_contents)
      set(${result_var} TRUE PARENT_SCOPE)
    else()
      set(${result_var} FALSE PARENT_SCOPE)
      message(STATUS "Directory ${dir} exists but is empty!")
    endif()
  else()
    set(${result_var} FALSE PARENT_SCOPE)
    message(STATUS "Directory ${dir} does not exist!")
  endif()
endfunction()

# libmpv archive containing the pre-built shared libraries & headers.
# Keep the generic x86_64 build so older Windows CPUs do not require AVX2.
set(LIBMPV_RELEASE "20260828")
set(LIBMPV_REVISION "182fa6ca49")
set(LIBMPV "mpv-dev-x86_64-${LIBMPV_RELEASE}-git-${LIBMPV_REVISION}.7z")

# Download URL & SHA-256 hash of the libmpv archive.
set(LIBMPV_URL "https://github.com/shinchiro/mpv-winbuild-cmake/releases/download/${LIBMPV_RELEASE}/${LIBMPV}")
set(LIBMPV_SHA256 "9efd04d351e09eca350d01da1b8b0c406537c037537111ba65ab43c91905635b")

# Download location of the libmpv archive.
set(LIBMPV_ARCHIVE "${CMAKE_BINARY_DIR}/${LIBMPV}")
set(LIBMPV_SRC "${CMAKE_BINARY_DIR}/libmpv")
set(LIBMPV_MARKER "${LIBMPV_SRC}/.simplelive-${LIBMPV_RELEASE}-${LIBMPV_REVISION}")

# --- Prefetched shared archive ------------------------------------------------
# Developers can prefetch the archive once inside the plugin's own root
# (third_party/media_kit_libs_windows_video). Reuse it only after the same
# checksum validation used for the build directory copy.
if(DEFINED SIMPLE_LIVE_LIBMPV_ARCHIVE)
  set(LIBMPV_SHARED_ARCHIVE "${SIMPLE_LIVE_LIBMPV_ARCHIVE}")
else()
  set(LIBMPV_SHARED_ARCHIVE "${CMAKE_CURRENT_LIST_DIR}/../${LIBMPV}")
endif()

if(EXISTS "${LIBMPV_SHARED_ARCHIVE}")
  file(SHA256 "${LIBMPV_SHARED_ARCHIVE}" LIBMPV_SHARED_ARCHIVE_SHA256)
  if(NOT "${LIBMPV_SHARED_ARCHIVE_SHA256}" STREQUAL "${LIBMPV_SHA256}")
    message(FATAL_ERROR "${LIBMPV_SHARED_ARCHIVE} SHA-256 verification failed.")
  endif()
  set(LIBMPV_BUILD_ARCHIVE_SHA256 "")
  if(EXISTS "${LIBMPV_ARCHIVE}")
    file(SHA256 "${LIBMPV_ARCHIVE}" LIBMPV_BUILD_ARCHIVE_SHA256)
  endif()
  if(NOT "${LIBMPV_BUILD_ARCHIVE_SHA256}" STREQUAL "${LIBMPV_SHA256}")
    execute_process(
      COMMAND "${CMAKE_COMMAND}" -E copy_if_different
        "${LIBMPV_SHARED_ARCHIVE}"
        "${LIBMPV_ARCHIVE}"
      RESULT_VARIABLE LIBMPV_COPY_RESULT
    )
    if(NOT LIBMPV_COPY_RESULT EQUAL 0)
      message(FATAL_ERROR "Failed to copy ${LIBMPV_SHARED_ARCHIVE}.")
    endif()
    message(STATUS "Reusing prefetched libmpv archive: ${LIBMPV_SHARED_ARCHIVE}")
  else()
    message(STATUS "libmpv archive already present in build dir.")
  endif()
  # Bypass the network: the build-dir copy is now valid, so skip download.
  set(LIBMPV_SHARED_READY TRUE)
else()
  set(LIBMPV_SHARED_READY FALSE)
  message(STATUS "No prefetched libmpv archive found at ${LIBMPV_SHARED_ARCHIVE}; will download.")
endif()

# Only attempt a network download if neither the build-dir copy nor the shared
# archive is available. This avoids hanging on GitHub when the archive has
# already been staged locally.
if(NOT LIBMPV_SHARED_READY AND NOT EXISTS "${LIBMPV_ARCHIVE}")
  download_and_verify_sha256(
    ${LIBMPV_URL}
    ${LIBMPV_SHA256}
    ${LIBMPV_ARCHIVE}
  )
endif()

set(LIBMPV_REQUIRED_FILES
  "${LIBMPV_SRC}/include/mpv/client.h"
  "${LIBMPV_SRC}/include/mpv/render.h"
  "${LIBMPV_SRC}/include/mpv/render_gl.h"
  "${LIBMPV_SRC}/include/mpv/stream_cb.h"
  "${LIBMPV_SRC}/libmpv-2.dll"
)

# --- Extract libmpv into build dir ---
# Force re-extraction if the marker is missing or the source is incomplete.
set(LIBMPV_NEEDS_REEXTRACT FALSE)
if(NOT EXISTS "${LIBMPV_MARKER}")
  set(LIBMPV_NEEDS_REEXTRACT TRUE)
  message(STATUS "libmpv marker missing; will extract.")
else()
  foreach(LIBMPV_PROBE_FILE IN LISTS LIBMPV_REQUIRED_FILES)
    if(NOT EXISTS "${LIBMPV_PROBE_FILE}")
      set(LIBMPV_NEEDS_REEXTRACT TRUE)
      message(STATUS "libmpv source incomplete (${LIBMPV_PROBE_FILE} missing); will re-extract.")
      break()
    endif()
  endforeach()
endif()

if(LIBMPV_NEEDS_REEXTRACT)
  check_directory_exists_and_not_empty("${LIBMPV_SRC}" LIBMPV_EXTRACTED)
  if(LIBMPV_EXTRACTED)
    # Old partial extraction: remove it and re-extract cleanly.
    file(REMOVE_RECURSE "${LIBMPV_SRC}")
  endif()

  if(NOT EXISTS "${LIBMPV_ARCHIVE}")
    message(FATAL_ERROR "libmpv archive not found at ${LIBMPV_ARCHIVE}")
  endif()

  if(NOT SEVENZ_EXECUTABLE)
    message(FATAL_ERROR "7-Zip not found; cannot extract ${LIBMPV_ARCHIVE}. Install 7-Zip or place 7z.exe under tools/7zip/ (e.g. via build_windows_release.bat).")
  endif()

  extract_archive("${LIBMPV_ARCHIVE}" "${CMAKE_BINARY_DIR}")

  # Normalise: 7z extracts the archive into the build root with include/ and
  # top-level libmpv-2.dll + libmpv.dll.a. The plugin source expects
  # CMAKE_BINARY_DIR/libmpv/{include,libmpv-2.dll,...}.
  set(EXTRACTED_DIR "${CMAKE_BINARY_DIR}/mpv-dev-x86_64-${LIBMPV_RELEASE}-git-${LIBMPV_REVISION}")
  if(EXISTS "${EXTRACTED_DIR}/include")
    # Single-subfolder layout: rename to libmpv
    if(EXISTS "${LIBMPV_SRC}")
      file(REMOVE_RECURSE "${LIBMPV_SRC}")
    endif()
    execute_process(COMMAND "${CMAKE_COMMAND}" -E rename "${EXTRACTED_DIR}" "${LIBMPV_SRC}")
    message(STATUS "Normalised extracted dir to ${LIBMPV_SRC}")
  elseif(EXISTS "${CMAKE_BINARY_DIR}/include")
    # Split layout at build root: move include/ + top-level files into libmpv/
    if(EXISTS "${LIBMPV_SRC}")
      file(REMOVE_RECURSE "${LIBMPV_SRC}")
    endif()
    file(MAKE_DIRECTORY "${LIBMPV_SRC}")
    execute_process(COMMAND "${CMAKE_COMMAND}" -E rename "${CMAKE_BINARY_DIR}/include" "${LIBMPV_SRC}/include")
    foreach(_top_file libmpv-2.dll libmpv.dll.a)
      if(EXISTS "${CMAKE_BINARY_DIR}/${_top_file}")
        execute_process(COMMAND "${CMAKE_COMMAND}" -E copy "${CMAKE_BINARY_DIR}/${_top_file}" "${LIBMPV_SRC}/${_top_file}")
      endif()
    endforeach()
    message(STATUS "Normalised split layout to ${LIBMPV_SRC}")
  else()
    message(FATAL_ERROR "Could not find extracted libmpv content. Delete ${CMAKE_BINARY_DIR} and rebuild.")
  endif()

  # media_kit_video includes the mpv headers with <client.h> (not <mpv/client.h>),
  # so copy the headers out of include/mpv/ up into include/ as well.
  if(EXISTS "${LIBMPV_SRC}/include/mpv")
    file(GLOB _mpv_headers "${LIBMPV_SRC}/include/mpv/*.h")
    foreach(_mpv_header ${_mpv_headers})
      get_filename_component(_h_name "${_mpv_header}" NAME)
      execute_process(
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different
          "${_mpv_header}" "${LIBMPV_SRC}/include/${_h_name}"
      )
    endforeach()
    message(STATUS "Copied mpv headers into ${LIBMPV_SRC}/include/ for <client.h> include style")
  endif()

  file(WRITE "${LIBMPV_MARKER}" "libmpv ${LIBMPV_RELEASE} revision ${LIBMPV_REVISION}")
  message(STATUS "Extracted libmpv ${LIBMPV_RELEASE} (${LIBMPV_REVISION}).")
endif()

# Re-verify after extraction that all required files are present.
foreach(LIBMPV_REQUIRED_FILE IN LISTS LIBMPV_REQUIRED_FILES)
  if(NOT EXISTS "${LIBMPV_REQUIRED_FILE}")
    message(FATAL_ERROR "libmpv archive is missing required file: ${LIBMPV_REQUIRED_FILE}")
  endif()
endforeach()

# --- ANGLE (OpenGL ES / EGL on Windows) ------------------------------------
# media_kit_video compiles against ANGLE headers + import libs and bundles the
# ANGLE DLLs. The archive is prefetched next to this plugin (downloaded once,
# MD5-verified). If it is missing, we download it the same way the original
# media_kit CMakeLists did (alexmercerind release, MD5 e866f13e...).
#
# The ANGLE.7z has a flat layout: include/{EGL,GLES2,KHR}, lib/{libEGL.dll.lib,
# libGLESv2.dll.lib} and the runtime DLLs at the archive root.
set(ANGLE_SHARED_ARCHIVE "${CMAKE_CURRENT_LIST_DIR}/../ANGLE.7z")
set(ANGLE_MD5 "e866f13e8d552348058afaafe869b1ed")
set(ANGLE_SRC "${CMAKE_BINARY_DIR}/ANGLE")

if(EXISTS "${ANGLE_SHARED_ARCHIVE}")
  file(MD5 "${ANGLE_SHARED_ARCHIVE}" ANGLE_ARCHIVE_MD5)
  if(NOT "${ANGLE_ARCHIVE_MD5}" STREQUAL "${ANGLE_MD5}")
    message(FATAL_ERROR "${ANGLE_SHARED_ARCHIVE} MD5 verification failed.")
  endif()
  set(ANGLE_READY FALSE)
  check_directory_exists_and_not_empty("${ANGLE_SRC}" ANGLE_READY)
  if(NOT ANGLE_READY)
    file(MAKE_DIRECTORY "${ANGLE_SRC}")
    extract_archive("${ANGLE_SHARED_ARCHIVE}" "${ANGLE_SRC}")
    message(STATUS "Extracted ANGLE to ${ANGLE_SRC}")
  else()
    message(STATUS "ANGLE already extracted at ${ANGLE_SRC}")
  endif()
else()
  message(STATUS "No prefetched ANGLE.7z; downloading from GitHub.")
  file(DOWNLOAD
    "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z"
    "${CMAKE_BINARY_DIR}/ANGLE.7z"
    EXPECTED_MD5 ${ANGLE_MD5}
    STATUS ANGLE_DOWNLOAD_STATUS
  )
  list(GET ANGLE_DOWNLOAD_STATUS 0 ANGLE_DOWNLOAD_RESULT)
  if(NOT ANGLE_DOWNLOAD_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to download ANGLE.7z: ${ANGLE_DOWNLOAD_STATUS}")
  endif()
  check_directory_exists_and_not_empty("${ANGLE_SRC}" ANGLE_READY)
  if(NOT ANGLE_READY)
    file(MAKE_DIRECTORY "${ANGLE_SRC}")
    extract_archive("${CMAKE_BINARY_DIR}/ANGLE.7z" "${ANGLE_SRC}")
    message(STATUS "Extracted ANGLE to ${ANGLE_SRC}")
  endif()
endif()

# --- Plugin target ---
set(PLUGIN_NAME media_kit_libs_windows_video_plugin)
add_library(${PLUGIN_NAME} SHARED
  "include/media_kit_libs_windows_video/media_kit_libs_windows_video_plugin_c_api.h"
  "media_kit_libs_windows_video_plugin_c_api.cpp"
)

apply_standard_settings(${PLUGIN_NAME})

set_target_properties(
  ${PLUGIN_NAME}
  PROPERTIES
  CXX_VISIBILITY_PRESET
  hidden
)
target_compile_definitions(
  ${PLUGIN_NAME}
  PRIVATE
  FLUTTER_PLUGIN_IMPL
)

target_include_directories(
  ${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include"
)
target_link_libraries(
  ${PLUGIN_NAME}
  PRIVATE
  flutter
  flutter_wrapper_plugin
)

set(
  media_kit_libs_windows_video_bundled_libraries
  "${LIBMPV_SRC}/libmpv-2.dll"
  "${ANGLE_SRC}/d3dcompiler_47.dll"
  "${ANGLE_SRC}/libEGL.dll"
  "${ANGLE_SRC}/libGLESv2.dll"
  "${ANGLE_SRC}/vk_swiftshader.dll"
  "${ANGLE_SRC}/vulkan-1.dll"
  "${ANGLE_SRC}/zlib.dll"
  PARENT_SCOPE
)
