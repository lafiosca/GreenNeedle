/*
 * seed_search_st: Single-threaded seed search for comparison/debugging.
 * Compile: clang -O2 -std=c11 -o seed_search_st seed_search_st.c -lm
 */
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <getopt.h>

#include "greenneedle.c"

static const char *search_single_thread(
    const char *start_seed, int max_seeds,
    const char *tag, const char *pack_list,
    const char *voucher, const char *legendary,
    const char *spectral_card, const char *spectral_card2,
    const char *tarot_card, const char *tarot_card2,
    const char *tarot_key_append, int tarot_pack_size,
    const char *voucher2,
    const char *wraith_joker, uint32_t rare_joker_mask,
    const char *wraith_edition
) {
    static char result[16];
    result[0] = '\0';

    char pack_keys[32][64];
    int pack_count = 0;
    if (pack_list && pack_list[0]) {
        char buf[512];
        strncpy(buf, pack_list, sizeof(buf) - 1);
        buf[sizeof(buf)-1] = '\0';
        char *tok = strtok(buf, ",");
        while (tok && pack_count < 32) {
            strncpy(pack_keys[pack_count++], tok, 63);
            tok = strtok(NULL, ",");
        }
    }

    bool want_tag          = tag && tag[0];
    bool want_pack         = pack_count > 0;
    bool want_voucher      = voucher && voucher[0];
    bool want_legendary    = legendary && legendary[0];
    bool want_spectral     = spectral_card && spectral_card[0];
    bool want_spectral2    = spectral_card2 && spectral_card2[0];
    bool want_tarot_card   = tarot_card && tarot_card[0];
    bool want_tarot_card2  = tarot_card2 && tarot_card2[0];
    bool want_voucher2     = voucher2 && voucher2[0];
    bool want_wraith_joker = wraith_joker && wraith_joker[0];
    bool want_wraith_edition = wraith_edition && wraith_edition[0];
    if (!tarot_key_append || !tarot_key_append[0]) tarot_key_append = "ar1";
    if (tarot_pack_size <= 0) tarot_pack_size = 5;

    uint64_t offset = 0;
    int start_len = start_seed ? (int)strlen(start_seed) : 0;
    for (int i = 0; i < start_len && i < SEED_LEN; i++) {
        char c = start_seed[i];
        int v = -1;
        for (int j = 0; j < ALPHA_LEN; j++) {
            if (ALPHA[j] == c) { v = j; break; }
        }
        if (v < 0) v = 0;
        offset = offset * ALPHA_LEN + v;
    }

    char seed[SEED_LEN + 1];
    seed[SEED_LEN] = '\0';

    for (int n = 0; n < max_seeds; n++) {
        uint64_t tmp = offset + n;
        for (int i = SEED_LEN - 1; i >= 0; i--) {
            seed[i] = ALPHA[tmp % ALPHA_LEN];
            tmp /= ALPHA_LEN;
        }
        int slen = SEED_LEN;
        double hs = pseudohash(seed, slen);
        bool ok = true;

        if (ok && want_tag) {
            if (strcmp(predict_tag_h(seed, slen, 1, hs, 0), tag) != 0) ok = false;
        }
        if (ok && want_pack) {
            const char *p = predict_pack_h(seed, slen, 2, hs);
            bool found = false;
            for (int i = 0; i < pack_count && !found; i++) {
                if (strcmp(p, pack_keys[i]) == 0) found = true;
            }
            if (!found) ok = false;
        }
        if (ok && want_voucher) {
            if (strcmp(predict_voucher_h(seed, slen, 1, 0, hs), voucher) != 0) ok = false;
        }
        if (ok && want_legendary) {
            if (strcmp(predict_legendary_h(seed, slen, hs), legendary) != 0) ok = false;
        }
        if (ok && want_spectral) {
            if (!check_spectral_card_h(seed, slen, "spe", 1, 4, NULL, hs, spectral_card))
                ok = false;
        }
        if (ok && want_spectral2) {
            if (!check_spectral_card_h(seed, slen, "spe", 1, 4, NULL, hs, spectral_card2))
                ok = false;
        }
        if (ok && want_tarot_card) {
            if (!check_tarot_card_h(seed, slen, tarot_key_append, 1, tarot_pack_size, hs, tarot_card))
                ok = false;
        }
        if (ok && want_tarot_card2) {
            if (!check_tarot_card_h(seed, slen, tarot_key_append, 1, tarot_pack_size, hs, tarot_card2))
                ok = false;
        }
        if (ok && want_wraith_joker) {
            if (strcmp(predict_wraith_joker_h(seed, slen, 1, rare_joker_mask, hs), wraith_joker) != 0)
                ok = false;
        }
        if (ok && want_wraith_edition) {
            if (strcmp(predict_wraith_edition_h(seed, slen, 1, hs), wraith_edition) != 0)
                ok = false;
        }
        if (ok && want_voucher2) {
            uint32_t used = 0;
            if (want_voucher) {
                int vidx = voucher_index_by_key(voucher);
                if (vidx >= 0) used = (1u << vidx);
            }
            if (strcmp(predict_voucher_h(seed, slen, 2, used, hs), voucher2) != 0)
                ok = false;
        }

        if (ok) {
            memcpy(result, seed, SEED_LEN);
            result[SEED_LEN] = '\0';
            return result;
        }
    }
    return result;
}

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

    int opt;
    while ((opt = getopt(argc, argv, "s:n:t:p:v:l:c:C:T:R:A:P:V:W:E:")) != -1) {
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
            default: return 1;
        }
    }

    const char *result = search_single_thread(start_seed, count, tag, pack, voucher, legendary, spectral, spectral2, tarot, tarot2, tarot_append, tarot_pack_size, voucher2, wraith_joker, 0xFFFFF, wraith_edition);
    if (result && result[0]) {
        printf("%s\n", result);
    }
    return (result && result[0]) ? 0 : 1;
}
