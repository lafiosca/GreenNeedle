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
#define _USE_MATH_DEFINES
#include <math.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

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

/* Common jokers in order (rarity=1, sorted by order field).
 * Used for predicting Judgement's joker creation. */
static const char *COMMON_JOKER_POOL[] = {
    "j_joker",            /* order 1   */
    "j_greedy_joker",     /* order 2   */
    "j_lusty_joker",      /* order 3   */
    "j_wrathful_joker",   /* order 4   */
    "j_gluttenous_joker", /* order 5   */
    "j_jolly",            /* order 6   */
    "j_zany",             /* order 7   */
    "j_mad",              /* order 8   */
    "j_crazy",            /* order 9   */
    "j_droll",            /* order 10  */
    "j_sly",              /* order 11  */
    "j_wily",             /* order 12  */
    "j_clever",           /* order 13  */
    "j_devious",          /* order 14  */
    "j_crafty",           /* order 15  */
    "j_half",             /* order 16  */
    "j_credit_card",      /* order 20  */
    "j_banner",           /* order 22  */
    "j_mystic_summit",    /* order 23  */
    "j_8_ball",           /* order 26  */
    "j_misprint",         /* order 27  */
    "j_raised_fist",      /* order 29  */
    "j_chaos",            /* order 30  */
    "j_scary_face",       /* order 33  */
    "j_abstract",         /* order 34  */
    "j_delayed_grat",     /* order 35  */
    "j_gros_michel",      /* order 38  */
    "j_even_steven",      /* order 39  */
    "j_odd_todd",         /* order 40  */
    "j_scholar",          /* order 41  */
    "j_business",         /* order 42  */
    "j_supernova",        /* order 43  */
    "j_ride_the_bus",     /* order 44  */
    "j_egg",              /* order 46  */
    "j_runner",           /* order 49  */
    "j_ice_cream",        /* order 50  */
    "j_splash",           /* order 52  */
    "j_blue_joker",       /* order 53  */
    "j_faceless",         /* order 57  */
    "j_green_joker",      /* order 58  */
    "j_superposition",    /* order 59  */
    "j_todo_list",        /* order 60  */
    NULL,                 /* order 61: j_cavendish -- UNAVAILABLE (yes_pool_flag='gros_michel_extinct') */
    "j_red_card",         /* order 63  */
    "j_square",           /* order 65  */
    "j_riff_raff",        /* order 67  */
    "j_photograph",       /* order 78  */
    "j_reserved_parking", /* order 82  */
    "j_mail",             /* order 83  */
    "j_hallucination",    /* order 85  */
    "j_fortune_teller",   /* order 86  */
    "j_juggler",          /* order 87  */
    "j_drunkard",         /* order 88  */
    "j_golden",           /* order 90  */
    "j_popcorn",          /* order 97  */
    "j_walkie_talkie",    /* order 101 */
    "j_smiley",           /* order 104 */
    "j_ticket",           /* order 106 */
    "j_swashbuckler",     /* order 110 */
    "j_hanging_chad",     /* order 115 */
    "j_shoot_the_moon",   /* order 140 */
};
#define COMMON_JOKER_POOL_SIZE 61

/* Uncommon jokers in order (rarity=2, sorted by order field).
 * Used for predicting Judgement's joker creation. */
static const char *UNCOMMON_JOKER_POOL[] = {
    "j_stencil",          /* order 17  */
    "j_four_fingers",     /* order 18  */
    "j_mime",             /* order 19  */
    "j_ceremonial",       /* order 21  */
    "j_marble",           /* order 24  */
    "j_loyalty_card",     /* order 25  */
    "j_dusk",             /* order 28  */
    "j_fibonacci",        /* order 31  */
    "j_steel_joker",      /* order 32  */
    "j_hack",             /* order 36  */
    "j_pareidolia",       /* order 37  */
    "j_space",            /* order 45  */
    "j_burglar",          /* order 47  */
    "j_blackboard",       /* order 48  */
    "j_sixth_sense",      /* order 54  */
    "j_constellation",    /* order 55  */
    "j_hiker",            /* order 56  */
    "j_card_sharp",       /* order 62  */
    "j_madness",          /* order 64  */
    "j_seance",           /* order 66  */
    "j_vampire",          /* order 68  */
    "j_shortcut",         /* order 69  */
    "j_hologram",         /* order 70  */
    "j_cloud_9",          /* order 73  */
    "j_rocket",           /* order 74  */
    "j_midas_mask",       /* order 76  */
    "j_luchador",         /* order 77  */
    "j_gift",             /* order 79  */
    "j_turtle_bean",      /* order 80  */
    "j_erosion",          /* order 81  */
    "j_to_the_moon",      /* order 84  */
    "j_stone",            /* order 89  */
    "j_lucky_cat",        /* order 91  */
    "j_bull",             /* order 93  */
    "j_diet_cola",        /* order 94  */
    "j_trading",          /* order 95  */
    "j_flash",            /* order 96  */
    "j_trousers",         /* order 98  */
    "j_ramen",            /* order 100 */
    "j_selzer",           /* order 102 */
    "j_castle",           /* order 103 */
    "j_mr_bones",         /* order 107 */
    "j_acrobat",          /* order 108 */
    "j_sock_and_buskin",  /* order 109 */
    "j_troubadour",       /* order 111 */
    "j_certificate",      /* order 112 */
    "j_smeared",          /* order 113 */
    "j_throwback",        /* order 114 */
    "j_rough_gem",        /* order 116 */
    "j_bloodstone",       /* order 117 */
    "j_arrowhead",        /* order 118 */
    "j_onyx_agate",       /* order 119 */
    "j_glass",            /* order 120 */
    "j_ring_master",      /* order 121 */
    "j_flower_pot",       /* order 122 */
    "j_merry_andy",       /* order 125 */
    "j_oops",             /* order 126 */
    "j_idol",             /* order 127 */
    "j_seeing_double",    /* order 128 */
    "j_matador",          /* order 129 */
    "j_satellite",        /* order 139 */
    "j_cartomancer",      /* order 142 */
    "j_astronomer",       /* order 143 */
    "j_bootstraps",       /* order 145 */
};
#define UNCOMMON_JOKER_POOL_SIZE 64

/* Rare jokers in order (rarity=3, sorted by order field).
 * Used for predicting Wraith's and Judgement's joker creation.
 * Pool key for Wraith: "Joker3wra" + ante
 * Pool key for Judgement: "Joker3jud" + ante */
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

/* Planet cards (order-sorted, 12 base + softlocked).
 * Pool uses all 12 base entries; Planet X, Ceres, Eris are softlocked but still
 * in the pool (they're added with add=true, just not always discovered).
 * Black Hole is a soul check (soul_Planet), not in the normal pool.
 * The game's Planet pool has exactly 12 entries (matching G.P_CENTER_POOLS["Planet"]). */
static const char *PLANET_POOL[] = {
    "c_mercury",    /* order 1  */
    "c_venus",      /* order 2  */
    "c_earth",      /* order 3  */
    "c_mars",       /* order 4  */
    "c_jupiter",    /* order 5  */
    "c_saturn",     /* order 6  */
    "c_uranus",     /* order 7  */
    "c_neptune",    /* order 8  */
    "c_pluto",      /* order 9  */
    "c_planet_x",   /* order 10 - softlocked */
    "c_ceres",      /* order 11 - softlocked */
    "c_eris",       /* order 12 - softlocked */
};
#define PLANET_POOL_SIZE 12

/* Booster packs with weights (matches Balatro's G.P_CENTER_POOLS['Booster']).
 * Weights from game.lua — order-sorted to match the game's iteration order. */
typedef struct { const char *key; double weight; } PackDef;
static const PackDef PACK_DEFS[] = {
    { "p_arcana_normal_1",    1.00 },
    { "p_arcana_normal_2",    1.00 },
    { "p_arcana_normal_3",    1.00 },
    { "p_arcana_normal_4",    1.00 },
    { "p_arcana_jumbo_1",     1.00 },
    { "p_arcana_jumbo_2",     1.00 },
    { "p_arcana_mega_1",      0.25 },
    { "p_arcana_mega_2",      0.25 },
    { "p_celestial_normal_1", 1.00 },
    { "p_celestial_normal_2", 1.00 },
    { "p_celestial_normal_3", 1.00 },
    { "p_celestial_normal_4", 1.00 },
    { "p_celestial_jumbo_1",  1.00 },
    { "p_celestial_jumbo_2",  1.00 },
    { "p_celestial_mega_1",   0.25 },
    { "p_celestial_mega_2",   0.25 },
    { "p_standard_normal_1",  1.00 },
    { "p_standard_normal_2",  1.00 },
    { "p_standard_normal_3",  1.00 },
    { "p_standard_normal_4",  1.00 },
    { "p_standard_jumbo_1",   1.00 },
    { "p_standard_jumbo_2",   1.00 },
    { "p_standard_mega_1",    0.25 },
    { "p_standard_mega_2",    0.25 },
    { "p_buffoon_normal_1",   0.60 },
    { "p_buffoon_normal_2",   0.60 },
    { "p_buffoon_jumbo_1",    0.60 },
    { "p_buffoon_mega_1",     0.15 },
    { "p_spectral_normal_1",  0.30 },
    { "p_spectral_normal_2",  0.30 },
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

    /* Game uses pseudoseed("Voucher" .. ante) — the ante is part of the key,
     * not an advance count. First call to a key does 1 advance internally. */
    char pool_key[32];
    int pklen = snprintf(pool_key, sizeof(pool_key), "Voucher%d", ante);
    double pseed = gn_pseudoseed_h(pool_key, pklen, seed, slen, hs);

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

/* Predict which joker Judgement creates for a given seed.
 * Judgement calls create_card('Joker', ..., nil, nil, ..., 'jud'):
 *   1. Rarity determined by pseudorandom('rarity' .. ante .. 'jud')
 *      >0.95 → Rare(3), >0.7 → Uncommon(2), else Common(1)
 *   2. Joker picked from rarity pool with key "Joker{R}jud{ante}"
 * Assumes all jokers unlocked (no availability mask). */
static const char *predict_judgement_joker_h(const char *seed, int slen, int ante, double hs) {
    if (hs < 0) hs = pseudohash(seed, slen);

    /* Step 1: determine rarity via pseudorandom('rarity' .. ante .. 'jud') */
    char rarity_key[32];
    int rklen = snprintf(rarity_key, sizeof(rarity_key), "rarity%djud", ante);
    double rarity_pseed = gn_pseudoseed_h(rarity_key, rklen, seed, slen, hs);
    LRandom rarity_rng = randomseed(rarity_pseed);
    double rarity_roll = l_random(&rarity_rng);

    const char **pool;
    int pool_size;
    int rarity;
    if (rarity_roll > 0.95) {
        pool = RARE_JOKER_POOL; pool_size = RARE_JOKER_POOL_SIZE; rarity = 3;
    } else if (rarity_roll > 0.7) {
        pool = UNCOMMON_JOKER_POOL; pool_size = UNCOMMON_JOKER_POOL_SIZE; rarity = 2;
    } else {
        pool = COMMON_JOKER_POOL; pool_size = COMMON_JOKER_POOL_SIZE; rarity = 1;
    }

    /* Step 2: pick joker from rarity pool */
    char pool_key[32];
    int pklen = snprintf(pool_key, sizeof(pool_key), "Joker%djud%d", rarity, ante);
    double pseed = gn_pseudoseed_h(pool_key, pklen, seed, slen, hs);
    LRandom rng = randomseed(pseed);
    uint64_t idx = l_randint(&rng, 1, (uint64_t)pool_size);

    /* Handle UNAVAILABLE slots (e.g. Cavendish) with resampling */
    if (pool[idx - 1] == NULL) {
        int resample = 1;
        while (pool[idx - 1] == NULL && resample < 100) {
            resample++;
            char reskey[64];
            int rklen = snprintf(reskey, sizeof(reskey), "Joker%djud%d_resample%d", rarity, ante, resample);
            double rpseed = gn_pseudoseed_h(reskey, rklen, seed, slen, hs);
            rng = randomseed(rpseed);
            idx = l_randint(&rng, 1, (uint64_t)pool_size);
        }
    }
    return pool[idx - 1] ? pool[idx - 1] : "j_joker";
}

/* Predict the joker created by Uncommon Tag or Rare Tag.
 * Uncommon Tag: create_card('Joker', ..., nil, 0.9, ..., 'uta') → forced uncommon
 * Rare Tag:     create_card('Joker', ..., nil, 1, ..., 'rta')   → forced rare
 * No rarity roll needed since it's forced by the _rarity parameter. */
static const char *predict_tag_joker_h(const char *seed, int slen, int ante,
                                        const char *tag_key, double hs) {
    if (hs < 0) hs = pseudohash(seed, slen);

    const char **pool;
    int pool_size;
    int rarity;
    const char *key_append;
    if (strcmp(tag_key, "tag_rare") == 0) {
        pool = RARE_JOKER_POOL; pool_size = RARE_JOKER_POOL_SIZE; rarity = 3;
        key_append = "rta";
    } else {
        /* tag_uncommon */
        pool = UNCOMMON_JOKER_POOL; pool_size = UNCOMMON_JOKER_POOL_SIZE; rarity = 2;
        key_append = "uta";
    }

    char pool_key[32];
    int pklen = snprintf(pool_key, sizeof(pool_key), "Joker%d%s%d", rarity, key_append, ante);
    double pseed = gn_pseudoseed_h(pool_key, pklen, seed, slen, hs);
    LRandom rng = randomseed(pseed);
    uint64_t idx = l_randint(&rng, 1, (uint64_t)pool_size);

    /* Handle UNAVAILABLE slots with resampling */
    if (pool[idx - 1] == NULL) {
        int resample = 1;
        while (pool[idx - 1] == NULL && resample < 100) {
            resample++;
            char reskey[64];
            int rklen2 = snprintf(reskey, sizeof(reskey), "Joker%d%s%d_resample%d", rarity, key_append, ante, resample);
            double rpseed = gn_pseudoseed_h(reskey, rklen2, seed, slen, hs);
            rng = randomseed(rpseed);
            idx = l_randint(&rng, 1, (uint64_t)pool_size);
        }
    }
    return pool[idx - 1] ? pool[idx - 1] : "j_joker";
}

/* Predict the edition of the joker Judgement creates.
 * Uses pseudoseed key "edijud" + ante with poll_edition base rates. */
static const char *predict_judgement_edition_h(const char *seed, int slen, int ante, double hs) {
    if (hs < 0) hs = pseudohash(seed, slen);
    char key[32];
    int klen = snprintf(key, sizeof(key), "edijud%d", ante);
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
    /* The game uses pseudorandom('soul_Spectral' .. ante) for BOTH the c_soul
     * and c_black_hole checks (same key, advancing state twice per slot). */
    char soul_key[64];
    int soul_klen = snprintf(soul_key, sizeof(soul_key), "soul_Spectral%d", ante);

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
    int soul_advance = 0;
    for (int slot = 1; slot <= pack_size; slot++) {
        /* Both checks use the same key ('soul_Spectral' .. ante) and always
         * execute, advancing state twice per slot regardless of outcome.
         * If both fire, c_black_hole wins (overwrites c_soul). */
        soul_advance++;
        double soul_pseed = gn_pseudoseed_advance_h(soul_key, soul_klen, seed, slen, soul_advance, hs);
        LRandom soul_rng = randomseed(soul_pseed);
        bool is_soul = (l_random(&soul_rng) > 0.997);

        soul_advance++;
        double bh_pseed = gn_pseudoseed_advance_h(soul_key, soul_klen, seed, slen, soul_advance, hs);
        LRandom bh_rng = randomseed(bh_pseed);
        bool is_bh = (l_random(&bh_rng) > 0.997);

        if (is_bh) {
            /* c_black_hole overwrites c_soul if both fire */
            if (out_cards) out_cards[slot - 1] = "c_black_hole";
            if (target_card && strcmp("c_black_hole", target_card) == 0) return true;
            continue;
        }
        if (is_soul) {
            if (out_cards) out_cards[slot - 1] = "c_soul";
            if (target_card && strcmp("c_soul", target_card) == 0) return true;
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

/* Search check: returns true if target_card appears in any slot (early exit) */
static bool check_spectral_card_h(const char *seed, int slen, const char *key_append, int ante,
                                   int pack_size, const char *extra_excluded, double hs,
                                   const char *target_card) {
    return predict_spectral_inner(seed, slen, key_append, ante, pack_size, extra_excluded, hs, NULL, target_card);
}

/* Check if a target planet card appears in a celestial pack.
 * soul_Planet check: >0.997 → Black Hole.
 * Normal cards drawn from PLANET_POOL with key "Planet{append}{ante}". */
static bool check_planet_card_h(const char *seed, int slen, const char *key_append, int ante,
                                 int pack_size, double hs, const char *target_card) {
    if (hs < 0) hs = pseudohash(seed, slen);
    char soul_key[64];
    int soul_klen = snprintf(soul_key, sizeof(soul_key), "soul_Planet%d", ante);
    char card_key[64];
    int card_klen = snprintf(card_key, sizeof(card_key), "Planet%s%d", key_append, ante);

    int card_advance = 0;
    for (int slot = 1; slot <= pack_size; slot++) {
        double soul_pseed = gn_pseudoseed_advance_h(soul_key, soul_klen, seed, slen, slot, hs);
        LRandom soul_rng = randomseed(soul_pseed);
        if (l_random(&soul_rng) > 0.997) {
            if (strcmp("c_black_hole", target_card) == 0) return true;
            /* Black Hole fires: card pool state NOT advanced */
        } else {
            card_advance++;
            double pseed = gn_pseudoseed_advance_h(card_key, card_klen, seed, slen, card_advance, hs);
            LRandom rng = randomseed(pseed);
            uint64_t idx = l_randint(&rng, 1, PLANET_POOL_SIZE);
            if (strcmp(PLANET_POOL[idx - 1], target_card) == 0) return true;
        }
    }
    return false;
}

/* Check if a target joker appears in a buffoon pack, optionally with a specific edition.
 * Buffoon packs use create_card("Joker", ..., nil, nil, true, true, nil, 'buf').
 * Rarity roll: pseudorandom('rarity' .. ante .. key_append), per slot.
 *   >0.95 → Rare(3), >0.7 → Uncommon(2), else Common(1).
 * Joker: pseudorandom_element(pool, pseudoseed('Joker' .. rarity .. key_append .. ante)).
 * Edition: poll_edition('edi' .. key_append .. ante), advanced per slot.
 * Advances are tracked per pool key across slots.
 * If target_edition is NULL/"", only the joker is checked.
 * If both target_joker and target_edition are set, they must match the same slot. */
static bool check_joker_card_h(const char *seed, int slen, const char *key_append, int ante,
                                int pack_size, double hs, const char *target_joker,
                                const char *target_edition) {
    if (hs < 0) hs = pseudohash(seed, slen);
    bool want_edition = target_edition && target_edition[0];
    bool want_joker = target_joker && target_joker[0];

    /* Track per-pool-key advance counts (one for each of 3 rarity levels) */
    int advance_common = 0, advance_uncommon = 0, advance_rare = 0;

    char rarity_key[32];
    int rarity_klen = snprintf(rarity_key, sizeof(rarity_key), "rarity%d%s", ante, key_append);

    /* Edition key: "edi" + key_append + ante */
    char edi_key[32];
    int edi_klen = snprintf(edi_key, sizeof(edi_key), "edi%s%d", key_append, ante);

    for (int slot = 1; slot <= pack_size; slot++) {
        /* Determine rarity */
        double rarity_pseed = gn_pseudoseed_advance_h(rarity_key, rarity_klen, seed, slen, slot, hs);
        LRandom rarity_rng = randomseed(rarity_pseed);
        double rarity_roll = l_random(&rarity_rng);

        const char **pool;
        int pool_size;
        int rarity;
        int *advance;
        if (rarity_roll > 0.95) {
            pool = RARE_JOKER_POOL; pool_size = RARE_JOKER_POOL_SIZE; rarity = 3;
            advance = &advance_rare;
        } else if (rarity_roll > 0.7) {
            pool = UNCOMMON_JOKER_POOL; pool_size = UNCOMMON_JOKER_POOL_SIZE; rarity = 2;
            advance = &advance_uncommon;
        } else {
            pool = COMMON_JOKER_POOL; pool_size = COMMON_JOKER_POOL_SIZE; rarity = 1;
            advance = &advance_common;
        }

        (*advance)++;
        char pool_key[32];
        int pklen = snprintf(pool_key, sizeof(pool_key), "Joker%d%s%d", rarity, key_append, ante);
        double pseed = gn_pseudoseed_advance_h(pool_key, pklen, seed, slen, *advance, hs);
        LRandom rng = randomseed(pseed);
        uint64_t idx = l_randint(&rng, 1, (uint64_t)pool_size);

        bool joker_match = !want_joker || (pool[idx - 1] && strcmp(pool[idx - 1], target_joker) == 0);

        if (joker_match && want_edition) {
            /* Check edition for this slot */
            double edi_pseed = gn_pseudoseed_advance_h(edi_key, edi_klen, seed, slen, slot, hs);
            LRandom edi_rng = randomseed(edi_pseed);
            double poll = l_random(&edi_rng);
            const char *edi = "";
            if (poll > 0.997) edi = "e_negative";
            else if (poll > 1.0 - 0.006) edi = "e_polychrome";
            else if (poll > 1.0 - 0.02) edi = "e_holographic";
            else if (poll > 1.0 - 0.04) edi = "e_foil";
            if (strcmp(edi, target_edition) == 0) return true;
        } else if (joker_match && !want_edition) {
            return true;
        }
    }
    return false;
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

/* --------------------------------------------------------------------------
 * Erratic deck prediction
 * -------------------------------------------------------------------------- */

/* Rank indices in the alphabetically-sorted P_CARDS pool: 2,3,4,5,6,7,8,9,A,J,K,Q,T = 0-12. */
#define ERRATIC_NUM_RANKS 13

/* Pool of 52 cards: suits C,D,H,S each with 13 ranks in ERRATIC_RANK_CHARS order.
 * Card at index i: suit = i/13 (0=C,1=D,2=H,3=S), rank = i%13. */

typedef struct {
    int  rank_idx[4];  /* rank char index (0-12), or -1 for "Any" */
    int  rank_min[4];
    int  rank_max[4];
    int  suit_min[4];  /* 0=clubs, 1=diamonds, 2=hearts, 3=spades */
    int  suit_max[4];
    bool active;       /* true if any filter is non-default */
} ErraticFilter;

/* Check if a seed's erratic deck composition matches the filter.
 * The erratic deck is 52 cards, each chosen by pseudoseed('erratic') called 52 times. */
static bool check_erratic_deck_h(const char *seed, int slen, const ErraticFilter *ef) {
    if (!ef->active) return true;

    /* Compute pseudohash("erratic" .. seed) as initial state */
    char buf[64];
    memcpy(buf, "erratic", 7);
    memcpy(buf + 7, seed, slen);
    double state = pseudohash(buf, 7 + slen);
    double hashed_seed = pseudohash(seed, slen);

    int rank_counts[ERRATIC_NUM_RANKS] = {0};
    int suit_counts[4] = {0};

    for (int i = 0; i < 52; i++) {
        /* Advance state (same as Lua pseudoseed stateful path) */
        double raw = fmod(2.134453429141 + state * 1.72431234, 1.0);
        state = fabs(round(raw * 1e13) / 1e13);
        double pseed = (state + hashed_seed) / 2.0;

        /* pseudorandom_element: seed Lua RNG, pick random(52) */
        LRandom lr = randomseed(pseed);
        int idx = (int)l_randint(&lr, 1, 52) - 1; /* 0-based */
        int suit = idx / 13;
        int rank = idx % 13;
        rank_counts[rank]++;
        suit_counts[suit]++;
    }

    /* Check rank filters */
    for (int i = 0; i < 4; i++) {
        if (ef->rank_idx[i] < 0) continue;
        int count = rank_counts[ef->rank_idx[i]];
        if (count < ef->rank_min[i] || count > ef->rank_max[i]) return false;
    }

    /* Check suit filters */
    for (int i = 0; i < 4; i++) {
        int count = suit_counts[i];
        if (count < ef->suit_min[i] || count > ef->suit_max[i]) return false;
    }

    return true;
}

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
    const char    *judgement_joker;
    const char    *judgement_edition;
    const char    *planet_card;
    const char    *planet_card2;
    const char    *planet_key_append;
    int            planet_pack_size;
    const char    *joker_card;
    const char    *joker_card2;
    const char    *joker_key_append;
    int            joker_pack_size;
    const char    *joker_edition;
    const char    *tag_joker;
    bool           want_tag, want_pack, want_voucher;
    bool           want_legendary, want_spectral;
    bool           want_tarot_card, want_tarot_card2;
    bool           want_spectral2, want_voucher2;
    bool           want_wraith_joker, want_wraith_edition;
    bool           want_judgement_joker, want_judgement_edition;
    bool           want_planet_card, want_planet_card2;
    bool           want_joker_card, want_joker_card2;
    bool           want_tag_joker;
    ErraticFilter  erratic;
    /* Output */
    char           result[SEED_LEN + 1];
    /* Shared: early exit flag (set by any thread that finds a match) */
    atomic_int    *found;
} SearchWorker;

#ifdef _WIN32
static DWORD WINAPI search_worker(LPVOID arg) {
#else
static void *search_worker(void *arg) {
#endif
    SearchWorker *w = (SearchWorker *)arg;
    char seed[SEED_LEN + 1];
    seed[SEED_LEN] = '\0';

    for (int n = 0; n < w->count; n++) {
        /* Check if another thread already found a result (every 32 seeds) */
#ifdef _WIN32
        if ((n & 31) == 0 && atomic_load(w->found)) return 0;
#else
        if ((n & 31) == 0 && atomic_load(w->found)) return NULL;
#endif

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
        if (ok && w->want_judgement_joker) {
            if (strcmp(predict_judgement_joker_h(seed, slen, 1, hs), w->judgement_joker) != 0)
                ok = false;
        }
        if (ok && w->want_judgement_edition) {
            if (strcmp(predict_judgement_edition_h(seed, slen, 1, hs), w->judgement_edition) != 0)
                ok = false;
        }
        if (ok && w->want_tag_joker) {
            if (strcmp(predict_tag_joker_h(seed, slen, 1, w->tag, hs), w->tag_joker) != 0)
                ok = false;
        }
        if (ok && w->want_planet_card) {
            if (!check_planet_card_h(seed, slen, w->planet_key_append, 1,
                                      w->planet_pack_size, hs, w->planet_card))
                ok = false;
        }
        if (ok && w->want_planet_card2) {
            if (!check_planet_card_h(seed, slen, w->planet_key_append, 1,
                                      w->planet_pack_size, hs, w->planet_card2))
                ok = false;
        }
        if (ok && w->want_joker_card) {
            if (!check_joker_card_h(seed, slen, w->joker_key_append, 1,
                                     w->joker_pack_size, hs, w->joker_card, w->joker_edition))
                ok = false;
        }
        if (ok && w->want_joker_card2) {
            if (!check_joker_card_h(seed, slen, w->joker_key_append, 1,
                                     w->joker_pack_size, hs, w->joker_card2, NULL))
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
        if (ok && w->erratic.active) {
            if (!check_erratic_deck_h(seed, slen, &w->erratic))
                ok = false;
        }

        if (ok) {
            memcpy(w->result, seed, SEED_LEN);
            w->result[SEED_LEN] = '\0';
            atomic_store(w->found, 1);
#ifdef _WIN32
            return 0;
#else
            return NULL;
#endif
        }
    }
#ifdef _WIN32
    return 0;
#else
    return NULL;
#endif
}

#ifdef _WIN32
__declspec(dllexport)
#endif
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
    int         spectral_pack_size,
    const char *judgement_joker,
    const char *judgement_edition,
    const char *planet_card,
    const char *planet_card2,
    const char *planet_key_append,
    int         planet_pack_size,
    const char *joker_card,
    const char *joker_card2,
    const char *joker_key_append,
    int         joker_pack_size,
    const char *joker_edition,
    const char *tag_joker,
    const char *erratic_filter
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
    bool want_judgement_joker = judgement_joker && judgement_joker[0];
    bool want_judgement_edition = judgement_edition && judgement_edition[0];
    bool want_planet_card = planet_card && planet_card[0];
    bool want_planet_card2 = planet_card2 && planet_card2[0];
    bool want_joker_card = joker_card && joker_card[0];
    bool want_joker_card2 = joker_card2 && joker_card2[0];
    bool want_tag_joker = tag_joker && tag_joker[0];

    /* Parse erratic filter: "r0,min0,max0,r1,min1,max1,r2,min2,max2,r3,min3,max3,smin0,smax0,smin1,smax1,smin2,smax2,smin3,smax3" */
    ErraticFilter ef = {
        .rank_idx = {-1, -1, -1, -1},
        .rank_min = {0, 0, 0, 0}, .rank_max = {52, 52, 52, 52},
        .suit_min = {0, 0, 0, 0}, .suit_max = {52, 52, 52, 52},
        .active = false
    };
    if (erratic_filter && erratic_filter[0]) {
        int vals[20];
        int nread = sscanf(erratic_filter,
            "%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%d",
            &vals[0],&vals[1],&vals[2],&vals[3],&vals[4],&vals[5],
            &vals[6],&vals[7],&vals[8],&vals[9],&vals[10],&vals[11],
            &vals[12],&vals[13],&vals[14],&vals[15],&vals[16],&vals[17],
            &vals[18],&vals[19]);
        if (nread == 20) {
            for (int i = 0; i < 4; i++) {
                ef.rank_idx[i] = vals[i*3];
                ef.rank_min[i] = vals[i*3+1];
                ef.rank_max[i] = vals[i*3+2];
            }
            for (int i = 0; i < 4; i++) {
                ef.suit_min[i] = vals[12 + i*2];
                ef.suit_max[i] = vals[12 + i*2 + 1];
            }
            /* Check if any filter is non-default */
            for (int i = 0; i < 4; i++) {
                if (ef.rank_idx[i] >= 0) { ef.active = true; break; }
                if (ef.suit_min[i] > 0 || ef.suit_max[i] < 52) { ef.active = true; break; }
            }
        }
    }

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
#ifdef _WIN32
    SYSTEM_INFO sysinfo;
    GetSystemInfo(&sysinfo);
    int num_threads = (int)sysinfo.dwNumberOfProcessors;
#else
    int num_threads = (int)sysconf(_SC_NPROCESSORS_ONLN);
#endif
    if (num_threads <= 0) num_threads = 4;
    if (num_threads > MAX_THREADS) num_threads = MAX_THREADS;
    if (num_threads > max_seeds) num_threads = max_seeds;

    atomic_int found_flag = 0;
    SearchWorker workers[MAX_THREADS];
#ifdef _WIN32
    HANDLE threads[MAX_THREADS];
#else
    pthread_t threads[MAX_THREADS];
#endif

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
        w->judgement_joker = judgement_joker;
        w->judgement_edition = judgement_edition;
        w->want_judgement_joker = want_judgement_joker;
        w->want_judgement_edition = want_judgement_edition;
        w->planet_card     = planet_card;
        w->planet_card2    = planet_card2;
        w->planet_key_append = planet_key_append && planet_key_append[0] ? planet_key_append : "pl1";
        w->planet_pack_size = planet_pack_size > 0 ? planet_pack_size : 5;
        w->want_planet_card = want_planet_card;
        w->want_planet_card2 = want_planet_card2;
        w->joker_card      = joker_card;
        w->joker_card2     = joker_card2;
        w->joker_key_append = joker_key_append && joker_key_append[0] ? joker_key_append : "buf";
        w->joker_pack_size = joker_pack_size > 0 ? joker_pack_size : 4;
        w->joker_edition   = joker_edition;
        w->want_joker_card = want_joker_card;
        w->want_joker_card2 = want_joker_card2;
        w->tag_joker       = tag_joker;
        w->want_tag_joker  = want_tag_joker;
        w->erratic         = ef;
        w->result[0]       = '\0';
        w->found           = &found_flag;
        cursor += chunk;
    }

    /* Launch all threads */
    for (int t = 0; t < num_threads; t++) {
#ifdef _WIN32
        threads[t] = CreateThread(NULL, 0, search_worker, &workers[t], 0, NULL);
#else
        pthread_create(&threads[t], NULL, search_worker, &workers[t]);
#endif
    }

    /* Wait for all threads to finish */
#ifdef _WIN32
    WaitForMultipleObjects(num_threads, threads, TRUE, INFINITE);
    for (int t = 0; t < num_threads; t++) {
        CloseHandle(threads[t]);
    }
#else
    for (int t = 0; t < num_threads; t++) {
        pthread_join(threads[t], NULL);
    }
#endif

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
