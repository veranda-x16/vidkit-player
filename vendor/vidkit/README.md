# VIDKIT

VIDKIT Player streams with **VIDKIT**, Anthony W. Henry's video and audio
library for the Commander X16 (MIT licence, the same author and licence
as this repository: [LICENSE](../../LICENSE)). Its library binary is kept
here so the player builds from this repository alone:

    VIDKIT-A000.BIN   23,583 bytes: three 8 KB banks loaded at $A000
                      (the third 7,199 bytes)
    SHA-256           cf69a2b0f1bfa1e119cde1aff7bc1d85830d097b5e2c238782a8e15fdf7d343e

**Where it comes from.** It is the VIDKIT build inside the first
`VIDKIT Player.cvt` published in this repository (commit 866bb8a): the
file is those three banked overlay records joined again, and the player
built from this source with it is that `.cvt` byte for byte, apart from
the date and time `vpack.py` stamps. VIDKIT's own version number is not
recorded in the binary; when VIDKIT is released on its own, this file
should name that release.

**Why the build checks it.** Prog8 for Veranda's `lib/vkx.p8` calls into
this VIDKIT build at fixed addresses (its jump tables, its golden RAM
variables and a hook inside bank B), so the Makefile checks the file
against the toolkit's `tools/vidkit.sha256` before using it, and stops
when it differs. `tools/vidkit_split.py` (the toolkit's) cuts it into the
three banked overlay records that are packed into the player.

A newer VIDKIT needs `lib/vkx.p8` checked against its memory map and
`tools/vidkit.sha256` changed, in a new toolkit version, and the binary
here replaced in the same change.
