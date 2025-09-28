# Based on c_src.mk from erlang.mk by Loic Hoguin <essen@ninenines.eu>

CURDIR := $(shell pwd)
BASEDIR := $(abspath $(CURDIR)/..)

PROJECT := sippet_nif

ERTS_INCLUDE_DIR ?= $(shell erl -noshell -s init stop -eval "io:format(\"~s/erts-~s/include/\", [code:root_dir(), erlang:system_info(version)]).")
ERL_INTERFACE_INCLUDE_DIR ?= $(shell erl -noshell -s init stop -eval "io:format(\"~s\", [code:lib_dir(erl_interface, include)]).")
ERL_INTERFACE_LIB_DIR ?= $(shell erl -noshell -s init stop -eval "io:format(\"~s\", [code:lib_dir(erl_interface, lib)]).")
ERL_ROOT ?= $(shell erl -noshell -s init stop -eval "io:format(\"~s\", [code:root_dir()]).")
ERL_VERSION := $(shell erl -noshell -eval 'io:fwrite("~s\n", [erlang:system_info(otp_release)]).' -s erlang halt)

C_SRC_DIR = $(CURDIR)

# Platform detection.

ifeq ($(PLATFORM),)
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Linux)
	PLATFORM = linux
else ifeq ($(UNAME_S),Darwin)
	PLATFORM = darwin
else ifeq ($(UNAME_S),SunOS)
	PLATFORM = solaris
else ifeq ($(UNAME_S),GNU)
	PLATFORM = gnu
else ifeq ($(UNAME_S),FreeBSD)
	PLATFORM = freebsd
else ifeq ($(UNAME_S),NetBSD)
	PLATFORM = netbsd
else ifeq ($(UNAME_S),OpenBSD)
	PLATFORM = openbsd
else ifeq ($(UNAME_S),DragonFly)
	PLATFORM = dragonfly
else ifeq ($(shell uname -o),Msys)
	PLATFORM = msys2
else
	$(error Unable to detect platform. Please open a ticket with the output of uname -a.)
endif
endif

# System type and C compiler/flags.

ifeq ($(PLATFORM),msys2)
	C_SRC_SHARED_EXTENSION ?= .dll
else
	C_SRC_SHARED_EXTENSION ?= .so
endif

C_SRC_OUTPUT ?= $(BASEDIR)/priv/$(PROJECT)$(C_SRC_SHARED_EXTENSION)

ifeq ($(PLATFORM),msys2)
# We hardcode the compiler used on MSYS2. The default CC=cc does
# not produce working code. The "gcc" MSYS2 package also doesn't.
	CC = /mingw64/bin/gcc
	CFLAGS ?= -O3 -std=c11 -finline-functions -fstack-protector -Wall -Wmissing-prototypes
	CXXFLAGS ?= -O3 -std=c++11 -finline-functions -fstack-protector -Wall
else ifeq ($(PLATFORM),darwin)
ifeq ($(ARCHFLAGS),)
	UNAME_M := $(shell uname -m)
ifeq ($(UNAME_M),arm64)
	ARCHFLAGS := -arch arm64
else ifeq ($(UNAME_M),x86_64)
	ARCHFLAGS := -arch x86_64
else
	$(error Unable to detect architecture. Please open a ticket with the output of uname -a.)
endif
endif
	CC ?= cc
	CFLAGS ?= -O3 -std=c11 $(ARCHFLAGS) -fstack-protector -Wall -Wmissing-prototypes
	CXXFLAGS ?= -O3 -std=c++11 $(ARCHFLAGS) -fstack-protector -Wall
	LDFLAGS ?= $(ARCHFLAGS) -flat_namespace -undefined dynamic_lookup
else ifeq ($(PLATFORM),freebsd)
	CC ?= cc
	CFLAGS ?= -O3 -std=c11 -finline-functions -fstack-protector -Wall -Wmissing-prototypes
	CXXFLAGS ?= -O3 -std=c++11 -finline-functions -fstack-protector -Wall
else ifeq ($(PLATFORM),linux)
	CC ?= gcc
	CFLAGS ?= -O3 -std=c11 -finline-functions -fstack-protector -Wall -Wmissing-prototypes
	CXXFLAGS ?= -O3 -std=c++11 -finline-functions -fstack-protector -Wall
else ifeq ($(PLATFORM),solaris)
	CC ?= cc
	CFLAGS ?= -O3 -std=c11 -finline-functions -fstack-protector -Wall -Wmissing-prototypes -fPIC
	CXXFLAGS ?= -O3 -std=c++11 -finline-functions -fstack-protector -Wall -fPIC
endif

ifneq ($(PLATFORM),msys2)
	CFLAGS += -fPIC
	CXXFLAGS += -fPIC
endif

ifneq ($(CROSSCOMPILER),)
	CC = $(CROSSCOMPILER)gcc
endif

CFLAGS += -I $(ERTS_INCLUDE_DIR) -I $(ERL_INTERFACE_INCLUDE_DIR)
CXXFLAGS += -I $(ERTS_INCLUDE_DIR) -I $(ERL_INTERFACE_INCLUDE_DIR)

ifeq ($(shell expr $(ERL_VERSION) \>= 23), 1)
	LDLIBS += -L $(ERL_INTERFACE_LIB_DIR) -lei
else
	LDLIBS += -L $(ERL_INTERFACE_LIB_DIR) -lei -lerl_interface
endif

ifeq ($(PLATFORM),darwin)
	LDFLAGS += -bundle -bundle_loader $(ERL_ROOT)/erts-*/bin/beam.smp
else
	LDFLAGS += -shared
endif
LDFLAGS += -lstdc++

# Verbosity.

c_verbose_0 = @echo " C     " $(?F);
c_verbose = $(c_verbose_$(V))

cpp_verbose_0 = @echo " CPP   " $(?F);
cpp_verbose = $(cpp_verbose_$(V))

link_verbose_0 = @echo " LD    " $(@F);
link_verbose = $(link_verbose_$(V))

SOURCES := $(shell find $(C_SRC_DIR) -type f \( -name "*.c" -o -name "*.C" -o -name "*.cc" -o -name "*.cpp" \))
OBJECTS = $(addsuffix .o, $(basename $(SOURCES)))

COMPILE_C = $(c_verbose) $(CC) $(CFLAGS) $(CPPFLAGS) -c
COMPILE_CPP = $(cpp_verbose) $(CXX) $(CXXFLAGS) $(CPPFLAGS) -c

$(C_SRC_OUTPUT): $(OBJECTS)
	@mkdir -p $(BASEDIR)/priv/
	$(link_verbose) $(CC) $(OBJECTS) $(LDFLAGS) $(LDLIBS) -o $(C_SRC_OUTPUT)

%.o: %.c
	$(COMPILE_C) $(OUTPUT_OPTION) $<

%.o: %.cc
	$(COMPILE_CPP) $(OUTPUT_OPTION) $<

%.o: %.C
	$(COMPILE_CPP) $(OUTPUT_OPTION) $<

%.o: %.cpp
	$(COMPILE_CPP) $(OUTPUT_OPTION) $<

clean:
	@rm -f $(C_SRC_OUTPUT) $(OBJECTS)
