# SynologyUploader

Upload all files in a local folder (recursively, in parallel) to a Synology NAS "file request" share, using the Synology Web API. Based on [Paul-DS/synology-upload-file-request](https://github.com/Paul-DS/synology-upload-file-request).

File requests are flat drop boxes on the Synology side, so subfolder structure is **not** recreated remotely — every file, regardless of its local subfolder, lands directly in the uploader's destination folder.

## Requirements

A Linux-like environment with `bash`, `curl`, `xargs`, `awk`, and GNU `stat`/`date` (e.g. Linux, WSL, or Git Bash with coreutils on Windows).

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

## Output

Each successful upload prints its own size and speed, plus a running total across all files uploaded so far:

```
OK: 'IMG_0001.jpg' (2.30 MB @ 4.10 MB/s) [12/50 done, 28.40 MB uploaded, running avg 3.85 MB/s]
```

When all uploads finish, a final summary reports the file count, total size, elapsed time, and average speed:

```
Summary:
  Files uploaded:  50 / 50
  Total size:      118.42 MB
  Elapsed time:    30.712s
  Average speed:   3.86 MB/s
```

If any files failed, they're listed below the summary and the script exits with a non-zero status.
