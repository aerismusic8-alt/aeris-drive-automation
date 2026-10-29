"""Music theory, chord charts and melody generation for the song engine.

Everything is derived from a key and a mood, with a seeded RNG, so a song is
reproducible: the same lyric file always yields the same melody and arrangement.
Melodies are a constrained random walk over the scale, weighted toward chord
tones on strong beats, which keeps them singable without hand-writing 20 tunes.
"""
from __future__ import annotations

import random
from dataclasses import dataclass, field

# Semitone offsets.
_NOTE = {"C": 0, "C#": 1, "Db": 1, "D": 2, "D#": 3, "Eb": 3, "E": 4, "F": 5,
         "F#": 6, "Gb": 6, "G": 7, "G#": 8, "Ab": 8, "A": 9, "A#": 10, "Bb": 10, "B": 11}

MAJOR = (0, 2, 4, 5, 7, 9, 11)
MINOR = (0, 2, 3, 5, 7, 8, 10)

# Mood -> (scale, tempo, progression as scale degrees, feel)
MOODS = {
    "sad":     {"scale": MINOR, "tempo": 68, "prog": [0, 5, 3, 4], "feel": "ballad"},
    "calm":    {"scale": MINOR, "tempo": 72, "prog": [0, 5, 2, 4], "feel": "ballad"},
    "warm":    {"scale": MAJOR, "tempo": 76, "prog": [0, 4, 5, 3], "feel": "ballad"},
    "hopeful": {"scale": MAJOR, "tempo": 80, "prog": [0, 3, 4, 5], "feel": "mid"},
    "mystic":  {"scale": MINOR, "tempo": 64, "prog": [0, 3, 5, 4], "feel": "ballad"},
    "epic":    {"scale": MINOR, "tempo": 92, "prog": [0, 5, 2, 4], "feel": "anthem"},
}


def midi_to_freq(midi: float) -> float:
    return 440.0 * (2.0 ** ((midi - 69) / 12.0))


def parse_key(key: str) -> tuple[int, tuple[int, ...]]:
    """'Am' / 'C' / 'F#m' -> (root midi in octave 3, scale intervals)."""
    key = key.strip()
    minor = key.endswith("m")
    name = key[:-1] if minor else key
    root = _NOTE[name]
    # Put the tonic in a comfortable low-mid octave (MIDI 48 = C3).
    return 48 + root, (MINOR if minor else MAJOR)


@dataclass
class Chord:
    degree: int
    notes: list[int]          # midi, low to high

    @property
    def root(self) -> int:
        return self.notes[0]


def diatonic(root_midi: int, scale: tuple[int, ...], degree: int,
             octave: int = 0) -> list[int]:
    """Triad on a scale degree, stacking scale thirds."""
    def step(i: int) -> int:
        oct_, idx = divmod(i, len(scale))
        return root_midi + 12 * (oct_ + octave) + scale[idx]
    d = degree
    return [step(d), step(d + 2), step(d + 4)]


def progression(root_midi: int, scale: tuple[int, ...],
                degrees: list[int], bars: int) -> list[Chord]:
    return [Chord(degrees[i % len(degrees)],
                  diatonic(root_midi, scale, degrees[i % len(degrees)]))
            for i in range(bars)]


# --- arrangement -----------------------------------------------------------

@dataclass
class Section:
    name: str
    bars: int
    lyric_lines: list[str] = field(default_factory=list)


def arrangement(seed: int, mood: str, lines: dict[str, list[str]]) -> list[Section]:
    """Return the song's section plan, drawing lyric lines from their pools."""
    rng = random.Random(seed)
    verse = lines.get("verse") or []
    chorus = lines.get("chorus") or []
    bridge = lines.get("bridge") or []

    def pick(pool: list[str], n: int) -> list[str]:
        if not pool:
            return []
        out = []
        for i in range(n):
            out.append(pool[(i + rng.randrange(len(pool))) % len(pool)])
        return out

    plan = [
        Section("intro", 4, []),
        Section("verse", 8, pick(verse, 8)),
        Section("chorus", 8, pick(chorus, 8)),
        Section("verse", 8, pick(verse, 8)),
        Section("chorus", 8, pick(chorus, 8)),
        Section("bridge", 4, pick(bridge or verse, 4)),
        Section("chorus", 8, pick(chorus, 8)),
        Section("outro", 4, []),
    ]
    return plan


# --- melody ----------------------------------------------------------------

# Rhythm patterns: note lengths in beats for a line, chosen so a line fills its
# bar allocation. A pattern is scaled if it does not sum to the target.
_RHYTHMS = [
    [1, 1, 1, 1],
    [0.5, 0.5, 1, 1, 1],
    [1, 0.5, 0.5, 1, 1],
    [1.5, 0.5, 1, 1],
    [0.5, 0.5, 0.5, 0.5, 1, 1],
    [1, 1, 0.5, 0.5, 1],
    [2, 1, 1],
    [1, 1, 2],
]


def _fit_rhythm(rng: random.Random, n: int, total_beats: float) -> list[float]:
    """Return n note lengths summing to total_beats."""
    base = _RHYTHMS[rng.randrange(len(_RHYTHMS))]
    # Stretch the pattern to n notes by repeating/trimming.
    out = []
    while len(out) < n:
        out.extend(base)
    out = out[:n]
    s = sum(out)
    return [max(0.25, v * total_beats / s) for v in out]


def melody_for_line(rng: random.Random, root_midi: int, scale: tuple[int, ...],
                    chord: Chord, n_syllables: int, total_beats: float,
                    prev_degree: int | None, register: int = 12) -> tuple[list[tuple[int, float]], int]:
    """Return ([(midi, beats)], last_degree) for a line, one note per syllable.

    The walk stays within `register` semitones of the tonic and prefers a chord
    tone on the first note of each line so phrases resolve against the harmony.
    """
    if n_syllables <= 0:
        return [], (prev_degree or 0)
    lengths = _fit_rhythm(rng, n_syllables, total_beats)
    chord_pcs = {n % 12 for n in chord.notes}

    deg = prev_degree if prev_degree is not None else 0
    notes: list[tuple[int, float]] = []
    for i, beats in enumerate(lengths):
        if i == 0:
            # Land on a chord tone near the previous note.
            cands = [d for d in range(-3, len(scale) + 8)
                     if (root_midi + _degree_semitone(scale, d)) % 12 in chord_pcs]
            deg = min(cands, key=lambda d: abs(d - deg)) if cands else deg
        else:
            deg += rng.choice([-2, -1, -1, 0, 1, 1, 2])
        deg = max(-4, min(len(scale) + 8, deg))
        midi = root_midi + 12 + _degree_semitone(scale, deg)  # +1 octave for the voice
        # Keep the voice in a comfortable range.
        while midi > root_midi + register + 7:
            midi -= 12
        while midi < root_midi + 4:
            midi += 12
        notes.append((midi, beats))
    return notes, deg


def _degree_semitone(scale: tuple[int, ...], degree: int) -> int:
    oct_, idx = divmod(degree, len(scale))
    return 12 * oct_ + scale[idx]
