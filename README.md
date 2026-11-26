# VIDKIT Player

A video and audio player for **Veranda** on the **Commander X16**: SPV
videos full screen, WAV and ZCM audio in its window. It streams from the
SD card with **VIDKIT**, Anthony W. Henry's banked-RAM streaming library,
which is packed inside the program. Its window follows Veranda's MOD
Player.

- **Download:** it comes with Veranda: `VIDKIT Player.cvt` is in
  `/VERANDA/APPS` of the SD-card zip of each
  [Veranda release](https://github.com/veranda-x16/veranda/releases)
  (and Veranda Update installs it). A build of this repository's latest
  source is the `VIDKIT Player` artifact of its
  [Actions](https://github.com/veranda-x16/vidkit-player/actions) runs.
- **Needs:** Veranda (API 5), the X16 ROM R48 or later, an SD card.
  High-bandwidth (SPI) videos play from the SD card only, not from the
  emulator's host file system.

## Install

Copy `VIDKIT Player.cvt` to `/VERANDA/APPS` on the SD card, then open it
from the desktop. SPV, WAV and ZCM are its documents.

## The window

| Panel | What |
|---|---|
| Playlist | the current folder: its folders and its SPV, WAV and ZCM files |
| Now playing | the file chosen: kind, format, size, rate, track, frames, time; the Play, Stop, Previous and Next buttons and the pause light |
| Deck | an audio CD whose sheen turns while audio plays, and the progress bar |

Videos play full screen. The window fades to black first, and fades back
in when the video ends. Audio plays in the window, and the buttons work
with the mouse while it plays.

## Menus and keys

| Menu | Items |
|---|---|
| VIDKIT Player | About VIDKIT Player |
| File | Play all, Quit |
| Play | Play, Stop, Next, Previous, Repeat, Shuffle, Play next (off by default) |

In the playlist: Up/Down, PgUp/PgDn, Home/End choose a file. Return opens
a folder or plays a file, Space plays, Right plays the next file,
Backspace goes up a folder; Left plays the previous file. Alt+Q quits.
The mouse wheel moves the selection a file a notch, as Up/Down do; the
list scrolls when the selection passes the top or bottom of the panel.

While it plays: Esc stops, Space pauses, Up/Down set the volume, F5
plays the file again when it ends (Esc still stops it). With Play next
or Shuffle on, Tab skips to the next file (Shuffle: a random one); a
skipped file keeps no bookmark. Playing a single file, Tab does nothing.
The Deck shows these keys.

With **Play next** on, the player goes on to the next file by itself.
A video followed by another video runs straight into it, fading through
black, without coming back to the window; so does a video skipped with
Tab when the next file is a video too.

## Bookmarks

Stopping a file part way leaves a bookmark beside it: `NAME.MARK` for
`NAME.SPV`, `NAME.WAV` or `NAME.ZCM`. It holds one 5-byte CBM float, the
video's frame or the audio's position in bytes. This is the same file
VIDKIT's stand-alone players (PLAYMOVIES and the others) write, so either
player resumes the other's bookmarks.

Choosing a bookmarked file asks **Resume where it stopped?**: Yes resumes
it, No starts it again from the beginning and deletes the bookmark.
Play next, Repeat and Play all use the bookmark without asking. A file
that plays to its end loses its bookmark.

A run of files (Play next, Repeat, Play all) holds Veranda's screen
blanking off until it ends, so the screen stays on with no key pressed.

## Building

You need Prog8 12.3.5 (`prog8c`, or its jar with Java 17 or later),
64tass, Python 3, make and git; Veranda's SDK (a Veranda checkout's
`make sdk`, which needs cc65); and Prog8 for Veranda
([veranda-prog8](https://github.com/veranda-x16/veranda-prog8)), the
toolkit, at the version `TOOLKIT` names. VIDKIT itself is in
[`vendor/vidkit/`](vendor/vidkit/README.md).

Side by side, as the Makefile expects by default:

    git clone https://github.com/veranda-x16/veranda.git ../veranda
    make -C ../veranda sdk
    make toolkit                     # veranda-prog8 at TOOLKIT's version, into ../veranda-prog8
    make PROG8C="java -jar /path/to/prog8c-12.3.5-all.jar"

The player is `build/VIDKIT Player.cvt`. `P8KIT=` and `VSDK=` name other
places for the toolkit and the SDK, `P8KIT_URL=` another place to clone
the toolkit from. An exported tree (no `.git`) builds the same with
`P8KIT=` given: Veranda's release build does that.

`make test EMU=/path/to/x16emu ROM=/path/to/rom.bin` builds a test
version (AUTOTEST) and runs it headless from an SD card image: it plays
the folder by itself (WAV files `tests/mkwav.py` makes: three to play
and twenty short ones that make the list longer than the panel; or
`MEDIA=` files, 8BG.WAV, BEEP.WAV and CHIME.WAV first) and checks what
it logs: the plays, the bookmarks, a stop with F5's loop on, *Play all*
in an empty folder, the mouse wheel, Tab (nothing for a single file; a
skip in a list, its bookmark gone, the next file played; with
`DOG1.SPV` and `DOG2.SPV` among MEDIA, a skip from one video straight
into the next), the blanking held off for the run and put back.

The GitHub workflow (`.github/workflows/ci.yml`) does the same on each
push: Veranda's SDK from veranda-x16/veranda, the toolkit at `TOOLKIT`'s
version, the build (the `.cvt` as an artifact) and `make test`.

## Credits

- **VIDKIT** by Anthony W. Henry: the streaming library, MIT licence
  (`vendor/vidkit/`).
- **Prog8 for Veranda**
  ([veranda-x16/veranda-prog8](https://github.com/veranda-x16/veranda-prog8)),
  MIT: the Prog8 target and libraries the player is built with.
- **Veranda** by Marcin Spoczynski
  ([veranda-x16/veranda](https://github.com/veranda-x16/veranda)), MIT
  licence: the API the player is written against; its window's layout and
  look follow Veranda's
  [MOD Player](https://github.com/veranda-x16/mod-player) (MIT).
- Written in [Prog8](https://github.com/irmen/prog8) 12.3.5 (Irmen de Jong).

## Licence

MIT, Copyright (c) 2026 Anthony W. Henry (see [LICENSE](LICENSE)). The
parts ported from Veranda's MOD Player keep their notice, Copyright (c)
2026 Marcin Spoczynski, MIT: see [NOTICE.md](NOTICE.md).
