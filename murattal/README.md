# Murattal

Stream murottal Al-Qur'an per surah and qari from mp3quran.net, played headless via mpv. Bar widget shows the current surah. The panel has two tabs: **Putar** (playback card, juz queue, qari filtered by riwayah, offline downloads, repeat/shuffle, speed, sleep timer, favorites) and **Teks** (the Arabic text of the current surah with optional Latin and Indonesian translation). The launcher searches surahs, juz, and qari.

## Plugin

| Field | Value |
| --- | --- |
| ID | `abuamar142/murattal` |
| Entries | Bar widget: `murottal`; panel: `browser`; service: `player`; launcher: `finder` |
| Launcher Prefix | `/quran` |

## Requirements

Install `mpv` and `socat` on `PATH`. `mpv` does headless playback, `socat` talks to its IPC socket for volume/seek/speed. Without `socat`, volume changes relaunch mpv and progress is parsed from mpv's log; seek is unavailable.

Optional: `mpv-mpris` (AUR, `mpv-mpris-git`) so the bar media widget, keyboard media keys, and `playerctl` can control playback. The plugin passes `--script=/usr/lib/mpv/mpris.so` to mpv when that file exists. Helper: `mpv-mpris-setup.sh`.

## Usage

Add the `murottal` widget to the bar. Click toggles play/stop, right-click opens the panel, scroll changes volume.

Open the panel:

```sh
noctalia msg panel-toggle abuamar142/murattal:browser
```

### Panel

- **Putar** — now playing, progress seek, prev/play/next, favorite toggle. Below it: a juz selector ("Putar juz" queues every surah of that juz and advances through them), a riwayah filter that narrows the qari dropdown, the qari and surah pickers, an offline download toggle for the current surah, repeat/shuffle, repeat count (1x–5x for memorisation), speed, and sleep timer.
- **Teks** — the text of the surah currently loaded in the player, fetched once from equran.id and cached under the plugin data dir. Paged 20 ayah at a time. Translation and transliteration follow the panel settings.

Playback position is saved every 15 s and on stop/exit, and restored on the next start, so a restart does not send you back to Al-Fatihah.

### Launcher

```
/quran <surah>          play a surah with the current qari
/quran juz 30           play a juz in order
/quran riwayah warsh    pick a qari from that riwayah
/quran unduh            download the current surah for offline playback
/quran rm               remove a favorite
```

Empty `/quran` lists favorites.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `default_volume` | `int` | `65` | mpv volume 0-100. |
| `mpv_bin` | `string` | `mpv` | mpv executable. |
| `show_name` (widget) | `bool` | `true` | Show surah name next to icon. |
| `max_length` (widget) | `int` | `24` | Max characters of surah name. |
| `show_translation` (panel) | `bool` | `true` | Show the Indonesian translation under each ayah. |
| `show_latin` (panel) | `bool` | `false` | Show the Latin transliteration under each ayah. |

## IPC

```sh
noctalia msg plugin abuamar142/murattal:player all play '{"reciterId":"1-1","surahId":1}'
noctalia msg plugin abuamar142/murattal:player all stop
noctalia msg plugin abuamar142/murattal:player all toggle
noctalia msg plugin abuamar142/murattal:player all next
noctalia msg plugin abuamar142/murattal:player all prev
noctalia msg plugin abuamar142/murattal:player all juz 30
noctalia msg plugin abuamar142/murattal:player all volume 60
noctalia msg plugin abuamar142/murattal:player all speed 1.25
noctalia msg plugin abuamar142/murattal:player all repeat
noctalia msg plugin abuamar142/murattal:player all repeatCount 3
noctalia msg plugin abuamar142/murattal:player all shuffle
noctalia msg plugin abuamar142/murattal:player all sleep 30
noctalia msg plugin abuamar142/murattal:player all seek 42
noctalia msg plugin abuamar142/murattal:player all download
noctalia msg plugin abuamar142/murattal:player all removeDownload
noctalia msg plugin abuamar142/murattal:player all refresh
```

## Notes

- Network: mp3quran.net reciter/surah catalog and audio, equran.id for surah text.
- Files: favorites at `favorites.json`, last position at `state.json`, downloaded audio at `audio/<moshaf>/NNN.mp3`, cached text at `text/NNN.json`, mpv IPC socket `mpv.sock` — all under the plugin data dir.
- Processes: one headless `mpv --no-video`. Killed on disable/uninstall/exit.
- A juz maps to every surah it touches, because the catalogue serves audio per surah; the first and last surah of a juz are shared with its neighbour.
