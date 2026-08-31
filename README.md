# LibWebSockets for Windows 32bit/64bit, Mac, or Linux

### IMPORTANT TO KNOW

There's 2 Branch:

- ` BUILD ` : contain everything to build LibWebSockets with the patch
- ` UNIT-TEST ` : contain unit-test file + the build of the patched LibWebSocket on /src/external/libwebsockets

### Libraries used:

- LibWebSockets - 4.3.0
- Mbed TLS - 2.28.9
- nghttp2 - 1.70.0
- Zlib - 1.3.2


### Compatibility:

- [ ✓ ] Windows XP
- [ x ] Windows 2000: The procedure entry point freeaddrinfo coult not be located in the dynamic link library WS2_32.dll
- [ x ] Windows Me: The file is linked to missing export KERNEL32.DLL :GetFileSizeEx.
- [ x ] Windows 98: The file is linked to missing export KERNEL32.DLL :GetFileSizeEx.

