# DirectX 8 headers and rendering backend selection
# GeneralsX @build BenderAI 10/02/2026 - Session 18
# Fighter19's approach: Fetch ONE OR THE OTHER, never both
#
# On Windows: Use min-dx8-sdk (minimal Windows DirectX headers + libs)
# On Linux:   Use DXVK native pre-built tarball (DirectX→Vulkan translation)
# On macOS:   Build DXVK from source using Meson + MoltenVK (DirectX→Metal bridge)
#
# CRITICAL: Mixing headers causes conflicts - dx8-src has incomplete types,
# DXVK has full DirectX8+Wine headers. Compiler picks first path = wrong headers.
#
# macOS DXVK build (Session 61, 24/02/2026):
#   DXVK 2.6 builds natively on macOS arm64 via its "native" build mode.
#   macOS fixes are maintained in the DXVK fork history consumed by this build.
#   This project no longer applies local patch scripts during configure/build.
#
# Reference: docs/WORKDIR/lessons/2026-02-LESSONS.md (historical patch rationale)

set(DXVK_VERSION "v2.6")

if(SAGE_USE_DX8)
  # Windows: Fetch min-dx8-sdk for native DirectX 8
  FetchContent_Declare(
    dx8
    GIT_REPOSITORY https://github.com/TheSuperHackers/min-dx8-sdk.git
    GIT_TAG        7bddff8c01f5fb931c3cb73d4aa8e66d303d97bc
  )
  FetchContent_MakeAvailable(dx8)
  message(STATUS "Using DirectX 8 SDK (Windows native)")

elseif(APPLE AND SAGE_USE_MOLTENVK)
  # macOS: Build DXVK 2.6 from source using Meson + MoltenVK
  # GeneralsX @build BenderAI 24/02/2026 - Phase 5 macOS port (Session 61)
  find_program(MESON_EXECUTABLE meson HINTS /usr/local/bin /opt/homebrew/bin)
  find_program(NINJA_EXECUTABLE ninja HINTS /usr/local/bin /opt/homebrew/bin)

  if(NOT MESON_EXECUTABLE)
    message(FATAL_ERROR "DXVK macOS build requires meson: brew install meson")
  endif()
  if(NOT NINJA_EXECUTABLE)
    message(FATAL_ERROR "DXVK macOS build requires ninja: brew install ninja")
  endif()

  # Detect host architecture so Clang targets the correct slice.
  # IMPORTANT: prefer CMAKE_OSX_ARCHITECTURES (set by the preset) over uname -m.
  # On Apple Silicon Macs running CMake / meson via Rosetta, uname -m returns
  # x86_64 even though the native executable arch is arm64. Using CMAKE_OSX_ARCHITECTURES
  # (e.g. "arm64" from the macos-vulkan preset) avoids building an x86_64 dylib that
  # the arm64 game binary cannot dlopen.
  if(CMAKE_OSX_ARCHITECTURES)
    # Use the first entry (handles "arm64;x86_64" fat-binary requests too)
    list(GET CMAKE_OSX_ARCHITECTURES 0 DXVK_HOST_ARCH)
  else()
    execute_process(
      COMMAND uname -m
      OUTPUT_VARIABLE DXVK_HOST_ARCH
      OUTPUT_STRIP_TRAILING_WHITESPACE
    )
  endif()
  message(STATUS "Building DXVK ${DXVK_VERSION} for macOS/${DXVK_HOST_ARCH} with Meson (${MESON_EXECUTABLE})")

  include(ExternalProject)
  # GeneralsX @build BenderAI 13/03/2026 Add explicit source mode to keep remote branch updates deterministic by default.
  set(DXVK_LOCAL_FORK_DIR "${CMAKE_SOURCE_DIR}/references/fbraz3-dxvk")
  option(SAGE_DXVK_USE_LOCAL_FORK "Build DXVK from local references/fbraz3-dxvk checkout" OFF)

  if(SAGE_DXVK_USE_LOCAL_FORK AND EXISTS "${DXVK_LOCAL_FORK_DIR}/.git")
    set(DXVK_SOURCE_DIR "${DXVK_LOCAL_FORK_DIR}")
    message(STATUS "DXVK macOS build: using local fork source at ${DXVK_SOURCE_DIR}")
    # iOS needs Patches/dxvk-ios.patch (bundle-relative MoltenVK dlopen + SDL3
    # drawable fixes) — apply it idempotently: skip when the working tree
    # already carries it (reverse-check passes), fail the configure otherwise
    # so an unpatched DXVK can never ship silently.
    if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
      execute_process(
        COMMAND git -C "${DXVK_LOCAL_FORK_DIR}" apply --reverse --check "${CMAKE_SOURCE_DIR}/Patches/dxvk-ios.patch"
        RESULT_VARIABLE DXVK_PATCH_ALREADY_APPLIED
        ERROR_QUIET)
      if(NOT DXVK_PATCH_ALREADY_APPLIED EQUAL 0)
        execute_process(
          COMMAND git -C "${DXVK_LOCAL_FORK_DIR}" apply "${CMAKE_SOURCE_DIR}/Patches/dxvk-ios.patch"
          RESULT_VARIABLE DXVK_PATCH_RESULT)
        if(NOT DXVK_PATCH_RESULT EQUAL 0)
          message(FATAL_ERROR "Failed to apply Patches/dxvk-ios.patch to references/fbraz3-dxvk — the iOS DXVK build requires it.")
        endif()
        message(STATUS "DXVK iOS: applied Patches/dxvk-ios.patch")
      else()
        message(STATUS "DXVK iOS: Patches/dxvk-ios.patch already applied")
      endif()
    endif()
  elseif(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # The remote clone has no way to receive the iOS patch; a silent fallback
    # here previously produced dylibs that die at Vulkan init on device.
    message(FATAL_ERROR "iOS DXVK requires the local fork submodule. Run: git submodule update --init references/fbraz3-dxvk")
  else()
    set(DXVK_SOURCE_DIR "${CMAKE_BINARY_DIR}/_deps/dxvk-src-fbraz3")
    message(STATUS "DXVK macOS build: using GitHub source clone at ${DXVK_SOURCE_DIR}")
  endif()
  set(DXVK_BUILD_DIR  "${CMAKE_BINARY_DIR}/_deps/dxvk-build-macos")
  set(DXVK_D3D8_LIB  "${DXVK_BUILD_DIR}/src/d3d8/libdxvk_d3d8.0.dylib")
  set(DXVK_D3D9_LIB  "${DXVK_BUILD_DIR}/src/d3d9/libdxvk_d3d9.0.dylib")

  # Detect Vulkan SDK location for Meson configuration.
  # VULKAN_SDK must point to the platform subdir (e.g. ~/VulkanSDK/1.4.x/macOS)
  # where lib/libvulkan.dylib and lib/libMoltenVK.dylib live.
  # GeneralsX @build BenderAI 03/03/2026: Normalize env path to macOS platform subdir
  set(VULKAN_SDK_ENV "$ENV{VULKAN_SDK}")

  # If VULKAN_SDK points to the version root (has macOS/ subdir), normalize it
  if(VULKAN_SDK_ENV AND EXISTS "${VULKAN_SDK_ENV}/macOS/lib/libMoltenVK.dylib")
    set(VULKAN_SDK_ENV "${VULKAN_SDK_ENV}/macOS")
    message(STATUS "DXVK macOS build: Normalized VULKAN_SDK to platform subdir: ${VULKAN_SDK_ENV}")
  endif()

  if(NOT VULKAN_SDK_ENV OR NOT EXISTS "${VULKAN_SDK_ENV}/lib/libMoltenVK.dylib")
    # Try home directory: look for ~/VulkanSDK/*/macOS
    file(GLOB VULKAN_HOME_DIRS "$ENV{HOME}/VulkanSDK/*/macOS")
    if(VULKAN_HOME_DIRS)
      list(SORT VULKAN_HOME_DIRS)
      list(REVERSE VULKAN_HOME_DIRS)
      list(GET VULKAN_HOME_DIRS 0 POTENTIAL_SDK)
      if(EXISTS "${POTENTIAL_SDK}/lib/libMoltenVK.dylib")
        set(VULKAN_SDK_ENV "${POTENTIAL_SDK}")
      endif()
    endif()
  endif()

  if(NOT VULKAN_SDK_ENV OR NOT EXISTS "${VULKAN_SDK_ENV}/lib/libMoltenVK.dylib")
    # Try common Homebrew locations
    foreach(BREW_PATH "/usr/local/Caskroom/vulkan-sdk/latest/VulkanSDK/macOS" "/opt/homebrew/Caskroom/vulkan-sdk/latest/VulkanSDK/macOS")
      if(EXISTS "${BREW_PATH}/lib/libMoltenVK.dylib")
        set(VULKAN_SDK_ENV "${BREW_PATH}")
        break()
      endif()
    endforeach()
  endif()

  if(VULKAN_SDK_ENV AND EXISTS "${VULKAN_SDK_ENV}/lib/libMoltenVK.dylib")
    message(STATUS "DXVK macOS build: Using Vulkan SDK at ${VULKAN_SDK_ENV}")
    set(VULKAN_SDK_ENV_VAR "VULKAN_SDK=${VULKAN_SDK_ENV}")
  else()
    message(WARNING "DXVK macOS build: Vulkan SDK / MoltenVK not found; Meson will search system paths")
    if(VULKAN_SDK_ENV)
      message(STATUS "  VULKAN_SDK checked: ${VULKAN_SDK_ENV}")
    endif()
    set(VULKAN_SDK_ENV_VAR "")
  endif()

  # iOS cross-compiles DXVK with a meson cross file (iPhoneOS sysroot); macOS uses
  # the native file. Arch/sysroot flags come from the machine file in both cases.
  if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    # The cross file is generated from a template so the iPhoneOS SDK path comes
    # from xcrun (Xcode-beta / renamed installs) instead of a hardcoded Xcode.app.
    execute_process(COMMAND xcrun --sdk iphoneos --show-sdk-path
                    OUTPUT_VARIABLE IOS_SDK OUTPUT_STRIP_TRAILING_WHITESPACE
                    COMMAND_ERROR_IS_FATAL ANY)
    configure_file(${CMAKE_SOURCE_DIR}/cmake/meson-arm64-ios-cross.ini.in
                   ${CMAKE_BINARY_DIR}/meson-arm64-ios-cross.ini @ONLY)
    set(DXVK_MESON_MACHINE_ARGS --cross-file ${CMAKE_BINARY_DIR}/meson-arm64-ios-cross.ini)
  else()
    set(DXVK_MESON_MACHINE_ARGS --native-file ${CMAKE_SOURCE_DIR}/cmake/meson-arm64-native.ini)
  endif()

  # Generate a pkg-config file for the in-tree (FetchContent) SDL3 so meson's
  # dependency('SDL3') resolves to it. Without this, meson silently falls back to a
  # system SDL2 (e.g. Homebrew) and compiles the WSI as Sdl2WsiDriver, which cannot
  # drive the SDL3 window the game creates (D3D device creation then fails at runtime).
  set(DXVK_SDL3_PC_DIR "${CMAKE_BINARY_DIR}/sdl3-pkgconfig")
  file(WRITE "${DXVK_SDL3_PC_DIR}/sdl3.pc"
"prefix=${CMAKE_BINARY_DIR}/_deps
libdir=\${prefix}/sdl3-build
includedir=\${prefix}/sdl3-src/include

Name: sdl3
Description: Simple DirectMedia Layer (in-tree FetchContent build)
Version: 3.4.2
Libs: -L\${libdir} -lSDL3
Cflags: -I\${includedir}
")
  if(DEFINED ENV{PKG_CONFIG_PATH})
    set(DXVK_PKG_CONFIG_PATH "${DXVK_SDL3_PC_DIR}:$ENV{PKG_CONFIG_PATH}")
  else()
    set(DXVK_PKG_CONFIG_PATH "${DXVK_SDL3_PC_DIR}")
  endif()
  set(DXVK_PKG_CONFIG_ENV "PKG_CONFIG_PATH=${DXVK_PKG_CONFIG_PATH}")

  if(SAGE_DXVK_USE_LOCAL_FORK AND EXISTS "${DXVK_LOCAL_FORK_DIR}/.git")
    ExternalProject_Add(dxvk_macos_build
      # GeneralsX @build BenderAI 13/03/2026 Build from local fbraz3 fork to avoid stale remote hash pins.
      SOURCE_DIR        ${DXVK_SOURCE_DIR}
      BINARY_DIR        ${DXVK_BUILD_DIR}
      DOWNLOAD_COMMAND  ""
      UPDATE_COMMAND    ""
      PATCH_COMMAND     ""
      CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CC=clang CXX=clang++ "CFLAGS=-arch ${DXVK_HOST_ARCH} -mcpu=apple-m1" "CXXFLAGS=-arch ${DXVK_HOST_ARCH} -mcpu=apple-m1" "LDFLAGS=-arch ${DXVK_HOST_ARCH}" "${DXVK_PKG_CONFIG_ENV}" ${VULKAN_SDK_ENV_VAR} ${MESON_EXECUTABLE} setup ${DXVK_BUILD_DIR} ${DXVK_SOURCE_DIR} ${DXVK_MESON_MACHINE_ARGS} -Ddxvk_native_wsi=sdl3 --buildtype=release --reconfigure
      BUILD_COMMAND     ${NINJA_EXECUTABLE} -C ${DXVK_BUILD_DIR} src/d3d9/libdxvk_d3d9.0.dylib src/d3d8/libdxvk_d3d8.0.dylib
      INSTALL_COMMAND   ""
      UPDATE_DISCONNECTED TRUE
    )
  else()
    # GeneralsX @build copilot 01/04/2026 Pin remote DXVK to immutable commit produced by fix/macos-size_t-cstddef.
    set(DXVK_REMOTE_REF 46a3bc018bcae408d49d3c500e4e536a11f6789a)
    ExternalProject_Add(dxvk_macos_build
      # GeneralsX @build BenderAI 08/04/2026 Consume pre-patched source from pinned fork commit.
      GIT_REPOSITORY    https://github.com/fbraz3/dxvk.git
      GIT_TAG           ${DXVK_REMOTE_REF}
      # GeneralsX @build copilot 01/04/2026 Keep pinned commit fetch reliable across clean CI builds.
      GIT_SHALLOW       FALSE
      SOURCE_DIR        ${DXVK_SOURCE_DIR}
      BINARY_DIR        ${DXVK_BUILD_DIR}
      PATCH_COMMAND     ""
      CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env CC=clang CXX=clang++ "CFLAGS=-arch ${DXVK_HOST_ARCH} -mcpu=apple-m1" "CXXFLAGS=-arch ${DXVK_HOST_ARCH} -mcpu=apple-m1" "LDFLAGS=-arch ${DXVK_HOST_ARCH}" "${DXVK_PKG_CONFIG_ENV}" ${VULKAN_SDK_ENV_VAR} ${MESON_EXECUTABLE} setup ${DXVK_BUILD_DIR} ${DXVK_SOURCE_DIR} ${DXVK_MESON_MACHINE_ARGS} -Ddxvk_native_wsi=sdl3 --buildtype=release --reconfigure
      BUILD_COMMAND     ${NINJA_EXECUTABLE} -C ${DXVK_BUILD_DIR} src/d3d9/libdxvk_d3d9.0.dylib src/d3d8/libdxvk_d3d8.0.dylib
      INSTALL_COMMAND   ""
      UPDATE_DISCONNECTED FALSE
    )
  endif()

  # Copy libdxvk_d3d9 + libdxvk_d3d8 to build dir and create unversioned symlinks.
  # d3d8 links against d3d9 via @rpath, so both must be present at runtime.
  add_custom_command(
    OUTPUT  "${CMAKE_BINARY_DIR}/libdxvk_d3d9.0.dylib"
            "${CMAKE_BINARY_DIR}/libdxvk_d3d8.0.dylib"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
              ${DXVK_D3D9_LIB} "${CMAKE_BINARY_DIR}/libdxvk_d3d9.0.dylib"
    COMMAND ${CMAKE_COMMAND} -E create_symlink
              libdxvk_d3d9.0.dylib "${CMAKE_BINARY_DIR}/libdxvk_d3d9.dylib"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
              ${DXVK_D3D8_LIB} "${CMAKE_BINARY_DIR}/libdxvk_d3d8.0.dylib"
    COMMAND ${CMAKE_COMMAND} -E create_symlink
              libdxvk_d3d8.0.dylib "${CMAKE_BINARY_DIR}/libdxvk_d3d8.dylib"
    DEPENDS dxvk_macos_build
    COMMENT "Installing libdxvk_d3d8 + libdxvk_d3d9 to build directory"
  )
  add_custom_target(dxvk_d3d8_install ALL
    DEPENDS "${CMAKE_BINARY_DIR}/libdxvk_d3d8.0.dylib"
            "${CMAKE_BINARY_DIR}/libdxvk_d3d9.0.dylib"
  )

  # Export path so other cmake files know where the headers are
  set(DXVK_INCLUDE_DIR "${DXVK_SOURCE_DIR}/include/native" CACHE PATH "DXVK native headers")
  # GeneralsX @build felipebraz 10/06/2025 Mirror lowercase dxvk_SOURCE_DIR that FetchContent sets on Linux
  # so CompatLib/CMakeLists.txt check works on macOS as well (CACHE PATH survives auto-regeneration)
  set(dxvk_SOURCE_DIR "${DXVK_SOURCE_DIR}" CACHE PATH "DXVK source directory (macOS)")
  message(STATUS "DXVK source directory: ${DXVK_SOURCE_DIR}")
  message(STATUS "DXVK d3d8 library:     ${DXVK_D3D8_LIB}")

elseif(CMAKE_SYSTEM_NAME STREQUAL "Android" OR ANDROID)
  # Android: cross-build DXVK 2.6 (d3d8 + d3d9) for arm64-v8a with Meson + the NDK
  # clang toolchain. Analogous to the iOS/macOS fork build but simpler: native
  # Vulkan (no MoltenVK), .so outputs (not .dylib), and the NDK's per-API clang
  # wrappers drive the cross-compile via a generated meson cross file. The two
  # arm64 .so's package into jniLibs/arm64-v8a in Task 3.
  # GeneralsX @build FadiLabib 06/07/2026 - Phase 3 Android renderer (Task P3-2)
  find_program(MESON_EXECUTABLE meson)
  find_program(NINJA_EXECUTABLE ninja)
  # DXVK compiles its shaders to SPIR-V at build time with a *host* glslang.
  find_program(GLSLANG_EXECUTABLE NAMES glslangValidator glslang)

  if(NOT MESON_EXECUTABLE)
    message(FATAL_ERROR "DXVK Android build requires meson (apt install meson / pip install meson)")
  endif()
  if(NOT NINJA_EXECUTABLE)
    message(FATAL_ERROR "DXVK Android build requires ninja (apt install ninja-build)")
  endif()
  if(NOT GLSLANG_EXECUTABLE)
    message(FATAL_ERROR "DXVK Android build requires a host glslang/glslangValidator (apt install glslang-tools)")
  endif()

  # Resolve the NDK toolchain bin dir: the per-API clang wrappers
  # (aarch64-linux-android29-clang[++]) already embed -target and --sysroot, plus
  # llvm-ar / llvm-strip. Prefer $ANDROID_NDK_HOME, fall back to CMAKE_ANDROID_NDK
  # (set by android.toolchain.cmake).
  set(DXVK_ANDROID_NDK "$ENV{ANDROID_NDK_HOME}")
  if(NOT DXVK_ANDROID_NDK)
    set(DXVK_ANDROID_NDK "${CMAKE_ANDROID_NDK}")
  endif()
  if(NOT DXVK_ANDROID_NDK OR NOT EXISTS "${DXVK_ANDROID_NDK}")
    message(FATAL_ERROR "DXVK Android build requires ANDROID_NDK_HOME or CMAKE_ANDROID_NDK to point at an NDK")
  endif()
  file(GLOB DXVK_NDK_PREBUILT_DIRS "${DXVK_ANDROID_NDK}/toolchains/llvm/prebuilt/*")
  if(NOT DXVK_NDK_PREBUILT_DIRS)
    message(FATAL_ERROR "DXVK Android build: no prebuilt toolchain under ${DXVK_ANDROID_NDK}/toolchains/llvm/prebuilt")
  endif()
  list(GET DXVK_NDK_PREBUILT_DIRS 0 DXVK_NDK_HOST_DIR)
  set(ANDROID_NDK_BIN "${DXVK_NDK_HOST_DIR}/bin")
  if(NOT EXISTS "${ANDROID_NDK_BIN}/aarch64-linux-android29-clang")
    message(FATAL_ERROR "DXVK Android build: NDK clang wrapper not found at ${ANDROID_NDK_BIN}/aarch64-linux-android29-clang")
  endif()
  # @GLSLANG@ substituted into the cross file's [binaries] glslang entry.
  set(GLSLANG "${GLSLANG_EXECUTABLE}")
  message(STATUS "Building DXVK ${DXVK_VERSION} for Android/arm64-v8a with Meson (NDK bin: ${ANDROID_NDK_BIN}, glslang: ${GLSLANG})")

  include(ExternalProject)

  # Android must build from the local fbraz3 fork: it carries the macOS/iOS DXVK
  # work and receives Patches/dxvk-android.patch. A remote clone cannot be patched
  # idempotently here, so require the submodule (never build an unpatched tree).
  set(DXVK_LOCAL_FORK_DIR "${CMAKE_SOURCE_DIR}/references/fbraz3-dxvk")
  if(NOT EXISTS "${DXVK_LOCAL_FORK_DIR}/.git")
    message(FATAL_ERROR "Android DXVK requires the local fork submodule. Run: git submodule update --init --recursive references/fbraz3-dxvk")
  endif()
  set(DXVK_SOURCE_DIR "${DXVK_LOCAL_FORK_DIR}")
  message(STATUS "DXVK Android build: using local fork source at ${DXVK_SOURCE_DIR}")

  # The fork's nested submodules (Vulkan-Headers, SPIRV-Headers, mingw-directx-headers,
  # libdisplay-info) must be present for meson. Initialising gitlinks is build setup,
  # not a source edit. Non-fatal: if this fails offline the build surfaces missing headers.
  execute_process(
    COMMAND git -C "${DXVK_LOCAL_FORK_DIR}" submodule update --init --recursive
    RESULT_VARIABLE DXVK_ANDROID_SUBMOD_RESULT)
  if(NOT DXVK_ANDROID_SUBMOD_RESULT EQUAL 0)
    message(WARNING "DXVK Android: 'git submodule update --init --recursive' on the fork returned ${DXVK_ANDROID_SUBMOD_RESULT}; nested submodules may be missing")
  endif()

  # Apply Patches/dxvk-android.patch idempotently: skip when the working tree
  # already carries it (reverse-check passes), fail the configure otherwise so an
  # unpatched DXVK (portability-subset use sites unguarded) can never build silently.
  execute_process(
    COMMAND git -C "${DXVK_LOCAL_FORK_DIR}" apply --reverse --check "${CMAKE_SOURCE_DIR}/Patches/dxvk-android.patch"
    RESULT_VARIABLE DXVK_ANDROID_PATCH_ALREADY_APPLIED
    ERROR_QUIET)
  if(NOT DXVK_ANDROID_PATCH_ALREADY_APPLIED EQUAL 0)
    execute_process(
      COMMAND git -C "${DXVK_LOCAL_FORK_DIR}" apply "${CMAKE_SOURCE_DIR}/Patches/dxvk-android.patch"
      RESULT_VARIABLE DXVK_ANDROID_PATCH_RESULT)
    if(NOT DXVK_ANDROID_PATCH_RESULT EQUAL 0)
      message(FATAL_ERROR "Failed to apply Patches/dxvk-android.patch to references/fbraz3-dxvk — the Android DXVK build requires it.")
    endif()
    message(STATUS "DXVK Android: applied Patches/dxvk-android.patch")
  else()
    message(STATUS "DXVK Android: Patches/dxvk-android.patch already applied")
  endif()

  # Generate the meson cross file from the template, filling in the NDK bin dir
  # and the host glslang. The wrappers embed -target/--sysroot, so no arch/sysroot
  # flags are needed in [built-in options] (unlike the iOS file).
  configure_file(${CMAKE_SOURCE_DIR}/cmake/meson-arm64-android-cross.ini.in
                 ${CMAKE_BINARY_DIR}/meson-arm64-android-cross.ini @ONLY)

  # Generate a pkg-config for the in-tree (FetchContent) Android SDL3 so meson's
  # dependency('SDL3') resolves to it. File name MUST be capital SDL3.pc — Linux is
  # case-sensitive and dependency('SDL3') looks for SDL3.pc. Without it meson silently
  # falls back to a system SDL2 and compiles the WSI as Sdl2WsiDriver.
  set(DXVK_SDL3_PC_DIR "${CMAKE_BINARY_DIR}/sdl3-pkgconfig")
  file(WRITE "${DXVK_SDL3_PC_DIR}/SDL3.pc"
"prefix=${CMAKE_BINARY_DIR}/_deps
libdir=\${prefix}/sdl3-build
includedir=\${prefix}/sdl3-src/include

Name: SDL3
Description: Simple DirectMedia Layer (in-tree FetchContent build, Android arm64)
Version: 3.4.2
Libs: -L\${libdir} -lSDL3
Cflags: -I\${includedir}
")
  if(DEFINED ENV{PKG_CONFIG_PATH})
    set(DXVK_PKG_CONFIG_PATH "${DXVK_SDL3_PC_DIR}:$ENV{PKG_CONFIG_PATH}")
  else()
    set(DXVK_PKG_CONFIG_PATH "${DXVK_SDL3_PC_DIR}")
  endif()
  set(DXVK_PKG_CONFIG_ENV "PKG_CONFIG_PATH=${DXVK_PKG_CONFIG_PATH}")

  set(DXVK_BUILD_DIR "${CMAKE_BINARY_DIR}/_deps/dxvk-build-android")
  # meson emits plain libdxvk_d3d8.so / libdxvk_d3d9.so targets (versioned .so.0.*
  # + symlinks land alongside). d3d8 links d3d9 via a bare-name NEEDED.
  set(DXVK_D3D8_LIB "${DXVK_BUILD_DIR}/src/d3d8/libdxvk_d3d8.so")
  set(DXVK_D3D9_LIB "${DXVK_BUILD_DIR}/src/d3d9/libdxvk_d3d9.so")

  ExternalProject_Add(dxvk_android_build
    SOURCE_DIR        ${DXVK_SOURCE_DIR}
    BINARY_DIR        ${DXVK_BUILD_DIR}
    DOWNLOAD_COMMAND  ""
    UPDATE_COMMAND    ""
    PATCH_COMMAND     ""
    CONFIGURE_COMMAND ${CMAKE_COMMAND} -E env "${DXVK_PKG_CONFIG_ENV}" ${MESON_EXECUTABLE} setup ${DXVK_BUILD_DIR} ${DXVK_SOURCE_DIR} --cross-file ${CMAKE_BINARY_DIR}/meson-arm64-android-cross.ini -Ddxvk_native_wsi=sdl3 --buildtype=release --reconfigure
    BUILD_COMMAND     ${NINJA_EXECUTABLE} -C ${DXVK_BUILD_DIR} src/d3d9/libdxvk_d3d9.so src/d3d8/libdxvk_d3d8.so
    INSTALL_COMMAND   ""
    UPDATE_DISCONNECTED TRUE
  )

  # Copy the built arm64 .so's to a known location in the build dir so Task 3's
  # packaging (jniLibs/arm64-v8a) can find them. Plain names — Android's linker
  # resolves the bare-name d3d8->d3d9 NEEDED from nativeLibraryDir, no symlinks needed.
  add_custom_command(
    OUTPUT  "${CMAKE_BINARY_DIR}/libdxvk_d3d9.so"
            "${CMAKE_BINARY_DIR}/libdxvk_d3d8.so"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${DXVK_D3D9_LIB} "${CMAKE_BINARY_DIR}/libdxvk_d3d9.so"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${DXVK_D3D8_LIB} "${CMAKE_BINARY_DIR}/libdxvk_d3d8.so"
    DEPENDS dxvk_android_build
    COMMENT "Installing libdxvk_d3d8 + libdxvk_d3d9 (arm64) to build directory"
  )
  add_custom_target(dxvk_d3d8_install ALL
    DEPENDS "${CMAKE_BINARY_DIR}/libdxvk_d3d8.so"
            "${CMAKE_BINARY_DIR}/libdxvk_d3d9.so"
  )

  # Export the fork header layout (include/native/...) — CompatLib consumes these
  # like the macOS build. CACHE PATH survives auto-regeneration.
  set(DXVK_INCLUDE_DIR "${DXVK_SOURCE_DIR}/include/native" CACHE PATH "DXVK native headers")
  set(dxvk_SOURCE_DIR "${DXVK_SOURCE_DIR}" CACHE PATH "DXVK source directory (Android)")
  message(STATUS "DXVK source directory: ${DXVK_SOURCE_DIR}")
  message(STATUS "DXVK d3d8 library:     ${DXVK_D3D8_LIB}")

else()
  # Linux: Fetch pre-built DXVK native binary for DirectX→Vulkan translation
  # Native 32-bit and 64-bit Linux binaries (.so)
  FetchContent_Declare(
    dxvk
    URL        https://github.com/doitsujin/dxvk/releases/download/v2.6/dxvk-native-2.6-steamrt-sniper.tar.gz
  )
  FetchContent_MakeAvailable(dxvk)
  message(STATUS "Using DXVK native (Linux DirectX→Vulkan)")
  message(STATUS "DXVK source directory: ${dxvk_SOURCE_DIR}")
endif()
