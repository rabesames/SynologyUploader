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

# --- Worker: upload a single file (flat, into the request destination) ---
upload_one() {
  local FILE="$1"
  local REL_PATH="${FILE#"$FOLDER"/}"
  local FILE_SIZE FILE_LAST_MODIFIED RESPONSE
  FILE_SIZE=$(stat --printf="%s" "$FILE")
  FILE_LAST_MODIFIED=$(date -r "$FILE" +%s%3N)

  echo "Uploading '$REL_PATH'..."

  RESPONSE=$(curl -s -L -X POST "$HOST/webapi/entry.cgi?api=SYNO.FileStation.Upload&method=upload&version=2&_sharing_id=%22$SHARING_ID%22" \
    -b "$COOKIE_JAR" \
    -F "overwrite=\"true\"" \
    -F "mtime=\"$FILE_LAST_MODIFIED\"" \
    -F "sharing_id=\"$SHARING_ID\"" \
    -F "uploader_name=\"$UPLOADER_NAME\"" \
    -F "size=\"$FILE_SIZE\"" \
    -F "file=@\"$FILE\"")

  if echo "$RESPONSE" | grep -q '"success" *: *true'; then
    echo "OK: '$REL_PATH'"
  else
    echo "FAILED: '$REL_PATH' -- response: $RESPONSE"
    echo "$REL_PATH" > "$RESULT_DIR/fail.$$.$RANDOM.$RANDOM"
  fi
}

export FOLDER HOST SHARING_ID UPLOADER_NAME COOKIE_JAR RESULT_DIR
export -f upload_one

# --- Upload every file in parallel ---
TOTAL=$(find "$FOLDER" -type f | wc -l)
if [ "$TOTAL" -eq 0 ]; then
  echo "Nothing to upload."
  exit 0
fi

echo "Found $TOTAL file(s) to upload from '$FOLDER' using $JOBS parallel job(s)..."
find "$FOLDER" -type f -print0 | xargs -0 -P "$JOBS" -I {} bash -c 'upload_one "$1"' _ {}

# --- Summary ---
FAILED=$(find "$RESULT_DIR" -type f | wc -l)
echo
if [ "$FAILED" -eq 0 ]; then
  echo "Done. $TOTAL file(s) uploaded successfully."
else
  echo "Done. $((TOTAL - FAILED)) succeeded, $FAILED failed:"
  cat "$RESULT_DIR"/* | sed 's/^/  - /'
  exit 1
fi