# cosmic-firefox-pip-sticky

A tiny user level service for Pop!_OS COSMIC that automatically makes Firefox Picture-in-Picture windows sticky above other windows on your COSMIC desktop.

This fixes the common COSMIC behavior where Firefox PiP works, but falls behind the next focused app. The service checks every 2 seconds and applies COSMIC's sticky window state to any Firefox PiP window that is not already sticky.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/cosmic-firefox-pip-fix/main/cosmic-firefox-pip-sticky.sh | bash -s -- install
```

## Update

```bash
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/cosmic-firefox-pip-fix/main/cosmic-firefox-pip-sticky.sh | bash -s -- update
```

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/cosmic-firefox-pip-fix/main/cosmic-firefox-pip-sticky.sh | bash -s -- uninstall
```

## Status

```bash
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/cosmic-firefox-pip-fix/main/cosmic-firefox-pip-sticky.sh | bash -s -- status
```

## Logs

```bash
curl -fsSL https://raw.githubusercontent.com/MagnetosphereLabs/cosmic-firefox-pip-fix/main/cosmic-firefox-pip-sticky.sh | bash -s -- logs
```

## How it works

The service runs this extremely light COSMIC window helper action every 2 seconds:

```bash
cosmic-ext-window-helper sticky true "title = 'Picture-in-Picture' and app_id ~= 'firefox'i and not is_sticky"
```

The `not is_sticky` clause prevents repeated state changes once the PiP window has already been fixed.

## Files installed

- `~/Apps/cosmic-firefox-pip-sticky/cosmic-firefox-pip-sticky.sh`
- `~/.config/systemd/user/cosmic-firefox-pip-sticky.service`

The installer also installs `cosmic-ext-window-helper` with `pipx` if it is missing. The uninstaller leaves `cosmic-ext-window-helper` installed because other COSMIC scripts may use it.

## Change the polling interval

The default interval is 2 seconds. To override it:

```bash
systemctl --user edit cosmic-firefox-pip-sticky.service
```

Add:

```ini
[Service]
Environment=INTERVAL_SECONDS=1
```

Then restart:

```bash
systemctl --user daemon-reload
systemctl --user restart cosmic-firefox-pip-sticky.service
```
