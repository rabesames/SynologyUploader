# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single bash script, `synology-upload-folder-request.sh`, that uploads all files in a local folder (recursively, in parallel) to a Synology NAS "file request" share via the Synology Web API (`SYNO.Core.Sharing.Login` and `SYNO.FileStation.Upload`). Based on https://github.com/Paul-DS/synology-upload-file-request.

File requests are flat drop boxes on the Synology side — subfolder structure is NOT recreated on the NAS. Every file, regardless of which subfolder it lives in locally, lands directly in the uploader's destination folder.

## Usage

```bash
bash synology-upload-folder-request.sh --host [HOST] --sharing_id [SHARING_ID] --password [PASSWORD] --uploader_name [UPLOADER_NAME] --folder [FOLDER] --jobs [N]
```

- `-H, --host` — NAS host including protocol and port, no trailing slash
- `-S, --sharing_id` — sharing ID provided by Synology
- `-P, --password` — file request password, if one is set (omit to use cookie-only init)
- `-F, --folder` — local folder whose files will be uploaded, recursively but flattened (must exist)
- `-U, --uploader_name` — uploader name reported to Synology
- `-j, --jobs` — parallel upload workers (default: 4)

There is no build, lint, or test tooling in this repo — it's a standalone script meant to be run directly with bash (requires `curl`, `xargs`, and GNU `stat`/`date`, i.e. a Linux-like environment or WSL/Git Bash with coreutils).

## Architecture

The script authenticates once into a shared cookie jar, then uploads every file in a single parallel pass (`upload_one`, via `xargs -P "$JOBS"`). There is no directory-tree pre-creation step — since Synology file requests are flat drop boxes, there's nothing to recreate remotely. File size and mtime (`date -r "$FILE" +%s%3N`) are sent alongside content, with `overwrite=true`.

Key mechanics:
- All shared state (`FOLDER`, `HOST`, `SHARING_ID`, cookie jar path, result dir) is `export`-ed, and `upload_one` is `export -f`'d, since workers run in `xargs`-spawned subshells.
- Failures are recorded as files in a temp `RESULT_DIR` rather than via shared variables, since parallel subshells can't mutate the parent's state — presence of any file there signals failure.
- Cleanup of the cookie jar and result dir is handled by a `trap ... EXIT`.
