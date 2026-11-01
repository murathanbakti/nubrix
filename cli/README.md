# notchctl

Send notifications to the Nubrix notch from any shell script. Needs only `bash` and `curl`.

## Install

`notchctl` ships with Nubrix and is installed by the hook installer, which puts a sealed, read-only copy at
`~/.config/nubrix/bin/notchctl`:

```sh
# Homebrew or install script
bash /Applications/Nubrix.app/Contents/Resources/nubrix-hooks/scripts/install-hooks.sh

# from a source checkout
scripts/install-hooks.sh
```

Run it again after updating Nubrix. Then use the copy directly, link it into a folder on your `PATH`, or add its
directory to your `PATH`:

```sh
~/.config/nubrix/bin/notchctl ping
ln -sf ~/.config/nubrix/bin/notchctl ~/.local/bin/notchctl
export PATH="$HOME/.config/nubrix/bin:$PATH"
```

Do not symlink `cli/notchctl` from a repository checkout: the sealed copy cannot be changed by a repository update or by
a program running as you.

## Usage

```sh
notchctl notify "Build done"
notchctl notify "Deploy finished" --title api --style success --duration 6
notchctl ping && echo "Nubrix is running"
notchctl --help
```

Styles: `success`, `error`, `info` (default), `warning`. Duration is in seconds (1-30, default 4).
Notifications appear as a banner on the closed notch; click it to open the Dev tab, which keeps the last 50.

## Examples

```sh
npm test && notchctl notify "Tests passed" --style success || notchctl notify "Tests failed" --style error
gh run watch && notchctl notify "CI done"
long-running-command; notchctl notify "Finished with exit code $?" --title "$(basename "$PWD")"
```

## How it works

Nubrix writes its loopback port, a random token and its process id to `~/.config/nubrix-run/agent-endpoint`
(directory mode 0700, file mode 0600). `notchctl` checks that the file is owned by you with mode 0600 and that its
process id belongs to a running `Nubrix.app` of yours, then posts JSON to `/v1/notify` with that bearer token; the token
and the message are passed to `curl` through file descriptors, never on its command line.
If Nubrix is not running (or the endpoint file is stale), `notchctl` prints an error to stderr and exits 1.
`NUBRIX_ENDPOINT_FILE` is honoured only together with `NUBRIX_DEV=1`, which also skips the owner, mode and process
checks (tests only).
