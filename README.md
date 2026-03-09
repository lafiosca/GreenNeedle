# Green Needle

A [Balatro](https://www.playbalatro.com/) mod for searching game seeds that match specific criteria. Find seeds with the exact skip tag, shop pack, vouchers, legendary joker, spectral cards, and pack contents you want before starting a run. Inspired by [Brainstorm](https://github.com/OceanRamen/Brainstorm), with a native C search engine, additional search filters, and a different approach to seed prediction.

Requires the [Lovely](https://github.com/ethangreen-dev/lovely-injector) mod loader.

*Charm Tag with Judgement + The Hanged Man, searching for a Negative Erosion:*

![Judgement joker and edition filtering](screenshots/settings1.png)

*Mega Spectral pack with The Soul + Ankh, Director's Cut voucher, and Chicot legendary:*

![Shop pack cards, vouchers, and legendary filtering](screenshots/settings2.png)

*The Soul + Judgement in the tag pack, filtering for Negative Blueprint and Perkeo legendary:*

![Combined tag pack, legendary, and Judgement filters](screenshots/settings3.png)

*The search overlay shows a running count of seeds checked vs. the estimated total, an elapsed timer, and the cumulative probability that a match should have been found by now:*

![Searching for seeds](screenshots/search.png)

## Features

- Search for seeds matching any combination of:
  - **Skip tag** (Charm Tag, Double Tag, etc.)
  - **Tag pack cards** (specific tarot cards in the Charm Tag's Mega Arcana pack)
  - **Shop pack type** (Arcana, Spectral, Buffoon, etc. — including size variants)
  - **Shop pack cards** (specific tarot or spectral cards in the shop pack)
  - **Spectral pack cards** (any of the 18 spectral cards, including The Soul and Black Hole)
  - **Wraith joker** — when Wraith is selected as a shop pack card, optionally filter for a specific rare joker it creates
  - **Wraith edition** — filter the edition (Foil, Holographic, Polychrome, Negative) of the Wraith joker
  - **Judgement joker** — when Judgement is selected as a tag pack card, filter for a specific joker it creates (paginated selector with all unlocked jokers)
  - **Judgement edition** — filter the edition of the Judgement joker
  - **Voucher Ante 1** (Telescope, Crystal Ball, etc.)
  - **Voucher Ante 2** (dynamically filtered based on Ante 1 selection)
  - **Legendary joker** (Canio, Perkeo, etc.) — appears when The Soul is selected in any card slot
- **Estimated seed count** shown in the settings panel and search overlay so you know roughly how many seeds to expect before finding a match
- **Cumulative likelihood** percentage displayed during search
- Native C search engine for fast multi-threaded searching (~millions of seeds/sec)
- Pure Lua fallback if the native library isn't available
- Live counter showing seeds searched and estimated total

## Installation

1. Install [Lovely](https://github.com/ethangreen-dev/lovely-injector) if you haven't already
2. Copy the `GreenNeedle` folder into your Balatro mods directory:
   - **macOS:** `~/Library/Application Support/Balatro/Mods/`
   - **Windows:** `%AppData%/Balatro/Mods/`
3. Launch Balatro — a **Green Needle** button will appear in the main menu

The mod works on all platforms via the pure-Lua search fallback. The pre-built native library (`greenneedle.dylib`) is macOS-only for now — see the Building section below if you'd like to compile for your platform.

## Usage

1. Click the **Green Needle** button in the main menu (or pause menu)
2. Configure your search filters (any combination)
3. Start or be in a run, then press **Ctrl+A** to start searching
4. Press **Ctrl+A** again to stop the search
5. When a matching seed is found, a new run starts automatically with that seed

## Building the Native Library

The native search library provides dramatically faster searching. Pre-built for macOS (universal binary: Apple Silicon arm64 + Intel x86_64).

The C source (`native/greenneedle.c`) is portable C11 with no platform-specific dependencies — it should compile on Windows and Linux as well.

To rebuild on macOS:

```bash
cd native
./build_macos.sh
```

Requires Xcode Command Line Tools (`xcode-select --install`).

## Settings

Settings are saved automatically to `settings.lua` in the mod directory. Delete this file to reset to defaults.

## License

[Mozilla Public License 2.0](LICENSE)
