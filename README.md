# jevsh

English | [日本語](README.ja.md)

Ask JEV how risky a shell command is before you run it.

jevsh sends the command line you give it to the JEV AI service (TypeSafe), shows the risk level (LOW / MEDIUM / HIGH / CRITICAL) with its confidence, and runs the command only if you answer `y`. JEV only advises; you decide.

```text
$ jevsh rm -rf ./build
Command: rm -rf ./build
JEV risk: HIGH (confidence 60%)
  LOW 1%  MEDIUM 29%  HIGH 70%  CRITICAL 0%
Run this command?
  y      run it now
  n      cancel (Enter also cancels)
[y/N]: n
Canceled.
```

## Requirements

- Linux with bash 4.4 or later
- `curl`
- A JEV API key from TypeSafe

jevsh is a single bash script. It does not need root, and it does not install anything else.

## Install

Download a tagged release into `~/.local/bin`, check it, and make it executable.

```bash
VERSION=v0.3.1
BASE=https://raw.githubusercontent.com/takeshiue/jevsh/$VERSION
mkdir -p ~/.local/bin
cd "$(mktemp -d)"
curl -fsSLO "$BASE/jevsh"
curl -fsSLO "$BASE/SHA256SUMS"
curl -fsSLO "$BASE/SHA256SUMS.sig"
curl -fsSLO "$BASE/jevsh-release.pub"
```

Check the signature and the checksum (see [Verify the download](#verify-the-download)), then:

```bash
install -m 755 jevsh ~/.local/bin/jevsh
command -v jevsh && jevsh --version
```

If `command -v jevsh` prints nothing, `~/.local/bin` is not in your `PATH` yet. On many distributions `~/.profile` adds it when the directory exists, so log in again or run `source ~/.profile`.

To install for all users instead, use `sudo install -m 755 jevsh /usr/local/bin/jevsh`.

Do not pipe the script into a shell (`curl ... | bash`). Download it, check it, then run it.

## Verify the download

Each release has `SHA256SUMS` signed with the jevsh release key (`SHA256SUMS.sig`). The public key is in the repository (`jevsh-release.pub`, and `allowed_signers` for `ssh-keygen`). Its fingerprint is:

```text
SHA256:LIdW6JBHIV1YvPQHU+suSOe87ZJgNZGZlfjNdl1kkKg
```

```bash
# Check that jevsh-release.pub is the jevsh release key.
ssh-keygen -lf jevsh-release.pub    # compare with the fingerprint above
echo "takeshi.uematsu@gmail.com $(cat jevsh-release.pub)" > allowed_signers
# Check that SHA256SUMS was signed by that key.
ssh-keygen -Y verify -f allowed_signers -I takeshi.uematsu@gmail.com \
  -n file -s SHA256SUMS.sig < SHA256SUMS
# Check that jevsh matches SHA256SUMS.
sha256sum -c --ignore-missing SHA256SUMS
```

## First run

The first time you assess a command, jevsh explains what is sent and asks for your API key. The key is checked with the API before it is saved to `~/.config/jevsh/config` (mode 0600). The key is never shown on screen.

You can also set the key with the `JEV_API_KEY` environment variable, or register or replace it at any time with `jevsh --set-key`.

## Usage

```text
jevsh [options] COMMAND [ARGS...]    assess, confirm, then run
jevsh [options] -c 'COMMAND LINE'    same, for a full line (pipes etc.)
jevsh --check [--fail-on LEVEL] COMMAND [ARGS...]
jevsh --check [--fail-on LEVEL] -c 'COMMAND LINE'
jevsh --set-key
jevsh --init bash
jevsh --yes | --no-jev COMMAND [ARGS...]
jevsh --enable-keybinding | --disable-keybinding
jevsh --help | --version
```

Only `y` or `Y` runs the command. Anything else, including Enter alone, cancels.

### Skip the question for low risks

To run low-risk commands without answering `y`, export `JEVSH_AUTO_RUN` in `~/.bashrc`:

```bash
export JEVSH_AUTO_RUN=LOW       # LOW runs without asking; MEDIUM and above still ask
```

With `MEDIUM`, both LOW and MEDIUM run without asking. The assessment is still shown, followed by `Running without asking (...)`. jevsh always asks when it could not assess the command, and never runs anything without a terminal. This works both for `jevsh COMMAND` and for the key binding.

### Pipes and redirections

Your shell handles `|`, `>`, `>>`, `<`, `&&`, `||` and `;` before jevsh runs, so jevsh would only see the part before them. Use `-c` with single quotes to assess the whole line:

```bash
jevsh -c 'cat data.csv | sort > out.txt'    # assesses the full line
jevsh cat data.csv | sort > out.txt         # assesses only "cat data.csv"
```

### Key binding

With the key binding you do not need to type `jevsh` or quotes. Type a command as usual, then press **Ctrl+X Enter** instead of Enter. The whole line, including pipes and redirections, is assessed. If you answer `n`, the line stays at the prompt so you can edit it. Enter alone still runs commands normally, without assessment.

jevsh offers to add the key binding right after you register your API key. You can also add or remove it at any time:

```bash
jevsh --enable-keybinding     # adds a marked block to ~/.bashrc (asks first, keeps a backup)
jevsh --disable-keybinding    # removes only that block
```

Then open a new terminal or run `source ~/.bashrc`.

**Ctrl+Enter** also works if your terminal sends a distinct key sequence for it (`ESC [ 13 ; 5 u`). Many terminals send the same code as Enter, so Ctrl+X Enter is the default that works everywhere. For example, in Windows Terminal add these entries to `actions` and `keybindings` in `settings.json`, keeping your existing entries:

```json
{"command":{"action":"sendInput","input":"\u001b[13;5u"},"id":"Jevsh.AssessLine"}
{"id":"Jevsh.AssessLine","keys":"ctrl+enter"}
```

To use another key, set `JEVSH_KEY` to a Readline key sequence in `~/.bashrc` before the jevsh block:

```bash
JEVSH_KEY='\C-x\C-a'
```

### Scripts and loops

`--check` assesses without asking and without running anything. It prints one line: `RISK CONFIDENCE LINE`.

```bash
$ jevsh --check find / -type f -delete
CRITICAL 1.00 find / -type f -delete
```

With `--fail-on LEVEL`, jevsh exits with status 1 if the risk is LEVEL or higher:

```bash
if jevsh --check --fail-on HIGH -c "$line"; then
    echo "below HIGH"
fi
```

Each line calls the API once, so large loops take time and use your API quota.

### Run without the question

- `jevsh --yes COMMAND` assesses the command, shows the result, and runs it without asking. If the command could not be assessed, nothing runs (exit status 3). It also works without a terminal; the result then goes to stderr.
- `jevsh --no-jev COMMAND` runs the command without assessment and without asking, as if you had typed it without jevsh.

Use `--yes` with care: it runs even CRITICAL commands. To skip the question only for low risks, use `JEVSH_AUTO_RUN` instead.

### In shell scripts

- The key binding works only at your interactive bash prompt. Lines in a shell script run as usual, without assessment.
- `jevsh COMMAND` inside a script asks on your terminal each time, when the script runs from a terminal. `y` runs the command.
- Without a terminal (cron, CI, `nohup`), jevsh cannot ask, so it does not run the command and exits with status 4. This is on purpose: nothing runs unconfirmed.
- For automation, use `--check` with `--fail-on` and let the script decide:

```bash
#!/usr/bin/env bash
line='find /var/log/app -name "*.log" -mtime +30 -delete'
if jevsh --check --fail-on HIGH -c "$line"; then
    bash -c "$line"
else
    echo "skipped: risk is HIGH or above" >&2
fi
```

### Exit status

| Mode | Status |
|---|---|
| `COMMAND` / `-c` | the command's own status if it ran; 2 usage error; 3 no API key; 4 canceled or no terminal to ask on |
| `--check` | 0 assessed; 1 risk at or above `--fail-on`; 2 usage error; 3 could not assess |
| other options | 0 success; 1 failure; 2 usage error |

If the API cannot be reached, jevsh says so and asks `Run without AI assessment? [y/N]`. The default is to cancel.

## What is sent

When you assess a command, jevsh sends to TypeSafe (`https://api.typesafe.ai`):

- the command line, exactly as typed, including any passwords or tokens in it
- the current directory
- your user name and shell name

Nothing else from your environment is collected. Nothing is sent when you press Enter alone. Your API key is sent only in the request header and is never shown or logged. See TypeSafe's terms for how they handle data.

## Uninstall

```bash
jevsh --disable-keybinding
rm ~/.local/bin/jevsh
rm -r ~/.config/jevsh
```

## Speed and accuracy

jevsh adds about 0.2 seconds per command, almost all of it the JEV API round trip. For 40 sample command lines, JEV's risk level matched the author's expectation for 29–31 of 40 in each of three runs. See [docs/benchmark.md](docs/benchmark.md) for the full results and raw data.

## License

MIT License. You are free to use, modify, and redistribute jevsh, including for commercial use, as long as you keep the copyright and license notice. Provided "as is", without warranty. See [LICENSE](LICENSE).

## Author

Takeshi Uematsu <takeshi.uematsu@gmail.com>
