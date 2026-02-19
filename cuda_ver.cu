/*
 * Вариант 16: Определить строку с максимальной суммой элементов
 * Реализация на GPU — NVIDIA CUDA
 *
 * Алгоритм:
 * 1. Ядро row_sums_kernel: каждый поток вычисляет сумму одной строки.
 * 2. Ядро reduce_max_kernel: параллельная редукция для нахождения строки с макс. суммой.
 */
#include <stdio.h>
#include <stdlib.h>
#include <float.h>
#include <cuda_runtime.h>

#define CUDA_CHECK(call)                                                     \
    do {                                                                     \
        cudaError_t err = (call);                                            \
        if (err != cudaSuccess) {                                            \
            fprintf(stderr, "CUDA error at %s:%d: %s\n",                     \
                    __FILE__, __LINE__, cudaGetErrorString(err));             \
            exit(1);                                                         \
        }                                                                    \
    } while (0)

/* Заполнение матрицы на хосте */
void fill_matrix(double *matrix, int N, int M, unsigned int seed)
{
    srand(seed);
    for (int i = 0; i < N * M; i++)
        matrix[i] = (double)rand() / RAND_MAX * 200.0 - 100.0;
}

/* Ядро: каждый поток вычисляет сумму одной строки */
__global__ void row_sums_kernel(const double *matrix, double *sums, int N, int M)
{
    int row = blockIdx.x * blockDim.x + threadIdx.x;
    if (row >= N) return;

    double s = 0.0;
    for (int j = 0; j < M; j++)
        s += matrix[row * M + j];
    sums[row] = s;
}

/*
 * Ядро: параллельная редукция — нахождение индекса максимальной суммы.
 * Использует shared memory для блочной редукции.
 */
__global__ void reduce_max_kernel(const double *sums, int N,
                                   double *block_max_vals, int *block_max_idxs)
{
    extern __shared__ char shared_mem[];
    double *s_vals = (double *)shared_mem;
    int    *s_idxs = (int *)(s_vals + blockDim.x);

    int tid = threadIdx.x;
    int gid = blockIdx.x * blockDim.x + threadIdx.x;

    if (gid < N) {
        s_vals[tid] = sums[gid];
        s_idxs[tid] = gid;
    } else {
        s_vals[tid] = -DBL_MAX;
        s_idxs[tid] = -1;
    }
    __syncthreads();

    for (int stride = blockDim.x / 2; stride > 0; stride >>= 1) {
        if (tid < stride) {
            if (s_vals[tid + stride] > s_vals[tid]) {
                s_vals[tid] = s_vals[tid + stride];
                s_idxs[tid] = s_idxs[tid + stride];
            }
        }
        __syncthreads();
    }

    if (tid == 0) {
        block_max_vals[blockIdx.x] = s_vals[0];
        block_max_idxs[blockIdx.x] = s_idxs[0];
    }
}

/* Хостовая функция: поиск максимума среди блочных результатов */
void find_max_from_blocks(const double *vals, const int *idxs, int count,
                          double *out_max, int *out_idx)
{
    *out_max = vals[0];
    *out_idx = idxs[0];
    for (int i = 1; i < count; i++) {
        if (vals[i] > *out_max) {
            *out_max = vals[i];
            *out_idx = idxs[i];
        }
    }
}

int main(int argc, char *argv[])
{
    if (argc < 3) {
        printf("Использование: %s <N> <M> [k]\n", argv[0]);
        return 1;
    }

    int N = atoi(argv[1]);
    int M = atoi(argv[2]);
    int k = (argc > 3) ? atoi(argv[3]) : 10000;

    /* Выделение и заполнение матрицы на хосте */
    size_t mat_size = (size_t)N * M * sizeof(double);
    double *h_matrix = (double *)malloc(mat_size);
    fill_matrix(h_matrix, N, M, 42);

    /* Выделение памяти на GPU */
    double *d_matrix, *d_sums;
    CUDA_CHECK(cudaMalloc(&d_matrix, mat_size));
    CUDA_CHECK(cudaMalloc(&d_sums, N * sizeof(double)));

    CUDA_CHECK(cudaMemcpy(d_matrix, h_matrix, mat_size, cudaMemcpyHostToDevice));

    /* Параметры запуска ядер */
    int block_size = 256;
    int grid_sums = (N + block_size - 1) / block_size;
    int grid_reduce = (N + block_size - 1) / block_size;

    /* Память для редукции */
    double *d_block_vals;
    int    *d_block_idxs;
    CUDA_CHECK(cudaMalloc(&d_block_vals, grid_reduce * sizeof(double)));
    CUDA_CHECK(cudaMalloc(&d_block_idxs, grid_reduce * sizeof(int)));

    double *h_block_vals = (double *)malloc(grid_reduce * sizeof(double));
    int    *h_block_idxs = (int *)malloc(grid_reduce * sizeof(int));

    size_t shared_size = block_size * (sizeof(double) + sizeof(int));

    /* Прогрев GPU */
    row_sums_kernel<<<grid_sums, block_size>>>(d_matrix, d_sums, N, M);
    CUDA_CHECK(cudaDeviceSynchronize());

    /* Замер времени через CUDA events */
    cudaEvent_t start, stop;
    CUDA_CHECK(cudaEventCreate(&start));
    CUDA_CHECK(cudaEventCreate(&stop));

    CUDA_CHECK(cudaEventRecord(start));

    for (int iter = 0; iter < k; iter++) {
        /* Вычисление суммы каждой строки */
        row_sums_kernel<<<grid_sums, block_size>>>(d_matrix, d_sums, N, M);

        /* Параллельная редукция для нахождения максимума */
        reduce_max_kernel<<<grid_reduce, block_size, shared_size>>>(
            d_sums, N, d_block_vals, d_block_idxs);
    }

    CUDA_CHECK(cudaEventRecord(stop));
    CUDA_CHECK(cudaEventSynchronize(stop));

    float total_ms;
    CUDA_CHECK(cudaEventElapsedTime(&total_ms, start, stop));
    double total_sec = total_ms / 1000.0;
    double avg_sec = total_sec / k;

    /* Получаем результат последней итерации */
    CUDA_CHECK(cudaMemcpy(h_block_vals, d_block_vals,
                           grid_reduce * sizeof(double), cudaMemcpyDeviceToHost));
    CUDA_CHECK(cudaMemcpy(h_block_idxs, d_block_idxs,
                           grid_reduce * sizeof(int), cudaMemcpyDeviceToHost));

    double max_sum;
    int max_row;
    find_max_from_blocks(h_block_vals, h_block_idxs, grid_reduce, &max_sum, &max_row);

    printf("=== CUDA алгоритм ===\n");
    printf("Размер матрицы: %d x %d\n", N, M);
    printf("Строка с макс. суммой: %d (сумма = %.2f)\n", max_row, max_sum);
    printf("Кол-во итераций (k): %d\n", k);
    printf("Общее время: %.6f с\n", total_sec);
    printf("Среднее время: %.9f с\n", avg_sec);
    printf("RESULT:%d:%.2f:%.9f\n", max_row, max_sum, avg_sec);

    /* Освобождение ресурсов */
    CUDA_CHECK(cudaEventDestroy(start));
    CUDA_CHECK(cudaEventDestroy(stop));
    cudaFree(d_matrix);
    cudaFree(d_sums);
    cudaFree(d_block_vals);
    cudaFree(d_block_idxs);
    free(h_matrix);
    free(h_block_vals);
    free(h_block_idxs);

    return 0;
}
