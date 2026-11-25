# VIDKIT Player

A video and audio player for **Veranda** on the **Commander X16**: SPV
videos full screen, WAV and ZCM audio in its window. It streams from the
SD card with **VIDKIT**, Anthony W. Henry's banked-RAM streaming library,
which is packed inside the program. Its window follows Veranda's MOD
Player.

- **Download:** [`VIDKIT Player.cvt`](VIDKIT%20Player.cvt) in this repository
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
Left goes up a folder. Alt+Q quits.

While it plays: Esc stops, Space pauses, Up/Down set the volume.

With **Play next** on, the player goes on to the next file by itself.
A video followed by another video runs straight into it, fading through
black, without coming back to the window.

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

## Credits

- **VIDKIT** by Anthony W. Henry: the streaming library, MIT licence.
- **Veranda** by Marcin Spoczynski
  ([veranda-x16/veranda](https://github.com/veranda-x16/veranda)), MIT
  licence: the API the player is written against; its window's layout and
  look follow Veranda's
  [MOD Player](https://github.com/veranda-x16/mod-player) (MIT).
- Written in [Prog8](https://github.com/irmen/prog8) 12.3.5 (Irmen de Jong).

## Licence

MIT, Copyright (c) 2026 Anthony W. Henry (see [LICENSE](LICENSE)).
