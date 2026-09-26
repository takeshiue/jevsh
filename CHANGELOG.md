# Changelog

0.3.1 is the first public release. Versions before it were development steps and were not released on their own; only released versions get a tag.

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

- `jevsh COMMAND [ARGS...]` and `jevsh -c 'LINE'`: assess with JEV, show the risk, confidence and probabilities, and run only after an explicit `y`
- `--check` and `--fail-on LEVEL` for scripts and loops
- Key binding: assess the current line with Ctrl+X Enter or Ctrl+Enter; `--init bash`, `--enable-keybinding`, `--disable-keybinding`
- First-run API key registration with a notice of what is sent, and a key check before saving; `--set-key`
- `--help`, `--version`
