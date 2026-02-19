/*
 * Вариант 16: Определить строку с максимальной суммой элементов
 * Параллельная реализация — MPI
 *
 * Алгоритм:
 * 1. Процесс 0 генерирует матрицу и рассылает строки по процессам (Scatter).
 * 2. Каждый процесс вычисляет суммы своих строк и находит локальный максимум.
 * 3. Через MPI_Allreduce (MPI_MAXLOC) определяется глобальный максимум.
 */
#include <stdio.h>
#include <stdlib.h>
#include <float.h>
#include <mpi.h>

void fill_matrix(double *matrix, int N, int M, unsigned int seed)
{
    srand(seed);
    for (int i = 0; i < N * M; i++)
        matrix[i] = (double)rand() / RAND_MAX * 200.0 - 100.0;
}

int main(int argc, char *argv[])
{
    MPI_Init(&argc, &argv);

    int rank, size;
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    if (argc < 3) {
        if (rank == 0)
            printf("Использование: mpirun -np <P> %s <N> <M> [k]\n", argv[0]);
        MPI_Finalize();
        return 1;
    }

    int N = atoi(argv[1]);
    int M = atoi(argv[2]);
    int k = (argc > 3) ? atoi(argv[3]) : 100000;

    /* Для простоты требуем, чтобы N делилось на количество процессов */
    int rows_per_proc = N / size;
    int remainder = N % size;

    /* Каждому процессу — rows_per_proc строк (+ 1 для первых remainder) */
    int local_rows = rows_per_proc + (rank < remainder ? 1 : 0);

    double *matrix = NULL;
    double *local_matrix = (double *)malloc(local_rows * M * sizeof(double));

    /* Рассчитываем sendcounts и displacements для Scatterv */
    int *sendcounts = NULL;
    int *displs = NULL;

    if (rank == 0) {
        matrix = (double *)malloc(N * M * sizeof(double));
        fill_matrix(matrix, N, M, 42);

        sendcounts = (int *)malloc(size * sizeof(int));
        displs = (int *)malloc(size * sizeof(int));
        int offset = 0;
        for (int p = 0; p < size; p++) {
            int r = rows_per_proc + (p < remainder ? 1 : 0);
            sendcounts[p] = r * M;
            displs[p] = offset;
            offset += sendcounts[p];
        }
    }

    int local_count = local_rows * M;

    /* Определяем global_row_offset для каждого процесса */
    int global_row_offset = 0;
    for (int p = 0; p < rank; p++)
        global_row_offset += rows_per_proc + (p < remainder ? 1 : 0);

    /* Замер времени */
    MPI_Barrier(MPI_COMM_WORLD);
    double t_start = MPI_Wtime();

    for (int iter = 0; iter < k; iter++) {
        /* Рассылка строк */
        MPI_Scatterv(matrix, sendcounts, displs, MPI_DOUBLE,
                      local_matrix, local_count, MPI_DOUBLE,
                      0, MPI_COMM_WORLD);

        /* Локальный поиск строки с макс. суммой */
        double local_max_sum = -DBL_MAX;
        int local_max_row = 0;

        for (int i = 0; i < local_rows; i++) {
            double row_sum = 0.0;
            for (int j = 0; j < M; j++)
                row_sum += local_matrix[i * M + j];
            if (row_sum > local_max_sum) {
                local_max_sum = row_sum;
                local_max_row = global_row_offset + i;
            }
        }

        /* Глобальная редукция: MPI_MAXLOC для пары (значение, ранг строки) */
        struct {
            double val;
            int idx;
        } local_result, global_result;

        local_result.val = local_max_sum;
        local_result.idx = local_max_row;

        MPI_Allreduce(&local_result, &global_result, 1,
                       MPI_DOUBLE_INT, MPI_MAXLOC, MPI_COMM_WORLD);

        /* Используем volatile чтобы компилятор не убрал цикл */
        if (iter == k - 1 && rank == 0) {
            printf("=== MPI алгоритм ===\n");
            printf("Размер матрицы: %d x %d\n", N, M);
            printf("Процессов: %d\n", size);
            printf("Строка с макс. суммой: %d (сумма = %.2f)\n",
                   global_result.idx, global_result.val);
        }
    }

    MPI_Barrier(MPI_COMM_WORLD);
    double t_end = MPI_Wtime();

    if (rank == 0) {
        double total_sec = t_end - t_start;
        double avg_sec = total_sec / k;
        printf("Кол-во итераций (k): %d\n", k);
        printf("Общее время: %.6f с\n", total_sec);
        printf("Среднее время: %.9f с\n", avg_sec);
        printf("RESULT:%d:%.2f:%.9f\n", 0, 0.0, avg_sec);

        free(sendcounts);
        free(displs);
        free(matrix);
    }

    free(local_matrix);
    MPI_Finalize();
    return 0;
}
