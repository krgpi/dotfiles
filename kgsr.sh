#!/bin/bash

# esa の ToDo / InProgress / InReview 記事の未完了チェックリスト項目と、
# 直近7日以内に更新された Done 記事を一覧表示する
# gh issue list ライクな表形式で、#番号を記事へのハイパーリンクにする
# .zshrc から kgsr 関数として呼び出される

set -euo pipefail

TEAM="${KGSR_ESA_TEAM:-ideoj}"
DONE_SINCE="$(date -v-7d +%F 2>/dev/null || date -d '7 days ago' +%F)"

# esaはグローバルCLIなので、カレントディレクトリのプロジェクト側 .mise.toml が
# node バージョンを固定していても影響を受けないようフルパスで呼ぶ
ESA_BIN="$HOME/.local/share/mise/installs/node/latest/bin/esa"

"$ESA_BIN" post search "tag:ToDo OR tag:InProgress OR tag:InReview OR tag:Done" --team "$TEAM" --per-page 100 \
    --json number,name,body_md,updated_at,url,tags \
  | jq -r --arg since "$DONE_SINCE" '
      .posts
      | map(select((.tags | index("Done") == null) or (.updated_at[0:10] >= $since)))
      | sort_by(.updated_at) | reverse | .[] |
      . as $p |
      (($p.tags | index("Done")) != null) as $isDone |
      ($p.tags | map(select(. == "ToDo" or . == "InProgress" or . == "InReview" or . == "Done")) | join(",")) as $status |
      ($p.updated_at | split("T")[0]) as $date |
      (if ($p.name | length) > 60 then ($p.name[0:59] + "…") else $p.name end) as $title |
      (if $isDone then
          [$status, ($p.number | tostring), $title, $date, $p.url, "(完了)"]
        else
          ($p.body_md // "") | split("\n")[] |
          select(test("^\\s*[-*] \\[ \\]")) |
          [$status, ($p.number | tostring), $title, $date, $p.url, .]
        end)
      | @tsv' \
  | awk -F'\t' '
      function color(text, code) { return "\033[" code "m" text "\033[0m" }
      function link(text, url) { return "\033]8;;" url "\033\\" text "\033]8;;\033\\" }
      function statuscolor(s) {
          if (s ~ /Done/) return 32
          if (s ~ /InReview/) return 34
          if (s ~ /InProgress/) return 33
          return 90
      }
      {
          status = $1; num = $2; title = $3; date = $4; url = $5
          item = $6
          sub(/^[ \t]*[-*] \[[ xXｘＸ]\][ \t]*/, "", item)

          w_status[NR] = status
          w_num[NR] = "#" num
          w_title[NR] = title
          w_date[NR] = date
          w_url[NR] = url
          w_item[NR] = item

          if (length(status) > mw_status) mw_status = length(status)
          if (length(w_num[NR]) > mw_num) mw_num = length(w_num[NR])
          if (length(w_title[NR]) > mw_title) mw_title = length(w_title[NR])
          if (length(date) > mw_date) mw_date = length(date)
      }
      END {
          for (i = 1; i <= NR; i++) {
              printf "%s  %s  %s  %s  %s\n", \
                  color(sprintf("%-" mw_status "s", w_status[i]), statuscolor(w_status[i])), \
                  link(color(sprintf("%-" mw_num "s", w_num[i]), 36), w_url[i]), \
                  sprintf("%-" mw_title "s", w_title[i]), \
                  color(sprintf("%-" mw_date "s", w_date[i]), 37), \
                  w_item[i]
          }
      }
  '
