# SPDX-License-Identifier: AGPL-3.0-or-later
"""Package a device .app into an IPA while preserving executable modes and symlinks."""
import argparse
import os
from pathlib import Path
import plistlib
import stat
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


def package(app: Path, ipa: Path) -> None:
    if app.suffix != ".app" or not app.is_dir():
        raise ValueError("Select a compiled iOS .app directory")
    with (app / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    executable = info.get("CFBundleExecutable")
    if not executable or not (app / executable).is_file():
        raise ValueError("App bundle is missing CFBundleExecutable")
    if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
        raise ValueError("Expected a device build (iPhoneOS)")
    if (app / "embedded.mobileprovision").exists() or (app / "_CodeSignature").exists():
        raise ValueError("Expected the app from flutter build ios --no-codesign")

    ipa.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(ipa, "w", compression=ZIP_DEFLATED) as archive:
        for entry in sorted(app.rglob("*")):
            name = (Path("Payload") / app.name / entry.relative_to(app)).as_posix()
            if entry.is_symlink():
                link = ZipInfo(name)
                link.create_system = 3
                link.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(link, os.fsencode(os.readlink(entry)))
            else:
                archive.write(entry, name)
    with ZipFile(ipa) as archive:
        invalid = archive.testzip()
        if invalid is not None:
            raise ValueError(f"Invalid IPA entry: {invalid}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("ipa", type=Path)
    args = parser.parse_args()
    package(args.app, args.ipa)
