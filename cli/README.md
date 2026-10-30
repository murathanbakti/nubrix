# notchctl

Send notifications to the Nubrix notch from any shell script. Needs only `bash` and `curl`.

## Install

```sh
ln -s "$PWD/cli/notchctl" /usr/local/bin/notchctl
```

or, without sudo:

```sh
mkdir -p ~/.local/bin && ln -sf "$PWD/cli/notchctl" ~/.local/bin/notchctl
```

Make sure `~/.local/bin` is on your `PATH`.

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

Nubrix writes its loopback port and a random token to `~/.config/nubrix/agent-endpoint`
(override with `NUBRIX_ENDPOINT_FILE`). `notchctl` posts JSON to `/v1/notify` with that bearer token.
If Nubrix is not running, `notchctl` prints an error to stderr and exits 1.
