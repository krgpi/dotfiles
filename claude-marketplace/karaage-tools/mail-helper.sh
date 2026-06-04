#!/usr/bin/env bash
# Apple Mail.app を AppleScript 経由で操作するヘルパー。
#
# 設計方針:
#   - 送信は一切行わない。draft は「下書き(Drafts)」へ保存、reply は返信ウィンドウを開くだけ。
#     send コマンドはこのスクリプトに存在しない（誤送信をコードレベルで防止）。
#   - 本文などの任意文字列は一時ファイル経由で AppleScript に渡し、osascript への
#     文字列埋め込みによるエスケープ崩れを避ける（read POSIX file as «class utf8»）。
#   - 引数は osascript の argv 経由で渡す。
#   - 統合受信トレイ(inbox)に対する `whose` フィルタは全件評価で AppleEvent タイムアウト
#     (-1712) を起こすため使わない。最新 N 件のプロパティを一括取得して走査する方式を採る。
#     よって read/search/reply の対象は「最新 N 件」の範囲（古すぎるメールは対象外）。
#   - read/reply の id は unread/recent/search の出力に含まれる ID を使う。
#
# 使い方:
#   mail-helper.sh unread [limit]                     未読メール一覧（既定20件）
#   mail-helper.sh recent [limit]                     最新メール一覧（既定20件）
#   mail-helper.sh read   <id>                        指定メールの本文全文
#   mail-helper.sh search <keyword> [limit]           件名・差出人にキーワードを含むメール
#   mail-helper.sh draft  <to> <subject> <body-file> [cc]   新規下書き作成（Drafts へ保存）
#   mail-helper.sh reply  <id> <body-file> [all]      返信下書きを開く（all で全員返信）

set -euo pipefail

# inbox の先頭から走査する最大件数。Mail は「件数 × 取得プロパティ種類数 × 約0.15秒」かかるため、
# 全件で取得するプロパティを最小化（unread は read status のみ、search は件名・差出人のみ）し、
# 絞り込んだ該当メールだけ詳細を取得して待ち時間を抑える。対象範囲は最新 SCAN_MAX 件。
SCAN_MAX=80

die() {
  echo "エラー: $*" >&2
  exit 1
}

abspath() {
  # 相対パスでも osascript の POSIX file が解決できるよう絶対パス化する
  case "$1" in
    /*) printf '%s\n' "$1" ;;
    *)  printf '%s/%s\n' "$PWD" "$1" ;;
  esac
}

cmd_unread() {
  local limit="${1:-20}"
  osascript - "$limit" "$SCAN_MAX" <<'APPLESCRIPT'
on run argv
  set lim to (item 1 of argv) as integer
  set scanMax to (item 2 of argv) as integer
  tell application "Mail"
    set total to count of messages of inbox
    if total is 0 then return "受信トレイにメールはありません。"
    if total < scanMax then set scanMax to total
    set reads to read status of (a reference to (messages 1 thru scanMax of inbox))
    set wantIdx to {}
    repeat with i from 1 to scanMax
      if (item i of reads) is false then
        set end of wantIdx to i
        if (count of wantIdx) ≥ lim then exit repeat
      end if
    end repeat
    if (count of wantIdx) is 0 then return "最新 " & scanMax & " 件に未読はありません。"
    set out to "未読メール " & (count of wantIdx) & " 件（最新 " & scanMax & " 件をスキャン）:" & linefeed
    repeat with k from 1 to (count of wantIdx)
      set msg to message (item k of wantIdx) of inbox
      set out to out & "---" & linefeed
      set out to out & "ID: " & (id of msg) & linefeed
      set out to out & "From: " & (sender of msg) & linefeed
      set out to out & "Subject: " & (subject of msg) & linefeed
      set out to out & "Date: " & ((date received of msg) as string) & linefeed
    end repeat
    return out
  end tell
end run
APPLESCRIPT
}

cmd_recent() {
  local limit="${1:-20}"
  osascript - "$limit" <<'APPLESCRIPT'
on run argv
  set lim to (item 1 of argv) as integer
  tell application "Mail"
    set total to count of messages of inbox
    if total is 0 then return "受信トレイにメールはありません。"
    if total < lim then set lim to total
    set msgsRef to a reference to (messages 1 thru lim of inbox)
    set ids to id of msgsRef
    set froms to sender of msgsRef
    set subjs to subject of msgsRef
    set dts to date received of msgsRef
  end tell
  set out to "最新メール " & lim & " 件:" & linefeed
  repeat with i from 1 to lim
    set out to out & "---" & linefeed
    set out to out & "ID: " & (item i of ids) & linefeed
    set out to out & "From: " & (item i of froms) & linefeed
    set out to out & "Subject: " & (item i of subjs) & linefeed
    set out to out & "Date: " & ((item i of dts) as string) & linefeed
  end repeat
  return out
end run
APPLESCRIPT
}

cmd_search() {
  local keyword="$1"
  local limit="${2:-20}"
  # 件名・差出人にキーワードを含むメールを最新 SCAN_MAX 件から探す。
  # 本文全文検索は重いため対象外（本文確認は read <id> を使う）。
  osascript - "$keyword" "$limit" "$SCAN_MAX" <<'APPLESCRIPT'
on run argv
  set kw to item 1 of argv
  set lim to (item 2 of argv) as integer
  set scanMax to (item 3 of argv) as integer
  tell application "Mail"
    set total to count of messages of inbox
    if total is 0 then return "受信トレイにメールはありません。"
    if total < scanMax then set scanMax to total
    set froms to sender of (a reference to (messages 1 thru scanMax of inbox))
    set subjs to subject of (a reference to (messages 1 thru scanMax of inbox))
    set wantIdx to {}
    repeat with i from 1 to scanMax
      if ((item i of subjs) contains kw) or ((item i of froms) contains kw) then
        set end of wantIdx to i
        if (count of wantIdx) ≥ lim then exit repeat
      end if
    end repeat
    if (count of wantIdx) is 0 then return "「" & kw & "」に一致するメールは最新 " & scanMax & " 件内にありません（件名・差出人で検索）。"
    set out to "「" & kw & "」に一致 " & (count of wantIdx) & " 件（最新 " & scanMax & " 件を検索、件名・差出人）:" & linefeed
    repeat with k from 1 to (count of wantIdx)
      set i to item k of wantIdx
      set msg to message i of inbox
      set out to out & "---" & linefeed
      set out to out & "ID: " & (id of msg) & linefeed
      set out to out & "From: " & (item i of froms) & linefeed
      set out to out & "Subject: " & (item i of subjs) & linefeed
      set out to out & "Date: " & ((date received of msg) as string) & linefeed
    end repeat
    return out
  end tell
end run
APPLESCRIPT
}

cmd_read() {
  local id="$1"
  osascript - "$id" "$SCAN_MAX" <<'APPLESCRIPT'
on run argv
  set theId to (item 1 of argv) as integer
  set scanMax to (item 2 of argv) as integer
  tell application "Mail"
    set total to count of messages of inbox
    if total is 0 then return "受信トレイにメールはありません。"
    if total < scanMax then set scanMax to total
    set ids to id of (a reference to (messages 1 thru scanMax of inbox))
    set idx to 0
    repeat with i from 1 to count of ids
      if (item i of ids) is theId then
        set idx to i
        exit repeat
      end if
    end repeat
    if idx is 0 then return "指定IDのメールが最新 " & scanMax & " 件内に見つかりません: " & theId
    set msg to message idx of inbox
    set out to "From: " & (sender of msg as string) & linefeed
    set out to out & "Subject: " & (subject of msg as string) & linefeed
    set out to out & "Date: " & ((date received of msg) as string) & linefeed
    try
      set out to out & "To: " & (address of to recipients of msg as string) & linefeed
    end try
    set out to out & "----- 本文 -----" & linefeed
    set out to out & (content of msg)
    return out
  end tell
end run
APPLESCRIPT
}

cmd_draft() {
  local to_addr="$1"
  local subject="$2"
  local body_file
  body_file="$(abspath "$3")"
  local cc_addr="${4:-}"
  [ -f "$body_file" ] || die "本文ファイルが見つかりません: $body_file"
  osascript - "$to_addr" "$subject" "$body_file" "$cc_addr" <<'APPLESCRIPT'
on run argv
  set toField to item 1 of argv
  set subjField to item 2 of argv
  set bodyFile to item 3 of argv
  set ccField to item 4 of argv
  set theBody to read (POSIX file bodyFile) as «class utf8»
  tell application "Mail"
    set newMessage to make new outgoing message with properties {subject:subjField, content:theBody, visible:true}
    tell newMessage
      repeat with addr in my splitTrim(toField)
        if addr is not "" then make new to recipient at end of to recipients with properties {address:addr}
      end repeat
      if ccField is not "" then
        repeat with addr in my splitTrim(ccField)
          if addr is not "" then make new cc recipient at end of cc recipients with properties {address:addr}
        end repeat
      end if
    end tell
    save newMessage
    activate
  end tell
  return "下書きを作成し、Drafts に保存しました（宛先: " & toField & "）。Mail.app で内容を確認してください。"
end run

on splitTrim(s)
  set tid to AppleScript's text item delimiters
  set AppleScript's text item delimiters to ","
  set parts to text items of s
  set AppleScript's text item delimiters to tid
  set acc to {}
  repeat with p in parts
    set end of acc to my trim(p as string)
  end repeat
  return acc
end splitTrim

on trim(t)
  repeat while t starts with " "
    set t to text 2 thru -1 of t
  end repeat
  repeat while t ends with " "
    set t to text 1 thru -2 of t
  end repeat
  return t
end trim
APPLESCRIPT
}

cmd_reply() {
  local id="$1"
  local body_file
  body_file="$(abspath "$2")"
  local all_flag="${3:-}"
  [ -f "$body_file" ] || die "本文ファイルが見つかりません: $body_file"
  # 引用を保持したまま本文を入れるため、reply で引用付き返信ウィンドウを開き、本文を
  # クリップボード経由でカーソル位置（引用の前）にペーストする。AppleScript の content では
  # 引用テキストを取得・保持できないため。System Events の keystroke を使うのでアクセシビリティ権限が必要。
  osascript - "$id" "$body_file" "$all_flag" "$SCAN_MAX" <<'APPLESCRIPT'
on run argv
  set theId to (item 1 of argv) as integer
  set bodyFile to item 2 of argv
  set replyAll to ((item 3 of argv) is "all")
  set scanMax to (item 4 of argv) as integer
  set theBody to read (POSIX file bodyFile) as «class utf8»
  set savedClip to missing value
  try
    set savedClip to the clipboard as text
  end try
  tell application "Mail"
    set total to count of messages of inbox
    if total is 0 then error "受信トレイにメールはありません。"
    if total < scanMax then set scanMax to total
    set ids to id of (a reference to (messages 1 thru scanMax of inbox))
    set idx to 0
    repeat with i from 1 to count of ids
      if (item i of ids) is theId then
        set idx to i
        exit repeat
      end if
    end repeat
    if idx is 0 then error "指定IDのメールが最新 " & scanMax & " 件内に見つかりません: " & theId
    set msg to message idx of inbox
    reply msg opening window yes reply to all replyAll
    activate
  end tell
  delay 1.2
  set the clipboard to theBody
  delay 0.2
  tell application "System Events"
    keystroke "v" using command down
  end tell
  delay 0.3
  if savedClip is not missing value then set the clipboard to savedClip
  return "返信下書きを開き、本文を引用の前に挿入しました。Mail.app で確認してください。"
end run
APPLESCRIPT
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    unread) cmd_unread "${2:-20}" ;;
    recent) cmd_recent "${2:-20}" ;;
    read)   [ -n "${2:-}" ] || die "使い方: read <id>"; cmd_read "$2" ;;
    search) [ -n "${2:-}" ] || die "使い方: search <keyword> [limit]"; cmd_search "$2" "${3:-20}" ;;
    draft)  [ $# -ge 4 ] || die "使い方: draft <to> <subject> <body-file> [cc]"; cmd_draft "$2" "$3" "$4" "${5:-}" ;;
    reply)  [ $# -ge 3 ] || die "使い方: reply <id> <body-file> [all]"; cmd_reply "$2" "$3" "${4:-}" ;;
    ""|-h|--help|help)
      awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"
      ;;
    *) die "不明なサブコマンド: $cmd（unread/recent/read/search/draft/reply）" ;;
  esac
}

main "$@"
