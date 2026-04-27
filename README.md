# Bad Apple // Beat Dash

A bullet-hell dodge game played on top of the original Bad Apple shadow-art video. Built in LÖVE2D 11.5 for [games.brassey.io](https://games.brassey.io).

The silhouette is decorative atmosphere — only spawned obstacles deal damage. Bullets, beams, waves, rings, spinners and chasers spawn on real beat / kick / snare / hat events extracted from the audio. Their warn windows resolve **on** the beat, so the music *is* the pattern.

The loop:

```
character room  →  play song  →  collect apples  →  shop  →  play again
                       ↑                                       ↓
                       └────────────────  unlocks  ───────────┘
```

## Run

```sh
love .
```

Targets LÖVE 11.5 / Lua 5.1.

## Controls

| Key | Where | Action |
| --- | --- | --- |
| **ENTER** / **SPACE** | menu | enter the character room |
| **ENTER** / **SPACE** | character | begin the song |
| **WASD** / **arrows** | play, lobby | move |
| **SPACE** / **SHIFT** | play, lobby | dash (i-frames + buffered while on cooldown) |
| **←** / **→** | character | pick colour (skips locked) |
| **↑** / **↓** | character, shop | aura / shop item |
| **B** | menu, character, dead, win | apple shop |
| **M** | menu, character | enter the cyber lobby |
| **L** | menu, character, win | toggle replay-on-win |
| **−** / **+** | menu | volume |
| **C** | menu | continue from last checkpoint |
| **R** / **ENTER** | dying, dead | revive / retry |
| **N** | dead | new run from start |
| **P** / **ESC** | play | pause |
| **Q** | paused | back to menu |
| **ESC** | most | up one level |

## Pipeline

1. Source video downloaded to `badapple_src.mp4` (gitignored, ~7 MB).
2. `ffmpeg` extracts the soundtrack to `assets/badapple.ogg`.
3. `ffmpeg` packs frames into 103 monochrome 1-bit spritesheets at 240 × 180 packed 8 × 8 (`assets/sheets/sheet_NNN.png`).
4. `ffmpeg` writes a separate 80 × 60 1-bit silhouette stream to `assets/collision.bin` (kept for future obstacle alignment; silhouette no longer hurts the player).
5. `tools/analyze_audio.py` decodes the OGG, runs band-split spectral-flux onset detection, estimates BPM by autocorrelation, and writes 4 362 events to `assets/beats.txt`.

Total runtime asset size: ~17 MB. Sheets are streamed lazily at runtime (4-entry LRU cache), so peak GPU RAM stays bounded regardless of song length.

## Architecture

```
bad-apple/
  conf.lua                       window 1920×1080, identity = bad_apple
  main.lua                       state machine, dispatcher, FX, achievements
  achievements.json              15-entry catalogue
  README.md, LICENSE, .gitignore
  assets/
    badapple.ogg                 extracted soundtrack
    beats.txt                    # bpm + (type, time, strength) events
    collision.bin                6572 frames × 80 × 60 1-bit silhouette mask
    sheets/sheet_001..103.png    monochrome spritesheets, 8 × 8 frames each
  src/
    video.lua                    lazy spritesheet cache + LRU eviction
    collision.lua                1-bit mask sampler + box-hit helper
    beats.lua                    cursor-based pre-roll event firer (+ proximity)
    player.lua                   3 × 3 fragment body, sparkle trail, dash buffer
    obstacles.lua                bullet / burst / beam / wave / ring / spinner / chaser
    director.lua                 song-aligned intensity ramp + deterministic gate
    glow.lua                     two-pass separable Gaussian bloom
    mosaic.lua                   silhouette colorizer shader (pink/cyan/violet/amber)
    save.lua                     atomic save (tmp + swap)
    multiplayer.lua              [[LOVEWEB_NET]] ghost positions / dashes / colour
    lobby.lua                    cyber-grid floor shader + lobby state draw
    character.lua                wardrobe / preview / unlocks display
    apples.lua                   collectible currency w/ optional magnet
    sfx.lua                      synthesised dash / hit / tick / revive / death
  lib/json.lua                   rxi/json.lua (MIT)
  tools/analyze_audio.py         band-split onset + BPM autocorrelation
```

## State machine

`boot → loading → menu → character → play → (paused | dying → reviving → play | dead | win) → menu`

Side states reachable from menu / character / dead / win:

- `shop` — pauses the world entirely (audio paused, no beats fire, no obstacles update)
- `lobby` — dedicated cyber-grid scene, separate from the song

## Player

- 3 × 3 grid of small rounded fragments + a bright central core. Each hit detaches one fragment (favouring the side opposite your input direction) and fires it off as a chunky shard plus a few smaller dust pieces. The body shrinks because it has fewer fragments, not because of a generic scale-down.
- Sparkle trail of small glowing rounded squares spawns behind the player when moving; dashing triples the spawn rate (or 6 × with the *Bigger Sparkle Trail* upgrade).
- Tight fixed hit-circle around the centre core — only direct contact with an obstacle's coloured hot zone hurts.
- Dash buffer: pressing dash during cooldown queues the dash and fires it as soon as the cooldown clears. `DASH_COOLDOWN 0.52` exceeds `IFRAME_DASH 0.40` with margin so dash spam can't grant permanent invulnerability.
- Hit-flash, knockback, screen shake, hit-stop (60 ms dt freeze for impact weight), red screen-edge tint on damage / cyan tint on close-call dodge.

## Obstacles

Every obstacle uses the same three-layer language so it reads at a glance:

1. soft outer glow halos (large, low alpha) — decorative, never hurt
2. bright pulsing white border ring — the visible danger edge (throbs at ~7 – 8 Hz, tied to `audio_t`)
3. filled rounded core in the accent colour — the actual hit zone

| Type | Shape | Telegraph | Hot |
| --- | --- | --- | --- |
| Bullet | rounded disc | accent guideline + expanding outline ring | 0.50 s |
| Burst | radial bullet ring | shared bullet preview | 0.50 s |
| Beam | rounded capsule | thin pulsing line + growing capsule preview | 0.55 s warn / 0.30 s fire |
| Wave | rounded slab pair with a gap | semi-transparent halves + pulsing white gap edges | 0.70 s |
| Ring | accent band, bright inner + outer borders | strobing accent outline growing radially | 0.50 s |
| Spinner | capped capsule arms with white core | strobing preview lines + centre marker | 0.65 s |
| Chaser | rounded orb that homes on the player | pulsing accent ring at spawn point | 0.60 s |

## Director

`Director.intensity(audio_t)` shapes the spawn density across the song:

```
intro (0-13)  verse 1 (13-46)  chorus 1 (46-78)  verse 2 (78-111)
chorus 2 (111-144)  bridge (144-177, cools off)  final chorus (177-210)  outro
```

The first 6 s lifts the floor to 0.05 so the player always sees one bullet early — the music's intro is otherwise too quiet to teach the loop. Climax peaks at 0.40.

`spawnGate(type, intensity, base)` is **deterministic** — accept every Nth event of a type at a rate scaled by intensity. No random coin-flip swings.

## Beat sync

`src/beats.lua` pre-rolls events 0.50 s ahead of the playhead so each obstacle's *fire* moment lands on the beat rather than starting on the beat. Soft revives rewind audio by 0.6 s — greater than the longest warn — so events that already fired pre-death aren't re-fired on resume.

## Saves

`save.json` (atomic write: tmp file + swap) tracks:

- `player_color` — selected palette index
- `aura_id` — selected aura cosmetic
- `upgrades` — owned shop items
- `apples` — currency balance
- `completions` — number of song clears (drives unlocks)
- `last_unlock` — string surfaced on the win screen
- `last_checkpoint`, `best_time`, `runs`, `deaths`, `hits_taken`, `dashes`
- `volume`, `completed`

Files in `love.filesystem` are cloud-synced by the portal so the character follows the user across sessions and devices. Missing keys are filled with sensible defaults at boot, so older saves keep working when new fields land.

## Apples + Shop

Glowing red apples spawn during play (every 3.2 – 5.5 s by intensity, 30 % faster with *Orchard's Bounty*), drift gently, and pop on contact for `+1 apple`. Shop items:

| Cost | Item | Effect |
| --- | --- | --- |
| 8 | Bigger Sparkle Trail | doubles trail density |
| 10 | Brighter Aura | wider glow halo |
| 15 | Quicker Dash | 25 % shorter cooldown |
| 18 | Apple Magnet | apples drift toward you |
| 25 | Extra Heart | +1 HP fragment |
| 20 | Greater Magnet | doubles magnet pull range |
| 30 | Second Wind | additional auto-revive marker |
| 35 | Sharper Score | +25 % score on every run |
| 40 | Orchard's Bounty | apples spawn 30 % more often |

## Unlocks (per song completion)

| Completions | Unlock |
| --- | --- |
| 1 | colour: lime |
| 2 | colour: ember + aura: Spinning Ring |
| 3 | colour: sky |
| 4 | colour: ivory + aura: Twin Echoes |
| 5 | colour: void |
| 6 | colour: blood + aura: Starlit Halo |
| 7 | colour: phantom |
| 8 | colour: gold |

Locked palette swatches show a padlock icon and the number of wins remaining; the win screen announces each new unlock as it lands.

## Cyber lobby

Press **M** from the menu (or character room) to enter the lobby. Dedicated scene with a neon grid-floor shader, a soft radial pool of accent light tracking your position, and a vertical scan-band sweep. The portal-authenticated handle floats above your square. Other connected players appear with their own colour, halo width and sparkle trail; their handles render above their squares. Position broadcasts at 4 Hz; latency is ~750 ms (it's presence + movement, not 60 Hz twitch).

## Achievements

15 entries in `achievements.json`, fired through `[[LOVEWEB_ACH]]unlock <key>`:

| Key | Title |
| --- | --- |
| first_blood | Tasted the Apple |
| first_dash | Quickstep |
| intro_clear | Past the Hush |
| halfway | Through the Mirror |
| chorus_survivor | Beneath the Chorus |
| apple_complete | Apple Consumed |
| untouched | Untouched |
| pacifist | Pacifist Runner |
| dasher | Dash Hand |
| close_call | Close Call |
| unbroken | Unbroken Combo |
| second_chance | It's NOT Over |
| flawless_intro | Clean Open |
| lobby_visitor | Not Alone |
| loop_lover | Loop Lover |

## Portal FX

Magic-print verbs emitted via `[[LOVEWEB_FX]]`:

- `flash <hex> <ms>` on hit / revive / win
- `shake <intensity> <ms>` on hit / death / heavy kicks
- `mood <hex> <0..1>` drifts at ~3 Hz with the song accent
- `ripple <hex> <x01> <y01> <ms>` on dash + revive
- `shatter <intensity> <ms>` on death + revive transitions

## Death / revive

Dying plays `IT'S OVER` for 1.6 s with the body shattering, music ducked to 20 % volume, then auto-transitions through a chromatic-glitch shader to `IT'S NOT OVER` for 1.4 s, restores volume, replays the death stinger as a revive swell, and resumes the song from `death_audio_t − 0.6 s` with full HP and brief invulnerability. Press **R** / **ENTER** during *dying* to skip straight to the revive. Hard `dead` state is reachable via N / R from the dead screen → new run / retry from checkpoint.

## License

MIT. The Bad Apple shadow-art video and audio are not redistributed in this repository — the build pipeline downloads the source and extracts assets locally.
