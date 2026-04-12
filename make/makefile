MESA_DIR = ../../../..

include $(MESA_DIR)/utils/makefile_header

PROG = ../colors_post_proc

FFLAGS = $(FCbasic) $(FCopenmp) -I$(MESA_DIR)/include -I$(MESA_DIR)/colors/make

SRCS = run.f90
OBJS = $(patsubst %.f90,%.o,$(SRCS))

VPATH = ../src

LOAD_MESA = -L$(MESA_LIB_DIR) -lcolors -lconst -lmath -lutils -lcrlibm

$(PROG): $(OBJS)
	$(FC) $(FCbasic) $(FCopenmp) -o $(PROG) $(OBJS) $(LOAD_MESA)

%.o: %.f90
	$(FC) $(FFLAGS) -c $< -o $@

.PHONY: clean
clean:
	-@rm -f *.o *.mod $(PROG)
