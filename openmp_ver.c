/*
 * Вариант 16: Определить строку с максимальной суммой элементов
 * Параллельная реализация — OpenMP
 */
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <float.h>
#include <omp.h>

void fill_matrix(double *matrix, int N, int M, unsigned int seed)
{
    srand(seed);
    for (int i = 0; i < N * M; i++)
        matrix[i] = (double)rand() / RAND_MAX * 200.0 - 100.0;
}

/*
 * Параллельный поиск строки с максимальной суммой.
 * Каждый поток вычисляет суммы строк в своём диапазоне,
 * затем через reduction находится глобальный максимум.
 */
int find_max_row_omp(const double *matrix, int N, int M, double *out_max_sum)
{
    int max_row = 0;
    double max_sum = -DBL_MAX;

    #pragma omp parallel
    {
        int local_max_row = 0;
        double local_max_sum = -DBL_MAX;

        #pragma omp for schedule(static) nowait
        for (int i = 0; i < N; i++) {
            double row_sum = 0.0;
            for (int j = 0; j < M; j++)
                row_sum += matrix[i * M + j];
            if (row_sum > local_max_sum) {
                local_max_sum = row_sum;
                local_max_row = i;
            }
        }

        #pragma omp critical
        {
            if (local_max_sum > max_sum) {
                max_sum = local_max_sum;
                max_row = local_max_row;
            }
        }
    }

    *out_max_sum = max_sum;
    return max_row;
}

int main(int argc, char *argv[])
{
    if (argc < 3) {
        printf("Использование: %s <N> <M> [k] [threads]\n", argv[0]);
        return 1;
    }

    int N = atoi(argv[1]);
    int M = atoi(argv[2]);
    int k = (argc > 3) ? atoi(argv[3]) : 100000;
    int num_threads = (argc > 4) ? atoi(argv[4]) : omp_get_max_threads();

    omp_set_num_threads(num_threads);

    double *matrix = (double *)malloc(N * M * sizeof(double));
    if (!matrix) {
        fprintf(stderr, "Ошибка выделения памяти\n");
        return 1;
    }

    fill_matrix(matrix, N, M, 42);

    double max_sum;
    int max_row = find_max_row_omp(matrix, N, M, &max_sum);

    /* Замер времени */
    struct timespec ts_start, ts_end;
    clock_gettime(CLOCK_MONOTONIC, &ts_start);

    for (int iter = 0; iter < k; iter++) {
        find_max_row_omp(matrix, N, M, &max_sum);
    }

    clock_gettime(CLOCK_MONOTONIC, &ts_end);

    double total_sec = (ts_end.tv_sec - ts_start.tv_sec)
                     + (ts_end.tv_nsec - ts_start.tv_nsec) / 1e9;
    double avg_sec = total_sec / k;

    printf("=== OpenMP алгоритм ===\n");
    printf("Размер матрицы: %d x %d\n", N, M);
    printf("Потоков: %d\n", num_threads);
    printf("Строка с макс. суммой: %d (сумма = %.2f)\n", max_row, max_sum);
    printf("Кол-во итераций (k): %d\n", k);
    printf("Общее время: %.6f с\n", total_sec);
    printf("Среднее время: %.9f с\n", avg_sec);

    printf("RESULT:%d:%.2f:%.9f\n", max_row, max_sum, avg_sec);

    free(matrix);
    return 0;
}
