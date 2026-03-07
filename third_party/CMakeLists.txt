cmake_minimum_required(VERSION 3.20)
project(CometImageCodecDependencies)

# Set universal binary architectures
set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "Build architectures for macOS")
set(CMAKE_OSX_DEPLOYMENT_TARGET "13.0" CACHE STRING "Minimum macOS deployment version")

# Optimization flags
set(CMAKE_C_FLAGS_RELEASE "-O3 -flto" CACHE STRING "C compiler flags for Release")
set(CMAKE_CXX_FLAGS_RELEASE "-O3 -flto" CACHE STRING "C++ compiler flags for Release")

# Build type
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE Release)
endif()

# libwebp configuration
set(WEBP_BUILD_ANIM_UTILS OFF CACHE BOOL "Build animation utilities")
set(WEBP_BUILD_CWEBP OFF CACHE BOOL "Build cwebp")
set(WEBP_BUILD_DWEBP OFF CACHE BOOL "Build dwebp")
set(WEBP_BUILD_GIF2WEBP OFF CACHE BOOL "Build gif2webp")
set(WEBP_BUILD_IMG2WEBP OFF CACHE BOOL "Build img2webp")
set(WEBP_BUILD_VWEBP OFF CACHE BOOL "Build vwebp")
set(WEBP_BUILD_WEBPINFO OFF CACHE BOOL "Build webpinfo")
set(WEBP_BUILD_WEBPMUX OFF CACHE BOOL "Build webpmux")
set(WEBP_BUILD_EXTRAS OFF CACHE BOOL "Build extras")
add_subdirectory(libwebp)

# libavif configuration
set(AVIF_CODEC_AOM LOCAL CACHE STRING "Use AOM codec (build locally)")
set(AVIF_LIBYUV LOCAL CACHE STRING "Build libyuv locally")
set(AVIF_BUILD_APPS OFF CACHE BOOL "Build avif apps")
set(AVIF_BUILD_TESTS OFF CACHE BOOL "Build avif tests")
set(AVIF_BUILD_EXAMPLES OFF CACHE BOOL "Build avif examples")
add_subdirectory(libavif)

# Installation
install(TARGETS webp webpdemux
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
)

install(TARGETS avif
    ARCHIVE DESTINATION lib
    LIBRARY DESTINATION lib
)
