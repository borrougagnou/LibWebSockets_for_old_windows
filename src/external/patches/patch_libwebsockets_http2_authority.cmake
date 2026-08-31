# libwebsockets 4.3-stable HTTP/2 :authority compatibility patch.
#
# libwebsockets 4.3-stable sends a normal Host header for HTTP/2 client
# requests while the :authority pseudo-header code is disabled with #if 0.
# Strict HTTP/2 servers can reject that request.
#
# Newer libwebsockets versions send the authority using the HTTP/2
# :authority pseudo-header instead of a normal Host header.

if(NOT DEFINED LWS_SOURCE_DIR)

    message(
        FATAL_ERROR
        "LWS_SOURCE_DIR is not defined"
    )

endif()


set(
    lws_http2_file
    "${LWS_SOURCE_DIR}/lib/roles/h2/http2.c"
)


if(NOT EXISTS "${lws_http2_file}")

    message(
        FATAL_ERROR
        "libwebsockets HTTP/2 source file not found: ${lws_http2_file}"
    )

endif()


file(
    READ
    "${lws_http2_file}"
    lws_http2_source
)


set(
    old_http2_authority_code
"//\tn = lws_hdr_total_length(wsi, _WSI_TOKEN_CLIENT_ORIGIN);
//\tsimp = lws_hdr_simple_ptr(wsi, _WSI_TOKEN_CLIENT_ORIGIN);
#if 0
\tif (n && simp && lws_add_http_header_by_token(wsi,
\t\t\t\tWSI_TOKEN_HTTP_COLON_AUTHORITY,
\t\t\t\t(unsigned char *)simp, n, &p, end))
\t\tgoto fail_length;
#endif


\tif (/*!wsi->client_h2_alpn && */n && simp &&
\t    lws_add_http_header_by_token(wsi, WSI_TOKEN_HOST,
\t\t\t\t(unsigned char *)simp, n, &p, end))
\t\tgoto fail_length;"
)


set(
    new_http2_authority_code
"//\tn = lws_hdr_total_length(wsi, _WSI_TOKEN_CLIENT_ORIGIN);
//\tsimp = lws_hdr_simple_ptr(wsi, _WSI_TOKEN_CLIENT_ORIGIN);

\tif (n && simp && lws_add_http_header_by_token(wsi,
\t\t\t\tWSI_TOKEN_HTTP_COLON_AUTHORITY,
\t\t\t\t(unsigned char *)simp, n, &p, end))
\t\tgoto fail_length;"
)


string(
    FIND
    "${lws_http2_source}"
    "${new_http2_authority_code}"
    http2_authority_already_patched
)


if(http2_authority_already_patched EQUAL -1)

    string(
        FIND
        "${lws_http2_source}"
        "${old_http2_authority_code}"
        http2_authority_position
    )

    if(http2_authority_position EQUAL -1)

        message(
            FATAL_ERROR
            "Unable to find the libwebsockets 4.3 HTTP/2 Host/:authority code to patch"
        )

    endif()

    string(
        REPLACE
        "${old_http2_authority_code}"
        "${new_http2_authority_code}"
        lws_http2_source
        "${lws_http2_source}"
    )

    file(
        WRITE
        "${lws_http2_file}"
        "${lws_http2_source}"
    )

    message(
        STATUS
        "Patched libwebsockets HTTP/2 :authority handling"
    )

else()

    message(
        STATUS
        "libwebsockets HTTP/2 :authority handling already patched"
    )

endif()
