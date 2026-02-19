CC      = gcc
MPICC   = mpicc
NVCC    = nvcc
CFLAGS  = -O2 -Wall
LDFLAGS = -lm

all: sequential openmp_ver mpi_ver cuda_ver

sequential: sequential.c
	$(CC) $(CFLAGS) -o bin/sequential $< $(LDFLAGS)

openmp_ver: openmp_ver.c
	$(CC) $(CFLAGS) -fopenmp -o bin/openmp_ver $< $(LDFLAGS)

mpi_ver: mpi_ver.c
	$(MPICC) $(CFLAGS) -o bin/mpi_ver $< $(LDFLAGS)

cuda_ver: cuda_ver.cu
	$(NVCC) -O2 -o bin/cuda_ver $<

clean:
	rm -rf bin/ *.exe

.PHONY: all clean
