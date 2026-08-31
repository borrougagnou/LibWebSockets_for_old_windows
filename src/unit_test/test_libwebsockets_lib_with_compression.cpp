#include <libwebsockets.h>
#include <zlib.h>

#include <chrono>
#include <cstddef>
#include <cstring>
#include <iostream>
#include <string>


static const char        http_user_agent[]                  = "libwebsockets-test/1.0";
static const char        http_accept_encoding[]             = "gzip, deflate";
static const std::size_t http_read_buffer_size              = 4096u;
static const std::size_t http_decompression_buffer_size     = 4096u;
static const std::size_t http_maximum_response_size         = 1024u * 1024u;
static const int         network_timeout_seconds            = 10;
static const int         request_timeout_seconds            = 20;


struct http_test_state {
    z_stream     decompression_stream;
    std::string  body;
    std::string  error_message;
    std::string  content_encoding;
    std::string  content_type;
    std::string  content_length;
    std::string  transfer_encoding;
    std::size_t  received_size;
    unsigned int status_code;
    bool         decompression_initialized;
    bool         decompression_finished;
    bool         done;
    bool         failed;
};


static int http_callback(struct lws *wsi, enum lws_callback_reasons reason, void *user, void *in, std::size_t len)
{
    http_test_state *state;
    unsigned char   **header_position;
    unsigned char   *header_end;
    unsigned char   decompression_buffer[http_decompression_buffer_size];
    char            read_buffer[LWS_PRE + http_read_buffer_size];
    char            header_buffer[256];
    char            *read_position;
    std::size_t     decompressed_size;
    int             header_length;
    int             read_size;
    int             zlib_result;
    int             zlib_window_bits;

    state = static_cast<http_test_state*>(user);

    if (!state && wsi)
        state = static_cast<http_test_state*>(lws_context_user(lws_get_context(wsi)));

    if (!state)
        return 0;

    switch (reason)
    {
        case LWS_CALLBACK_CLIENT_CONNECTION_ERROR:
        {
            if (in && len != 0u)
                state->error_message.assign(static_cast<const char*>(in), len);
            else
                state->error_message = "The HTTP connection failed";

            state->failed = true;
            state->done   = true;

            if (wsi)
                lws_cancel_service(lws_get_context(wsi));

            return 0;
        }

        case LWS_CALLBACK_CLIENT_APPEND_HANDSHAKE_HEADER:
        {
            if (!wsi || !in)
            {
                state->error_message = "Unable to create the HTTP request headers";
                state->failed        = true;
                state->done          = true;
                return -1;
            }

            header_position = reinterpret_cast<unsigned char**>(in);

            if (!header_position || !*header_position)
            {
                state->error_message = "Unable to create the HTTP request headers";
                state->failed        = true;
                state->done          = true;
                return -1;
            }

            header_end = *header_position + len;

            if (lws_add_http_header_by_name(
                    wsi,
                    reinterpret_cast<const unsigned char*>("user-agent:"),
                    reinterpret_cast<const unsigned char*>(http_user_agent),
                    sizeof(http_user_agent) - 1u,
                    header_position,
                    header_end))
            {
                state->error_message = "Unable to add the User-Agent header";
                state->failed        = true;
                state->done          = true;
                return -1;
            }

            if (lws_add_http_header_by_name(
                    wsi,
                    reinterpret_cast<const unsigned char*>("accept-encoding:"),
                    reinterpret_cast<const unsigned char*>(http_accept_encoding),
                    sizeof(http_accept_encoding) - 1u,
                    header_position,
                    header_end))
            {
                state->error_message = "Unable to add the Accept-Encoding header";
                state->failed        = true;
                state->done          = true;
                return -1;
            }

            return 0;
        }

        case LWS_CALLBACK_ESTABLISHED_CLIENT_HTTP:
        {
            state->status_code = lws_http_client_http_response(wsi);

            state->content_encoding.clear();
            state->content_type.clear();
            state->content_length.clear();
            state->transfer_encoding.clear();

            header_length = lws_hdr_copy(
                              wsi,
                              header_buffer,
                              static_cast<int>(sizeof(header_buffer)),
                              WSI_TOKEN_HTTP_CONTENT_ENCODING);

            if (header_length > 0)
                state->content_encoding.assign(header_buffer, static_cast<std::size_t>(header_length));

            header_length = lws_hdr_copy(
                              wsi,
                              header_buffer,
                              static_cast<int>(sizeof(header_buffer)),
                              WSI_TOKEN_HTTP_CONTENT_TYPE);

            if (header_length > 0)
                state->content_type.assign(header_buffer, static_cast<std::size_t>(header_length));

            header_length = lws_hdr_copy(
                              wsi,
                              header_buffer,
                              static_cast<int>(sizeof(header_buffer)),
                              WSI_TOKEN_HTTP_CONTENT_LENGTH);

            if (header_length > 0)
                state->content_length.assign(header_buffer, static_cast<std::size_t>(header_length));

            header_length = lws_hdr_copy(
                              wsi,
                              header_buffer,
                              static_cast<int>(sizeof(header_buffer)),
                              WSI_TOKEN_HTTP_TRANSFER_ENCODING);

            if (header_length > 0)
                state->transfer_encoding.assign(header_buffer, static_cast<std::size_t>(header_length));

            zlib_window_bits = 0;

            if (state->content_encoding == "gzip")
                zlib_window_bits = 16 + MAX_WBITS;
            else if (state->content_encoding == "deflate")
                zlib_window_bits = MAX_WBITS;
            else if (!state->content_encoding.empty()
                  && state->content_encoding != "identity")
            {
                state->error_message = "Unsupported Content-Encoding: "
                                     + state->content_encoding;
                state->failed        = true;
                state->done          = true;
                return -1;
            }


            if (zlib_window_bits != 0)
            {
                std::memset(&state->decompression_stream, 0, sizeof(state->decompression_stream));

                zlib_result = inflateInit2(&state->decompression_stream, zlib_window_bits);
                if (zlib_result != Z_OK)
                {
                    state->error_message = "Unable to initialize zlib decompression";
                    state->failed        = true;
                    state->done          = true;
                    return -1;
                }

                state->decompression_initialized = true;
                state->decompression_finished    = false;
            }

            return 0;
        }

        case LWS_CALLBACK_RECEIVE_CLIENT_HTTP:
        {
            read_position = read_buffer + LWS_PRE;
            read_size     = static_cast<int>(sizeof(read_buffer) - LWS_PRE);

            if (lws_http_client_read(wsi, &read_position, &read_size) < 0)
            {
                state->error_message = "Unable to read the HTTP response";
                state->failed        = true;
                state->done          = true;
                return -1;
            }

            return 0;
        }

        case LWS_CALLBACK_RECEIVE_CLIENT_HTTP_READ:
        {
            if (!in || len == 0u)
                return 0;

            state->received_size += len;
            if (!state->decompression_initialized)
            {
                if (len > http_maximum_response_size || state->body.size() > http_maximum_response_size - len)
                {
                    state->error_message = "HTTP response exceeded the maximum allowed size";
                    state->failed        = true;
                    state->done          = true;
                    return -1;
                }

                state->body.append(static_cast<const char*>(in), len);

                return 0;
            }


            if (state->decompression_finished)
            {
                state->error_message = "Received data after the compressed stream ended";
                state->failed        = true;
                state->done          = true;
                return -1;
            }


            state->decompression_stream.next_in  = reinterpret_cast<Bytef*>(in);
            state->decompression_stream.avail_in = static_cast<uInt>(len);

            do
            {
                state->decompression_stream.next_out  = decompression_buffer;
                state->decompression_stream.avail_out = static_cast<uInt>(sizeof(decompression_buffer));

                zlib_result = inflate(&state->decompression_stream, Z_NO_FLUSH);

                decompressed_size = sizeof(decompression_buffer) - state->decompression_stream.avail_out;
                if (decompressed_size != 0u)
                {
                    if (decompressed_size > http_maximum_response_size
                     || state->body.size() > http_maximum_response_size - decompressed_size)
                    {
                        state->error_message = "Decompressed HTTP response exceeded the maximum allowed size";
                        state->failed        = true;
                        state->done          = true;
                        return -1;
                    }

                    state->body.append(reinterpret_cast<const char*>(decompression_buffer), decompressed_size);
                }


                if (zlib_result == Z_STREAM_END)
                {
                    state->decompression_finished = true;
                    break;
                }

                if (zlib_result != Z_OK && zlib_result != Z_BUF_ERROR)
                {
                    state->error_message = "Unable to decompress the HTTP response";
                    state->failed        = true;
                    state->done          = true;
                    return -1;
                }

                if (zlib_result == Z_BUF_ERROR && decompressed_size == 0u)
                    break;

            } while (state->decompression_stream.avail_in != 0u || state->decompression_stream.avail_out == 0u);

            return 0;
        }

        case LWS_CALLBACK_COMPLETED_CLIENT_HTTP:
        {
            state->done = true;
            lws_cancel_service(lws_get_context(wsi));
            return 0;
        }

        case LWS_CALLBACK_CLOSED_CLIENT_HTTP:
        {
            if (!state->done)
            {
                state->error_message = "The HTTP connection closed before the request completed";
                state->failed        = true;
                state->done          = true;
                lws_cancel_service(lws_get_context(wsi));
            }

            return 0;
        }

        default:
            break;
    }

    return lws_callback_http_dummy(wsi, reason, user, in, len);
}


static const struct lws_protocols http_protocols[] =
{
    {
        "http", http_callback, 0, 0, 0, nullptr, 0
    },
    LWS_PROTOCOL_LIST_TERM
};


int main(int argc, char **argv)
{
    struct lws_context_creation_info context_info;
    struct lws_client_connect_info   connect_info;
    struct lws_context               *context;
    struct lws                       *connection;
    http_test_state                  state;
    const char                       *request_url;
    const char                       *ca_certificate_path;
    const char                       *protocol;
    const char                       *address;
    const char                       *url_path;
    const char                       *alpn;
    std::string                      url_buffer;
    std::string                      request_path;
    std::chrono::steady_clock::time_point deadline;
    int                              port;
    int                              service_result;
    int                              ssl_connection;
    bool                             use_ssl;

    if (argc < 2 || argc > 3)
    {
        std::cerr << "Usage: " << argv[0] << " <url> [ca-certificate-file]" << std::endl;
        return 1;
    }

    request_url         = argv[1];
    ca_certificate_path = argc == 3 ? argv[2] : nullptr;

    url_buffer = request_url;

    protocol = nullptr;
    address  = nullptr;
    url_path = nullptr;
    port     = 0;

    if (url_buffer.empty()
     || lws_parse_uri(&url_buffer[0], &protocol, &address, &port, &url_path) != 0)
    {
        std::cerr << "ERROR: Unable to parse the URL" << std::endl;
        return 1;
    }

    use_ssl = protocol && std::strcmp(protocol, "https") == 0;

    if (!use_ssl && (!protocol || std::strcmp(protocol, "http") != 0))
    {
        std::cerr << "ERROR: Only HTTP and HTTPS URLs are supported" << std::endl;
        return 1;
    }

    request_path = url_path ? url_path : "/";

    if (request_path.empty())
        request_path = "/";
    else if (request_path[0] != '/')
        request_path.insert(0u, "/");

    std::memset(&state.decompression_stream, 0, sizeof(state.decompression_stream));

    state.body.clear();
    state.error_message.clear();
    state.content_encoding.clear();
    state.content_type.clear();
    state.content_length.clear();
    state.transfer_encoding.clear();

    state.received_size             = 0u;
    state.status_code               = 0u;
    state.decompression_initialized = false;
    state.decompression_finished    = false;
    state.done                      = false;
    state.failed                    = false;

    std::memset(&context_info, 0, sizeof(context_info));

    context_info.port                 = CONTEXT_PORT_NO_LISTEN;
    context_info.protocols            = http_protocols;
    context_info.user                 = &state;
    context_info.options              = LWS_SERVER_OPTION_DO_SSL_GLOBAL_INIT
                                      | LWS_SERVER_OPTION_H2_JUST_FIX_WINDOW_UPDATE_OVERFLOW;
    context_info.connect_timeout_secs = network_timeout_seconds;

    if (use_ssl && ca_certificate_path)
        context_info.client_ssl_ca_filepath = ca_certificate_path;

    context = lws_create_context(&context_info);

    if (!context)
    {
        std::cerr << "ERROR: Unable to create the libwebsockets context" << std::endl;
        return 1;
    }

    ssl_connection = 0;
    alpn           = "http/1.1";

    if (use_ssl)
    {
        ssl_connection = LCCSCF_USE_SSL;

        if (!ca_certificate_path)
        {
            ssl_connection |= LCCSCF_ALLOW_INSECURE;

            std::cerr
                << "WARNING: No CA certificate file was provided."
                << std::endl
                << "WARNING: HTTPS certificate verification is disabled for this test."
                << std::endl;
        }

        #if defined(LWS_WITH_HTTP2)

            alpn = "h2,http/1.1";

            ssl_connection |= LCCSCF_H2_QUIRK_OVERFLOWS_TXCR
                            | LCCSCF_H2_QUIRK_NGHTTP2_END_STREAM;

        #endif
    }

    std::memset(&connect_info, 0, sizeof(connect_info));

    connect_info.context        = context;
    connect_info.address        = address;
    connect_info.port           = port;
    connect_info.path           = request_path.c_str();
    connect_info.host           = address;
    connect_info.origin         = address;
    connect_info.method         = "GET";
    connect_info.protocol       = http_protocols[0].name;
    connect_info.userdata       = &state;
    connect_info.alpn           = alpn;
    connect_info.ssl_connection = ssl_connection;

    std::cout << "Requesting: "      << request_url << std::endl;
    std::cout << "CA certificate: "  << (ca_certificate_path ? ca_certificate_path : "not provided") << std::endl;
    std::cout << "Protocol: "        << protocol << std::endl;
    std::cout << "Host: "            << address << std::endl;
    std::cout << "Port: "            << port << std::endl;
    std::cout << "ALPN: "            << alpn << std::endl;
    std::cout << "Accept-Encoding: " << http_accept_encoding << std::endl;


    connection = lws_client_connect_via_info(&connect_info);

    if (!connection)
    {
        std::cerr << "ERROR: Unable to create the HTTP connection" << std::endl;
        lws_context_destroy(context);
        return 1;
    }

    deadline = std::chrono::steady_clock::now() + std::chrono::seconds(request_timeout_seconds);

    while (!state.done)
    {
        service_result = lws_service(context, 100);

        if (service_result < 0)
        {
            state.error_message = "The libwebsockets service loop failed";
            state.failed        = true;
            break;
        }

        if (std::chrono::steady_clock::now() >= deadline)
        {
            state.error_message = "The HTTP request timed out";
            state.failed        = true;
            break;
        }
    }

    lws_context_destroy(context);

    if (state.decompression_initialized)
    {
        if (!state.failed && !state.decompression_finished)
        {
            state.error_message = "The compressed HTTP response ended before the compression stream completed";
            state.failed = true;
        }

        inflateEnd(&state.decompression_stream);
    }

    if (state.failed)
    {
        std::cerr << "ERROR: " << state.error_message << std::endl;
        return 1;
    }

    std::cout << std::endl;
    std::cout << "Final HTTP status: " << state.status_code << std::endl;

    std::cout << "Content-Encoding: "   << (state.content_encoding.empty()  ? "none"         : state.content_encoding)  << std::endl;
    std::cout << "Content-Type: "       << (state.content_type.empty()      ? "not provided" : state.content_type)      << std::endl;
    std::cout << "Content-Length: "     << (state.content_length.empty()    ? "not provided" : state.content_length)    << std::endl;
    std::cout << "Transfer-Encoding: "  << (state.transfer_encoding.empty() ? "none"         : state.transfer_encoding) << std::endl;
    std::cout << "Received body size: " << state.received_size << " bytes" << std::endl;
    std::cout << "Final body size: "    << state.body.size()   << " bytes" << std::endl;

    if (!state.body.empty())
        std::cout << std::endl << "Decoded response:" << std::endl << state.body << std::endl;

    if (state.status_code < 200u || state.status_code >= 300u)
    {
        std::cerr << "ERROR: The HTTP server returned status " << state.status_code << std::endl;
        return 1;
    }

    if (state.body.empty())
    {
        std::cerr << "ERROR: The HTTP server returned an empty response" << std::endl;
        return 1;
    }

    std::cout << std::endl << "libwebsockets compression test succeeded" << std::endl;
    return 0;
}
