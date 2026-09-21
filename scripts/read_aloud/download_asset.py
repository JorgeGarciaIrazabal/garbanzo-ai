"""Download a public pinned Hugging Face asset in verified HTTP ranges.

Only complete, SHA-256-verified files are placed in the Hugging Face cache.
Each range is retained under .ai/local to make interrupted downloads resumable.
"""

import argparse
import concurrent.futures
import hashlib
import os
import re
import time
from pathlib import Path

import requests


def download(repo, revision, filename, cache, workers, seed=None):
    url = f"https://huggingface.co/{repo}/resolve/{revision}/{filename}"
    response = requests.head(url, timeout=20)
    response.raise_for_status()
    length = int(response.headers["x-linked-size"])
    digest = response.headers["x-linked-etag"].strip('"')
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("Asset does not advertise a SHA-256 digest")
    if response.headers["x-repo-commit"] != revision:
        raise ValueError("Resolved revision changed")
    repository_cache = cache / "hub" / ("models--" + repo.replace("/", "--"))
    blob = repository_cache / "blobs" / digest
    pointer = repository_cache / "snapshots" / revision / filename
    valid_cache = False
    if blob.is_file():
        with blob.open("rb") as cached:
            valid_cache = hashlib.file_digest(cached, "sha256").hexdigest() == digest
    if valid_cache:
        print(f"Verified cached asset: {blob}")
    else:
        parts = repository_cache / "ranges" / digest
        parts.mkdir(parents=True, exist_ok=True)
        size = 8 * 1024 * 1024
        count = (length + size - 1) // size
        if seed is not None:
            if not seed.is_file() or seed.stat().st_size > length:
                raise ValueError("Seed must be an existing partial file for this asset")
            with seed.open("rb") as source:
                for index in range(seed.stat().st_size // size):
                    path = parts / f"{index:06d}.part"
                    if not path.is_file() or path.stat().st_size != size:
                        path.write_bytes(source.read(size))
                    else:
                        source.seek(size, 1)

        def fetch(index):
            start = index * size
            end = min(start + size, length) - 1
            path = parts / f"{index:06d}.part"
            expected = end - start + 1
            if path.is_file() and path.stat().st_size == expected:
                return
            for attempt in range(4):
                try:
                    with requests.get(
                        url,
                        headers={"Range": f"bytes={start}-{end}"},
                        stream=True,
                        timeout=(20, 90),
                    ) as response:
                        response.raise_for_status()
                        if (
                            response.status_code != 206
                            or response.headers.get("content-range")
                            != f"bytes {start}-{end}/{length}"
                        ):
                            raise RuntimeError("Server did not honor the requested byte range")
                        temporary = path.with_suffix(".tmp")
                        with temporary.open("wb") as target:
                            for chunk in response.iter_content(chunk_size=1024 * 1024):
                                target.write(chunk)
                        if temporary.stat().st_size != expected:
                            raise RuntimeError("Downloaded range has the wrong size")
                        temporary.replace(path)
                        return
                except (requests.RequestException, RuntimeError):
                    if attempt == 3:
                        raise
                    time.sleep(2**attempt)

        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            list(pool.map(fetch, range(count)))
        temporary_blob = blob.with_suffix(".assembling")
        blob.parent.mkdir(parents=True, exist_ok=True)
        hasher = hashlib.sha256()
        with temporary_blob.open("wb") as target:
            for index in range(count):
                with (parts / f"{index:06d}.part").open("rb") as source:
                    while chunk := source.read(1024 * 1024):
                        target.write(chunk)
                        hasher.update(chunk)
        if temporary_blob.stat().st_size != length or hasher.hexdigest() != digest:
            temporary_blob.unlink()
            for path in parts.glob("*.part"):
                path.unlink()
            raise RuntimeError("Final asset size or SHA-256 does not match the pinned source")
        temporary_blob.replace(blob)
        for path in parts.glob("*.part"):
            path.unlink()
        parts.rmdir()
        print(f"Verified downloaded asset: {blob}")
    pointer.parent.mkdir(parents=True, exist_ok=True)
    if pointer.is_symlink():
        if pointer.resolve(strict=False) != blob.resolve():
            pointer.unlink()
    elif pointer.exists():
        raise RuntimeError("Snapshot pointer is a regular file; refusing to overwrite it")
    if not pointer.is_symlink():
        pointer.symlink_to(os.path.relpath(blob, pointer.parent))
    return pointer


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("repo")
    parser.add_argument("revision")
    parser.add_argument("filename")
    parser.add_argument("--cache", type=Path, default=Path.home() / ".cache/huggingface")
    parser.add_argument("--workers", type=int, default=8)
    parser.add_argument("--seed", type=Path)
    args = parser.parse_args()
    if args.workers < 1 or args.workers > 16:
        parser.error("workers must be between 1 and 16")
    print(download(args.repo, args.revision, args.filename, args.cache, args.workers, args.seed))


if __name__ == "__main__":
    main()
