CC      = gcc
MPICC   = mpicc
NVCC    = nvcc
CFLAGS  = -O2 -Wall
LDFLAGS = -lm

all: sequential openmp_ver mpi_ver cuda_ver

sequential: sequential.c
	$(CC) $(CFLAGS) -o $@ $< $(LDFLAGS)

openmp_ver: openmp_ver.c
	$(CC) $(CFLAGS) -fopenmp -o $@ $< $(LDFLAGS)

mpi_ver: mpi_ver.c
	$(MPICC) $(CFLAGS) -o $@ $< $(LDFLAGS)

cuda_ver: cuda_ver.cu
	$(NVCC) -O2 -o $@ $<

clean:
	rm -f sequential openmp_ver mpi_ver cuda_ver *.exe

.PHONY: all clean
