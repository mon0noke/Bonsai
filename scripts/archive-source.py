#!/usr/bin/env python3
"""Archive corresponding source and pinned dependencies, preserving Unix links."""
from pathlib import Path
import os
import plistlib
import stat
import sys
import zipfile

root = Path(__file__).resolve().parent.parent
version = plistlib.loads((root / 'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
destination = Path(sys.argv[1]) if len(sys.argv) > 1 else root / f'outputs/Bonsai-{version}-Source.zip'
paths = []
for name in ['Sources', 'Tests', 'Resources', 'scripts', 'docs', 'Vendor',
             'Package.swift', 'LICENSE', 'NOTICE.md', 'README.md', '.gitignore']:
    path = root / name
    paths.extend(sorted(path.rglob('*')) if path.is_dir() else [path])
paths = sorted(path for path in paths if path.is_symlink() or path.is_file())
destination.parent.mkdir(parents=True, exist_ok=True)
with zipfile.ZipFile(destination, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for path in paths:
        name = 'Bonsai-Source/' + path.relative_to(root).as_posix()
        if path.is_symlink():
            target = os.readlink(path)
            # Every framework link must remain within its corresponding source directory.
            resolved = (path.parent / target).resolve()
            assert not os.path.isabs(target) and resolved.is_relative_to(root), path
            info = zipfile.ZipInfo(name)
            info.create_system = 3
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(info, target.encode(), compress_type=zipfile.ZIP_DEFLATED)
        else:
            archive.write(path, name)
with zipfile.ZipFile(destination) as archive:
    assert archive.testzip() is None and len(archive.infolist()) == len(paths)
    for path in paths:
        name = 'Bonsai-Source/' + path.relative_to(root).as_posix()
        expected = os.readlink(path).encode() if path.is_symlink() else path.read_bytes()
        assert archive.read(name) == expected, name
        if path.is_symlink():
            assert stat.S_ISLNK(archive.getinfo(name).external_attr >> 16), name
print(f'PASS source archive: {len(paths)} entries, CRC and every byte/link target verified: {destination}')
