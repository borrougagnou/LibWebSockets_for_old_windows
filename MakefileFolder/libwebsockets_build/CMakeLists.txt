# HOW TO USE:

### Normal build
## cmake -S MakefileFolder/libwebsockets_build -B build/lws_deps/build
## cmake --build build/lws_deps/build

### Normal build with DEBUG REDIRECT PATCH
## cmake -S MakefileFolder/libwebsockets_build -B build/lws_deps/build -DLWS_DEBUG_REDIRECT_PATCH=ON
## cmake --build build/lws_deps/build

### Visual Studio build
## cmake -S MakefileFolder/libwebsockets_build -B build/lws_deps/build -G "Visual Studio 17 2022" -A Win32 -T v141_xp
## cmake --build build/lws_deps/build --config Release


# IMPORTANT TO REMEMBER !!!
# This file is in MakefileFolder/libwebsockets_build/
# ROOT_DIR is two levels up from this file !

cmake_minimum_required(VERSION 3.10)
project(Libwebsockets)

# built-in CMake module that provides `ExternalProject_Add()` command
# Allows downloading, configuring, building and installing external projects.
include(ExternalProject)

get_filename_component(ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../.." ABSOLUTE)
set(BUILD_BASE "${ROOT_DIR}/build/lws_deps")
set(SRC_DIR "${BUILD_BASE}/src")
set(BUILD_DIR "${BUILD_BASE}/obj")


### OS and Arch Detection
if(WIN32)

    if(CMAKE_SIZEOF_VOID_P EQUAL 8)
        set(OS_FOLDER "Windows-x64")
    else()
        set(OS_FOLDER "Windows-x32")
    endif()

elseif(APPLE)

    set(OS_FOLDER "Mac")

elseif(UNIX)

    set(OS_FOLDER "Linux")

else()

    message(FATAL_ERROR "Unsupported operating system")

endif()

set(INSTALL_DIR "${ROOT_DIR}/src/external/libwebsockets/${OS_FOLDER}")

### Windows XP SP3 Support Flag
set(EXTRA_C_FLAGS "")
if(WIN32 AND MINGW)
    set(EXTRA_C_FLAGS "-D_WIN32_WINNT=0x0501")
endif()


# DEBUG patches (if enabled)
option(LWS_DEBUG_REDIRECT_PATCH "Apply the libwebsockets DEBUG redirect patch"      OFF)
option(LWS_DEBUG_MBEDTLS_PATCH  "Apply the libwebsockets DEBUG mbedTLS error patch" OFF)


# CMake Flags
set(COMMON_CMAKE_ARGS
    -DCMAKE_INSTALL_PREFIX=${INSTALL_DIR}
    -DBUILD_SHARED_LIBS=OFF
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_C_FLAGS=${EXTRA_C_FLAGS}
)


## BUILD PART -----------------

# 1. Build zlib
ExternalProject_Add(zlib
    GIT_REPOSITORY https://github.com/madler/zlib.git
    GIT_TAG v1.3.2
    GIT_SHALLOW TRUE
    SOURCE_DIR ${SRC_DIR}/zlib
    BINARY_DIR ${BUILD_DIR}/zlib
    CMAKE_ARGS
        ${COMMON_CMAKE_ARGS}
        -DSKIP_INSTALL_SHARED_LIB=ON
)

# 2. Build mbedTLS
ExternalProject_Add(mbedtls
    GIT_REPOSITORY https://github.com/Mbed-TLS/mbedtls.git
    GIT_TAG v2.28.9
    GIT_SHALLOW TRUE
    SOURCE_DIR ${SRC_DIR}/mbedtls
    BINARY_DIR ${BUILD_DIR}/mbedtls

    # Windows XP / MinGW:
    # prevent Mbed TLS from importing _vsnprintf_s from msvcrt.dll
    PATCH_COMMAND
        ${CMAKE_COMMAND}
            -DMBEDTLS_MINGW_BUILD=${MINGW}
            -DMBEDTLS_SOURCE_DIR=<SOURCE_DIR>
            -P "${ROOT_DIR}/src/external/patches/patch_mbedtls_windows_xp.cmake"

    CMAKE_ARGS
        ${COMMON_CMAKE_ARGS}
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        -DENABLE_PROGRAMS=OFF
        -DENABLE_TESTING=OFF
    DEPENDS zlib
)

# 3. Build nghttp2
ExternalProject_Add(nghttp2
    GIT_REPOSITORY https://github.com/nghttp2/nghttp2.git
    GIT_TAG v1.70.0
    GIT_SHALLOW TRUE
    SOURCE_DIR ${SRC_DIR}/nghttp2
    BINARY_DIR ${BUILD_DIR}/nghttp2

    CMAKE_ARGS
        ${COMMON_CMAKE_ARGS}
        -DENABLE_LIB_ONLY=ON
        -DBUILD_STATIC_LIBS=ON
        -DENABLE_DOC=OFF
        -DBUILD_TESTING=OFF
        -DENABLE_FAILMALLOC=OFF
        -DWITH_OPENSSL=OFF
        -DWITH_LIBNGTCP2=OFF
        -DWITH_LIBNGHTTP3=OFF
    DEPENDS mbedtls
)

# 4. Build libwebsockets
ExternalProject_Add(libwebsockets
    GIT_REPOSITORY https://github.com/warmcat/libwebsockets.git
    GIT_TAG v4.3.10
    GIT_SHALLOW TRUE
    SOURCE_DIR ${SRC_DIR}/lws
    BINARY_DIR ${BUILD_DIR}/lws

    ### Patch hardcoded Windows 7 (0x0601) target to Windows XP (0x0501)
    PATCH_COMMAND
        ${CMAKE_COMMAND}
            -DLWS_WINDOWS_BUILD=${WIN32}
            -DLWS_SOURCE_DIR=<SOURCE_DIR>
            -P "${ROOT_DIR}/src/external/patches/patch_libwebsockets_windows_xp.cmake"

        # Patch the v4.3 for XP Compatibility
        COMMAND
        ${CMAKE_COMMAND}
            -DLWS_WINDOWS_BUILD=${WIN32}
            -DLWS_SOURCE_DIR=<SOURCE_DIR>
            -P "${ROOT_DIR}/src/external/patches/patch_libwebsockets_windows_xp_source_compatibility.cmake"

        # Patch the v4.3 authority bug (all OS)
        COMMAND
        ${CMAKE_COMMAND}
            -DLWS_SOURCE_DIR=<SOURCE_DIR>
            -P "${ROOT_DIR}/src/external/patches/patch_libwebsockets_http2_authority.cmake"

	# Patch the v4.3 about the relative redirect URL
        COMMAND
        ${CMAKE_COMMAND}
            -DLWS_SOURCE_DIR=<SOURCE_DIR>
            -P "${ROOT_DIR}/src/external/patches/patch_libwebsockets_relative_redirect.cmake"


    CMAKE_ARGS
        ${COMMON_CMAKE_ARGS}
        -DCMAKE_POLICY_VERSION_MINIMUM=3.5
        -DCMAKE_PREFIX_PATH=${INSTALL_DIR}
        -DDISABLE_WERROR=ON
        ### SSL / mbedTLS
        -DLWS_WITH_SSL=ON
        -DLWS_WITH_MBEDTLS=ON
        -DLWS_MBEDTLS_INCLUDE_DIRS=${INSTALL_DIR}/include
        -DLWS_MBEDTLS_LIBRARIES=${INSTALL_DIR}/lib/libmbedtls.a;${INSTALL_DIR}/lib/libmbedx509.a;${INSTALL_DIR}/lib/libmbedcrypto.a
        -DLWS_HAVE_mbedtls_ssl_conf_alpn_protocols=ON
        -DLWS_HAVE_mbedtls_ssl_get_alpn_protocol=ON
        ### zlib
        -DLWS_WITH_ZLIB=ON
        -DLWS_WITH_BUNDLED_ZLIB=OFF
        -DLWS_ZLIB_INCLUDE_DIRS=${INSTALL_DIR}/include
        -DLWS_ZLIB_LIBRARIES=${INSTALL_DIR}/lib/libzlibstatic.a
        ### HTTP/2
        -DLWS_WITH_HTTP2=ON
        ### Static library
        -DLWS_WITH_STATIC=ON
        -DLWS_WITH_SHARED=OFF
        ### Extensions
        -DLWS_WITHOUT_EXTENSIONS=OFF
        ### Disable test applications
        -DLWS_WITHOUT_TESTAPPS=ON
        -DLWS_WITHOUT_TEST_SERVER=ON
        -DLWS_WITHOUT_TEST_SERVER_EXTPOLL=ON
        -DLWS_WITHOUT_TEST_PING=ON
        -DLWS_WITHOUT_TEST_CLIENT=ON
        ### Disable examples
        -DLWS_WITH_MINIMAL_EXAMPLES=OFF

    DEPENDS nghttp2
)

