# SynologyUploader

Upload all files in a local folder (recursively, in parallel) to a Synology NAS "file request" share, using the Synology Web API. Based on [Paul-DS/synology-upload-file-request](https://github.com/Paul-DS/synology-upload-file-request).

File requests are flat drop boxes on the Synology side, so subfolder structure is **not** recreated remotely — every file, regardless of its local subfolder, lands directly in the uploader's destination folder.

## Requirements

A Linux-like environment with `bash`, `curl`, `xargs`, and GNU `stat`/`date` (e.g. Linux, WSL, or Git Bash with coreutils on Windows).

## Usage

```bash
bash synology-upload-folder-request.sh --host [HOST] --sharing_id [SHARING_ID] --password [PASSWORD] --uploader_name [UPLOADER_NAME] --folder [FOLDER] --jobs [N]
```

### Options

| Flag | Description |
| --- | --- |
| `-H, --host` | Host name of the Synology NAS, including the protocol (HTTP/HTTPS) and port, without trailing slash |
| `-S, --sharing_id` | Sharing ID provided by Synology |
| `-P, --password` | The password for the file request, if defined |
| `-F, --folder` | The folder whose files will be uploaded, recursively but flattened |
| `-U, --uploader_name` | Uploader name |
| `-j, --jobs` | Number of parallel uploads (default: 4) |

### Example

```bash
bash synology-upload-folder-request.sh \
  --host https://nas.example.com:5001 \
  --sharing_id abcd1234 \
  --uploader_name "Rommel" \
  --folder ./photos \
  --jobs 8
```
