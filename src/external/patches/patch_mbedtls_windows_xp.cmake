if(NOT MBEDTLS_MINGW_BUILD)
    message(STATUS "Mbed TLS Windows XP MinGW patch: not a MinGW build, skipping")
    return()
endif()

set(
    MBEDTLS_PLATFORM_FILE
    "${MBEDTLS_SOURCE_DIR}/library/platform.c"
)

if(NOT EXISTS "${MBEDTLS_PLATFORM_FILE}")
    message(
        FATAL_ERROR
        "Mbed TLS platform.c not found: ${MBEDTLS_PLATFORM_FILE}"
    )
endif()

file(
    READ
    "${MBEDTLS_PLATFORM_FILE}"
    MBEDTLS_PLATFORM_CONTENT
)

set(
    OLD_CODE
"#if defined(_TRUNCATE)
    ret = vsnprintf_s(s, n, _TRUNCATE, fmt, arg);"
)

set(
    NEW_CODE
"#if defined(_TRUNCATE) && !defined(__MINGW32__)
    ret = vsnprintf_s(s, n, _TRUNCATE, fmt, arg);"
)

string(
    FIND
    "${MBEDTLS_PLATFORM_CONTENT}"
    "${NEW_CODE}"
    PATCH_ALREADY_APPLIED
)

if(NOT PATCH_ALREADY_APPLIED EQUAL -1)

    message(
        STATUS
        "Mbed TLS Windows XP MinGW patch already applied"
    )

    return()

endif()

string(
    FIND
    "${MBEDTLS_PLATFORM_CONTENT}"
    "${OLD_CODE}"
    PATCH_LOCATION
)

if(PATCH_LOCATION EQUAL -1)

    message(
        FATAL_ERROR
        "Unable to find the Mbed TLS vsnprintf_s code to patch"
    )

endif()

string(
    REPLACE
    "${OLD_CODE}"
    "${NEW_CODE}"
    MBEDTLS_PLATFORM_CONTENT
    "${MBEDTLS_PLATFORM_CONTENT}"
)

file(
    WRITE
    "${MBEDTLS_PLATFORM_FILE}"
    "${MBEDTLS_PLATFORM_CONTENT}"
)

message(
    STATUS
    "Applied Mbed TLS Windows XP MinGW vsnprintf_s patch"
)
