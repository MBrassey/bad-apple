# Bad Apple // Beat Dash

A bullet-hell dodge game played on top of the original Bad Apple shadow-art video. Built in LÖVE2D 11.5 for [games.brassey.io](https://games.brassey.io).

The silhouette is your background **and** an obstacle: any pixel of the silhouette overlapping the player deals damage. On top of that, bullets, beams, waves, rings, spinners, and chasers spawn on real beat / kick / snare / hat events extracted directly from the audio.

## What makes it tick

- **Real video, native rendering.** The source video is unpacked into 75 monochrome 1-bit spritesheets (480x360 cells) packed 8x11 each. The current frame is `floor(audio_time * 30)`, indexed off the audio source's `:tell()`, so the silhouette is locked to the music to within a frame.
- **Real audio drives everything.** A Python pre-pass (`tools/analyze_audio.py`) decodes the OGG, splits into low/mid/high bands, runs spectral-flux onset detection on each, estimates BPM by autocorrelation of the full-band onset envelope, and builds a phase-aligned beat grid that gets snapped to nearby strong onsets. The result lives in `assets/beats.txt` -- 4362 ordered events.
- **JSAB-style player.** A glowy rounded-corner square that's also a health bar: full HP at 36px, shrinking to 14px as you take hits. Every hit blasts off a chunk of the body as flying shards, applies a knockback nudge, gives short i-frames and a flash.
- **Dash with i-frames.** Snappy 0.18s dash, 0.45s cooldown, 0.22s of i-frames, ripple FX on cast, dense trail while active. Dashing through an obstacle's hot zone counts as a *close call* -- there's an achievement for it.
- **It's NOT over.** Death plays a "IT'S OVER" slam-down, shatters the body, then automatically transitions through a chromatic-glitch revive screen ("IT'S NOT OVER") and resumes from the exact death point with full HP and brief invulnerability. Holding a checkpoint every 12s gives a fallback retry point on quit.
- **Difficulty ramp.** `Director.intensity(t)` shapes spawn density across the song: intro/verse spawn singles, build adds rings and waves, choruses add beams and spinners, climax adds chasers. Same beat stream drives both spawns and visual pulse, so silhouette halo, obstacles, and screen shake hit on the same downbeats.
- **Bloom.** Two-pass separable Gaussian blur, threshold-pass for highlights, kicked harder on every kick beat.
- **Lobby ghosts.** Press **M** to join the public lobby. Other players show up as faded glowy squares smoothed toward their last reported position. Broadcasts at 4Hz over the portal's `[[LOVEWEB_NET]]` event bridge.
- **Score + combo.** Time-alive scoring with a dodge combo multiplier, a per-run best-combo tracker, and a session loop counter for replay-on-win.
- **Achievements.** 15 catalogued in `achievements.json`, fired through `[[LOVEWEB_ACH]]` magic-print verbs.

## Controls

| Key | Action |
| --- | --- |
| **WASD** / **arrows** | move |
| **Space** / **Shift** | dash (i-frames during dash + tail) |
| **Esc** / **P** | pause |
| **Q** (paused) | back to menu |
| **R** / **Enter** (dying) | skip "IT'S OVER" and revive immediately |
| **R** / **Enter** (dead) | retry from last checkpoint |
| **N** (dead) | new run from start |
| **L** | toggle replay-on-win |
| **M** (menu) | join / leave the lobby |
| **-** / **+** (menu) | volume |

## Run

```sh
love .
```

The game targets LÖVE 11.5 and Lua 5.1.

## Pipeline

1. Source video downloaded to `badapple_src.mp4` (gitignored, 7 MB).
2. `ffmpeg` extracts the soundtrack to `assets/badapple.ogg` (libvorbis q=5, 3.4 MB).
3. `ffmpeg` packs frames into 75 1-bit monochrome spritesheets (`assets/sheets/sheet_NNN.png`, 8.8 MB total).
4. `ffmpeg` writes a separate 80x60 1-bit collision stream (`assets/collision.bin`, 3.8 MB) sampled per frame for silhouette pixel hits.
5. `tools/analyze_audio.py` produces `assets/beats.txt`.

Total runtime asset size: 17 MB.

## Layout

```
bad-apple/
  conf.lua                     window 1920x1080, identity = bad_apple
  main.lua                     state machine, FX, achievements, lobby, score
  achievements.json            15-entry catalogue
  README.md, LICENSE, .gitignore
  assets/
    badapple.ogg               extracted soundtrack
    beats.txt                  # bpm + ordered (type, time, strength) events
    collision.bin              6572 frames * 80x60 1-bit silhouette mask
    sheets/sheet_001..075.png  monochrome spritesheets, 8x11 frames each
  src/
    video.lua                  sheet loader, frame quad picker, silhouette draw
    collision.lua              1-bit mask sampler with box-hit helper
    beats.lua                  beats.txt loader + cursor-based event firer
    player.lua                 dash, glow, shards, hp-as-size body
    obstacles.lua              bullet / burst / beam / wave / ring / chaser / spinner
    director.lua               intensity ramp + per-event obstacle picker
    glow.lua                   two-pass separable Gaussian bloom
    save.lua                   checkpoint + run-stats persistence
    multiplayer.lua            lobby ghosts via [[LOVEWEB_NET]]
  lib/json.lua                 rxi/json.lua (MIT)
  tools/analyze_audio.py       band-split onset + BPM autocorr
```

## Saves

`save.json` (in the LÖVE save directory, cloud-synced on the portal) tracks `last_checkpoint`, `best_time`, `runs`, `deaths`, `hits_taken`, `dashes`, `volume`, and `completed`. Auto-stamped every 12s of survival; survives the dying/reviving loop so you only lose checkpoint progress on a hard quit.

## Achievements

| key | title | rarity |
| --- | --- | --- |
| first_blood | First Blood | common |
| first_dash | Quickstep | common |
| intro_clear | Past the Hush | common |
| halfway | Halfway House | uncommon |
| chorus_survivor | Through the Chorus | uncommon |
| apple_complete | Apple Consumed | rare |
| untouched | Untouched | legendary |
| pacifist | Pacifist Runner | legendary |
| dasher | Dash Hand | uncommon |
| close_call | Close Call | uncommon |
| unbroken | Unbroken Combo | rare |
| second_chance | It's NOT Over | common |
| flawless_intro | Clean Open | uncommon |
| lobby_visitor | Not Alone | uncommon |
| loop_lover | Loop Lover | rare |

## License

MIT. The Bad Apple shadow-art video and audio are not redistributed in this repository -- the build pipeline downloads the source video, extracts assets, then everything but the source is committed.
