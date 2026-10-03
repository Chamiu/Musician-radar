#!/bin/bash
# =================================================================
# Minimal iTMS New Release Radar — 本番仕様（log隔離版・決定稿）
#
# 仕様:
#   - 本体と artists.txt は同じパスにセットで置く（セット必須）
#   - ログは本体の下の log/ ディレクトリに隔離して貯める
#   - 監視対象: artists.txt に記載の artistId を lookup API で直撃
#     （同名別人・コラボ名義も全部拾う＝選別は人間が後でやる）
#   - releaseDate 先頭10文字が当日と完全一致のみ抽出
#   - YYYY-MM-DD.md に「アーティスト名 : ID」付き階層構造で記録
#   - ignore.txt は人間用メモ（シェルは一切読まない・仕様）
#
# 依存: curl, jq, awk, grep, sed のみ（Pythonの影なし）
# =================================================================

# 本番仕様: 当日の日付を date コマンドが自動で拾う
TEST_DATE=""

# 自分の置き場所へ移動（＝artists.txtと同居する約束の場所）
cd "$(dirname "$0")" || exit 1

# ログ用ディレクトリ（無ければ掘る）
LOG_DIR="log"
mkdir -p "$LOG_DIR"

# 基準日の決定（TEST_DATEが空なら当日）
if [ -n "$TEST_DATE" ]; then
  TODAY="$TEST_DATE"
  echo "🧪【テストモード】基準日を ${TODAY} に偽装中にゃ！"
else
  TODAY=$(date "+%Y-%m-%d")
fi

LOG_DIR="log/itms"                      # ← iTMS専用の隔離部屋に
mkdir -p "$LOG_DIR"                     # ← 無ければ掘る（log/itms/ まで一気に掘れる）
LOG_FILE="${LOG_DIR}/${TODAY}.md"
ARTIST_FILE="artists-itms.txt"          # ← サービス別の定義ファイルに

if [ ! -f "$ARTIST_FILE" ]; then
  echo "エラー: ${ARTIST_FILE} が見つからないにゃ！本体と同じ場所に置いてね。"
  exit 1
fi

echo "🐾 iTMSレーダー起動中... (基準日: ${TODAY})"
echo "--------------------------------------------------"

while IFS= read -r LINE || [ -n "$LINE" ]; do
  # コメント行・空行はスキップ
  [[ "$LINE" =~ ^# ]] || [ -z "$LINE" ] && continue

  # 行の先頭のIDだけ切り出す（# 以降は人間用の名前メモ）
  ARTIST_ID=$(echo "$LINE" | awk '{print $1}')

  echo "🔍 捜索中: ID ${ARTIST_ID}"

  # Lookup API をIDで直撃（同名別人のノイズ一切なし・JPストア明示）
  RESPONSE=$(curl -sG "https://itunes.apple.com/lookup" \
    --data-urlencode "id=${ARTIST_ID}" \
    --data-urlencode "entity=album" \
    --data-urlencode "limit=200" \
    --data-urlencode "country=JP")

  # 当日一致の件数をカウント
  MATCHED_COUNT=$(echo "$RESPONSE" | jq --arg today "$TODAY" \
    '[.results[] | select(.wrapperType == "collection") | select(.releaseDate[0:10] == $today)] | length')

  if [ "$MATCHED_COUNT" -gt 0 ]; then
    echo "  ✨ 【新譜発見！】 ${MATCHED_COUNT}件ヒット！"

    echo "$RESPONSE" | jq -r --arg today "$TODAY" \
      '.results[]
       | select(.wrapperType == "collection")
       | select(.releaseDate[0:10] == $today)
       | "\(.artistId)\t\(.artistName)\t\(.collectionName)\t\(.collectionViewUrl)"' \
    | while IFS=$'\t' read -r artist_id found_artist album_name store_url; do

      # まだ当日のログがなければ見出しを作る
      if [ ! -f "$LOG_FILE" ]; then
        echo "# ${TODAY}" > "$LOG_FILE"
        echo "" >> "$LOG_FILE"
      fi

      # 指定どおりの階層構造＋ID付記で記録
      echo "- ${found_artist} : ${artist_id}" >> "$LOG_FILE"
      echo "  - ${album_name}" >> "$LOG_FILE"
      echo "    - ${store_url}" >> "$LOG_FILE"

      echo "    📝 記録完了: ${album_name} (ID: ${artist_id})"
    done
  else
    echo "    (基準日の新譜なし)"
  fi

  # APIへの礼儀として1秒ウェイト
  sleep 1

done < "$ARTIST_FILE"

echo "--------------------------------------------------"
echo "🐾 探索終了にゃ！"
if [ -f "$LOG_FILE" ]; then
  echo "📄 結果ファイル: ${LOG_FILE}"
else
  echo "※基準日にはどのアーティストからも新譜は検知されなかったにゃ。"
fi
