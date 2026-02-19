#!/usr/bin/env python3
"""
Вычислительный эксперимент: сравнение производительности
последовательного, OpenMP, MPI и CUDA алгоритмов.

Задача (вариант 16): определить строку с максимальной суммой элементов.

Запуск: python benchmark.py
"""

import subprocess
import re
import sys
import os

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt

# ============== Настройки эксперимента ==============

# Размеры матрицы (N x N) для тестирования
SIZES = [100, 500, 1000, 2000, 3000, 5000]

# Количество итераций усреднения для каждого размера
# Для больших матриц уменьшаем k, иначе слишком долго
ITERATIONS = {
    100:  100000,
    500:  10000,
    1000: 5000,
    2000: 1000,
    3000: 500,
    5000: 100,
}

MPI_PROCESSES = 4  # кол-во процессов MPI

# Имена исполняемых файлов (Windows: .exe)
EXT = ".exe" if sys.platform == "win32" else ""
SEQ_BIN   = f"./sequential{EXT}"
OMP_BIN   = f"./openmp_ver{EXT}"
MPI_BIN   = f"./mpi_ver{EXT}"
CUDA_BIN  = f"./cuda_ver{EXT}"

# ===================================================


def parse_result(output):
    """Извлекает среднее время из строки RESULT:row:sum:avg_time"""
    for line in output.strip().split('\n'):
        if line.startswith('RESULT:'):
            parts = line.split(':')
            return float(parts[3])
    return None


def run_benchmark(cmd, label):
    """Запускает команду и возвращает среднее время."""
    try:
        result = subprocess.run(
            cmd, capture_output=True, text=True, timeout=600, shell=True
        )
        if result.returncode != 0:
            print(f"  [ОШИБКА] {label}: {result.stderr.strip()}")
            return None
        print(result.stdout.strip())
        return parse_result(result.stdout)
    except FileNotFoundError:
        print(f"  [ПРОПУСК] {label}: исполняемый файл не найден")
        return None
    except subprocess.TimeoutExpired:
        print(f"  [ТАЙМАУТ] {label}: превышено 600 с")
        return None


def main():
    results = {
        "Последовательный": {},
        "OpenMP":           {},
        "MPI":              {},
        "CUDA":             {},
    }

    for N in SIZES:
        k = ITERATIONS.get(N, 1000)
        M = N  # квадратная матрица
        print(f"\n{'='*60}")
        print(f"  Матрица {N} x {M}, k = {k}")
        print(f"{'='*60}")

        # Последовательный
        t = run_benchmark(f"{SEQ_BIN} {N} {M} {k}", "Последовательный")
        if t is not None:
            results["Последовательный"][N] = t

        # OpenMP
        t = run_benchmark(f"{OMP_BIN} {N} {M} {k}", "OpenMP")
        if t is not None:
            results["OpenMP"][N] = t

        # MPI
        t = run_benchmark(f"mpirun -np {MPI_PROCESSES} {MPI_BIN} {N} {M} {k}", "MPI")
        if t is not None:
            results["MPI"][N] = t

        # CUDA
        t = run_benchmark(f"{CUDA_BIN} {N} {M} {k}", "CUDA")
        if t is not None:
            results["CUDA"][N] = t

    # ============ Вывод таблицы результатов ============
    print(f"\n\n{'='*80}")
    print("СВОДНАЯ ТАБЛИЦА: среднее время выполнения (секунды)")
    print(f"{'='*80}")
    header = f"{'Размер':>8}"
    for name in results:
        header += f" | {name:>18}"
    print(header)
    print("-" * len(header))

    for N in SIZES:
        row = f"{N:>8}"
        for name in results:
            val = results[name].get(N)
            if val is not None:
                row += f" | {val:>18.9f}"
            else:
                row += f" | {'—':>18}"
        print(row)

    # ============ Таблица ускорения ============
    print(f"\n{'='*80}")
    print("УСКОРЕНИЕ (относительно последовательного)")
    print(f"{'='*80}")
    header2 = f"{'Размер':>8}"
    for name in ["OpenMP", "MPI", "CUDA"]:
        header2 += f" | {name:>18}"
    print(header2)
    print("-" * len(header2))

    for N in SIZES:
        row = f"{N:>8}"
        seq_t = results["Последовательный"].get(N)
        for name in ["OpenMP", "MPI", "CUDA"]:
            par_t = results[name].get(N)
            if seq_t and par_t and par_t > 0:
                speedup = seq_t / par_t
                row += f" | {speedup:>17.2f}x"
            else:
                row += f" | {'—':>18}"
        print(row)

    # ============ Построение графиков ============
    os.makedirs("results", exist_ok=True)

    colors = {
        "Последовательный": "#1f77b4",
        "OpenMP":           "#ff7f0e",
        "MPI":              "#2ca02c",
        "CUDA":             "#d62728",
    }
    markers = {
        "Последовательный": "o",
        "OpenMP":           "s",
        "MPI":              "^",
        "CUDA":             "D",
    }

    # График 1: Время от размера входных данных
    plt.figure(figsize=(10, 6))
    for name, data in results.items():
        if data:
            sizes = sorted(data.keys())
            times = [data[s] for s in sizes]
            plt.plot(sizes, times, marker=markers[name], label=name,
                     color=colors[name], linewidth=2, markersize=8)

    plt.xlabel("Размер матрицы (N × N)", fontsize=12)
    plt.ylabel("Среднее время выполнения (с)", fontsize=12)
    plt.title("Зависимость времени выполнения от размера входных данных", fontsize=14)
    plt.legend(fontsize=11)
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig("results/time_vs_size.png", dpi=150)
    print("\nГрафик сохранён: results/time_vs_size.png")

    # График 2: Ускорение
    plt.figure(figsize=(10, 6))
    for name in ["OpenMP", "MPI", "CUDA"]:
        data = results[name]
        seq_data = results["Последовательный"]
        if data and seq_data:
            sizes = sorted(set(data.keys()) & set(seq_data.keys()))
            speedups = [seq_data[s] / data[s] for s in sizes if data[s] > 0]
            valid_sizes = [s for s in sizes if data[s] > 0]
            if valid_sizes:
                plt.plot(valid_sizes, speedups, marker=markers[name], label=name,
                         color=colors[name], linewidth=2, markersize=8)

    plt.axhline(y=1, color='gray', linestyle='--', alpha=0.5, label='Без ускорения')
    plt.xlabel("Размер матрицы (N × N)", fontsize=12)
    plt.ylabel("Ускорение (раз)", fontsize=12)
    plt.title("Ускорение параллельных реализаций относительно последовательной", fontsize=14)
    plt.legend(fontsize=11)
    plt.grid(True, alpha=0.3)
    plt.tight_layout()
    plt.savefig("results/speedup.png", dpi=150)
    print("График сохранён: results/speedup.png")

    # Сохранение данных в CSV
    with open("results/benchmark_data.csv", "w") as f:
        f.write("N,Sequential,OpenMP,MPI,CUDA\n")
        for N in SIZES:
            vals = []
            for name in ["Последовательный", "OpenMP", "MPI", "CUDA"]:
                v = results[name].get(N)
                vals.append(f"{v:.9f}" if v else "")
            f.write(f"{N},{','.join(vals)}\n")
    print("Данные сохранены: results/benchmark_data.csv")


if __name__ == "__main__":
    main()
