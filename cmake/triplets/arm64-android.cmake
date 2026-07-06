# Overlay triplet: pin the Android API level so vcpkg-built static libs match
# the engine's ANDROID_PLATFORM (pattern: arm64-ios.cmake pins the iOS target).
set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME Android)
set(VCPKG_CMAKE_SYSTEM_VERSION 29)
set(VCPKG_MAKE_BUILD_TRIPLET "--host=aarch64-linux-android")
# GeneralsX @build FadiLabib 06/07/2026 vcpkg's android.cmake toolchain does NOT
# derive ANDROID_ABI from VCPKG_TARGET_ARCHITECTURE — it just includes the NDK
# toolchain, which then defaults to armeabi-v7a (32-bit). Without this line every
# port builds elf32-littlearm and find_package rejects them against the arm64
# project (freetype-config reports "(32bit)"). Matches vcpkg's built-in triplet.
set(VCPKG_CMAKE_CONFIGURE_OPTIONS -DANDROID_ABI=arm64-v8a)
