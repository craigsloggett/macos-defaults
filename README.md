# macos-defaults

A POSIX shell tool for managing macOS preferences as code.

Record the settings you want as data, then apply them on any Mac, check them for drift, and find the ones you have not recorded yet.

## Why Not A Script Of `defaults write` Lines

`defaults write` returns 0 for a key macOS no longer reads. There is no such thing as a failed write, so a write-only script cannot tell you it has stopped working, and it will not. That is why `.macos` scripts copied from a gist rot silently: several long-circulated keys do nothing on current macOS, and every run still reports success.

Keeping the settings as `(domain, key, type, value)` records instead makes two checks possible that a script cannot have:

| Command | What it catches                                                                              |
| ------- | -------------------------------------------------------------------------------------------- |
| `lint`  | A mistyped domain or key. Pure text validation, no macOS needed, so it runs in CI.             |
| `check` | A setting changed in the GUI and never recorded, and a key retired by an OS upgrade.           |

Applying restarts only the processes whose domains actually changed, so a re-run is silent. Restarting Dock and Finder unconditionally is why these scripts get run once and never again.

## Install

```sh
brew install craigsloggett/tap/macos-defaults
```

## Use

```sh
macos-defaults lint      # Validate the records as text.
macos-defaults check     # Report drift, exit non-zero. Changes nothing.
macos-defaults apply     # Write the drift, restart the affected processes.
macos-defaults doctor    # Report on what cannot be scripted at all.
```

Records are read from `./settings` unless `--settings DIR` says otherwise. Run `check` regularly; a settings repository first executed on rebuild day is one nobody has tested.

## Record Format

Tab separated, four fields, one file per System Settings pane:

```
# System Settings > Desktop & Dock
com.apple.dock	autohide	bool	true
com.apple.dock	tilesize	int	45
com.apple.dock	show-recents	bool	false
```

Types are the `defaults write` flags: `bool`, `int`, `float`, `string`. Dictionaries and arrays are deliberately excluded; bending a flat format to express `persistent-apps` would ruin it for everything else, and that key is machine specific anyway.

Always confirm the type with `defaults read-type <domain> <key>` before recording. A bool and an int both read as `1`, so a wrong type looks settled under `check` while applying it rewrites the key with the wrong type. `check` compares types as well as values for exactly this reason.

See [`examples/`](examples) for annotated records.

## Finding The Key Behind A Toggle

There are around 470 preference domains on a typical Mac, and dozens of them rewrite themselves every hour while the machine sits idle. A plain before and after diff drowns the signal, so take a third snapshot with nothing touched to measure that noise, then subtract it:

```sh
macos-defaults snapshot before
sleep 20
macos-defaults snapshot control     # Nothing touched: pure noise.

# Now flip exactly one toggle in System Settings.
macos-defaults snapshot after

macos-defaults diff before control >/tmp/noise
macos-defaults diff before after | grep -vxF -f /tmp/noise
```

That prints the domains that changed. Pass one as an argument to see the hunks:

```sh
macos-defaults diff before after com.apple.dock
```

Snapshots go to `$XDG_STATE_HOME/macos-defaults/snapshots`, never into your repository, because they contain access tokens, account identifiers and the hardware UUID. Override with `--snapshots DIR`.

A fresh macOS VM makes a better discovery clean room than your daily driver, since a pristine install with no iCloud has almost no preference churn.

## Restart Map

`share/restart.conf` maps each domain to the process that re-reads it. `logout` means the domain has no owning process and its keys are read at login, so the tool prints a note instead of logging you out. `none` means the value is consulted per use.

Every domain you record must appear in that map or in your own `settings/restart.conf`, which takes precedence. `lint` enforces this, so a new record cannot be applied and then silently fail to take effect.

## What Not To Record

Never capture a whole Apple domain. Most of them are mostly machine state:

| Domain                      | Why                                                                 |
| --------------------------- | --------------------------------------------------------------------- |
| `com.apple.finder`          | Over a thousand lines of column widths and window bounds around roughly twenty real settings. |
| `com.apple.spaces`          | Keyed by physical display UUID. Restoring it on new hardware produces phantom Spaces. |
| `com.apple.dock`            | `persistent-apps` embeds file bookmark blobs with inode and volume UUID. |
| `com.apple.controlcenter`   | Opaque blobs plus menu bar pixel offsets tied to your display width.   |
| `MobileMeAccounts`          | Your Apple ID and per-service tokens. A read-only cache of server state. |
| Anything under `-currentHost` | Keyed by hardware UUID, so meaningless after a hardware change.       |

## What Cannot Be Scripted

`doctor` reports on these. TCC privacy grants are the hard blocker: both databases are protected by System Integrity Protection, and `tccutil` supports one verb, `reset`, so it can revoke but never grant. FileVault, iCloud sign-in, Touch ID enrollment, login items under `SMAppService`, the default browser, and the wallpaper all need a human too.

`doctor` always exits 0. These are human actions, and a check that blocks an install is a check that gets deleted.

## Layout

| Path                    | Purpose                                                    |
| ----------------------- | ------------------------------------------------------------ |
| `bin/macos-defaults.sh` | Front end. Resolves paths, parses shared options, dispatches. |
| `libexec/apply.sh`      | The `apply`, `check` and `lint` engine.                       |
| `libexec/snapshot.sh`   | Captures every domain under a label.                          |
| `libexec/diff.sh`       | Compares two snapshots.                                       |
| `libexec/doctor.sh`     | Reports on what cannot be scripted.                           |
| `share/restart.conf`    | Domain to process map.                                        |
| `share/noise.conf`      | Keys macOS rewrites on its own, stripped before diffing.      |

## License

MIT
