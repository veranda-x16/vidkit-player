# Credits and licences

VIDKIT Player is under the MIT licence ([LICENSE](LICENSE)), Copyright
(c) 2026 Anthony W. Henry, except where a part says otherwise below.

## Parts ported from other projects

- **Veranda MOD Player** (github.com/veranda-x16/mod-player), MIT licence,
  Copyright (c) 2026 Marcin Spoczynski: the window's layout, look and
  button pictures (`main.p8`, from its `examples/veranda/vmp_ui.c`,
  `vmp_pat.c`, `vmp_pics.c`).

## Included

- **VIDKIT**, Anthony W. Henry, MIT licence: the library the player
  streams with, `vendor/vidkit/VIDKIT-A000.BIN` (its origin and SHA-256:
  `vendor/vidkit/README.md`), packed into `VIDKIT Player.cvt` as three
  banked overlays.

## Built with, not included

- **Prog8 for Veranda** (github.com/veranda-x16/veranda-prog8, the
  version in `TOOLKIT`), MIT licence, Anthony W. Henry: the Prog8 target
  and libraries (`vr`, `vrkit`, `vrlook`, `vkx`, `vktape`) compiled into
  the player; parts of it port Veranda (MIT, Marcin Spoczynski). Its
  `NOTICE.md` has the details.
- **Prog8** (github.com/irmen/prog8), Irmen de Jong: the compiler, GNU GPL
  3.0 with an exception for generated code: "the resulting files
  (intermediate source codes and resulting binary program) created by the
  compiler are excluded from the GPL and are free to use in whatever way
  desired, commercially or not" (Prog8's README). The Prog8 library code
  compiled in (`strings`, `conv` ...) is part of that output.
- **Veranda** (github.com/veranda-x16/veranda), MIT: its SDK's tools
  (`vpack.py`, `vcard.py`) and kernel for building and testing; nothing of
  them is in the player but the API it calls.
