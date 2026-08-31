## COMPILER
CC      = gcc
CXX     = g++

BUILD_DIR = build

CFLAGS   += -Wextra -Wall -Werror
CXXFLAGS += -std=c++11 -Wextra -Wall -Werror


# PLATFORM DETECTION + OBJECT PER PLATFORM
ifeq ($(OS),Windows_NT)
	PLATFORM = WINDOWS
	OBJ += $(OBJ_WIN)

	WINDOWS_STATIC_LDFLAGS = -static -static-libgcc -static-libstdc++
else
	UNAME_S := $(shell uname -s)

	ifeq ($(UNAME_S),Linux)
		PLATFORM = LINUX
		OBJ += $(OBJ_LINUX)
	endif

	ifeq ($(UNAME_S),Darwin)
		PLATFORM = MAC
		OBJ += $(OBJ_MAC)
	endif
endif

