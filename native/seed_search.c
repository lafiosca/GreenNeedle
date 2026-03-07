/*
 * seed_search: CLI wrapper around greenneedle_search.
 * Compile: clang -O2 -std=c11 -o seed_search seed_search.c -lm -lpthread
 * Usage:   ./seed_search [options]
 *   -s START_SEED   Starting seed (default: 11111111)
 *   -n COUNT        Number of seeds to search (default: 1000000)
 *   -t TAG          Tag filter (e.g. tag_charm)
 *   -p PACK         Pack filter (comma-separated, e.g. p_spectral_mega_1)
 *   -v VOUCHER      Voucher filter (e.g. v_telescope)
 *   -l LEGENDARY    Legendary filter (e.g. j_perkeo)
 *   -c CARD         Spectral card filter (e.g. c_ankh)
 *   -C CARD2        Spectral card 2 filter
 *   -T CARD         Tarot card filter (e.g. c_emperor)
 *   -R CARD2        Tarot card 2 filter
 *   -A APPEND       Tarot key append (default: ar1)
 *   -P SIZE         Tarot pack size (default: 5)
 *   -V VOUCHER2     Ante 2 voucher filter (e.g. v_observatory)
 *   -W WRAITH       Wraith rare joker filter (e.g. j_blueprint)
 *   -E EDITION      Wraith edition filter (e.g. e_negative)
 *   -S SIZE         Spectral pack size (default: 4)
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <getopt.h>
#include "greenneedle.c"

int main(int argc, char **argv) {
    const char *start_seed = "11111111";
    int count = 1000000;
    const char *tag = "";
    const char *pack = "";
    const char *voucher = "";
    const char *legendary = "";
    const char *spectral = "";
    const char *spectral2 = "";
    const char *tarot = "";
    const char *tarot2 = "";
    const char *tarot_append = "ar1";
    int tarot_pack_size = 5;
    const char *voucher2 = "";
    const char *wraith_joker = "";
    const char *wraith_edition = "";
    int spectral_pack_size = 4;

    int opt;
    while ((opt = getopt(argc, argv, "s:n:t:p:v:l:c:C:T:R:A:P:V:W:E:S:")) != -1) {
        switch (opt) {
            case 's': start_seed = optarg; break;
            case 'n': count = atoi(optarg); break;
            case 't': tag = optarg; break;
            case 'p': pack = optarg; break;
            case 'v': voucher = optarg; break;
            case 'l': legendary = optarg; break;
            case 'c': spectral = optarg; break;
            case 'C': spectral2 = optarg; break;
            case 'T': tarot = optarg; break;
            case 'R': tarot2 = optarg; break;
            case 'A': tarot_append = optarg; break;
            case 'P': tarot_pack_size = atoi(optarg); break;
            case 'V': voucher2 = optarg; break;
            case 'W': wraith_joker = optarg; break;
            case 'E': wraith_edition = optarg; break;
            case 'S': spectral_pack_size = atoi(optarg); break;
            default:
                fprintf(stderr, "Usage: %s [-s start] [-n count] [-t tag] [-p pack] [-v voucher] [-l legendary] [-c spectral] [-C spectral2] [-T tarot] [-R tarot2] [-A append] [-P size] [-V voucher2] [-W wraith] [-E edition] [-S spectral_size]\n", argv[0]);
                return 1;
        }
    }

    fprintf(stderr, "Searching %d seeds from %s...\n", count, start_seed);
    fprintf(stderr, "  tag=%s pack=%s voucher=%s legendary=%s spectral=%s tarot=%s voucher2=%s wraith=%s edition=%s\n",
            tag, pack, voucher, legendary, spectral, tarot, voucher2, wraith_joker, wraith_edition);

    const char *result = greenneedle_search(start_seed, count, tag, pack, voucher, legendary, spectral, 0, tarot, tarot_append, tarot_pack_size, voucher2, tarot2, spectral2, wraith_joker, 0xFFFFF, wraith_edition, spectral_pack_size);

    if (result && result[0]) {
        printf("%s\n", result);
        fprintf(stderr, "Found: %s\n", result);
    } else {
        fprintf(stderr, "No match found.\n");
        return 1;
    }
    return 0;
}
