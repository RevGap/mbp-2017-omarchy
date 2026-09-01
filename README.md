# Omarchy on the 2017 15″ MacBook Pro (MacBookPro14,3)

A tested, reproducible guide for installing **[Omarchy](https://github.com/basecamp/omarchy)** on the 2017 15-inch Touch Bar MacBook Pro — while **preserving the Apple T1 firmware** so the Touch Bar, webcam, Wi-Fi, audio, and keyboard backlight all keep working.

The upstream T1 toolkit ([nohzafk/omarchy-macbookpro-t1](https://github.com/nohzafk/omarchy-macbookpro-t1)) was verified on the 13″ Intel-only MacBookPro14,2. This repo documents a full install on the **15″ MacBookPro14,3 with the Radeon Pro 555 dGPU**, including the Radeon-specific suspend behavior discovered during live testing.

## 📖 Read the full guide

**→ [mbp-2017-omarchy/README.md](mbp-2017-omarchy/README.md)**

It covers the entire process end to end: protecting (or recovering) the T1 firmware on Apple's EFI partition, backing up the ESP, shrinking macOS, installing Omarchy alongside it, the Touch Bar DKMS driver and its persistence fix, audio, Wi-Fi NVRAM, keyboard backlight, brightness keybindings, and the Radeon suspend workaround.

## What works

| Feature | Status |
|---|---|
| Touch Bar (real Esc + F1–F12, persistent) | ✅ |
| Webcam | ✅ |
| Keyboard / trackpad | ✅ |
| Keyboard backlight | ✅ |
| Display brightness | ✅ |
| Wi-Fi 2.4 + 5 GHz | ✅ |
| Bluetooth | ✅ |
| Speakers / audio | ✅ |
| Radeon Pro 555 (awake) | ✅ |
| Deep suspend / S3 | ❌ Radeon SMU firmware fails to reload on resume — suspend is disabled instead |
| Touch ID | ❌ No Linux driver |

## The one rule that matters

**Never format Apple's ~314 MB EFI partition.** It stores the T1 firmware (`EFI/APPLE/EMBEDDEDOS/combined.memboot`). Wipe it and the Touch Bar, webcam, and Touch ID all disappear until you reinstall macOS via Internet Recovery. Use Omarchy's *free space install*, never the full-disk install. The guide covers both prevention and recovery.

## What's in this repo

```
mbp-2017-omarchy/
├── README.md                              # The full installation guide
├── hypr/
│   └── bindings.lua                       # Brightness keybindings (no F-row on this chassis)
├── scripts/
│   └── install-hypr-overrides.sh          # Installs the bindings into ~/.config/hypr
└── systemd/
    ├── macbook-kbd-backlight.service      # Persists keyboard backlight level across reboots
    └── macbook-no-suspend.conf            # logind lid policy (suspend disabled — see guide §15)
```

## Tested on

- MacBookPro14,3 (2017 15″ Touch Bar) · Radeon Pro 555 · Apple T1 / iBridge
- Omarchy on kernel `7.1.8-arch1-3`

## Credits

Most of the difficult T1-specific work belongs to the upstream projects:

- [nohzafk/omarchy-macbookpro-t1](https://github.com/nohzafk/omarchy-macbookpro-t1) — T1 Omarchy toolkit
- [F13-Kr1pt0n/macbook-pro-touchbar-driver](https://github.com/F13-Kr1pt0n/macbook-pro-touchbar-driver) — Touch Bar driver lineage
- [davidjo/snd_hda_macbookpro](https://github.com/davidjo/snd_hda_macbookpro) — Cirrus audio driver
- [basecamp/omarchy](https://github.com/basecamp/omarchy) — Omarchy itself
