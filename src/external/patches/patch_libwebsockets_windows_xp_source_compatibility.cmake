# libwebsockets v4.3-stable Windows XP source compatibility patch.
#
# v4.3-stable uses WSAPoll() for the native Windows event loop.
# WSAPoll() and the WSAPOLLFD / POLL* declarations require Windows Vista
# or newer in the Windows SDK.
#
# This patch keeps the v4.3 event-loop architecture and adds an XP fallback:
#
#   - define the poll structure and event values used by libwebsockets when
#     targeting Windows versions older than Vista;
#   - use Winsock select() instead of WSAPoll() on those targets;
#   - keep WSAPoll() unchanged for Vista and newer Windows versions.
#
# This patch intentionally does not change WINVER or _WIN32_WINNT.
# The separate patch_libwebsockets_windows_xp.cmake patch remains responsible
# for selecting the Windows XP target in libwebsockets' CMake configuration.


if(NOT LWS_WINDOWS_BUILD)

    message(
        STATUS
        "libwebsockets Windows XP source compatibility patch: not a Windows build, skipping"
    )

    return()

endif()


if(NOT DEFINED LWS_SOURCE_DIR)

    message(
        FATAL_ERROR
        "LWS_SOURCE_DIR is not defined"
    )

endif()


set(
    LWS_PUBLIC_HEADER
    "${LWS_SOURCE_DIR}/include/libwebsockets.h"
)

set(
    LWS_WINDOWS_SERVICE_FILE
    "${LWS_SOURCE_DIR}/lib/plat/windows/windows-service.c"
)


if(NOT EXISTS "${LWS_PUBLIC_HEADER}")

    message(
        FATAL_ERROR
        "libwebsockets public header not found: ${LWS_PUBLIC_HEADER}"
    )

endif()


if(NOT EXISTS "${LWS_WINDOWS_SERVICE_FILE}")

    message(
        FATAL_ERROR
        "libwebsockets Windows service file not found: ${LWS_WINDOWS_SERVICE_FILE}"
    )

endif()


# --------------------------------------------------------------------------
# Windows XP does not expose pollfd / WSAPOLLFD or the POLL* constants.
#
# Keep the v4.3 values on Vista+, and provide the same Winsock poll bit values
# directly when targeting XP.
# --------------------------------------------------------------------------

file(
    READ
    "${LWS_PUBLIC_HEADER}"
    LWS_PUBLIC_HEADER_CONTENT
)

set(
    OLD_WINDOWS_POLL_DEFINITIONS
"#define lws_pollfd pollfd
#define LWS_POLLHUP\t(POLLHUP)
#define LWS_POLLIN\t(POLLRDNORM | POLLRDBAND)
#define LWS_POLLOUT\t(POLLWRNORM)"
)

set(
    NEW_WINDOWS_POLL_DEFINITIONS
"/* LWS_WINDOWS_XP_SOURCE_COMPATIBILITY */
#if (defined(_WIN32_WINNT) && (_WIN32_WINNT < 0x0600)) || (defined(WINVER) && (WINVER < 0x0600))

struct lws_pollfd {
\tlws_sockfd_type fd;
\tSHORT events;
\tSHORT revents;
};

#define LWS_POLLHUP\t(0x0002)
#define LWS_POLLIN\t(0x0100 | 0x0200)
#define LWS_POLLOUT\t(0x0010)

#else

#define lws_pollfd pollfd
#define LWS_POLLHUP\t(POLLHUP)
#define LWS_POLLIN\t(POLLRDNORM | POLLRDBAND)
#define LWS_POLLOUT\t(POLLWRNORM)

#endif"
)

string(
    FIND
    "${LWS_PUBLIC_HEADER_CONTENT}"
    "LWS_WINDOWS_XP_SOURCE_COMPATIBILITY"
    WINDOWS_POLL_ALREADY_PATCHED
)

if(WINDOWS_POLL_ALREADY_PATCHED EQUAL -1)

    string(
        FIND
        "${LWS_PUBLIC_HEADER_CONTENT}"
        "${OLD_WINDOWS_POLL_DEFINITIONS}"
        WINDOWS_POLL_POSITION
    )

    if(WINDOWS_POLL_POSITION EQUAL -1)

        message(
            FATAL_ERROR
            "Unable to find the libwebsockets v4.3 Windows poll definitions to patch"
        )

    endif()

    string(
        REPLACE
        "${OLD_WINDOWS_POLL_DEFINITIONS}"
        "${NEW_WINDOWS_POLL_DEFINITIONS}"
        LWS_PUBLIC_HEADER_CONTENT
        "${LWS_PUBLIC_HEADER_CONTENT}"
    )

    file(
        WRITE
        "${LWS_PUBLIC_HEADER}"
        "${LWS_PUBLIC_HEADER_CONTENT}"
    )

    message(
        STATUS
        "Patched libwebsockets Windows XP poll declarations"
    )

else()

    message(
        STATUS
        "libwebsockets Windows XP poll declarations already patched"
    )

endif()


# --------------------------------------------------------------------------
# Replace WSAPoll() with select() only when targeting pre-Vista Windows.
#
# select() is available on Windows XP and works with the TCP / UDP sockets
# used by the v4.3 native Windows event loop, including its UDP wakeup pair.
# --------------------------------------------------------------------------

file(
    READ
    "${LWS_WINDOWS_SERVICE_FILE}"
    LWS_WINDOWS_SERVICE_CONTENT
)

set(
    OLD_SERVICE_VARIABLES
"\tstruct lws *wsi;
\tunsigned int i;
\tint n;"
)

set(
    NEW_SERVICE_VARIABLES
"\tstruct lws *wsi;
\tunsigned int i;
#if (defined(_WIN32_WINNT) && (_WIN32_WINNT < 0x0600)) || (defined(WINVER) && (WINVER < 0x0600))
\tfd_set read_fds;
\tfd_set write_fds;
\tfd_set except_fds;
\tstruct timeval select_timeout;
\tunsigned int valid_socket_count;
#endif
\tint d;
\tint n;"
)

set(
    OLD_WINDOWS_WAIT
"\tint d = WSAPoll((WSAPOLLFD *)&pt->fds[0], pt->fds_count, (int)(timeout_us / LWS_US_PER_MS));
\tif (d < 0) {
\t\tlwsl_err(\"%s: WSAPoll failed: count %d, err %d: %d\\n\", __func__, pt->fds_count, d, WSAGetLastError());"
)

set(
    NEW_WINDOWS_WAIT
"/* LWS_WINDOWS_XP_SELECT_COMPATIBILITY */
#if (defined(_WIN32_WINNT) && (_WIN32_WINNT < 0x0600)) || (defined(WINVER) && (WINVER < 0x0600))
\tFD_ZERO(&read_fds);
\tFD_ZERO(&write_fds);
\tFD_ZERO(&except_fds);
\tvalid_socket_count = 0;

\tif (pt->fds_count > FD_SETSIZE) {
\t\tWSASetLastError(WSAENOBUFS);
\t\td = SOCKET_ERROR;
\t} else {
\t\tfor (i = 0; i < pt->fds_count; i++) {
\t\t\tpfd = &pt->fds[i];
\t\t\tpfd->revents = 0;

\t\t\tif (pfd->fd == LWS_SOCK_INVALID)
\t\t\t\tcontinue;

\t\t\tvalid_socket_count++;

\t\t\tif (pfd->events & LWS_POLLIN)
\t\t\t\tFD_SET(pfd->fd, &read_fds);

\t\t\tif (pfd->events & LWS_POLLOUT)
\t\t\t\tFD_SET(pfd->fd, &write_fds);

\t\t\tFD_SET(pfd->fd, &except_fds);
\t\t}

\t\tif (!valid_socket_count) {
\t\t\tif (timeout_us)
\t\t\t\tSleep((DWORD)(timeout_us / LWS_US_PER_MS));

\t\t\td = 0;
\t\t} else {
\t\t\tselect_timeout.tv_sec = (long)(timeout_us / LWS_US_PER_SEC);
\t\t\tselect_timeout.tv_usec = (long)(timeout_us % LWS_US_PER_SEC);

\t\t\td = select(0, &read_fds, &write_fds, &except_fds,
\t\t\t\t   &select_timeout);

\t\t\tif (d > 0) {
\t\t\t\tfor (i = 0; i < pt->fds_count; i++) {
\t\t\t\t\tpfd = &pt->fds[i];

\t\t\t\t\tif (pfd->fd == LWS_SOCK_INVALID)
\t\t\t\t\t\tcontinue;

\t\t\t\t\tif (FD_ISSET(pfd->fd, &read_fds))
\t\t\t\t\t\tpfd->revents |= LWS_POLLIN;

\t\t\t\t\tif (FD_ISSET(pfd->fd, &write_fds))
\t\t\t\t\t\tpfd->revents |= LWS_POLLOUT;

\t\t\t\t\tif (FD_ISSET(pfd->fd, &except_fds))
\t\t\t\t\t\tpfd->revents |= LWS_POLLHUP;
\t\t\t\t}
\t\t\t}
\t\t}
\t}
#else
\td = WSAPoll((WSAPOLLFD *)&pt->fds[0], pt->fds_count,
\t\t    (int)(timeout_us / LWS_US_PER_MS));
#endif
\tif (d < 0) {
\t\tlwsl_err(\"%s: Windows socket wait failed: count %d, err %d: %d\\n\", __func__, pt->fds_count, d, WSAGetLastError());"
)

string(
    FIND
    "${LWS_WINDOWS_SERVICE_CONTENT}"
    "LWS_WINDOWS_XP_SELECT_COMPATIBILITY"
    WINDOWS_WAIT_ALREADY_PATCHED
)

if(WINDOWS_WAIT_ALREADY_PATCHED EQUAL -1)

    string(
        FIND
        "${LWS_WINDOWS_SERVICE_CONTENT}"
        "${OLD_SERVICE_VARIABLES}"
        SERVICE_VARIABLES_POSITION
    )

    if(SERVICE_VARIABLES_POSITION EQUAL -1)

        message(
            FATAL_ERROR
            "Unable to find the libwebsockets v4.3 Windows service variables to patch"
        )

    endif()

    string(
        FIND
        "${LWS_WINDOWS_SERVICE_CONTENT}"
        "${OLD_WINDOWS_WAIT}"
        WINDOWS_WAIT_POSITION
    )

    if(WINDOWS_WAIT_POSITION EQUAL -1)

        message(
            FATAL_ERROR
            "Unable to find the libwebsockets v4.3 WSAPoll service code to patch"
        )

    endif()

    string(
        REPLACE
        "${OLD_SERVICE_VARIABLES}"
        "${NEW_SERVICE_VARIABLES}"
        LWS_WINDOWS_SERVICE_CONTENT
        "${LWS_WINDOWS_SERVICE_CONTENT}"
    )

    string(
        REPLACE
        "${OLD_WINDOWS_WAIT}"
        "${NEW_WINDOWS_WAIT}"
        LWS_WINDOWS_SERVICE_CONTENT
        "${LWS_WINDOWS_SERVICE_CONTENT}"
    )

    file(
        WRITE
        "${LWS_WINDOWS_SERVICE_FILE}"
        "${LWS_WINDOWS_SERVICE_CONTENT}"
    )

    message(
        STATUS
        "Patched libwebsockets Windows XP select() event-loop fallback"
    )

else()

    message(
        STATUS
        "libwebsockets Windows XP select() event-loop fallback already patched"
    )

endif()
