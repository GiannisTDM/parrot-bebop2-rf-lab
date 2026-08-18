#!/usr/bin/env python3
"""Extract Parrot PLF filesystem entries using only the Python standard library."""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import struct
import sys
import zlib


HEADER = struct.Struct("<4s13I")
SECTION = struct.Struct("<5I")


def safe_relative_path(raw_name: bytes) -> Path:
    name = raw_name.decode("utf-8", errors="surrogateescape")
    parts = [part for part in PurePosixPath(name).parts if part not in ("", "/", ".")]
    if not parts or ".." in parts:
        raise ValueError(f"unsafe PLF path: {name!r}")
    return Path(*parts)


def replace_path(path: Path) -> None:
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("plf", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    blob = args.plf.read_bytes()
    if len(blob) < HEADER.size:
        raise ValueError("file is shorter than the PLF header")

    fields = HEADER.unpack_from(blob)
    magic = fields[0]
    if magic != b"PLF!":
        raise ValueError("not a PLF file")

    (
        header_version,
        header_length,
        entry_header_length,
        file_type,
        entry_point,
        target_platform,
        target_application,
        hardware_compatibility,
        version_major,
        version_minor,
        version_bugfix,
        language_zone,
        declared_file_length,
    ) = fields[1:]

    if entry_header_length != SECTION.size:
        raise ValueError(f"unsupported section header length: {entry_header_length}")
    if header_length < HEADER.size or header_length > len(blob):
        raise ValueError(f"invalid PLF header length: {header_length}")

    rootfs = args.output / "rootfs"
    data_root = args.output / "data"
    partitions_root = args.output / "partitions"
    # PLFs contain many directory symlinks. Reusing an old extraction tree can
    # make a later file entry traverse one of those links, so rebuild only the
    # extractor-owned subdirectories before processing any sections.
    for owned_tree in (rootfs, data_root, partitions_root):
        replace_path(owned_tree)
    rootfs.mkdir(parents=True, exist_ok=True)
    data_root.mkdir(parents=True, exist_ok=True)
    partitions_root.mkdir(parents=True, exist_ok=True)

    manifest: list[dict[str, object]] = []
    section_rows: list[dict[str, object]] = []
    offset = header_length
    section_number = 0
    limit = min(declared_file_length, len(blob))

    while offset + SECTION.size <= limit:
        section_number += 1
        section_type, section_length, crc32, load_address, uncompressed_size = SECTION.unpack_from(blob, offset)
        data_offset = offset + SECTION.size
        data_end = data_offset + section_length
        if data_end > limit:
            raise ValueError(f"section {section_number} extends beyond the declared PLF length")

        stored_data = blob[data_offset:data_end]
        payload = gzip.decompress(stored_data) if uncompressed_size else stored_data
        if uncompressed_size and len(payload) != uncompressed_size:
            raise ValueError(
                f"section {section_number}: expected {uncompressed_size} decompressed bytes, got {len(payload)}"
            )

        row = {
            "number": section_number,
            "type": section_type,
            "offset": offset,
            "stored_size": section_length,
            "uncompressed_size": len(payload),
            "compressed": bool(uncompressed_size),
            "header_crc32": f"{crc32:08x}",
            "stored_crc32": f"{zlib.crc32(stored_data) & 0xffffffff:08x}",
            "load_address": f"0x{load_address:08x}",
        }

        if section_type in (4, 5, 9):
            raw_name, separator, entry_data = payload.partition(b"\0")
            if separator and raw_name:
                try:
                    relative = safe_relative_path(raw_name)
                except ValueError as exc:
                    row["error"] = str(exc)
                else:
                    if section_type == 9:
                        if len(entry_data) < 12:
                            row["error"] = "filesystem entry metadata is truncated"
                        else:
                            mode = int.from_bytes(entry_data[:4], "little")
                            kind = stat.S_IFMT(mode)
                            content = entry_data[12:]
                            path = rootfs / relative
                            path.parent.mkdir(parents=True, exist_ok=True)

                            if kind == stat.S_IFDIR:
                                path.mkdir(parents=True, exist_ok=True)
                                entry_kind = "directory"
                            elif kind == stat.S_IFREG:
                                replace_path(path)
                                path.write_bytes(content)
                                os.chmod(path, stat.S_IMODE(mode))
                                entry_kind = "file"
                            elif kind == stat.S_IFLNK:
                                target = content.split(b"\0", 1)[0].decode("utf-8", errors="surrogateescape")
                                replace_path(path)
                                path.symlink_to(target)
                                entry_kind = "symlink"
                            else:
                                entry_kind = f"special-{kind:#x}"

                            row["path"] = relative.as_posix()
                            row["entry_kind"] = entry_kind
                            row["mode"] = f"{mode:#06o}"
                            manifest.append(
                                {
                                    "path": relative.as_posix(),
                                    "kind": entry_kind,
                                    "mode": f"{mode:#06o}",
                                    "size": len(content),
                                    "sha256": hashlib.sha256(content).hexdigest()
                                    if entry_kind == "file"
                                    else None,
                                    "section": section_number,
                                }
                            )
                    else:
                        path = data_root / relative
                        if section_type == 5:
                            path.mkdir(parents=True, exist_ok=True)
                            row["entry_kind"] = "directory"
                        else:
                            path.parent.mkdir(parents=True, exist_ok=True)
                            replace_path(path)
                            path.write_bytes(entry_data)
                            row["entry_kind"] = "file"
                        row["path"] = relative.as_posix()
        elif section_type != 11:
            path = partitions_root / f"section-{section_number:05d}-type-{section_type}.bin"
            path.write_bytes(payload)
            row["path"] = str(path.relative_to(args.output))

        section_rows.append(row)
        offset = data_end + (-section_length % 4)

    metadata = {
        "source": str(args.plf.resolve()),
        "source_sha256": hashlib.sha256(blob).hexdigest(),
        "actual_file_length": len(blob),
        "header_version": header_version,
        "header_length": header_length,
        "entry_header_length": entry_header_length,
        "file_type": file_type,
        "entry_point": f"0x{entry_point:08x}",
        "target_platform": target_platform,
        "target_application": target_application,
        "hardware_compatibility": hardware_compatibility,
        "version": f"{version_major}.{version_minor}.{version_bugfix}",
        "language_zone": language_zone,
        "declared_file_length": declared_file_length,
        "section_count": section_number,
        "filesystem_entry_count": len(manifest),
    }
    (args.output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    (args.output / "sections.json").write_text(json.dumps(section_rows, indent=2) + "\n")
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    print(json.dumps(metadata, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, gzip.BadGzipFile) as exc:
        print(f"extract_plf.py: {exc}", file=sys.stderr)
        raise SystemExit(1)
