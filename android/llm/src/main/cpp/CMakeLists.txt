cmake_minimum_required(VERSION 3.22)
project(echollm C CXX)

include(FetchContent)
FetchContent_Declare(llama
    URL https://github.com/ggml-org/llama.cpp/archive/refs/tags/b11840.tar.gz)

set(GGML_NATIVE OFF CACHE BOOL "" FORCE)
set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
set(GGML_OPENMP OFF CACHE BOOL "" FORCE)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_COMMON OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_TOOLS OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
set(LLAMA_BUILD_SERVER OFF CACHE BOOL "" FORCE)
set(LLAMA_CURL OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(llama)

add_library(echollm SHARED llm_jni.cpp)
target_link_libraries(echollm PRIVATE llama log android)
# Keep ggml private to this library so it can't clash with the copy inside the Whisper library.
target_link_options(echollm PRIVATE "-Wl,--exclude-libs,ALL" "-Wl,--gc-sections")
target_compile_options(echollm PRIVATE -O3)
