# Concert assets — sources and licences

These are real recordings, not synthesised noise. K rejected the first
"live concert" mix (2026-11-09) because the hall was a decaying pink-noise
impulse and the applause was band-limited noise: it read as a hiss, not a room
of people. The two files here replace those noise generators.

Both are committed (small: 0.7 MB + 1.2 MB) so a fresh clone renders with no
download. Neither needs a login and neither costs anything.

## `hall-ir.wav`

A measured impulse response of a real concert venue, used by `afir` to convolve
the song into the hall.

- Source: OpenAIR — The Open Acoustic Impulse Response Library, University of
  York. https://webfiles.york.ac.uk/OPENAIR/
- Original: `1st-baptist-nashville_far_wide.wav` (stereo, 96 kHz, 3.5 s).
- Licence: Creative Commons. OpenAIR states the data is "a rich resource of
  impulse response measurements for commercial audio software and computer games
  developers, composers, musicians and sound artists" and that it ships in
  Ableton Live, Reason, Studio One and Codemasters' games, so commercial use is
  intended. See https://www.york.ac.uk/physics-engineering-technology/research/
  communication-technologies/projects/open-acoustic-impulse-response-library/
- Prepared: downsampled to 48 kHz stereo to match the mix sample rate.

## `applause.wav`

A real audience applauding, looped under the intro/outro swells.

- Source: Wikimedia Commons, `277021 sandermotions applause-2.wav`.
- Original recording: https://freesound.org/people/Sandermotions/sounds/277021/
- Licence: **CC0** (public domain — no attribution required, commercial use OK).
- Prepared: resampled to 48 kHz stereo.
