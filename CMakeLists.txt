# HOW TO USE:
# mkdir cmake-build
# cd cmake-build
# cmake ..
# cmake --build .
#
# Windows architecture can be selected with:
# cmake -DARCH=x64 ..
# cmake -DARCH=x32 ..
## Or with Visual Studio (64):
# cmake -S . -B cmake-build-x64 -A x64
# cmake --build cmake-build-x64
# For Visual Studio (32):
# cmake -S . -B cmake-build-x32 -A Win32
# cmake --build cmake-build-x32

cmake_minimum_required(VERSION 3.15)
project(CHILKEY_ND104_Multitool C CXX)

set(CMAKE_CXX_STANDARD 11)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY         "${CMAKE_BINARY_DIR}")
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}")


# PLATFORM DETECTION
set(ARCH "x64" CACHE STRING "Target architecture")
if (WIN32)

	message(STATUS "Windows Detected")
	message(STATUS "Architecture: ${ARCH}")

	# LibWebSockets library
	set(LWS_TEST_INSTALL ${CMAKE_SOURCE_DIR}/src/external/libwebsockets/Windows-${ARCH})
	set(LWS_TEST_LIBRARY ${LWS_TEST_INSTALL}/lib/libwebsockets_static.a)

elseif(APPLE)

	message(STATUS "MacOS Detected")

	# LibWebSockets library
	set(LWS_TEST_INSTALL ${CMAKE_SOURCE_DIR}/src/external/libwebsockets/Mac)
	set(LWS_TEST_LIBRARY ${LWS_TEST_INSTALL}/lib/libwebsockets.a)

else()

	message(STATUS "Linux Detected")

	# LibWebSockets library
	set(LWS_TEST_INSTALL ${CMAKE_SOURCE_DIR}/src/external/libwebsockets/Linux)
	set(LWS_TEST_LIBRARY ${LWS_TEST_INSTALL}/lib/libwebsockets.a)

endif()


# LibWebSockets must already be built
if(NOT EXISTS ${LWS_TEST_LIBRARY})
	message(FATAL_ERROR "libwebsockets library not found: ${LWS_TEST_LIBRARY}")
endif()

# Static MinGW runtime on Windows (make executables independent of MinGW runtime DLLs)
if(WIN32 AND CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
	add_link_options(-static -static-libgcc -static-libstdc++)
endif()

# TEST LibWebSockets Test Program
add_executable(lws_lib_test             src/unit_test/test_libwebsockets_lib.cpp)
add_executable(lws_lib_test_compression src/unit_test/test_libwebsockets_lib_with_compression.cpp)

### Lib by Program ----------------

# Programs who need LibWebSockets
set(LWS_PROGRAMS
	lws_lib_test
	lws_lib_test_compression
)

### Lib config ----------------

# LibWebSockets Config
foreach(PROGRAM ${LWS_PROGRAMS})
	# Allow the use of: "#include <libwebsockets.h>"
	target_include_directories(${PROGRAM} PRIVATE ${LWS_TEST_INSTALL}/include)
	# Equiv to: "-L$(LWS_TEST_INSTALL)/lib"
	target_link_directories(${PROGRAM} PRIVATE ${LWS_TEST_INSTALL}/lib)
endforeach()


### Libraries -----------------

if(WIN32)

	# LibWebSockets libraries
	foreach(PROGRAM ${LWS_PROGRAMS})
		# Static LWS applications on Windows
		target_compile_definitions(${PROGRAM} PRIVATE LWS_STATICLIB)
		target_link_libraries(${PROGRAM}
			websockets_static
			mbedtls
			mbedx509
			mbedcrypto
			z
			nghttp2
			ws2_32
			userenv
			crypt32
			iphlpapi
		)
	endforeach()

elseif(APPLE)

	# LibWebSockets libraries
	foreach(PROGRAM ${LWS_PROGRAMS})
		target_link_libraries(${PROGRAM}
			websockets
			mbedtls
			mbedx509
			mbedcrypto
			z
			nghttp2
			pthread
		)
	endforeach()

else()

	# LibWebSockets libraries
	foreach(PROGRAM ${LWS_PROGRAMS})
		target_link_libraries(${PROGRAM}
			websockets
			mbedtls
			mbedx509
			mbedcrypto
			z
			nghttp2
			pthread
			dl
			m
		)
	endforeach()

endif()

