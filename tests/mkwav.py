#!/usr/bin/env python3
"""The test's media: WAV files made here, so `make test` needs no one's
recordings. 22,050 Hz, 16 bits, stereo (88,200 bytes a second, as the test's
bookmark expects of 8BG.WAV), a few tones.

    python3 tests/mkwav.py <folder>      8BG.WAV (12 s), BEEP.WAV (6 s), CHIME.WAV (6 s)

MIT licence (see LICENSE)."""
import math
import os
import struct
import sys
import wave

RATE = 22050


def tone(path, secs, notes):
    frames = bytearray()
    n = int(RATE * secs)
    for i in range(n):
        f = notes[(i * len(notes)) // n]
        v = int(8000 * math.sin(2 * math.pi * f * i / RATE))
        frames += struct.pack('<hh', v, v)
    with wave.open(path, 'wb') as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    d = sys.argv[1]
    os.makedirs(d, exist_ok=True)
    tone(os.path.join(d, '8BG.WAV'), 12, [262, 330, 392, 523])
    tone(os.path.join(d, 'BEEP.WAV'), 6, [440, 880])
    tone(os.path.join(d, 'CHIME.WAV'), 6, [660, 550, 440])


if __name__ == '__main__':
    main()
