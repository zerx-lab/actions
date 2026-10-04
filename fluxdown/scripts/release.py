#!/usr/bin/env python3
"""Resolve a complete stable FluxDown component release; emit GitHub outputs."""

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

REPO = "zerx-lab/FluxDown"
STABLE_TAG = re.compile(r"v(\d+)\.(\d+)\.(\d+)")


def asset_names(component, version):
    if component == "app":
        return {"x64": f"FluxDown-{version}-linux-x64.tar.gz"}
    return {
        "x64": f"FluxDown-CLI-{version}-linux-x64.tar.gz",
        "arm64": f"FluxDown-CLI-{version}-linux-arm64.tar.gz",
    }


def select_release(releases, component, version=""):
    if version and not STABLE_TAG.fullmatch(f"v{version}"):
        raise ValueError(f"AUR 只接受稳定版本号 X.Y.Z，收到：{version}")
    candidates = []
    for release in releases:
        match = STABLE_TAG.fullmatch(release["tag_name"])
        if not match or release["draft"] or release["prerelease"]:
            continue
        current = release["tag_name"][1:]
        if version and current != version:
            continue
        required = set(asset_names(component, current).values())
        required.add(f"SHA256SUMS-{component}.txt")
        uploaded = {
            asset["name"] for asset in release["assets"]
            if asset["state"] == "uploaded"
        }
        if required <= uploaded:
            candidates.append((tuple(map(int, match.groups())), release))
    if not candidates:
        raise ValueError(f"找不到资产齐全的 {component} 稳定发布：{version or 'latest'}")
    return max(candidates, key=lambda candidate: candidate[0])[1]


def verify_downloads(directory, component, version):
    manifest = directory / f"SHA256SUMS-{component}.txt"
    checksums = {}
    for line in manifest.read_text().splitlines():
        if not line.strip():
            continue
        digest, name = line.split(maxsplit=1)
        name = name.removeprefix("*")
        if not re.fullmatch(r"[0-9a-f]{64}", digest) or name in checksums:
            raise ValueError(f"无效或重复的 SHA256 清单项：{name}")
        checksums[name] = digest
    result = {}
    for arch, name in asset_names(component, version).items():
        digest = hashlib.sha256()
        with (directory / name).open("rb") as archive:
            for chunk in iter(lambda: archive.read(1024 * 1024), b""):
                digest.update(chunk)
        actual = digest.hexdigest()
        if checksums.get(name) != actual:
            raise ValueError(f"{name} 与 {manifest.name} 不一致或缺少校验项")
        result[arch] = actual
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("component", choices=("app", "cli"))
    parser.add_argument("version", nargs="?", default="")
    parser.add_argument("--download-dir", type=Path)
    args = parser.parse_args()
    # 校验输入后才访问 API；手动版本查询不依赖 latest。
    if args.version and not STABLE_TAG.fullmatch(f"v{args.version}"):
        raise ValueError(f"AUR 只接受稳定版本号 X.Y.Z，收到：{args.version}")
    if args.version:
        response = subprocess.check_output([
            "gh", "api", f"repos/{REPO}/releases/tags/v{args.version}",
        ], text=True)
        releases = [json.loads(response)]
    else:
        response = subprocess.check_output([
            "gh", "api", "--paginate", "--slurp",
            f"repos/{REPO}/releases?per_page=100",
        ], text=True)
        releases = [release for page in json.loads(response) for release in page]
    release = select_release(releases, args.component, args.version)
    version = release["tag_name"][1:]
    outputs = {"version": version}
    if args.download_dir:
        args.download_dir.mkdir(parents=True, exist_ok=True)
        command = [
            "gh", "release", "download", release["tag_name"], "--repo", REPO,
            "--dir", str(args.download_dir), "--clobber",
            "--pattern", f"SHA256SUMS-{args.component}.txt",
        ]
        for name in asset_names(args.component, version).values():
            command.extend(("--pattern", name))
        subprocess.run(command, check=True)
        outputs.update(verify_downloads(args.download_dir, args.component, version))
    for key, value in outputs.items():
        print(f"{key}={value}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        sys.exit(f"FluxDown release: {error}")
