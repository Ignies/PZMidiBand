# PZ MIDI Band

Port of the Space Station 14 instrument system to Project Zomboid (Build 42 MP).

## Features

- Right-click any instrument item → **Play MIDI…**
- Load a `.mid` file from `Zomboid/midi/` (folder is created automatically on first launch).
- Real-time synthesis through the JVM's built-in **Gervill** synthesizer using a SoundFont (`.sf2`) - no native DLL, no FMOD integration required.
- Start a band as the **master**; other nearby players can **join** on a specific MIDI channel so each player sounds like their own instrument.
- Positional audio: volume falls off with distance from the master; server stops relaying events past ~36 tiles.

## Soundfont

The mod ships **without** a bundled SoundFont to keep download size small and avoid licensing headaches. On first launch the mod extracts a tiny fallback and looks for any of the following (in order):

1. `Zomboid/midi/soundfont.sf2` (user override — drop any `.sf2` here)
2. `<mod>/media/soundfonts/soundfont.sf2` (if the user copies one in)
3. JDK built-in `EmergencyGMSoundbank` (very quiet & lo-fi but works everywhere)

Recommended free soundfonts:

- **TimGM6mb** (~5.7 MB, MIT) - http://sourceforge.net/p/mscore/code/HEAD/tree/trunk/mscore/share/sound/
- **GeneralUser GS** (~30 MB, permissive) - http://www.schristiancollins.com/generaluser.php

Drop the file into `Zomboid/midi/soundfont.sf2` and restart the game.

## Compatibility

- **Project Zomboid Build 42 MP unstable** (required)
- Base PZ guitar-family items are supported out of the box
- **Nade's Craftable Instruments** (Workshop `3564084857`) is detected at runtime - each of its items maps to a sensible default GM program (saxophone, keytar, flute, etc.)

## Status

v0.1 - skeleton / first playable.
