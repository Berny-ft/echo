cmake_minimum_required(VERSION 3.22)
project(echowhisper C CXX)

include(FetchContent)
FetchContent_Declare(whisper
    URL https://github.com/ggml-org/whisper.cpp/archive/refs/tags/v1.9.5.tar.gz)

# Tensor G2 (Pixel 7) and newer: ARMv8.2 with dot-product and fp16 arithmetic.
set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(WHISPER_BUILD_SERVER OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(whisper)

add_library(echowhisper SHARED whisper_jni.cpp)
target_link_libraries(echowhisper PRIVATE whisper log android)
# Keep ggml private to this library so it can't clash with the copy inside the LLM library.
target_link_options(echowhisper PRIVATE "-Wl,--exclude-libs,ALL" "-Wl,--gc-sections")
target_compile_options(echowhisper PRIVATE -O3)
