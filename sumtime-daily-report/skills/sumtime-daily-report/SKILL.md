---
name: sumtime-daily-report
description: その日の作業（GitHub の自分の Issue コメント・PR・コミット、Claude Code のセッション）を集め、SumTime（クラウド工数管理 sumtime.intra.use-eng.co.jp）の予実入力に、プロジェクト・作業・時間・コメントを提案して登録するスキル。「SumTime に登録」「SUM TIME」「サムタイム」「工数を入力」「工数登録」「実績登録」「今日の実績を入れて」「先週分の実績」「予実入力」「作業実績のコメントを入れて」などの指示で使用する。
---

# SumTime 予実入力の自動登録

その日の作業を集めて SumTime の作業枠（時間帯・プロジェクト・作業・コメント）を提案し、
ユーザーの承認を得てから登録する。

## 前提

- Claude in Chrome が接続されていること。つながらないときは拡張のインストールと
  サイドパネルでのサインインを案内して止まる
- 登録（保存・削除）は、提案した一覧にユーザーの明示的な承認をもらってから行う
- **SumTime は Claude のタブでだけ開く。** ユーザーには SumTime を自分で開かないよう案内する
  （開いたままの別画面が登録内容を上書きするため。下の「落とし穴」参照）
  - Claude が操作・確認できるのは Claude のタブグループ内のタブだけで、ユーザーのタブは閉じられない
  - ログイン状態は Chrome 全体で共通なので、ログイン済みなら Claude のタブはそのまま使える
  - **ログインが必要なときだけ**、Claude のタブでログイン画面を開き、ユーザーにそのタブで入力してもらう。
    パスワードは Claude からは入力しない
  - それでもユーザーが別の画面で SumTime を開いているときは、その画面を閉じてもらってから登録する

## 決まり（ユーザーと合意済み）

- **Issue に紐づかない作業は時間管理外。** 登録せず、何をしていたか分かるように別の表で見せる。
  ユーザーが「これは登録して」と指示したものだけ登録する
- **一覧には必ず No（通し番号）を付ける。** 登録する表と時間管理外の表を通して連番にする。
  ユーザーは「No.3 を 3 時間に」のように No で訂正を指示する
- **コメントは `Issue #N 概要` の形。** 初回は `Issue #N ` + Issue のタイトルをそのまま使う
- **同じ Issue のコメントは日をまたいでも一字一句同じにする。**
  SumTime はコメントでグループ化して集計するため。登録前に過去の SumTime の実績から
  `Issue #N ` で始まるコメントを探し、あればその文言をそのまま使う（Issue のタイトルが
  後で変わっても合わせない）。1 つのコメントに複数の Issue を混ぜない
- **プロジェクト・作業は Claude が判断して提案する。** 判断できないときはユーザーに聞く
- **時間はおおよそでよい。** Claude Code では複数の作業を並行するため、時刻から正確には出せない。
  判断の難しさ・調査の量が多い作業ほど多く割り当て、その日の勤務時間（既存の合計、
  または始業〜終業から休憩を除いた時間）を Issue の作業で埋める。15 分単位にする

## 手順

1. **対象日を決める**（指定が無ければ今日。JST）
2. **作業を集める**（自分の分だけ。他の人の PR・コミットは除く）
   - Issue：`gh search issues --involves @me --updated ">=<対象日>"` で候補を出し、各 Issue の
     `repos/<owner>/<repo>/issues/<N>/timeline` から、対象日に自分が行った操作（commented・closed・
     cross-referenced 等）だけを残す。時刻は UTC なので JST に直す（前日 15:00Z 以降）。
     `--updated <日付>` や範囲指定にすると、対象日より後にも更新された Issue が漏れる
     （過去の日を扱うときに特に注意）
   - PR：`gh pr list --state all --search "updated:>=<日付>"` で author が自分のもの
   - コミット：`git log --all --since=<日付> --author=<自分>`
   - セッション：`list_sessions`（`include_archived: true`）の `lastActivityAt` が対象日のもの。
     Issue との紐づきは `search_session_transcripts` で `#N` を検索して確かめる。
     題名だけで Issue に紐づけない
3. **SumTime を読む**（Chrome で `http://sumtime.intra.use-eng.co.jp/sumtime/app/resources/manhours-inputs` を開く）
   - 対象日の既存の枠・休憩、プロジェクト・作業の一覧（後述の lists）
   - 過去 180 日のコメント（同じ Issue の文言を再利用するため）
4. **案を出す。** 2 つの表にする
   - 登録する作業：`No / 時間 / h / プロジェクト→作業 / SumTime コメント`
   - 時間管理外：`No / セッション・作業 / 最後に操作した時刻`
   - 既存の枠を置き換える・消すときは、そのことを明記する
5. **承認をもらう。** 訂正は No で受け、表を出し直して再度承認をもらう
6. **登録する**（後述）
7. **自分のタブを読み込み直す。** API で書いたあとは Claude のタブも古い内容を持っているため、
   すぐに再読み込みする
8. **確かめる。** 少し時間を置いてから lists を読み直し、全枠の時間・作業（`working_schedule_id`）・
   コメントと、余分な枠・時間の重なりが無いこと、日ごとの合計が案どおりであることを突き合わせる。
   応答が 200 でも作業が変わっていないことがある（後述の「登録・更新」を参照）。画面をスクリーンショットで確認してから結果を No 付きの表で報告する。
   `updated_at` が自分の書き込みより後の枠があれば、別の画面からの上書きを疑う
   （`read_network_requests` で自分のタブが送った `update-schedule` の件数と照合できる）
9. **Claude のタブを閉じる。** 確認とスクリーンショットが済んだら、報告の前に `tabs_context_mcp` で
   自分のタブグループのタブを引き、`tabs_close_mcp` ですべて閉じる。グループの最後のタブを閉じると
   Chrome がグループごと消す（閉じないとセッションごとにグループが残り続ける）。
   訂正の指示が来たら、そのとき新しいタブで開き直す

## SumTime の API（2026-09-28 に実際の保存操作で確認）

Laravel Nova 製。ページ内の `Nova.request()`（axios。CSRF 等は自動で付く）から呼ぶ。

### 読み込み

```js
{const l=await Nova.request().get('/api/sumtime/resources/manhours-inputs/lists',
  {params:{start_at:'2026/9/28 0:00:00',end_at:'2026/9/29 0:00:00'}});
window.__v=l.data.datas;}
window.__v.working_achievements.map(a=>[a.id,a.working_schedule_id,a.start_at,a.end_at,a.achievement_time,a.working_memo].join(' | '))
```

`datas` の中身:

- `working_achievements`：作業枠。`id` / `working_schedule_id` / `start_at` / `end_at`（`YYYY-MM-DD HH:MM:SS`）/ `achievement_time` / `working_memo`
- `non_working_achievements`：休憩など。作業枠と重ねない
- `working_schedules`：プロジェクト・作業の一覧。`isFolder: false` の行が選べる作業。
  `working_schedule_id` / `customer_name` / `project_name` / `working_schedule_name` / `memo_required`
  （例：コクヨ｜ボードラインシステム刷新｜評価・修正 = 39。ID は必ず毎回ここから引く）

### 登録・更新

```js
await Nova.request().post('/api/sumtime/resources/manhours-inputs/update-schedule',{params:{
  working_achievement_id: null,          // 新規は null、更新は既存の id
  working_schedule_id: 39,
  start_at: '2026-09-28 15:15:00',
  end_at:   '2026-09-28 18:15:00',
  working_memo: 'Issue #758 ...'
}})
// 応答: {datas:{working_achievement_id: <id>}}
```

時間の変更も同じ呼び出しで `start_at` / `end_at` を変える。

**既存の枠の `working_schedule_id`（プロジェクト・作業）は、この呼び出しでは変わらない。**
応答は 200 で時間とコメントは変わるが、作業は元のまま残る（2026-09-28 に 8 枠で確認）。
作業を変えるときは、同じ時間・コメントで新しい枠（`working_achievement_id: null`）を作ってから、
元の枠を delete-schedule で削除する。

### 削除

```js
await Nova.request().post('/api/sumtime/resources/manhours-inputs/delete-schedule',
  {params:{working_achievement_id: 16223}})
// 応答: {datas:[]}
```

（2026-09-28 に画面のゴミ箱ボタンからの削除を記録して確認。画面では「予定を削除します。宜しいですか？」→ OK）

同じ時間帯に枠が重なっていると画面では下の枠を選べない。画面から消すときは、先に
update-schedule でその枠を空いている時間へずらしてから消す。

### 送る中身の記録のしかた

画面操作の前に XHR をフックし、画面から 1 回保存して `window.__cap` を読む。

```js
window.__cap=[];
if(!window.__hooked){window.__hooked=true;
const os=XMLHttpRequest.prototype.send, oo=XMLHttpRequest.prototype.open;
XMLHttpRequest.prototype.open=function(m,u){this.__m=m;this.__u=u;return oo.apply(this,arguments)};
XMLHttpRequest.prototype.send=function(b){if(/update-schedule|delete-schedule/.test(this.__u)){const x=this;const rec={m:this.__m,u:String(this.__u).replace(/\?.*/,''),body:String(b)};
this.addEventListener('load',()=>{rec.status=x.status;rec.resp=String(x.responseText).slice(0,500)});window.__cap.push(rec);}return os.apply(this,arguments)};}
```

## 落とし穴

- **古い内容を持ったまま開いている別の SumTime 画面が、API で書いた内容を上書きする。**
  2026-09-28 に、ユーザーがログインに使った画面を開いたままにしていたところ、ユーザーが保存操作を
  していないのに、コメントが元の文言に戻り、重なる時間帯に旧コメントの枠が新しく作られた
  （Claude のタブが送った件数は意図した分だけだったことを `read_network_requests` で確認）。
  画面を閉じたあとは起きていない。どの操作で保存が走るのかは未確認。
  SumTime は Claude のタブでだけ開き（前提を参照）、登録後は自分のタブも読み込み直す。
  画面を閉じる操作そのもので保存が走った可能性もあるため、閉じたあとも読み直して確かめる
- `javascript_tool` の結果に URL のクエリ文字列等が含まれると `[BLOCKED: Cookie/query string data]`
  で返らない。結果は `window.__x` に入れ、必要な項目だけに絞って返す
- `javascript_tool` はページのスコープを共有するため、トップレベルの `const` を 2 回目に宣言すると
  `Identifier has already been declared` になる。`{ ... }` のブロックで囲み、結果は `window.__x` に入れる
- 画面から編集するとき：枠をダブルクリックすると「作業詳細編集」が開く。**テキストエリアを
  クリックしてから** `ctrl+a` → 入力する（クリックしないとページ全体が選択されるだけ）。
  ダイアログは Enter で保存されるため、コメントに改行を入れない
- クリック座標はスクリーンショットが報告する座標系で指定する（縮小表示の画素ではない）
- ページ遷移の直後はスクリーンショットが白い。数秒待ってから撮る
