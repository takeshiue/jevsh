# jevsh

[English](README.md) | 日本語

シェルコマンドを実行する前に、その危険度を JEV に尋ねます。

jevsh は、指定したコマンド行を AI サービス JEV（TypeSafe）へ送り、危険度（LOW / MEDIUM / HIGH / CRITICAL）と確信度を表示します。`y` と答えたときだけコマンドを実行します。JEV は助言するだけで、判断するのはあなたです。

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

## 動作環境

- bash 4.4 以降が動く Linux
- `curl`
- TypeSafe の JEV API キー

jevsh は bash スクリプト1ファイルです。root 権限は不要で、ほかに何もインストールしません。

## インストール

次の1行を実行します。v0.3.2 のリリースをダウンロードし、`SHA256SUMS` と照合して、`~/.local/bin` にインストールし、版数を表示します。

```bash
mkdir -p ~/.local/bin && cd "$(mktemp -d)" && curl -fsSL --remote-name-all https://raw.githubusercontent.com/takeshiue/jevsh/v0.3.2/{jevsh,SHA256SUMS} && sha256sum -c SHA256SUMS && install -m 755 jevsh ~/.local/bin/jevsh && ~/.local/bin/jevsh --version
```

そのあと `jevsh` が「command not found」になる場合は、`~/.local/bin` がまだ `PATH` に入っていません。ログインし直すか `source ~/.profile` を実行してください。それでも入らない場合は `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc && source ~/.bashrc` を実行します。

全ユーザー向けに入れる場合は、`install -m 755 jevsh ~/.local/bin/jevsh` の部分を `sudo install -m 755 jevsh /usr/local/bin/jevsh` に置き換えます。

jevsh は1ファイルで、インストーラーはありません。シェルへ直接流し込む（`curl ... | bash`）方法は使わないでください。

### 署名の確認（任意）

`SHA256SUMS` は jevsh のリリース用の鍵で署名しています。ダウンロードしたものが本当に作者のものかを確かめるには、インストールの1行のあと、同じディレクトリで次を実行します。

```bash
curl -fsSL --remote-name-all https://raw.githubusercontent.com/takeshiue/jevsh/v0.3.2/{SHA256SUMS.sig,jevsh-release.pub}
ssh-keygen -lf jevsh-release.pub
echo "takeshi.uematsu@gmail.com $(cat jevsh-release.pub)" > allowed_signers
ssh-keygen -Y verify -f allowed_signers -I takeshi.uematsu@gmail.com -n file -s SHA256SUMS.sig < SHA256SUMS
```

2行目が表示するフィンガープリントが `SHA256:LIdW6JBHIV1YvPQHU+suSOe87ZJgNZGZlfjNdl1kkKg` であること、最後の行が `Good "file" signature` と表示することを確認します。

## 初回の実行

初めてコマンドを評価するとき、jevsh は送信される内容を説明し、API キーを尋ねます。キーは API で使えることを確かめてから `~/.config/jevsh/config`（権限 0600）へ保存します。キーが画面に表示されることはありません。

環境変数 `JEV_API_KEY` でキーを指定することもできます。`jevsh --set-key` でいつでも登録・置き換えができます。

## 使い方

```text
jevsh [options] COMMAND [ARGS...]    評価し、確認してから実行
jevsh [options] -c 'COMMAND LINE'    同じ（パイプなどを含む行全体）
jevsh --check [--fail-on LEVEL] COMMAND [ARGS...]
jevsh --check [--fail-on LEVEL] -c 'COMMAND LINE'
jevsh --set-key
jevsh --init bash
jevsh --yes | --no-jev COMMAND [ARGS...]
jevsh --enable-keybinding | --disable-keybinding
jevsh --help | --version
```

コマンドを実行するのは `y` か `Y` と答えたときだけです。Enter だけを含め、それ以外の答えはすべて中止になります。

### 危険度が低いときは確認を省く

危険度の低いコマンドを `y` と答えずに実行したい場合は、`~/.bashrc` で `JEVSH_AUTO_RUN` を export します。

```bash
export JEVSH_AUTO_RUN=LOW       # LOW は確認なしで実行、MEDIUM 以上は従来どおり確認
```

`MEDIUM` にすると、LOW と MEDIUM が確認なしで実行されます。評価結果は表示され、続けて `Running without asking (...)` と表示されます。評価できなかったときは必ず確認し、端末がない場合は何も実行しません。`jevsh COMMAND` と評価キーの両方で有効です。

### パイプとリダイレクト

`|`、`>`、`>>`、`<`、`&&`、`||`、`;` は jevsh が動く前にシェルが処理するため、jevsh にはその手前の部分しか届きません。行全体を評価するには、`-c` とシングルクォートを使います。

```bash
jevsh -c 'cat data.csv | sort > out.txt'    # 行全体を評価する
jevsh cat data.csv | sort > out.txt         # "cat data.csv" だけを評価する
```

### 評価キー

評価キーを使うと、`jevsh` も引用符も打つ必要がありません。いつもどおりコマンドを打ち、Enter の代わりに **Ctrl+X Enter** を押します。パイプやリダイレクトを含む行全体が評価されます。`n` と答えると、行が入力欄に残るので、直してから実行できます。Enter だけを押したときは、今までどおり評価なしで実行されます。

jevsh は API キーを登録した直後に、評価キーを追加するか尋ねます。いつでも追加・削除できます。

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

- 評価キーは、対話中の bash のプロンプトでだけ働きます。シェルスクリプトの中の行は、今までどおり評価なしで実行されます。
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

jevsh を通すと、1コマンドあたり約0.2秒増えます。そのほとんどは JEV API との通信です。40のコマンド行の例では、JEV の危険度が作者の予想と一致したのは、3回それぞれ40行中29〜31行でした。結果の全体と生データは [docs/benchmark.ja.md](docs/benchmark.ja.md) にあります。

## ライセンス

MIT License です。著作権表示とライセンス文を残す限り、商用を含めて自由に使用・改変・再配布できます。無保証で提供します。詳しくは [LICENSE](LICENSE) を参照してください。

## 作者

Takeshi Uematsu <takeshi.uematsu@gmail.com>
