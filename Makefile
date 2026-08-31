include MakefileFolder/base.mk

# UNIT_TEST
include MakefileFolder/test_libwebsockets.mk
include MakefileFolder/test_libwebsockets_compression.mk

# If one of the .mk files defines a rule before "`all:`", Make program may choose that as the default goal.
# To prevent that explicitly set .DEFAULT_GOAL. (https://www.gnu.org/software/make/manual/html_node/Goals.html)
.DEFAULT_GOAL := all

all: $(PROGRAMS)


clean:
	rm -rf build
	rm -f $(PROGRAMS)
	rm -f $(PROGRAMS:%=%.exe)


.PHONY: all clean

