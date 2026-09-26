#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# Automated tests for jevsh with a mock curl. No network access is used.
# Requires: bash, script and setsid (util-linux), coreutils.
# Usage: tests/run-tests.sh [TEST_ID...]

# Assertions are written in single quotes on purpose and expanded by eval in
# check(); VERSION_RE is used only inside such strings.
# shellcheck disable=SC2016,SC2034,SC1091

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)
JEVSH=$ROOT/jevsh
PASS_COUNT=0
FAIL_COUNT=0
FAILED_IDS=()
KEY=testkey-ABC.123_xyz
VERSION=$(sed -n 's/^JEVSH_VERSION="\(.*\)"$/\1/p' "$JEVSH")
VERSION_RE=${VERSION//./\\.}

for tool in script setsid; do
    if ! command -v "$tool" > /dev/null 2>&1; then
        printf 'BLOCKED: %s (util-linux) is required\n' "$tool" >&2
        exit 2
    fi
done

# ---------------------------------------------------------------------------
# Fixture helpers

new_env() {
    T=$(mktemp -d)
    export HOME=$T/home
    export MOCK_DIR=$T/mock
    mkdir -p "$HOME" "$MOCK_DIR" "$T/work"
    export PATH="$ROOT/tests/mock:$ROOT:/usr/local/bin:/usr/bin:/bin"
    unset JEV_API_KEY XDG_CONFIG_HOME JEVSH_KEY JEV_API_URL JEVSH_AUTO_RUN
    export JEV_API_KEY=$KEY
    respond HIGH 0.6 0.01 0.29 0.7 0.0
    cd "$T/work" || exit 1
}

cleanup_env() {
    cd / || true
    rm -rf -- "$T"
}

# respond RISK CONFIDENCE P_LOW P_MEDIUM P_HIGH P_CRITICAL
respond() {
    printf '{"model":"jev-1.13.0","answers":{"risk":{"type":"choice","choice":"%s","confidence":%s,"probabilities":{"CRITICAL":%s,"LOW":%s,"MEDIUM":%s,"HIGH":%s}}},"usage":{"input_tokens":1,"output_tokens":2}}' \
        "$1" "$2" "$6" "$3" "$4" "$5" > "$MOCK_DIR/response"
    printf '200' > "$MOCK_DIR/http_code"
    rm -f "$MOCK_DIR/curl_exit"
}

respond_raw() {
    printf '%s' "$1" > "$MOCK_DIR/response"
    printf '%s' "${2:-200}" > "$MOCK_DIR/http_code"
    rm -f "$MOCK_DIR/curl_exit"
}

curl_fails() {
    printf '%s' "${1:-7}" > "$MOCK_DIR/curl_exit"
}

call_count() {
    [[ -f $MOCK_DIR/calls ]] && wc -l < "$MOCK_DIR/calls" || echo 0
}

sent_line() {
    # Extract command_line from the recorded request (test-only helper; relies on
    # jevsh's fixed field order).
    sed -E 's/.*"command_line":"(([^"\\]|\\.)*)".*/\1/' "$MOCK_DIR/request"
}

# Run jevsh without a controlling terminal.
run_no_tty() {
    setsid -w "$@" < /dev/null
}

# Wait until PATTERN has appeared COUNT times in FILE (at most 15 seconds).
# The screen file is read while script(1) writes to it; that is the point.
# shellcheck disable=SC2094
wait_for() {
    local file=$1 pattern=$2 count=$3 attempt
    for ((attempt = 0; attempt < 150; attempt++)); do
        if (($(grep -oF -- "$pattern" "$file" 2> /dev/null | wc -l) >= count)); then
            sleep 0.1
            return 0
        fi
        sleep 0.1
    done
    return 1
}

# Run a command inside a pseudo terminal and type answers into it.
# Each answer is either "PATTERN=>TEXT" (send TEXT after PATTERN appears once
# more on the screen) or plain TEXT (send after a short delay). TEXT uses
# printf %b escapes.
# Usage: run_pty "COMMAND STRING" ANSWER...
# shellcheck disable=SC2094
run_pty() {
    local command=$1 screen=$T/pty.screen
    shift
    : > "$screen"
    {
        local item pattern text
        declare -A seen=()
        sleep 0.3
        for item in "$@"; do
            if [[ $item == *'=>'* ]]; then
                pattern=${item%%=>*}
                text=${item#*=>}
                seen[$pattern]=$((${seen[$pattern]:-0} + 1))
                wait_for "$screen" "$pattern" "${seen[$pattern]}"
            else
                sleep 0.6
                text=$item
            fi
            printf '%b' "$text"
        done
        sleep 1
    } | script -qec "$command; echo \"__EXIT=\$?\"" /dev/null > "$screen" 2>&1
    tr -d '\r' < "$screen"
}

pty_exit() {
    sed -n 's/.*__EXIT=\([0-9]*\).*/\1/p' <<< "$1" | tail -n 1
}

# ---------------------------------------------------------------------------
# Assertions

CURRENT_ID=
CURRENT_OK=1
CURRENT_NOTES=()

begin() {
    CURRENT_ID=$1
    CURRENT_OK=1
    CURRENT_NOTES=()
    new_env
}

check() {
    local description=$1
    shift
    if ! "$@"; then
        CURRENT_OK=0
        CURRENT_NOTES+=("$description")
    fi
}

end() {
    cleanup_env
    if ((CURRENT_OK)); then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf 'PASS %s\n' "$CURRENT_ID"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_IDS+=("$CURRENT_ID")
        printf 'FAIL %s\n' "$CURRENT_ID"
        printf '     - %s\n' "${CURRENT_NOTES[@]}"
    fi
}

contains() { [[ $1 == *"$2"* ]]; }
not_contains() { [[ $1 != *"$2"* ]]; }
equals() { [[ $1 == "$2" ]]; }

selected() {
    ((${#SELECTED[@]} == 0)) && return 0
    local id
    for id in "${SELECTED[@]}"; do
        [[ $id == "$1" ]] && return 0
    done
    return 1
}

# ---------------------------------------------------------------------------
# Tests

t001() {
    begin T-001
    check "bash -n jevsh" bash -n "$JEVSH"
    check "bash -n tests" bash -n "$ROOT/tests/run-tests.sh"
    check "bash -n mock" bash -n "$ROOT/tests/mock/curl"
    end
}

t002() {
    begin T-002
    local out
    out=$("$JEVSH" --version)
    check "exit 0" equals "$?" 0
    check "format: $out" eval '[[ $out =~ ^jevsh\ $VERSION_RE\ \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$ ]]'
    end
}

t003() {
    begin T-003
    unset JEV_API_KEY
    local out status item
    out=$("$JEVSH" --help)
    status=$?
    check "exit 0" equals "$status" 0
    check "first line" eval '[[ ${out%%$'"'"'\n'"'"'*} =~ ^jevsh\ $VERSION_RE\ \(last\ updated\ [0-9-]{10}\)$ ]]'
    for item in "-c 'cat data.csv | sort > out.txt'" "single quotes" "JEVSH_KEY" "JEVSH_AUTO_RUN" "Shell scripts" "--yes" "--no-jev" "What is sent" \
        "Exit status" "MIT License" "modify" "Takeshi Uematsu <takeshi.uematsu@gmail.com>" "Ctrl+X Enter"; do
        check "help contains: $item" contains "$out" "$item"
    done
    check "no API call" equals "$(call_count)" 0
    end
}

t004() {
    begin T-004
    local args status err
    local -a cases=(
        "--bogus ls"
        "-c ls ls"
        "-c"
        "--check --fail-on SEVERE ls"
        "--fail-on HIGH ls"
        ""
        "--init zsh"
        "--set-key ls"
    )
    for args in "${cases[@]}"; do
        # shellcheck disable=SC2086
        err=$(run_no_tty "$JEVSH" $args 2>&1 > /dev/null)
        status=$?
        check "[$args] exit 2 (got $status)" equals "$status" 2
        check "[$args] message" contains "$err" "jevsh:"
    done
    check "no API call" equals "$(call_count)" 0
    end
}

t010() {
    begin T-010
    local out status
    out=$(run_no_tty "$JEVSH" --check rm -rf ./build)
    status=$?
    check "exit 0 (got $status)" equals "$status" 0
    check "output: $out" equals "$out" "HIGH 0.60 rm -rf ./build"
    end
}

t011() {
    begin T-011
    local status
    respond HIGH 0.7 0 0.1 0.7 0.2
    run_no_tty "$JEVSH" --check --fail-on HIGH ls > /dev/null
    status=$?
    check "HIGH -> 1 (got $status)" equals "$status" 1
    respond MEDIUM 0.7 0.1 0.7 0.2 0
    run_no_tty "$JEVSH" --check --fail-on HIGH ls > /dev/null
    status=$?
    check "MEDIUM -> 0 (got $status)" equals "$status" 0
    respond CRITICAL 0.9 0 0 0.1 0.9
    run_no_tty "$JEVSH" --check --fail-on=HIGH ls > /dev/null
    status=$?
    check "CRITICAL -> 1 (got $status)" equals "$status" 1
    end
}

t012() {
    begin T-012
    local out status
    out=$(run_no_tty "$JEVSH" --check ls 2>&1)
    status=$?
    check "exit 0" equals "$status" 0
    check "no question" not_contains "$out" "[y/N]"
    end
}

t013() {
    begin T-013
    local out status name
    local long
    long=$(printf '%*s' 9000 '' | tr ' ' 'x')
    declare -A bodies=(
        [malformed]='{"error":"x"}'
        [duplicate]='{"model":"jev-1","answers":{"risk":{"type":"choice","choice":"LOW","confidence":1.0,"probabilities":{"LOW":1.0,"LOW":0.0,"HIGH":0.0,"CRITICAL":0.0}}},"usage":{"input_tokens":1,"output_tokens":2}}'
        [backslash]='{"model":"jev-1","answers":{"risk":{"type":"choice","choice":"LOW","confidence":1.0,"probabilities":{"LOW":1.0,"MEDIUM":0.0,"HIGH":0.0,"CRITICAL":0.0}}},"usage":{"input_tokens":1,"output_tokens":2},"x":"\u001b"}'
        [oversize]="$long"
    )
    for name in "${!bodies[@]}"; do
        respond_raw "${bodies[$name]}"
        out=$(run_no_tty "$JEVSH" --check ls 2>&1)
        status=$?
        check "$name exit 3 (got $status)" equals "$status" 3
        check "$name reason" contains "$out" "jev assessment unavailable"
        check "$name no raw body" not_contains "$out" '"model"'
    done
    respond_raw '{"detail":"secret-detail"}' 401
    out=$(run_no_tty "$JEVSH" --check ls 2>&1)
    check "401 exit 3" equals "$?" 3
    check "401 reason" contains "$out" "rejected (HTTP 401)"
    check "401 no body" not_contains "$out" "secret-detail"
    respond_raw 'oops' 500
    out=$(run_no_tty "$JEVSH" --check ls 2>&1)
    check "500 exit 3" equals "$?" 3
    check "500 reason" contains "$out" "HTTP 500"
    curl_fails 7
    out=$(run_no_tty "$JEVSH" --check ls 2>&1)
    check "network exit 3" equals "$?" 3
    check "network reason" contains "$out" "cannot reach"
    end
}

t014() {
    begin T-014
    run_no_tty "$JEVSH" --check -c 'cat a | sort > b' > /dev/null
    check "line sent: $(sent_line)" equals "$(sent_line)" 'cat a | sort > b'
    end
}

t020() {
    begin T-020
    local request
    run_no_tty "$JEVSH" --check ls -la > /dev/null
    request=$(cat "$MOCK_DIR/request")
    check "command_line" contains "$request" '"command_line":"ls -la"'
    check "working_directory" contains "$request" "\"working_directory\":\"$T/work\""
    check "user" contains "$request" "\"user\":\"$(id -un)\""
    check "shell" contains "$request" '"shell":"bash"'
    check "model" contains "$request" '"model":"jev-latest"'
    check "criteria" contains "$request" '"CRITICAL":"Severe system-wide or irreversible impact"'
    check "no HOME leak beyond cwd" not_contains "${request//$T\/work/}" "$HOME"
    end
}

t021() {
    begin T-021
    # shellcheck disable=SC2016
    run_no_tty "$JEVSH" --check touch 'a b' '$HOME' '*' > /dev/null
    # JSON escapes each backslash, so a\ b is sent as a\\ b.
    check "boundaries: $(sent_line)" equals "$(sent_line)" 'touch a\\ b \\$HOME \\*'
    end
}

t022() {
    begin T-022
    local out
    out=$(run_no_tty "$JEVSH" --check ls 2>&1)
    check "key not in curl args" not_contains "$(cat "$MOCK_DIR/args")" "$KEY"
    check "key not in output" not_contains "$out" "$KEY"
    check "key sent via config" contains "$(cat "$MOCK_DIR/config_used")" "Authorization: Bearer $KEY"
    check "config via fd" eval 'grep -Eq "^/(dev/fd|proc/self/fd)/" "$MOCK_DIR/args"'
    end
}

t023() {
    begin T-023
    JEV_API_URL=http://example.invalid run_no_tty "$JEVSH" --check ls > /dev/null
    check "fixed URL" eval 'grep -qxF "https://api.typesafe.ai/v1/systemone" "$MOCK_DIR/args"'
    check "no override" not_contains "$(cat "$MOCK_DIR/args")" "example.invalid"
    end
}

t024() {
    begin T-024
    run_no_tty "$JEVSH" --check -c 'mysql -u root password=abc123' > /dev/null
    check "sent as typed" equals "$(sent_line)" 'mysql -u root password=abc123'
    end
}

t030() {
    begin T-030
    local out
    out=$(run_pty "'$JEVSH' touch '$T/x'" '[y/N]: =>n\n')
    check "not created" eval '[[ ! -e $T/x ]]'
    check "Canceled shown" contains "$out" "Canceled."
    check "exit 4 (got $(pty_exit "$out"))" equals "$(pty_exit "$out")" 4
    end
}

t031() {
    begin T-031
    local out
    out=$(run_pty "'$JEVSH' touch '$T/a b'" '[y/N]: =>y\n')
    check "one file 'a b'" eval '[[ -e "$T/a b" && ! -e $T/a ]]'
    check "exit 0 (got $(pty_exit "$out"))" equals "$(pty_exit "$out")" 0
    end
}

t032() {
    begin T-032
    run_pty "'$JEVSH' touch '$T/empty'" '[y/N]: =>\n' > /dev/null
    check "empty answer cancels" eval '[[ ! -e $T/empty ]]'
    run_pty "'$JEVSH' touch '$T/yes'" '[y/N]: =>yes\n' > /dev/null
    check "yes cancels" eval '[[ ! -e $T/yes ]]'
    run_pty "'$JEVSH' touch '$T/upper'" '[y/N]: =>Y\n' > /dev/null
    check "Y runs" eval '[[ -e $T/upper ]]'
    end
}

t033() {
    begin T-033
    local out
    out=$(run_pty "'$JEVSH' false" '[y/N]: =>y\n')
    check "exit 1 (got $(pty_exit "$out"))" equals "$(pty_exit "$out")" 1
    end
}

t034() {
    begin T-034
    local out
    out=$(run_pty "'$JEVSH' -c 'printf x | tr x y > \"$T/p\"'" '[y/N]: =>y\n')
    check "file content y" equals "$(cat "$T/p" 2> /dev/null)" y
    check "line sent" equals "$(sent_line)" "printf x | tr x y > \\\"$T/p\\\""
    end
}

t035() {
    begin T-035
    local out
    out=$(run_pty "'$JEVSH' rm -rf ./build" '[y/N]: =>n\n')
    check "Command line" contains "$out" "Command: rm -rf ./build"
    check "risk line" contains "$out" "jev risk: HIGH (confidence 60%)"
    check "percentages" contains "$out" "LOW 1%  MEDIUM 29%  HIGH 70%  CRITICAL 0%"
    check "y explained" contains "$out" "y      run it now"
    check "n explained" contains "$out" "n      cancel (Enter also cancels)"
    check "answer echoed" contains "$out" "[y/N]: n"
    end
}

t036() {
    begin T-036
    local out
    export ESCARG=$'\e[31mred'
    # Simple form: printf %q already turns ESC into $'\E...'.
    out=$(run_pty "'$JEVSH' printf \"\$ESCARG\"" '[y/N]: =>n\n')
    check "simple form quoted" contains "$out" "Command: printf \$'\\E[31mred'"
    # -c form: the raw line is shown with ESC escaped as \x1b.
    out=$(run_pty "'$JEVSH' -c \"echo \$ESCARG\"" '[y/N]: =>n\n')
    check "-c form escaped" contains "$out" 'Command: echo \x1b[31mred'
    check "no raw ESC on Command lines" eval '! grep -q $'"'"'^Command: .*\x1b'"'"' <<< "$out"'
    end
}

t037() {
    begin T-037
    local status
    run_no_tty "$JEVSH" touch "$T/z" 2> /dev/null
    status=$?
    check "not created" eval '[[ ! -e $T/z ]]'
    check "exit 4 (got $status)" equals "$status" 4
    end
}

t038() {
    begin T-038
    local out
    curl_fails 7
    out=$(run_pty "'$JEVSH' touch '$T/f1'" '[y/N]: =>n\n')
    check "question shown" contains "$out" "Run without AI assessment?"
    check "n does not run" eval '[[ ! -e $T/f1 ]]'
    run_pty "'$JEVSH' touch '$T/f2'" '[y/N]: =>y\n' > /dev/null
    check "y runs" eval '[[ -e $T/f2 ]]'
    end
}

t039() {
    begin T-039
    local out
    out=$(run_pty "'$JEVSH' touch '$T/int'; stty -a | grep -o ' echo ' | head -1" '[y/N]: =>\003')
    check "not created" eval '[[ ! -e $T/int ]]'
    check "Canceled shown" contains "$out" "Canceled."
    check "echo restored" contains "$out" " echo "
    end
}

t040() {
    begin T-040
    unset JEV_API_KEY
    local out
    out=$(run_pty "'$JEVSH' touch '$T/k1'" '[y/N]: =>n\n')
    check "notice" contains "$out" "What is sent: each command line you assess"
    check "question" contains "$out" "Register an API key now? [y/N]"
    check "not created" eval '[[ ! -e $T/k1 ]]'
    check "nothing saved" eval '[[ ! -e $HOME/.config/jevsh/config ]]'
    check "exit 3 (got $(pty_exit "$out"))" equals "$(pty_exit "$out")" 3
    check "no API call" equals "$(call_count)" 0
    end
}

t041() {
    begin T-041
    unset JEV_API_KEY
    local out config=$HOME/.config/jevsh/config
    local newkey=NEWkey-0123456789
    out=$(run_pty "'$JEVSH' --check ls" '[y/N]: =>y\n' "(input is hidden): =>$newkey\\n" '[Y/n]: =>n\n')
    check "OK shown" contains "$out" "Checking the key... OK"
    check "saved line" equals "$(cat "$config" 2> /dev/null)" "api_key=$newkey"
    check "mode 0600" equals "$(stat -c %a "$config" 2> /dev/null)" 600
    check "key hidden" not_contains "$out" "$newkey"
    check "check line sent" contains "$(cat "$MOCK_DIR/request")" '"command_line":"ls"'
    check "true sent first" equals "$(call_count)" 2
    end
}

t042() {
    begin T-042
    unset JEV_API_KEY
    local out
    respond_raw '{"detail":"no"}' 401
    out=$(run_pty "'$JEVSH' --set-key" '(input is hidden): =>bad-key-1\n' '[y/N]: =>n\n')
    check "failure shown" contains "$out" "failed: the API key was rejected (HTTP 401)"
    check "retry offered" contains "$out" "Try again? [y/N]"
    check "not saved" eval '[[ ! -e $HOME/.config/jevsh/config ]]'
    end
}

t043() {
    begin T-043
    unset JEV_API_KEY
    local config=$HOME/.config/jevsh/config
    mkdir -p "${config%/*}"
    printf 'api_key=OLDkey\n' > "$config"
    chmod 600 "$config"
    respond_raw '{"detail":"no"}' 401
    run_pty "'$JEVSH' --set-key" '(input is hidden): =>another-key\n' '[y/N]: =>n\n' > /dev/null
    check "old config kept" equals "$(cat "$config")" "api_key=OLDkey"
    check "no temp files" equals "$(find "${config%/*}" -name '.config.*' | wc -l)" 0
    end
}

t044() {
    begin T-044
    local config=$HOME/.config/jevsh/config
    mkdir -p "${config%/*}"
    printf 'api_key=FILEkey\n' > "$config"
    chmod 600 "$config"
    run_no_tty "$JEVSH" --check ls > /dev/null
    check "env key used" contains "$(cat "$MOCK_DIR/config_used")" "Bearer $KEY"
    end
}

t045() {
    begin T-045
    unset JEV_API_KEY
    local config=$HOME/.config/jevsh/config out status
    mkdir -p "${config%/*}"
    printf 'api_key=FILEkey-secret\n' > "$config"
    chmod 644 "$config"
    out=$(run_no_tty "$JEVSH" --check ls 2>&1)
    status=$?
    check "0644 -> exit 3" equals "$status" 3
    check "0644 reason" contains "$out" "mode 0600"
    check "0644 key hidden" not_contains "$out" "FILEkey-secret"
    chmod 600 "$config"
    printf 'api_key=a\napi_key=b\n' > "$config"
    out=$(run_no_tty "$JEVSH" --check ls 2>&1)
    check "two lines -> exit 3" equals "$?" 3
    printf 'api_key=bad key!\n' > "$config"
    out=$(run_no_tty "$JEVSH" --check ls 2>&1)
    check "bad format -> exit 3" equals "$?" 3
    check "bad format hidden" not_contains "$out" "bad key!"
    rm -f "$config"
    printf 'api_key=LINKED\n' > "$T/real"
    chmod 600 "$T/real"
    ln -s "$T/real" "$config"
    out=$(run_no_tty "$JEVSH" --check ls 2>&1)
    check "symlink -> exit 3" equals "$?" 3
    check "symlink reason" contains "$out" "symbolic link"
    check "no API call" equals "$(call_count)" 0
    end
}

t046() {
    begin T-046
    unset JEV_API_KEY
    local out status
    out=$(run_no_tty "$JEVSH" --check ls 2>&1)
    status=$?
    check "exit 3 (got $status)" equals "$status" 3
    check "message" contains "$out" "no API key. Run 'jevsh --set-key' first."
    end
}

t050() {
    begin T-050
    local out
    out=$("$JEVSH" --init bash)
    check "ctrl+enter" contains "$out" "bind -x '\"\\e[13;5u\":__jevsh_assess_line'"
    check "ctrl+x enter" contains "$out" "bind -x '\"\\C-x\\C-m\":__jevsh_assess_line'"
    check "absolute path" contains "$out" "__jevsh_self=$JEVSH"
    check "valid bash" bash -n <(printf '%s\n' "$out")
    end
}

t051() {
    begin T-051
    local out err
    out=$(JEVSH_KEY='\C-x\C-a' "$JEVSH" --init bash)
    check "custom key" contains "$out" "bind -x '\"\\C-x\\C-a\":__jevsh_assess_line'"
    check "only custom" equals "$(grep -c '^bind -x' <<< "$out")" 1
    err=$(JEVSH_KEY='\C-x"' "$JEVSH" --init bash 2>&1 > "$T/init.out")
    check "warning" contains "$err" "JEVSH_KEY must not contain quotes"
    check "defaults used" equals "$(grep -c '^bind -x' "$T/init.out")" 2
    end
}

write_rc() {
    cat > "$T/rc" << EOF
PS1='PROMPT\$ '
HISTFILE=$T/history
export PATH='$PATH' MOCK_DIR='$MOCK_DIR' JEV_API_KEY='$KEY' HOME='$HOME'
eval "\$('$JEVSH' --init bash)"
EOF
}

t052() {
    begin T-052
    write_rc
    local out
    out=$(run_pty "bash --noprofile --rcfile '$T/rc' -i" "PROMPT\$ =>touch '$T/b1'" '\030\r' '[y/N]: =>n\n' '\003' 'exit\n')
    check "assessment shown" contains "$out" "jev risk: HIGH"
    check "not run" eval '[[ ! -e $T/b1 ]]'
    check "line stays" contains "$out" "The line stays at the prompt for editing."
    check "line retained on prompt" eval "grep -q \"PROMPT\\\$ touch '\$T/b1'\\^C\" <<< \"\$out\""
    end
}

t053() {
    begin T-053
    write_rc
    local out
    mkdir -p "$T/dest"
    out=$(run_pty "bash --noprofile --rcfile '$T/rc' -i" "PROMPT\$ =>cd '$T/dest' && touch k" '\030\r' '[y/N]: =>y\n' 'pwd; history 3\n' 'exit\n')
    check "file created" eval '[[ -e $T/dest/k ]]'
    check "cwd changed in shell" contains "$out" "$T/dest"$'\n'
    check "history has line" contains "$out" "cd '$T/dest' && touch k"
    end
}

t054() {
    begin T-054
    write_rc
    local out
    out=$(run_pty "bash --noprofile --rcfile '$T/rc' -i" "PROMPT\$ =>touch '$T/b2'" '\033[13;5u' '[y/N]: =>n\n' '\003' 'exit\n')
    check "assessment shown" contains "$out" "jev risk: HIGH"
    check "not run" eval '[[ ! -e $T/b2 ]]'
    end
}

t055() {
    begin T-055
    write_rc
    run_pty "bash --noprofile --rcfile '$T/rc' -i" "PROMPT\$ =>touch '$T/plain'\\n" 'exit\n' > /dev/null
    check "runs" eval '[[ -e $T/plain ]]'
    check "no API call" equals "$(call_count)" 0
    end
}

t056() {
    begin T-056
    write_rc
    run_pty "bash --noprofile --rcfile '$T/rc' -i" "PROMPT\$ =>cat /etc/hostname | sort > '$T/out'" '\030\r' '[y/N]: =>n\n' '\003' 'exit\n' > /dev/null
    check "line sent: $(sent_line)" equals "$(sent_line)" "cat /etc/hostname | sort > '$T/out'"
    check "not run" eval '[[ ! -e $T/out ]]'
    end
}

t057() {
    begin T-057
    local out
    respond LOW 0.95 0.95 0.05 0 0
    export JEVSH_AUTO_RUN=LOW
    out=$(run_pty "'$JEVSH' touch '$T/a1'")
    check "ran without asking" eval '[[ -e $T/a1 ]]'
    check "message" contains "$out" "Running without asking (risk LOW is at or below JEVSH_AUTO_RUN=LOW)."
    check "no question" not_contains "$out" "[y/N]"
    check "assessment shown" contains "$out" "jev risk: LOW (confidence 95%)"
    write_rc
    printf 'export JEVSH_AUTO_RUN=LOW\n' >> "$T/rc"
    run_pty "bash --noprofile --rcfile '$T/rc' -i" "PROMPT\$ =>touch '$T/a2'" '\030\r' 'exit\n' > /dev/null
    check "binding ran without asking" eval '[[ -e $T/a2 ]]'
    unset JEVSH_AUTO_RUN
    end
}

t058() {
    begin T-058
    local out
    export JEVSH_AUTO_RUN=LOW
    out=$(run_pty "'$JEVSH' touch '$T/h1'" '[y/N]: =>n\n')
    check "asked" contains "$out" "Run this command?"
    check "not run" eval '[[ ! -e $T/h1 ]]'
    unset JEVSH_AUTO_RUN
    end
}

t059() {
    begin T-059
    local out status
    export JEVSH_AUTO_RUN=CRITICAL
    curl_fails 7
    out=$(run_pty "'$JEVSH' touch '$T/u1'" '[y/N]: =>n\n')
    check "unavailable asks" contains "$out" "Run without AI assessment?"
    check "unavailable not run" eval '[[ ! -e $T/u1 ]]'
    respond LOW 0.95 0.95 0.05 0 0
    run_no_tty "$JEVSH" touch "$T/u2" 2> /dev/null
    status=$?
    check "no tty not run" eval '[[ ! -e $T/u2 ]]'
    check "no tty exit 4 (got $status)" equals "$status" 4
    export JEVSH_AUTO_RUN=bogus
    out=$(run_pty "'$JEVSH' touch '$T/u3'" '[y/N]: =>n\n')
    check "invalid warns" contains "$out" "JEVSH_AUTO_RUN must be LOW, MEDIUM, HIGH or CRITICAL; asking instead."
    check "invalid not run" eval '[[ ! -e $T/u3 ]]'
    unset JEVSH_AUTO_RUN
    end
}

make_bashrc() {
    printf '# user settings\nalias ll="ls -la"\nexport FOO=bar' > "$HOME/.bashrc"
    cp "$HOME/.bashrc" "$T/original"
}

t060() {
    begin T-060
    make_bashrc
    local out
    out=$(run_pty "'$JEVSH' --enable-keybinding" '[Y/n]: =>\r')
    check "one block" equals "$(grep -cxF '# >>> jevsh >>>' "$HOME/.bashrc")" 1
    check "prefix unchanged" eval 'head -c "$(stat -c %s "$T/original")" "$HOME/.bashrc" | cmp -s - "$T/original"'
    check "block at end" equals "$(tail -n 1 "$HOME/.bashrc")" "# <<< jevsh <<<"
    check "backup equals original" eval 'cmp -s "$(ls "$HOME"/.bashrc.jevsh-backup-* | head -1)" "$T/original"'
    check "notice shown" contains "$out" "Pressing Enter alone still runs the command normally"
    check "added message" contains "$out" "source ~/.bashrc"
    end
}

t061() {
    begin T-061
    make_bashrc
    printf '\n' >> "$HOME/.bashrc"
    cp "$HOME/.bashrc" "$T/original"
    run_pty "'$JEVSH' --enable-keybinding" '[Y/n]: =>\r' > /dev/null
    local out
    out=$(run_pty "'$JEVSH' --enable-keybinding")
    check "still one block" equals "$(grep -cxF '# >>> jevsh >>>' "$HOME/.bashrc")" 1
    check "already message" contains "$out" "already in"
    "$JEVSH" --disable-keybinding > /dev/null
    check "restored exactly" cmp -s "$HOME/.bashrc" "$T/original"
    out=$("$JEVSH" --disable-keybinding)
    check "none message" contains "$out" "No jevsh key binding found"
    check "still exact" cmp -s "$HOME/.bashrc" "$T/original"
    end
}

t062() {
    begin T-062
    unset JEV_API_KEY
    make_bashrc
    local out
    out=$(run_pty "'$JEVSH' --set-key" '(input is hidden): =>KEYnew-1\n' '[Y/n]: =>n\n')
    check "offer shown" contains "$out" "Add the key binding to ~/.bashrc? [Y/n]"
    check "unchanged on n" cmp -s "$HOME/.bashrc" "$T/original"
    rm -f "$HOME/.bashrc"
    printf 'x\n' > "$T/target"
    ln -s "$T/target" "$HOME/.bashrc"
    out=$(run_pty "'$JEVSH' --enable-keybinding" '[Y/n]: =>\r')
    check "symlink message" contains "$out" "symbolic link"
    check "prints block" contains "$out" "eval \"\$($JEVSH --init bash)\""
    check "target unchanged" equals "$(cat "$T/target")" x
    check "still symlink" eval '[[ -L $HOME/.bashrc ]]'
    end
}

t100() {
    begin T-100
    run_no_tty "$JEVSH" --no-jev touch "$T/n1"
    check "simple ran" eval '[[ -e $T/n1 ]]'
    run_no_tty "$JEVSH" --no-jev -c "printf ok > '$T/n2'"
    check "-c ran" equals "$(cat "$T/n2" 2> /dev/null)" ok
    run_no_tty "$JEVSH" --yes --no-jev touch "$T/n3"
    check "--yes --no-jev ran" eval '[[ -e $T/n3 ]]'
    unset JEV_API_KEY
    run_no_tty "$JEVSH" --no-jev touch "$T/n4"
    check "no key needed" eval '[[ -e $T/n4 ]]'
    check "no API call" equals "$(call_count)" 0
    end
}

t101() {
    begin T-101
    local out err status
    out=$(run_pty "'$JEVSH' --yes touch '$T/y1'")
    check "tty ran" eval '[[ -e $T/y1 ]]'
    check "tty no question" not_contains "$out" "[y/N]"
    check "tty shows risk" contains "$out" "jev risk: HIGH (confidence 60%)"
    check "tty message" contains "$out" "Running without asking (--yes)."
    err=$(run_no_tty "$JEVSH" --yes touch "$T/y2" 2>&1 > /dev/null)
    status=$?
    check "no tty ran" eval '[[ -e $T/y2 ]]'
    check "no tty exit 0 (got $status)" equals "$status" 0
    check "no tty result on stderr" contains "$err" "jev risk: HIGH (confidence 60%)"
    end
}

t102() {
    begin T-102
    local status err
    curl_fails 7
    err=$(run_no_tty "$JEVSH" --yes touch "$T/z1" 2>&1)
    status=$?
    check "unavailable not run" eval '[[ ! -e $T/z1 ]]'
    check "unavailable exit 3 (got $status)" equals "$status" 3
    check "unavailable message" contains "$err" "Nothing was run."
    unset JEV_API_KEY
    respond HIGH 0.6 0.01 0.29 0.7 0.0
    run_no_tty "$JEVSH" --yes touch "$T/z2" 2> /dev/null
    status=$?
    check "no key not run" eval '[[ ! -e $T/z2 ]]'
    check "no key exit 3 (got $status)" equals "$status" 3
    end
}

t103() {
    begin T-103
    local status
    run_no_tty "$JEVSH" --check --yes ls > /dev/null 2>&1
    status=$?
    check "--check --yes exit 2 (got $status)" equals "$status" 2
    run_no_tty "$JEVSH" --check --no-jev ls > /dev/null 2>&1
    status=$?
    check "--check --no-jev exit 2 (got $status)" equals "$status" 2
    check "no API call" equals "$(call_count)" 0
    end
}

# Build a fake release in $T/rel signed by a throwaway key, like scripts/release.sh does.
make_fake_release() {
    mkdir -p "$T/rel"
    cp "$JEVSH" "$ROOT/install.sh" "$T/rel/"
    (cd "$T/rel" && sha256sum jevsh install.sh > SHA256SUMS)
    ssh-keygen -q -t ed25519 -N '' -C test -f "$T/signkey"
    cp "$T/signkey.pub" "$T/rel/jevsh-release.pub"
    ssh-keygen -q -Y sign -f "$T/signkey" -n file "$T/rel/SHA256SUMS"
    FAKE_FP=$(ssh-keygen -lf "$T/signkey.pub" | awk '{print $2}')
}

run_installer() {
    # setsid: no terminal, so install.sh skips the interactive setup.
    PATH=/usr/local/bin:/usr/bin:/bin JEVSH_INSTALL_BASE="file://$T/rel" JEVSH_INSTALL_DIR="$T/bin" \
        JEVSH_INSTALL_KEY_FINGERPRINT="$FAKE_FP" setsid -w bash "$ROOT/install.sh" < /dev/null 2>&1
}

t104() {
    begin T-104
    write_rc
    local out
    # A real Enter key sends CR, and Readline turns off CR-to-NL translation
    # while a key binding runs. The answer must still be accepted.
    out=$(run_pty "bash --noprofile --rcfile '$T/rc' -i" "PROMPT\$ =>touch '$T/cr1'" '\030\r' '[y/N]: =>y\r' 'exit\r')
    check "binding: y + CR runs" eval '[[ -e $T/cr1 ]]'
    out=$(run_pty "bash --noprofile --rcfile '$T/rc' -i" "PROMPT\$ =>touch '$T/cr2'" '\030\r' '[y/N]: =>n\r' '\003' 'exit\r')
    check "binding: n + CR cancels" eval '[[ ! -e $T/cr2 ]]'
    check "binding: cancel message" contains "$out" "Canceled."
    out=$(run_pty "'$JEVSH' touch '$T/cr3'" '[y/N]: =>y\r')
    check "command form: y + CR runs" eval '[[ -e $T/cr3 ]]'
    end
}

t120() {
    begin T-120
    local out status
    make_fake_release
    out=$(run_installer)
    status=$?
    check "exit 0 (got $status): $out" equals "$status" 0
    check "installed" eval '[[ -x $T/bin/jevsh ]]'
    check "mode 755" equals "$(stat -c %a "$T/bin/jevsh" 2> /dev/null)" 755
    check "same file" cmp -s "$T/bin/jevsh" "$JEVSH"
    check "checksum message" contains "$out" "Checksum OK."
    check "signature message" contains "$out" "Signature OK ($FAKE_FP)."
    check "version shown" contains "$out" "Installed jevsh $VERSION"
    end
}

t121() {
    begin T-121
    local out status
    make_fake_release
    printf '#' >> "$T/rel/jevsh"
    out=$(run_installer)
    status=$?
    check "tampered: exit 1 (got $status)" equals "$status" 1
    check "tampered: message" contains "$out" "checksum mismatch. Nothing was installed."
    check "tampered: not installed" eval '[[ ! -e $T/bin/jevsh ]]'
    cp "$JEVSH" "$T/rel/jevsh"
    ssh-keygen -q -t ed25519 -N '' -C other -f "$T/otherkey"
    rm -f "$T/rel/SHA256SUMS.sig"
    ssh-keygen -q -Y sign -f "$T/otherkey" -n file "$T/rel/SHA256SUMS"
    out=$(run_installer)
    status=$?
    check "wrong signer: exit 1 (got $status)" equals "$status" 1
    check "wrong signer: message" contains "$out" "bad signature. Nothing was installed."
    check "wrong signer: not installed" eval '[[ ! -e $T/bin/jevsh ]]'
    cp "$T/otherkey.pub" "$T/rel/jevsh-release.pub"
    out=$(run_installer)
    check "wrong key: message" contains "$out" "unexpected signing key"
    check "wrong key: not installed" eval '[[ ! -e $T/bin/jevsh ]]'
    end
}

t122() {
    begin T-122
    local out
    make_fake_release
    printf '# user settings\n' > "$HOME/.bashrc"
    cp "$HOME/.bashrc" "$T/original"
    out=$(run_installer)
    check "PATH hint" contains "$out" "is not in your PATH yet"
    check "hint line" contains "$out" "export PATH=\"$T/bin:\$PATH\""
    check "next step" contains "$out" 'Next: run "jevsh --set-key"'
    check "bashrc unchanged" cmp -s "$HOME/.bashrc" "$T/original"
    end
}

# ---------------------------------------------------------------------------

SELECTED=("$@")
ALL=(t001 t002 t003 t004 t010 t011 t012 t013 t014 t020 t021 t022 t023 t024
    t030 t031 t032 t033 t034 t035 t036 t037 t038 t039
    t040 t041 t042 t043 t044 t045 t046
    t050 t051 t052 t053 t054 t055 t056 t057 t058 t059 t060 t061 t062
    t100 t101 t102 t103 t104 t120 t121 t122)

printf 'jevsh tests on %s, bash %s\n' "$(. /etc/os-release 2> /dev/null && printf '%s' "$PRETTY_NAME")" "$BASH_VERSION"
for test in "${ALL[@]}"; do
    id="T-${test#t}"
    selected "$id" || continue
    "$test"
done
printf '\n%d passed, %d failed\n' "$PASS_COUNT" "$FAIL_COUNT"
((FAIL_COUNT == 0)) || {
    printf 'Failed: %s\n' "${FAILED_IDS[*]}"
    exit 1
}
