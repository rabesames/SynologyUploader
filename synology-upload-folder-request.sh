#!/bin/bash
# Upload all files in a folder (recursively, in parallel) to a Synology file request.
# File requests are flat drop boxes, so subfolders are NOT recreated on the NAS;
# every file lands directly in the uploader's destination folder.
# Based on: https://github.com/Paul-DS/synology-upload-file-request

COOKIE_JAR="$(mktemp /tmp/syno_folder_upload_cookies.XXXXXX)"
RESULT_DIR="$(mktemp -d /tmp/syno_folder_upload_results.XXXXXX)"
trap 'rm -rf "$COOKIE_JAR" "$RESULT_DIR"' EXIT

JOBS=4  # default number of parallel uploads

while [ $# -gt 0 ]; do
  case "$1" in
    --host*|-H*)
      if [[ "$1" != *=* ]]; then shift; fi
      HOST="${1#*=}"
      ;;
    --sharing_id*|-S*)
      if [[ "$1" != *=* ]]; then shift; fi
      SHARING_ID="${1#*=}"
      ;;
    --password*|-P*)
      if [[ "$1" != *=* ]]; then shift; fi
      PASSWORD="${1#*=}"
      ;;
    --folder*|-F*)
      if [[ "$1" != *=* ]]; then shift; fi
      FOLDER="${1#*=}"
      ;;
    --uploader_name*|-U*)
      if [[ "$1" != *=* ]]; then shift; fi
      UPLOADER_NAME="${1#*=}"
      ;;
    --jobs*|-j*)
      if [[ "$1" != *=* ]]; then shift; fi
      JOBS="${1#*=}"
      ;;
    --help|-h)
      echo "-------------------------------------------------------------------------------"
      echo "Bash script to upload a folder's files (in parallel) to a Synology file request"
      echo "-------------------------------------------------------------------------------"
      echo
      echo "Syntax: bash synology-upload-folder-request.sh --host [HOST] --sharing_id [SHARING_ID] --password [PASSWORD] --uploader_name [UPLOADER_NAME] --folder [FOLDER] --jobs [N]"
      echo
      echo "Options:"
      echo "-H, --host            Host name of the Synology NAS, including the protocol (HTTP/HTTPS) and the port, without trailing slash"
      echo "-S, --sharing_id      Sharing ID provided by Synology"
      echo "-P, --password        The password for the file request, if defined"
      echo "-F, --folder          The folder whose files will be uploaded (recursively)"
      echo "-U, --uploader_name   Uploader name"
      echo "-j, --jobs            Number of parallel uploads (default: 4)"
      echo
      exit 0
      ;;
    *)
      >&2 printf "Error: Invalid argument\n"
      exit 1
      ;;
  esac
  shift
done

if [ -z "$HOST" ]; then
  echo "Invalid host"; exit 1
fi
if [ -z "$SHARING_ID" ]; then
  echo "Invalid sharing ID"; exit 1
fi
if [ -z "$FOLDER" ] || [ ! -d "$FOLDER" ]; then
  echo "Invalid folder (must be an existing directory)"; exit 1
fi
if [ -z "$UPLOADER_NAME" ]; then
  echo "Invalid uploader name"; exit 1
fi
if ! [[ "$JOBS" =~ ^[0-9]+$ ]] || [ "$JOBS" -lt 1 ]; then
  echo "Invalid jobs value (must be a positive integer)"; exit 1
fi

FOLDER="${FOLDER%/}"

# --- Authenticate once (cookie jar is then shared read-only by all workers) ---
if [ -n "$PASSWORD" ]; then
  echo "Login to Synology file share..."
  curl -s -L -X POST "$HOST/sharing/webapi/entry.cgi/SYNO.Core.Sharing.Login" \
    -j -c "$COOKIE_JAR" \
    -d "api=SYNO.Core.Sharing.Login&method=login&version=1&sharing_id=%22$SHARING_ID%22&password=%22$PASSWORD%22" > /dev/null
else
  echo "Initialize connection..."
  curl -s -L "$HOST/sharing/$SHARING_ID" \
    -j -c "$COOKIE_JAR" > /dev/null
fi

# --- Helpers: human-readable byte sizes and speeds (used for progress/summary) ---
human_size() {
  awk -v bytes="$1" 'BEGIN {
    split("B KB MB GB TB", units, " ")
    size = bytes; i = 1
    while (size >= 1024 && i < 5) { size /= 1024; i++ }
    printf "%.2f %s", size, units[i]
  }'
}

human_speed() {
  # $1 = bytes, $2 = seconds
  awk -v bytes="$1" -v secs="$2" 'BEGIN {
    if (secs <= 0) secs = 0.001
    bps = bytes / secs
    split("B/s KB/s MB/s GB/s TB/s", units, " ")
    i = 1
    while (bps >= 1024 && i < 5) { bps /= 1024; i++ }
    printf "%.2f %s", bps, units[i]
  }'
}

# --- Worker: upload a single file (flat, into the request destination) ---
upload_one() {
  local FILE="$1"
  local REL_PATH="${FILE#"$FOLDER"/}"
  local FILE_SIZE FILE_LAST_MODIFIED RESPONSE
  local START_MS END_MS DURATION_S SPEED SIZE_H
  FILE_SIZE=$(stat --printf="%s" "$FILE")
  FILE_LAST_MODIFIED=$(date -r "$FILE" +%s%3N)

  echo "Uploading '$REL_PATH'..."

  START_MS=$(date +%s%3N)
  RESPONSE=$(curl -s -L -X POST "$HOST/webapi/entry.cgi?api=SYNO.FileStation.Upload&method=upload&version=2&_sharing_id=%22$SHARING_ID%22" \
    -b "$COOKIE_JAR" \
    -F "overwrite=\"true\"" \
    -F "mtime=\"$FILE_LAST_MODIFIED\"" \
    -F "sharing_id=\"$SHARING_ID\"" \
    -F "uploader_name=\"$UPLOADER_NAME\"" \
    -F "size=\"$FILE_SIZE\"" \
    -F "file=@\"$FILE\"")
  END_MS=$(date +%s%3N)
  DURATION_S=$(awk -v ms="$((END_MS - START_MS))" 'BEGIN { printf "%.3f", ms / 1000 }')

  if echo "$RESPONSE" | grep -q '"success" *: *true'; then
    echo "$FILE_SIZE" > "$RESULT_DIR/ok.$$.$RANDOM.$RANDOM"

    SIZE_H=$(human_size "$FILE_SIZE")
    SPEED=$(human_speed "$FILE_SIZE" "$DURATION_S")
    local DONE RUN_BYTES RUN_ELAPSED_S RUN_AVG_SPEED
    DONE=$(find "$RESULT_DIR" -name 'ok.*' -o -name 'fail.*' | wc -l)
    RUN_BYTES=$(cat "$RESULT_DIR"/ok.* 2>/dev/null | awk '{sum+=$1} END{print sum+0}')
    RUN_ELAPSED_S=$(awk -v now_ms="$END_MS" -v start_ms="$UPLOAD_START_MS" 'BEGIN { printf "%.3f", (now_ms - start_ms) / 1000 }')
    RUN_AVG_SPEED=$(human_speed "$RUN_BYTES" "$RUN_ELAPSED_S")

    echo "OK: '$REL_PATH' ($SIZE_H @ $SPEED) [$DONE/$TOTAL done, $(human_size "$RUN_BYTES") uploaded, running avg $RUN_AVG_SPEED]"
  else
    echo "FAILED: '$REL_PATH' -- response: $RESPONSE"
    echo "$REL_PATH" > "$RESULT_DIR/fail.$$.$RANDOM.$RANDOM"
  fi
}

export FOLDER HOST SHARING_ID UPLOADER_NAME COOKIE_JAR RESULT_DIR
export -f upload_one human_size human_speed

# --- Upload every file in parallel ---
TOTAL=$(find "$FOLDER" -type f | wc -l)
if [ "$TOTAL" -eq 0 ]; then
  echo "Nothing to upload."
  exit 0
fi

echo "Found $TOTAL file(s) to upload from '$FOLDER' using $JOBS parallel job(s)..."
export TOTAL UPLOAD_START_MS="$(date +%s%3N)"
find "$FOLDER" -type f -print0 | xargs -0 -P "$JOBS" -I {} bash -c 'upload_one "$1"' _ {}
UPLOAD_END_MS=$(date +%s%3N)

# --- Summary ---
FAILED=$(find "$RESULT_DIR" -name 'fail.*' -type f | wc -l)
SUCCEEDED=$(find "$RESULT_DIR" -name 'ok.*' -type f | wc -l)
TOTAL_BYTES=0
if [ "$SUCCEEDED" -gt 0 ]; then
  TOTAL_BYTES=$(cat "$RESULT_DIR"/ok.* | awk '{sum+=$1} END{print sum+0}')
fi
ELAPSED_S=$(awk -v end_ms="$UPLOAD_END_MS" -v start_ms="$UPLOAD_START_MS" 'BEGIN { printf "%.3f", (end_ms - start_ms) / 1000 }')

echo
echo "Summary:"
echo "  Files uploaded:  $SUCCEEDED / $TOTAL"
echo "  Total size:      $(human_size "$TOTAL_BYTES")"
echo "  Elapsed time:    ${ELAPSED_S}s"
echo "  Average speed:   $(human_speed "$TOTAL_BYTES" "$ELAPSED_S")"

if [ "$FAILED" -gt 0 ]; then
  echo
  echo "$FAILED file(s) failed:"
  cat "$RESULT_DIR"/fail.* | sed 's/^/  - /'
  exit 1
fi