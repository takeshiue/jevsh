#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Takeshi Uematsu <takeshi.uematsu@gmail.com>
#
# Install jevsh into ~/.local/bin.
#
#   curl -fsSLO https://raw.githubusercontent.com/takeshiue/jevsh/main/install.sh && bash install.sh && source ~/.bashrc
#
# It downloads one release of jevsh, checks it against SHA256SUMS, checks the
# signature when ssh-keygen is available, and copies the file into place.
# On a terminal it then offers the first-time setup (API key and the
# Ctrl+Enter key binding); ~/.bashrc changes only if you agree there.
# The final "source ~/.bashrc" runs in your own shell, so Ctrl+Enter works
# right away.
#
# Usage: bash install.sh [vX.Y.Z]
#   JEVSH_INSTALL_DIR   where to install (default: ~/.local/bin)

set -euo pipefail

JEVSH_RELEASE="v0.4.1"
RELEASE_KEY_FINGERPRINT="SHA256:LIdW6JBHIV1YvPQHU+suSOe87ZJgNZGZlfjNdl1kkKg"
SIGNER="takeshi.uematsu@gmail.com"

# Test hooks: the automated tests point these at a local fake release.
key_fingerprint=${JEVSH_INSTALL_KEY_FINGERPRINT:-$RELEASE_KEY_FINGERPRINT}
release=${1:-$JEVSH_RELEASE}
base=${JEVSH_INSTALL_BASE:-https://raw.githubusercontent.com/takeshiue/jevsh/$release}
install_dir=${JEVSH_INSTALL_DIR:-$HOME/.local/bin}

fail() {
    printf 'install.sh: %s\n' "$*" >&2
    exit 1
}

[[ $release =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must look like v1.2.3, not '$release'."
for tool in curl sha256sum install; do
    command -v "$tool" > /dev/null 2>&1 || fail "$tool is required."
done

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cd "$work"

printf 'Downloading jevsh %s ...\n' "$release"
curl -fsSL --remote-name-all "$base/jevsh" "$base/SHA256SUMS" ||
    fail "download failed from $base"

sha256sum -c --ignore-missing --quiet SHA256SUMS ||
    fail "checksum mismatch. Nothing was installed."
grep -qE '  jevsh$' SHA256SUMS || fail "SHA256SUMS does not list jevsh. Nothing was installed."
printf 'Checksum OK.\n'

if command -v ssh-keygen > /dev/null 2>&1; then
    curl -fsSL --remote-name-all "$base/SHA256SUMS.sig" "$base/jevsh-release.pub" ||
        fail "could not download the signature."
    fingerprint=$(ssh-keygen -lf jevsh-release.pub | awk '{print $2}')
    [[ $fingerprint == "$key_fingerprint" ]] ||
        fail "unexpected signing key $fingerprint. Nothing was installed."
    printf '%s %s\n' "$SIGNER" "$(cat jevsh-release.pub)" > allowed_signers
    ssh-keygen -Y verify -f allowed_signers -I "$SIGNER" -n file \
        -s SHA256SUMS.sig < SHA256SUMS > /dev/null 2>&1 ||
        fail "bad signature. Nothing was installed."
    printf 'Signature OK (%s).\n' "$fingerprint"
else
    printf 'ssh-keygen not found; skipped the signature check.\n'
fi

mkdir -p -- "$install_dir"
install -m 755 jevsh "$install_dir/jevsh"
printf 'Installed %s\n' "$("$install_dir/jevsh" --version) to $install_dir/jevsh"

case ":$PATH:" in
    *":$install_dir:"*) ;;
    *)
        printf '\n%s is not in your PATH yet. Log in again, or run:\n' "$install_dir"
        # shellcheck disable=SC2016
        printf '  echo '\''export PATH="%s:$PATH"'\'' >> ~/.bashrc && source ~/.bashrc\n' "$install_dir"
        ;;
esac

jevsh=$install_dir/jevsh
config=${XDG_CONFIG_HOME:-$HOME/.config}/jevsh/config
[[ ${XDG_CONFIG_HOME:-} == /* ]] || config=$HOME/.config/jevsh/config

if ! { : < /dev/tty; } 2> /dev/null; then
    printf '\nNext: run "jevsh --set-key" to register your jev API key and set up Ctrl+Enter.\n'
    exit 0
fi

printf '\n'
if [[ -z ${JEV_API_KEY:-} && ! -e $config ]]; then
    printf 'Set up jevsh now (jev API key and Ctrl+Enter)? [Y/n]: '
    read -r answer < /dev/tty || answer=n
    if [[ -z $answer || $answer == [yY] ]]; then
        "$jevsh" --set-key < /dev/tty || true
    else
        printf 'Skipped. Run "jevsh --set-key" later.\n'
    fi
elif ! grep -qxF '# >>> jevsh >>>' "$HOME/.bashrc" 2> /dev/null; then
    "$jevsh" --enable-keybinding < /dev/tty || true
fi

if grep -qxF '# >>> jevsh >>>' "$HOME/.bashrc" 2> /dev/null; then
    printf '\nCtrl+Enter (or Ctrl+X Enter) is ready in new terminals. If you used the\n'
    printf 'one-line command from the README, it also works in this terminal now.\n'
fi
