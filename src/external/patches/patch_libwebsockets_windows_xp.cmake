if(NOT DEFINED LWS_SOURCE_DIR)
    message(FATAL_ERROR "LWS_SOURCE_DIR is not defined")
endif()

set(LWS_CMAKE_FILE "${LWS_SOURCE_DIR}/CMakeLists.txt")

if(NOT EXISTS "${LWS_CMAKE_FILE}")
    message(FATAL_ERROR "libwebsockets CMakeLists.txt not found: ${LWS_CMAKE_FILE}")
endif()

file(READ "${LWS_CMAKE_FILE}" FILE_CONTENT)

string(REPLACE
    "0x0601"
    "0x0501"
    PATCHED_CONTENT
    "${FILE_CONTENT}"
)

if(FILE_CONTENT STREQUAL PATCHED_CONTENT)
    message(STATUS "libwebsockets Windows XP patch: nothing to change")
else()
    file(WRITE "${LWS_CMAKE_FILE}" "${PATCHED_CONTENT}")
    message(STATUS "libwebsockets Windows XP patch: 0x0601 -> 0x0501")
endif()

