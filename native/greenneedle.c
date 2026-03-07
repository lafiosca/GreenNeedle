/*
 * Green Needle native seed searcher
 * Fast C implementation of Balatro's pseudorandom functions for seed searching.
 *
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

#include <stdint.h>
#include <stdbool.h>
#include <stdatomic.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <pthread.h>
#include <unistd.h>

/* --------------------------------------------------------------------------
 * Lua 5.4 PRNG (4-state xor-shift, matches math.randomseed / math.random)
 * -------------------------------------------------------------------------- */

typedef struct {
    uint64_t state[4];
    union { uint64_t ul; double d; } out;
} LRandom;

static void _randint(LRandom *lr) {
    uint64_t z, r = 0;
    z = lr->state[0];
    z = (((z<<31)^z)>>45) ^ ((z & ((uint64_t)(int64_t)-1<<1)) << 18);
    r ^= z; lr->state[0] = z;

    z = lr->state[1];
    z = (((z<<19)^z)>>30) ^ ((z & ((uint64_t)(int64_t)-1<<6)) << 28);
    r ^= z; lr->state[1] = z;

    z = lr->state[2];
    z = (((z<<24)^z)>>48) ^ ((z & ((uint64_t)(int64_t)-1<<9)) << 7);
    r ^= z; lr->state[2] = z;

    z = lr->state[3];
    z = (((z<<21)^z)>>39) ^ ((z & ((uint64_t)(int64_t)-1<<17)) << 8);
    r ^= z; lr->state[3] = z;

    lr->out.ul = r;
}

static LRandom randomseed(double d) {
    LRandom lr;
    uint32_t r = 0x11090601;
    for (int i = 0; i < 4; i++) {
        uint32_t m = 1u << (r & 255);
        r >>= 8;
        d = d * 3.14159265358979323846;
        d = d + 2.7182818284590452354;
        lr.out.d = d;
        uint64_t u = lr.out.ul;
        if (u < m) u += m;
        lr.state[i] = u;
    }
    for (int i = 0; i < 10; i++) _randint(&lr);
    return lr;
}

static double l_random(LRandom *lr) {
    _randint(lr);
    lr->out.ul = (lr->out.ul & 0x000FFFFFFFFFFFFFULL) | 0x3FF0000000000000ULL;
    lr->out.d -= 1.0;
    return lr->out.d;
}

static uint64_t l_randint(LRandom *lr, uint64_t min, uint64_t max) {
    double d = l_random(lr);
    uint64_t range = max - min + 1;
    uint64_t idx = (uint64_t)(d * (double)range);
    if (idx >= range) idx = range - 1; /* clamp rounding edge case */
    return idx + min;
}

/* --------------------------------------------------------------------------
 * pseudohash -- matches Balatro's pseudohash(str)
 * -------------------------------------------------------------------------- */

static double pseudohash(const char *s, int len) {
    double num = 1.0;
    for (int i = len - 1; i >= 0; i--) {
        double c = (double)(unsigned char)s[i];
        /* Reproduce the Lua floating-point computation exactly:
         * num = ((1.1239285023/num)*c*pi + pi*(i+1)) % 1
         * Immolate splits into int/fract parts for precision; we do the same. */
        double term1 = (1.1239285023 / num) * c * M_PI;
        double term2 = M_PI * (i + 1);
        double val = term1 + term2;
        /* fract */
        num = val - floor(val);
    }
    return num;
}

/* --------------------------------------------------------------------------
 * pseudoseed -- matches Balatro's pseudoseed(key, predict_seed) predict path
 * -------------------------------------------------------------------------- */

static double gn_pseudoseed(const char *key, int klen, const char *seed, int slen) {
    /* key .. seed */
    char buf[512];
    memcpy(buf, key, klen);
    memcpy(buf + klen, seed, slen);
    double _pseed = pseudohash(buf, klen + slen);
    /* advance */
    _pseed = fabs(fmod(2.134453429141 + _pseed * 1.72431234, 1.0));
    /* round to 13 decimal places (matches string.format("%.13f")) */
    _pseed = round(_pseed * 1e13) / 1e13;
    double hashed = pseudohash(seed, slen);
    return (_pseed + hashed) / 2.0;
}

/* Advance the pseudoseed state N times (for multi-ante voucher prediction).
 * Each call to pseudoseed for the same key in the live game advances the state. */
static double gn_pseudoseed_advance(const char *key, int klen, const char *seed, int slen, int advances) {
    char buf[512];
    memcpy(buf, key, klen);
    memcpy(buf + klen, seed, slen);
    double state = pseudohash(buf, klen + slen);
    for (int i = 0; i < advances; i++) {
        state = fabs(fmod(2.134453429141 + state * 1.72431234, 1.0));
        state = round(state * 1e13) / 1e13;
    }
    double hashed = pseudohash(seed, slen);
    return (state + hashed) / 2.0;
}

/* Cached variants: accept pre-computed pseudohash(seed) to avoid redundant hashing */
static double gn_pseudoseed_h(const char *key, int klen, const char *seed, int slen, double hashed_seed) {
    char buf[512];
    memcpy(buf, key, klen);
    memcpy(buf + klen, seed, slen);
    double _pseed = pseudohash(buf, klen + slen);
    _pseed = fabs(fmod(2.134453429141 + _pseed * 1.72431234, 1.0));
    _pseed = round(_pseed * 1e13) / 1e13;
    return (_pseed + hashed_seed) / 2.0;
}

static double gn_pseudoseed_advance_h(const char *key, int klen, const char *seed, int slen,
                                       int advances, double hashed_seed) {
    char buf[512];
    memcpy(buf, key, klen);
    memcpy(buf + klen, seed, slen);
    double state = pseudohash(buf, klen + slen);
    for (int i = 0; i < advances; i++) {
        state = fabs(fmod(2.134453429141 + state * 1.72431234, 1.0));
        state = round(state * 1e13) / 1e13;
    }
    return (state + hashed_seed) / 2.0;
}

/* --------------------------------------------------------------------------
 * Pool definitions -- mirrors Balatro's G.P_CENTER_POOLS ordering
 * All pools are sorted by 'order' field as Balatro does at startup.
 *
 * Pool key construction (from get_current_pool):
 *   _pool_key = _type .. (_append or '') .. ante
 * So for Tarot with key_append='ar1' at ante 1: "Tarot" + "ar1" + "1" = "Tarotar11"
 * For Spectral with key_append='spe' at ante 1: "Spectral" + "spe" + "1" = "Spectralspe1"
 *
 * Soul slots do NOT advance the card pool state (forced_key bypasses pseudorandom_element).
 * -------------------------------------------------------------------------- */

/* Tags (order-sorted, all 24 from game.lua).
 * Some are marked UNAVAILABLE at ante 1:
 *   - tag_rare requires j_blueprint (not discovered on fresh profile)
 *   - min_ante=2 tags: negative, standard, meteor, buffoon, handy,
 *                      garbage, ethereal, top_up, orbital */
typedef struct { const char *key; bool ante1_available; } TagDef;
static const TagDef TAG_POOL[] = {
    { "tag_uncommon",   true  }, /* order 1  */
    { "tag_rare",       true  }, /* order 2  - requires j_blueprint (discovered) */
    { "tag_negative",   false }, /* order 3  - min_ante 2, requires e_negative */
    { "tag_foil",       true  }, /* order 4  - requires e_foil (discovered) */
    { "tag_holo",       true  }, /* order 5  - requires e_holo (discovered) */
    { "tag_polychrome", true  }, /* order 6  - requires e_polychrome (discovered) */
    { "tag_investment", true  }, /* order 7  */
    { "tag_voucher",    true  }, /* order 8  */
    { "tag_boss",       true  }, /* order 9  */
    { "tag_standard",   false }, /* order 10 - min_ante 2 */
    { "tag_charm",      true  }, /* order 11 */
    { "tag_meteor",     false }, /* order 12 - min_ante 2 */
    { "tag_buffoon",    false }, /* order 13 - min_ante 2 */
    { "tag_handy",      false }, /* order 14 - min_ante 2 */
    { "tag_garbage",    false }, /* order 15 - min_ante 2 */
    { "tag_ethereal",   false }, /* order 16 - min_ante 2 */
    { "tag_coupon",     true  }, /* order 17 */
    { "tag_double",     true  }, /* order 18 */
    { "tag_juggle",     true  }, /* order 19 */
    { "tag_d_six",      true  }, /* order 20 */
    { "tag_top_up",     false }, /* order 21 - min_ante 2 */
    { "tag_skip",       true  }, /* order 22 */
    { "tag_orbital",    false }, /* order 23 - min_ante 2 */
    { "tag_economy",    true  }, /* order 24 */
};
#define TAG_POOL_SIZE 24

/* Vouchers (order-sorted). Even-index entries (0-based) are base tier,
 * odd-index are upgrades. Upgrade vouchers require their base to be used. */
typedef struct { const char *key; const char *requires; } VoucherDef;
static const VoucherDef VOUCHER_DEFS[] = {
    { "v_overstock_norm",  NULL },               /* order 1  */
    { "v_overstock_plus",  "v_overstock_norm" }, /* order 2  */
    { "v_clearance_sale",  NULL },               /* order 3  */
    { "v_liquidation",     "v_clearance_sale" }, /* order 4  */
    { "v_hone",            NULL },               /* order 5  */
    { "v_glow_up",         "v_hone" },           /* order 6  */
    { "v_reroll_surplus",  NULL },               /* order 7  */
    { "v_reroll_glut",     "v_reroll_surplus" }, /* order 8  */
    { "v_crystal_ball",    NULL },               /* order 9  */
    { "v_omen_globe",      "v_crystal_ball" },   /* order 10 */
    { "v_telescope",       NULL },               /* order 11 */
    { "v_observatory",     "v_telescope" },      /* order 12 */
    { "v_grabber",         NULL },               /* order 13 */
    { "v_nacho_tong",      "v_grabber" },        /* order 14 */
    { "v_wasteful",        NULL },               /* order 15 */
    { "v_recyclomancy",    "v_wasteful" },       /* order 16 */
    { "v_tarot_merchant",  NULL },               /* order 17 */
    { "v_tarot_tycoon",    "v_tarot_merchant" }, /* order 18 */
    { "v_planet_merchant", NULL },               /* order 19 */
    { "v_planet_tycoon",   "v_planet_merchant"},  /* order 20 */
    { "v_seed_money",      NULL },               /* order 21 */
    { "v_money_tree",      "v_seed_money" },     /* order 22 */
    { "v_blank",           NULL },               /* order 23 */
    { "v_antimatter",      "v_blank" },          /* order 24 */
    { "v_magic_trick",     NULL },               /* order 25 */
    { "v_illusion",        "v_magic_trick" },    /* order 26 */
    { "v_hieroglyph",      NULL },               /* order 27 */
    { "v_petroglyph",      "v_hieroglyph" },     /* order 28 */
    { "v_directors_cut",   NULL },               /* order 29 */
    { "v_retcon",          "v_directors_cut" },  /* order 30 */
    { "v_paint_brush",     NULL },               /* order 31 */
    { "v_palette",         "v_paint_brush" },    /* order 32 */
};
#define VOUCHER_DEFS_SIZE 32

/* Legendary jokers in order */
static const char *LEGENDARY_POOL[] = {
    "j_caino",
    "j_triboulet",
    "j_yorick",
    "j_chicot",
    "j_perkeo",
};
#define LEGENDARY_POOL_SIZE 5

/* Rare jokers in order (rarity=3, sorted by order field).
 * Used for predicting Wraith's rare joker creation.
 * Pool key: "Joker3wra" + ante */
static const char *RARE_JOKER_POOL[] = {
    "j_dna",              /* order 51  */
    "j_vagabond",         /* order 71  */
    "j_baron",            /* order 72  */
    "j_obelisk",          /* order 75  */
    "j_baseball",         /* order 92  */
    "j_ancient",          /* order 99  */
    "j_campfire",         /* order 105 */
    "j_blueprint",        /* order 123 */
    "j_wee",              /* order 124 */
    "j_hit_the_road",     /* order 130 */
    "j_duo",              /* order 131 */
    "j_trio",             /* order 132 */
    "j_family",           /* order 133 */
    "j_order",            /* order 134 */
    "j_tribe",            /* order 135 */
    "j_stuntman",         /* order 136 */
    "j_invisible",        /* order 137 */
    "j_brainstorm",       /* order 138 */
    "j_drivers_license",  /* order 141 */
    "j_burnt",            /* order 144 */
};
#define RARE_JOKER_POOL_SIZE 20

/* Tarot cards (order-sorted, 22 cards from game.lua) */
static const char *TAROT_POOL[] = {
    "c_fool",            /* order 1  */
    "c_magician",        /* order 2  */
    "c_high_priestess",  /* order 3  */
    "c_empress",         /* order 4  */
    "c_emperor",         /* order 5  */
    "c_heirophant",      /* order 6  */
    "c_lovers",          /* order 7  */
    "c_chariot",         /* order 8  */
    "c_justice",         /* order 9  */
    "c_hermit",          /* order 10 */
    "c_wheel_of_fortune",/* order 11 */
    "c_strength",        /* order 12 */
    "c_hanged_man",      /* order 13 */
    "c_death",           /* order 14 */
    "c_temperance",      /* order 15 */
    "c_devil",           /* order 16 */
    "c_tower",           /* order 17 */
    "c_star",            /* order 18 */
    "c_moon",            /* order 19 */
    "c_sun",             /* order 20 */
    "c_judgement",       /* order 21 */
    "c_world",           /* order 22 */
};
#define TAROT_POOL_SIZE 22

/* Spectral cards (order-sorted, 18 entries total).
 * c_soul and c_black_hole are forced to UNAVAILABLE by get_current_pool (add=false),
 * but they still occupy pool slots 17 and 18. math.random(#pool) uses pool size 18,
 * so we must also use 18 and treat the last two slots as UNAVAILABLE. */
static const char *SPECTRAL_POOL[] = {
    "c_familiar",    /* order 1  */
    "c_grim",        /* order 2  */
    "c_incantation", /* order 3  */
    "c_talisman",    /* order 4  */
    "c_aura",        /* order 5  */
    "c_wraith",      /* order 6  */
    "c_sigil",       /* order 7  */
    "c_ouija",       /* order 8  */
    "c_ectoplasm",   /* order 9  */
    "c_immolate",    /* order 10 */
    "c_ankh",        /* order 11 */
    "c_deja_vu",     /* order 12 */
    "c_hex",         /* order 13 */
    "c_trance",      /* order 14 */
    "c_medium",      /* order 15 */
    "c_cryptid",     /* order 16 */
    NULL,            /* order 17: c_soul    -- UNAVAILABLE (add=false) */
    NULL,            /* order 18: c_black_hole -- UNAVAILABLE (add=false) */
};
#define SPECTRAL_POOL_SIZE 18
#define SPECTRAL_CARDS_AVAILABLE 16  /* only indices 0..15 are real cards */

/* Booster packs with weights (matches Balatro's G.P_CENTER_POOLS['Booster']) */
typedef struct { const char *key; double weight; } PackDef;
static const PackDef PACK_DEFS[] = {
    { "p_arcana_normal_1",    4.00 },
    { "p_arcana_normal_2",    4.00 },
    { "p_arcana_normal_3",    4.00 },
    { "p_arcana_normal_4",    4.00 },
    { "p_arcana_jumbo_1",     2.00 },
    { "p_arcana_jumbo_2",     2.00 },
    { "p_arcana_mega_1",      0.50 },
    { "p_arcana_mega_2",      0.50 },
    { "p_celestial_normal_1", 4.00 },
    { "p_celestial_normal_2", 4.00 },
    { "p_celestial_normal_3", 4.00 },
    { "p_celestial_normal_4", 4.00 },
    { "p_celestial_jumbo_1",  2.00 },
    { "p_celestial_jumbo_2",  2.00 },
    { "p_celestial_mega_1",   0.50 },
    { "p_celestial_mega_2",   0.50 },
    { "p_standard_normal_1",  4.00 },
    { "p_standard_normal_2",  4.00 },
    { "p_standard_normal_3",  4.00 },
    { "p_standard_normal_4",  4.00 },
    { "p_standard_jumbo_1",   2.00 },
    { "p_standard_jumbo_2",   2.00 },
    { "p_standard_mega_1",    0.50 },
    { "p_standard_mega_2",    0.50 },
    { "p_buffoon_normal_1",   1.20 },
    { "p_buffoon_normal_2",   1.20 },
    { "p_buffoon_jumbo_1",    0.60 },
    { "p_buffoon_mega_1",     0.15 },
    { "p_spectral_normal_1",  0.60 },
    { "p_spectral_normal_2",  0.60 },
    { "p_spectral_jumbo_1",   0.30 },
    { "p_spectral_mega_1",    0.07 },
};
#define PACK_DEFS_SIZE 32

/* --------------------------------------------------------------------------
 * Prediction functions
 * -------------------------------------------------------------------------- */

/* Build voucher pool given used_vouchers bitmask (bit i = VOUCHER_DEFS[i] used).
 * Returns count of available slots; pool_out[] filled with indices into VOUCHER_DEFS
 * or -1 for UNAVAILABLE, length VOUCHER_DEFS_SIZE. */
static void build_voucher_pool(uint32_t used_mask, int pool_out[VOUCHER_DEFS_SIZE]) {
    for (int i = 0; i < VOUCHER_DEFS_SIZE; i++) {
        const VoucherDef *v = &VOUCHER_DEFS[i];
        bool available = true;
        /* already used */
        if (used_mask & (1u << i)) { available = false; }
        /* requires not yet used */
        if (available && v->requires) {
            bool req_found = false;
            for (int j = 0; j < VOUCHER_DEFS_SIZE; j++) {
                if (strcmp(VOUCHER_DEFS[j].key, v->requires) == 0) {
                    if (used_mask & (1u << j)) req_found = true;
                    break;
                }
            }
            if (!req_found) available = false;
        }
        pool_out[i] = available ? i : -1;
    }
}

static int voucher_index_by_key(const char *key) {
    for (int i = 0; i < VOUCHER_DEFS_SIZE; i++) {
        if (strcmp(VOUCHER_DEFS[i].key, key) == 0) return i;
    }
    return -1;
}

/* All prediction functions accept an optional hashed_seed parameter.
 * Pass a negative value (e.g. -1.0) to compute pseudohash(seed) internally;
 * pass a pre-computed value to avoid redundant hashing in tight loops. */

static const char *predict_voucher_h(const char *seed, int slen, int ante,
                                      uint32_t used_mask, double hs) {
    if (hs < 0) hs = pseudohash(seed, slen);
    int pool[VOUCHER_DEFS_SIZE];
    build_voucher_pool(used_mask, pool);

    double pseed = gn_pseudoseed_advance_h("Voucher", 7, seed, slen, ante - 1, hs);

    LRandom rng = randomseed(pseed);
    uint64_t idx = l_randint(&rng, 1, (uint64_t)VOUCHER_DEFS_SIZE);
    int chosen = pool[idx - 1];

    int resample = 1;
    while (chosen == -1 && resample < 100) {
        char reskey[64];
        int rklen = snprintf(reskey, sizeof(reskey), "Voucher%d_resample%d", ante, resample + 1);
        double rpseed = gn_pseudoseed_h(reskey, rklen, seed, slen, hs);
        rng = randomseed(rpseed);
        idx = l_randint(&rng, 1, (uint64_t)VOUCHER_DEFS_SIZE);
        chosen = pool[idx - 1];
        resample++;
    }
    if (chosen == -1) return VOUCHER_DEFS[0].key;
    return VOUCHER_DEFS[chosen].key;
}

static const char *predict_legendary_h(const char *seed, int slen, double hs) {
    if (hs < 0) hs = pseudohash(seed, slen);
    double pseed = gn_pseudoseed_h("Joker4", 6, seed, slen, hs);
    LRandom rng = randomseed(pseed);
    uint64_t idx = l_randint(&rng, 1, (uint64_t)LEGENDARY_POOL_SIZE);
    return LEGENDARY_POOL[idx - 1];
}

/* Predict the rare joker that Wraith creates.
 * Pool key: "Joker3wra" + ante (ante is 1-indexed).
 * rare_avail_mask: bitmask of unlocked rare jokers (bit i = RARE_JOKER_POOL[i] available).
 * Assumes no jokers currently owned (empty used_jokers). */
static const char *predict_wraith_joker_h(const char *seed, int slen, int ante,
                                           uint32_t rare_avail_mask, double hs) {
    if (hs < 0) hs = pseudohash(seed, slen);
    char pool_key[32];
    int pklen = snprintf(pool_key, sizeof(pool_key), "Joker3wra%d", ante);
    double pseed = gn_pseudoseed_h(pool_key, pklen, seed, slen, hs);
    LRandom rng = randomseed(pseed);
    uint64_t idx = l_randint(&rng, 1, (uint64_t)RARE_JOKER_POOL_SIZE);

    bool avail = (rare_avail_mask >> (idx - 1)) & 1;
    int resample = 1;
    while (!avail && resample < 100) {
        resample++;
        char reskey[64];
        int rklen = snprintf(reskey, sizeof(reskey), "Joker3wra%d_resample%d", ante, resample);
        double rpseed = gn_pseudoseed_h(reskey, rklen, seed, slen, hs);
        rng = randomseed(rpseed);
        idx = l_randint(&rng, 1, (uint64_t)RARE_JOKER_POOL_SIZE);
        avail = (rare_avail_mask >> (idx - 1)) & 1;
    }
    return RARE_JOKER_POOL[idx - 1];
}

/* tag_avail_mask: bitmask of available tags (bit i = TAG_POOL[i] available).
 * If 0, falls back to the hardcoded ante1_available flags. */
static const char *predict_tag_h(const char *seed, int slen, int ante, double hs, uint32_t tag_avail_mask) {
    if (hs < 0) hs = pseudohash(seed, slen);
    bool use_mask = (tag_avail_mask != 0);
    char pool_key[16];
    int pklen = snprintf(pool_key, sizeof(pool_key), "Tag%d", ante);
    double pseed = gn_pseudoseed_h(pool_key, pklen, seed, slen, hs);
    LRandom rng = randomseed(pseed);
    uint64_t idx = l_randint(&rng, 1, (uint64_t)TAG_POOL_SIZE);

    int it = 1;
    bool avail = use_mask ? ((tag_avail_mask >> (idx - 1)) & 1) : TAG_POOL[idx - 1].ante1_available;
    while (!avail && it < 100) {
        it++;
        char reskey[32];
        int rklen = snprintf(reskey, sizeof(reskey), "Tag%d_resample%d", ante, it);
        double rpseed = gn_pseudoseed_h(reskey, rklen, seed, slen, hs);
        rng = randomseed(rpseed);
        idx = l_randint(&rng, 1, (uint64_t)TAG_POOL_SIZE);
        avail = use_mask ? ((tag_avail_mask >> (idx - 1)) & 1) : TAG_POOL[idx - 1].ante1_available;
    }
    return TAG_POOL[idx - 1].key;
}

static const char *predict_pack_h(const char *seed, int slen, int slot, double hs) {
    if (slot == 1) return "p_buffoon_normal_1";
    if (hs < 0) hs = pseudohash(seed, slen);

    char key[32];
    int klen = snprintf(key, sizeof(key), "shop_pack1");
    double pseed = gn_pseudoseed_h(key, klen, seed, slen, hs);

    double total_weight = 0.0;
    for (int i = 0; i < PACK_DEFS_SIZE; i++) total_weight += PACK_DEFS[i].weight;

    LRandom rng = randomseed(pseed);
    double poll = l_random(&rng) * total_weight;
    double cumulative = 0.0;
    for (int i = 0; i < PACK_DEFS_SIZE; i++) {
        cumulative += PACK_DEFS[i].weight;
        if (cumulative >= poll) return PACK_DEFS[i].key;
    }
    return PACK_DEFS[PACK_DEFS_SIZE - 1].key;
}

static bool check_soul_h(const char *seed, int slen, const char *soul_type,
                          int ante, int pack_size, double hs) {
    if (hs < 0) hs = pseudohash(seed, slen);
    char key[64];
    int klen = snprintf(key, sizeof(key), "soul_%s%d", soul_type, ante);
    for (int i = 1; i <= pack_size; i++) {
        double pseed = gn_pseudoseed_advance_h(key, klen, seed, slen, i, hs);
        LRandom rng = randomseed(pseed);
        if (l_random(&rng) > 0.997) return true;
    }
    return false;
}

/* Predict the edition of the joker Wraith creates.
 * Uses pseudoseed key "ediwra" + ante. poll_edition base rates (no Hone/Glow Up):
 *   > 0.997  → Negative   (0.3%)
 *   > 0.994  → Polychrome (0.6%)
 *   > 0.98   → Holographic (2%)
 *   > 0.96   → Foil       (4%)
 *   else     → No edition  (~93.1%)
 * Returns edition key string, or "" for no edition. */
static const char *predict_wraith_edition_h(const char *seed, int slen, int ante, double hs) {
    if (hs < 0) hs = pseudohash(seed, slen);
    char key[32];
    int klen = snprintf(key, sizeof(key), "ediwra%d", ante);
    double pseed = gn_pseudoseed_h(key, klen, seed, slen, hs);
    LRandom rng = randomseed(pseed);
    double poll = l_random(&rng);
    if (poll > 0.997) return "e_negative";
    if (poll > 1.0 - 0.006) return "e_polychrome";
    if (poll > 1.0 - 0.02) return "e_holographic";
    if (poll > 1.0 - 0.04) return "e_foil";
    return "";
}

/* Search check for tarot cards: returns true if target_card appears in any slot (early exit).
 * Same logic as predict_tarot_cards but with hashed_seed cache and early termination. */
static bool check_tarot_card_h(const char *seed, int slen, const char *key_append, int ante,
                                int pack_size, double hs, const char *target_card) {
    if (hs < 0) hs = pseudohash(seed, slen);
    char soul_key[64];
    int soul_klen = snprintf(soul_key, sizeof(soul_key), "soul_Tarot%d", ante);
    char card_key[64];
    int card_klen = snprintf(card_key, sizeof(card_key), "Tarot%s%d", key_append, ante);

    int card_advance = 0;
    for (int slot = 1; slot <= pack_size; slot++) {
        double soul_pseed = gn_pseudoseed_advance_h(soul_key, soul_klen, seed, slen, slot, hs);
        LRandom soul_rng = randomseed(soul_pseed);
        if (l_random(&soul_rng) > 0.997) {
            if (strcmp("c_soul", target_card) == 0) return true;
            /* Soul fires: card pool state NOT advanced */
        } else {
            card_advance++;
            double pseed = gn_pseudoseed_advance_h(card_key, card_klen, seed, slen, card_advance, hs);
            LRandom rng = randomseed(pseed);
            uint64_t idx = l_randint(&rng, 1, TAROT_POOL_SIZE);
            if (strcmp(TAROT_POOL[idx - 1], target_card) == 0) return true;
        }
    }
    return false;
}

/* Core spectral prediction with cached hashed_seed.
 * out_cards: if non-NULL, fills with predicted card keys for all slots.
 * target_card: if non-NULL, returns true as soon as this card is found (early exit). */
static bool predict_spectral_inner(const char *seed, int slen, const char *key_append, int ante,
                                    int pack_size, const char *extra_excluded, double hs,
                                    const char **out_cards, const char *target_card) {
    char tarot_soul_key[64];
    int tarot_soul_klen = snprintf(tarot_soul_key, sizeof(tarot_soul_key), "soul_Tarot%d", ante);
    char spectral_soul_key[64];
    int spectral_soul_klen = snprintf(spectral_soul_key, sizeof(spectral_soul_key), "soul_Spectral%d", ante);

    char card_key[64];
    int card_klen = snprintf(card_key, sizeof(card_key), "Spectral%s%d", key_append, ante);

    bool unavailable[SPECTRAL_POOL_SIZE];
    for (int i = 0; i < SPECTRAL_POOL_SIZE; i++)
        unavailable[i] = (SPECTRAL_POOL[i] == NULL);

    if (extra_excluded && extra_excluded[0]) {
        for (int i = 0; i < SPECTRAL_CARDS_AVAILABLE; i++) {
            if (strcmp(SPECTRAL_POOL[i], extra_excluded) == 0) {
                unavailable[i] = true;
                break;
            }
        }
    }

    int card_advance = 0;
    for (int slot = 1; slot <= pack_size; slot++) {
        /* c_soul check */
        double soul_pseed = gn_pseudoseed_advance_h(tarot_soul_key, tarot_soul_klen, seed, slen, slot, hs);
        LRandom soul_rng = randomseed(soul_pseed);
        if (l_random(&soul_rng) > 0.997) {
            if (out_cards) out_cards[slot - 1] = "c_soul";
            if (target_card && strcmp("c_soul", target_card) == 0) return true;
            continue;
        }
        /* c_black_hole check */
        double bh_pseed = gn_pseudoseed_advance_h(spectral_soul_key, spectral_soul_klen, seed, slen, slot, hs);
        LRandom bh_rng = randomseed(bh_pseed);
        if (l_random(&bh_rng) > 0.997) {
            if (out_cards) out_cards[slot - 1] = "c_black_hole";
            if (target_card && strcmp("c_black_hole", target_card) == 0) return true;
            continue;
        }
        /* Normal spectral card */
        card_advance++;
        double pseed = gn_pseudoseed_advance_h(card_key, card_klen, seed, slen, card_advance, hs);
        LRandom rng = randomseed(pseed);
        uint64_t idx = l_randint(&rng, 1, SPECTRAL_POOL_SIZE);

        int resample = 1;
        while (unavailable[idx - 1] && resample < 100) {
            resample++;
            char reskey[64];
            int rklen = snprintf(reskey, sizeof(reskey), "Spectral%s%d_resample%d", key_append, ante, resample);
            double rpseed = gn_pseudoseed_h(reskey, rklen, seed, slen, hs);
            LRandom rrng = randomseed(rpseed);
            idx = l_randint(&rrng, 1, SPECTRAL_POOL_SIZE);
        }

        const char *card = SPECTRAL_POOL[idx - 1];
        if (out_cards) out_cards[slot - 1] = card;
        if (target_card && card && strcmp(card, target_card) == 0) return true;
        unavailable[idx - 1] = true;
    }
    return false;
}

/* Full prediction (fills out_cards array) */
static void predict_spectral_cards(const char *seed, int slen, const char *key_append, int ante,
                                    int pack_size, const char *extra_excluded,
                                    const char **out_cards) {
    double hs = pseudohash(seed, slen);
    predict_spectral_inner(seed, slen, key_append, ante, pack_size, extra_excluded, hs, out_cards, NULL);
}

/* Search check: returns true if target_card appears in any slot (early exit) */
static bool check_spectral_card_h(const char *seed, int slen, const char *key_append, int ante,
                                   int pack_size, const char *extra_excluded, double hs,
                                   const char *target_card) {
    return predict_spectral_inner(seed, slen, key_append, ante, pack_size, extra_excluded, hs, NULL, target_card);
}

/* --------------------------------------------------------------------------
 * Public API -- called from Lua via FFI
 * -------------------------------------------------------------------------- */

/*
 * Search for a seed matching the given filters starting from `start_seed`.
 * Searches up to `max_seeds` candidates.
 *
 * Filters (pass NULL/"" to disable):
 *   tag           - required ante-1 tag key (e.g. "tag_charm"), or ""
 *   pack_list     - required ante-1 shop pack key(s), comma-separated, or ""
 *   voucher       - required ante-1 voucher key (e.g. "v_telescope"), or ""
 *   legendary     - required legendary joker key (e.g. "j_perkeo"), or ""
 *   spectral_card - required card in first mega spectral pack (e.g. "c_ankh"), or ""
 *                   ("c_soul" and "c_black_hole" are also valid)
 *
 * Returns a newly-allocated string with the found seed, or "" if not found.
 * The caller must NOT free this string (it's a static buffer).
 */
/* --------------------------------------------------------------------------
 * Thread worker for parallel seed search
 * -------------------------------------------------------------------------- */

static const char ALPHA[] = "123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
#define ALPHA_LEN 35
#define SEED_LEN  8
#define MAX_THREADS 16

typedef struct {
    /* Input: seed range */
    uint64_t       start_offset;
    int            count;
    /* Input: filters (read-only pointers) */
    const char    *tag;
    uint32_t       tag_avail_mask;
    const char   (*pack_keys)[64];
    int            pack_count;
    const char    *voucher;
    const char    *legendary;
    const char    *spectral_card;
    const char    *tarot_card;
    const char    *tarot_card2;
    const char    *tarot_key_append;
    int            tarot_pack_size;
    int            spectral_pack_size;
    const char    *spectral_card2;
    const char    *voucher2;
    const char    *wraith_joker;
    uint32_t       rare_joker_mask;
    const char    *wraith_edition;
    bool           want_tag, want_pack, want_voucher;
    bool           want_legendary, want_spectral;
    bool           want_tarot_card, want_tarot_card2;
    bool           want_spectral2, want_voucher2;
    bool           want_wraith_joker, want_wraith_edition;
    /* Output */
    char           result[SEED_LEN + 1];
    /* Shared: early exit flag (set by any thread that finds a match) */
    atomic_int    *found;
} SearchWorker;

static void *search_worker(void *arg) {
    SearchWorker *w = (SearchWorker *)arg;
    char seed[SEED_LEN + 1];
    seed[SEED_LEN] = '\0';

    for (int n = 0; n < w->count; n++) {
        /* Check if another thread already found a result (every 32 seeds) */
        if ((n & 31) == 0 && atomic_load(w->found)) return NULL;

        uint64_t tmp = w->start_offset + n;
        for (int i = SEED_LEN - 1; i >= 0; i--) {
            seed[i] = ALPHA[tmp % ALPHA_LEN];
            tmp /= ALPHA_LEN;
        }
        int slen = SEED_LEN;
        double hs = pseudohash(seed, slen);
        bool ok = true;

        if (ok && w->want_tag) {
            if (strcmp(predict_tag_h(seed, slen, 1, hs, w->tag_avail_mask), w->tag) != 0) ok = false;
        }
        if (ok && w->want_pack) {
            const char *p = predict_pack_h(seed, slen, 2, hs);
            bool found = false;
            for (int i = 0; i < w->pack_count && !found; i++) {
                if (strcmp(p, w->pack_keys[i]) == 0) found = true;
            }
            if (!found) ok = false;
        }
        if (ok && w->want_voucher) {
            if (strcmp(predict_voucher_h(seed, slen, 1, 0, hs), w->voucher) != 0) ok = false;
        }
        if (ok && w->want_legendary) {
            if (strcmp(predict_legendary_h(seed, slen, hs), w->legendary) != 0) ok = false;
        }
        if (ok && w->want_spectral) {
            if (!check_spectral_card_h(seed, slen, "spe", 1, w->spectral_pack_size, NULL, hs, w->spectral_card))
                ok = false;
        }
        if (ok && w->want_spectral2) {
            if (!check_spectral_card_h(seed, slen, "spe", 1, w->spectral_pack_size, NULL, hs, w->spectral_card2))
                ok = false;
        }
        if (ok && w->want_tarot_card) {
            if (!check_tarot_card_h(seed, slen, w->tarot_key_append, 1,
                                     w->tarot_pack_size, hs, w->tarot_card))
                ok = false;
        }
        if (ok && w->want_tarot_card2) {
            if (!check_tarot_card_h(seed, slen, w->tarot_key_append, 1,
                                     w->tarot_pack_size, hs, w->tarot_card2))
                ok = false;
        }
        if (ok && w->want_wraith_joker) {
            if (strcmp(predict_wraith_joker_h(seed, slen, 1, w->rare_joker_mask, hs), w->wraith_joker) != 0)
                ok = false;
        }
        if (ok && w->want_wraith_edition) {
            if (strcmp(predict_wraith_edition_h(seed, slen, 1, hs), w->wraith_edition) != 0)
                ok = false;
        }
        if (ok && w->want_voucher2) {
            /* Ante 2 voucher: the ante 1 voucher was purchased, so mark it used */
            uint32_t used = 0;
            if (w->want_voucher) {
                int vidx = voucher_index_by_key(w->voucher);
                if (vidx >= 0) used = (1u << vidx);
            }
            if (strcmp(predict_voucher_h(seed, slen, 2, used, hs), w->voucher2) != 0)
                ok = false;
        }

        if (ok) {
            memcpy(w->result, seed, SEED_LEN);
            w->result[SEED_LEN] = '\0';
            atomic_store(w->found, 1);
            return NULL;
        }
    }
    return NULL;
}

const char *greenneedle_search(
    const char *start_seed,
    int         max_seeds,
    const char *tag,
    const char *pack_list,
    const char *voucher,
    const char *legendary,
    const char *spectral_card,
    uint32_t    tag_avail_mask,
    const char *tarot_card,
    const char *tarot_key_append,
    int         tarot_pack_size,
    const char *voucher2,
    const char *tarot_card2,
    const char *spectral_card2,
    const char *wraith_joker,
    uint32_t    rare_joker_mask,
    const char *wraith_edition,
    int         spectral_pack_size
) {
    static char result[16];
    result[0] = '\0';

    /* Parse pack_list into individual keys */
    char pack_keys[32][64];
    int  pack_count = 0;
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

    if (max_seeds <= 0) max_seeds = 1000;

    bool want_tag          = tag && tag[0];
    bool want_pack         = pack_count > 0;
    bool want_voucher      = voucher && voucher[0];
    bool want_legendary    = legendary && legendary[0];
    bool want_spectral     = spectral_card && spectral_card[0];
    bool want_tarot_card   = tarot_card && tarot_card[0];
    bool want_voucher2     = voucher2 && voucher2[0];
    bool want_tarot_card2  = tarot_card2 && tarot_card2[0];
    bool want_spectral2    = spectral_card2 && spectral_card2[0];
    bool want_wraith_joker = wraith_joker && wraith_joker[0];
    bool want_wraith_edition = wraith_edition && wraith_edition[0];

    /* Decode start_seed to a uint64 */
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

    /* Determine thread count */
    int num_threads = (int)sysconf(_SC_NPROCESSORS_ONLN);
    if (num_threads <= 0) num_threads = 4;
    if (num_threads > MAX_THREADS) num_threads = MAX_THREADS;
    if (num_threads > max_seeds) num_threads = max_seeds;

    atomic_int found_flag = 0;
    SearchWorker workers[MAX_THREADS];
    pthread_t threads[MAX_THREADS];

    int seeds_per_thread = max_seeds / num_threads;
    int remainder = max_seeds % num_threads;

    int cursor = 0;
    for (int t = 0; t < num_threads; t++) {
        SearchWorker *w = &workers[t];
        int chunk = seeds_per_thread + (t < remainder ? 1 : 0);
        w->start_offset    = offset + cursor;
        w->count           = chunk;
        w->tag             = tag;
        w->tag_avail_mask  = tag_avail_mask;
        w->pack_keys       = (const char (*)[64])pack_keys;
        w->pack_count      = pack_count;
        w->voucher         = voucher;
        w->legendary       = legendary;
        w->spectral_card   = spectral_card;
        w->tarot_card      = tarot_card;
        w->tarot_card2     = tarot_card2;
        w->tarot_key_append = tarot_key_append && tarot_key_append[0] ? tarot_key_append : "ar1";
        w->tarot_pack_size = tarot_pack_size > 0 ? tarot_pack_size : 5;
        w->spectral_pack_size = spectral_pack_size > 0 ? spectral_pack_size : 4;
        w->spectral_card2  = spectral_card2;
        w->voucher2        = voucher2;
        w->want_tag        = want_tag;
        w->want_pack       = want_pack;
        w->want_voucher    = want_voucher;
        w->want_legendary  = want_legendary;
        w->want_spectral   = want_spectral;
        w->want_tarot_card = want_tarot_card;
        w->want_tarot_card2 = want_tarot_card2;
        w->want_spectral2  = want_spectral2;
        w->want_voucher2   = want_voucher2;
        w->wraith_joker    = wraith_joker;
        w->rare_joker_mask = rare_joker_mask;
        w->wraith_edition  = wraith_edition;
        w->want_wraith_joker = want_wraith_joker;
        w->want_wraith_edition = want_wraith_edition;
        w->result[0]       = '\0';
        w->found           = &found_flag;
        cursor += chunk;
    }

    /* Launch all threads */
    for (int t = 0; t < num_threads; t++) {
        pthread_create(&threads[t], NULL, search_worker, &workers[t]);
    }

    /* Wait for all threads to finish */
    for (int t = 0; t < num_threads; t++) {
        pthread_join(threads[t], NULL);
    }

    /* Collect first result found (lowest offset wins for determinism) */
    for (int t = 0; t < num_threads; t++) {
        if (workers[t].result[0]) {
            strncpy(result, workers[t].result, SEED_LEN);
            result[SEED_LEN] = '\0';
            return result;
        }
    }

    return result; /* empty string = not found */
}
