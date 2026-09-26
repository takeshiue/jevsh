# Changelog

0.3.1 is the first public release. Versions before it were development steps and were not released on their own; only released versions get a tag.

## 0.3.7 - 2026-09-26

- README: remove the line before the first example.

## 0.3.6 - 2026-09-26

- README: show the first example in a root shell again, without `sudo -i`.

## 0.3.5 - 2026-09-26

- README: show the first example after `sudo -i`, so it is clear the line runs as root.

## 0.3.4 - 2026-09-26

- Write the tool name jev in lowercase everywhere, including messages such as `jev risk:`.
- README: lead with what jevsh is for: risks that come from how commands are combined (pipes, redirections), with real examples. Install with `install.sh`. Usage lists what each option does.

## 0.3.3 - not released

- `install.sh`: install with `curl -fsSLO .../install.sh && bash install.sh`. It checks the checksum and, when `ssh-keygen` is available, the signature, then copies jevsh to `~/.local/bin`. It does not change `~/.bashrc`.
- README: the key binding (Ctrl+Enter) is now introduced first.

## 0.3.2 - 2026-09-26

- README: install with one line (download, checksum check and install). Signature verification is now an optional step.

## 0.3.1 - 2026-09-26

First public release. Includes everything below.

- Code cleanup for ShellCheck. No change in behavior.

## 0.3.0 - not released

- `--yes`: assess and show the result, then run without asking. Nothing runs if the command could not be assessed. Works without a terminal (the result goes to stderr).
- `--no-jev`: run without assessment and without asking.

## 0.2.0 - not released

- `JEVSH_AUTO_RUN=LEVEL`: run without asking when the risk is at or below LEVEL. The assessment is still shown, and jevsh always asks when it could not assess the command.
- Help: explain how jevsh behaves in shell scripts.

## 0.1.0 - not released

- `jevsh COMMAND [ARGS...]` and `jevsh -c 'LINE'`: assess with jev, show the risk, confidence and probabilities, and run only after an explicit `y`
- `--check` and `--fail-on LEVEL` for scripts and loops
- Key binding: assess the current line with Ctrl+X Enter or Ctrl+Enter; `--init bash`, `--enable-keybinding`, `--disable-keybinding`
- First-run API key registration with a notice of what is sent, and a key check before saving; `--set-key`
- `--help`, `--version`
