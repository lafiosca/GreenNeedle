/*
 * Benchmark: throughput test for seed search.
 * Uses filters unlikely to match to force full scan of all seeds.
 * Compile: clang -O2 -std=c11 -o bench bench.c -lm && ./bench
 */
#include <stdio.h>
#include <string.h>
#include <time.h>
#include "greenneedle.c"

static double bench(const char *label, const char *start, int count,
                    const char *tag, const char *pack,
                    const char *voucher, const char *legendary,
                    const char *spectral) {
    struct timespec t0, t1;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    const char *r = greenneedle_search(start, count, tag, pack, voucher, legendary, spectral, 0, "", "", 5, "", "", "", "", 0xFFFFF, "", 4);
    clock_gettime(CLOCK_MONOTONIC, &t1);
    double ms = (t1.tv_sec - t0.tv_sec) * 1000.0 + (t1.tv_nsec - t0.tv_nsec) / 1e6;
    printf("  %-40s %6d seeds  %7.1f ms  %7.0f seeds/ms  result='%s'\n",
           label, count, ms, count / ms, r);
    return ms;
}

int main(void) {
    int cores = (int)sysconf(_SC_NPROCESSORS_ONLN);
    printf("CPU cores: %d (using up to %d threads)\n\n", cores, cores > MAX_THREADS ? MAX_THREADS : cores);

    printf("Throughput tests (threaded with %d threads):\n", cores > MAX_THREADS ? MAX_THREADS : cores);

    /* Tag-only: cheapest filter, ~1/24 match rate */
    bench("tag only", "AAAAAAAA", 100000,
          "tag_charm", "", "", "", "");

    /* Voucher combo: telescope + observatory */
    bench("voucher combo", "AAAAAAAA", 100000,
          "", "", "v_telescope", "", "");

    /* Tag + spectral: tag pre-filters, spectral is expensive */
    bench("tag + spectral", "AAAAAAAA", 100000,
          "tag_charm", "", "", "", "c_cryptid");

    /* Heavy: all filters */
    bench("tag + legendary + spectral", "AAAAAAAA", 100000,
          "tag_charm", "", "", "j_perkeo", "c_cryptid");

    printf("\nScaling (tag + spectral):\n");
    bench("10k", "AAAAAAAA", 10000, "tag_charm", "", "", "", "c_cryptid");
    bench("50k", "AAAAAAAA", 50000, "tag_charm", "", "", "", "c_cryptid");
    bench("100k", "AAAAAAAA", 100000, "tag_charm", "", "", "", "c_cryptid");
    bench("500k", "AAAAAAAA", 500000, "tag_charm", "", "", "", "c_cryptid");
    bench("1M", "AAAAAAAA", 1000000, "tag_charm", "", "", "", "c_cryptid");

    return 0;
}
