# Murattal

Stream murottal Al-Qur'an per surah and qari from mp3quran.net, played headless via mpv. Bar widget shows the current surah. The panel uses searchable qari/surah dropdowns and exposes progress seek, repeat, shuffle, speed, sleep timer, and per-qari favorites; launcher searches surahs.

## Plugin

| Field | Value |
| --- | --- |
| ID | `abuamar142/murattal` |
| Entries | Bar widget: `murottal`; panel: `browser`; service: `player`; launcher: `finder` |
| Launcher Prefix | `/quran` |

## Requirements

Install `mpv` and `socat` on `PATH`. `mpv` does headless playback, `socat` talks to its IPC socket for volume/seek/speed. Without `socat`, volume changes relaunch mpv and progress is parsed from mpv's log; seek is unavailable.

## Usage

Add the `murottal` widget to the bar. Click toggles play/stop, right-click opens the panel, scroll changes volume.

Open the panel:

```sh
noctalia msg panel-toggle abuamar142/murattal:browser
```

Launcher: type `/quran <surah>` and press Enter to play. Empty `/quran` lists favorites. Type `/quran rm` to remove a favorite.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `default_volume` | `int` | `65` | mpv volume 0-100. |
| `mpv_bin` | `string` | `mpv` | mpv executable. |
| `show_name` (widget) | `bool` | `true` | Show surah name next to icon. |
| `max_length` (widget) | `int` | `24` | Max characters of surah name. |

## IPC

```sh
noctalia msg plugin abuamar142/murattal:player all play '{"reciterId":"1-1","surahId":1}'
noctalia msg plugin abuamar142/murattal:player all stop
noctalia msg plugin abuamar142/murattal:player all toggle
noctalia msg plugin abuamar142/murattal:player all next
noctalia msg plugin abuamar142/murattal:player all prev
noctalia msg plugin abuamar142/murattal:player all volume 60
noctalia msg plugin abuamar142/murattal:player all speed 1.25
noctalia msg plugin abuamar142/murattal:player all repeat
noctalia msg plugin abuamar142/murattal:player all shuffle
noctalia msg plugin abuamar142/murattal:player all sleep 30
noctalia msg plugin abuamar142/murattal:player all seek 42
noctalia msg plugin abuamar142/murattal:player all refresh
```

## Notes

- Network: mp3quran.net reciter/surah catalog and audio files.
- Files: favorites at plugin data dir `favorites.json`, mpv IPC socket `mpv.sock`.
- Processes: one headless `mpv --no-video`. Killed on disable/uninstall/exit.
