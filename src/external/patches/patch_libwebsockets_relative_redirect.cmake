# libwebsockets 4.3-stable relative HTTP redirect fix.
#
# In v4.3.10, the redirect classifier treats every Location value without
# a ':' as an absolute-path redirect:
#
#     if (p[0] == '/' || !strchr(p, ':')) {
#
# That makes the later relative-path branch unreachable for values such as:
#
#     Location: 2
#
# For a request to /redirect/3, that should resolve relative to the current
# path instead of becoming /2.

if(NOT DEFINED LWS_SOURCE_DIR)
    message(FATAL_ERROR "LWS_SOURCE_DIR is not defined")
endif()

set(client_http_file
    "${LWS_SOURCE_DIR}/lib/roles/http/client/client-http.c"
)

if(NOT EXISTS "${client_http_file}")
    message(FATAL_ERROR
        "libwebsockets HTTP client source file not found: ${client_http_file}"
    )
endif()

file(READ
    "${client_http_file}"
    client_http_source
)

set(relative_redirect_old
"\t\tif (p[0] == '/' || !strchr(p, ':')) {"
)

set(relative_redirect_new
"\t\tif (p[0] == '/') {"
)

string(FIND
    "${client_http_source}"
    "${relative_redirect_old}"
    relative_redirect_match
)

if(relative_redirect_match EQUAL -1)

    string(FIND
        "${client_http_source}"
        "${relative_redirect_new}"
        relative_redirect_already_patched
    )

    if(relative_redirect_already_patched EQUAL -1)
        message(FATAL_ERROR
            "Unable to patch ${client_http_file}: "
            "the libwebsockets 4.3 relative redirect condition was not found"
        )
    endif()

    message(STATUS
        "libwebsockets relative redirect handling already patched"
    )

else()

    string(REPLACE
        "${relative_redirect_old}"
        "${relative_redirect_new}"
        client_http_source
        "${client_http_source}"
    )

    file(WRITE
        "${client_http_file}"
        "${client_http_source}"
    )

    message(STATUS
        "Patched libwebsockets relative redirect handling"
    )

endif()
