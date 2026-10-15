#!/usr/bin/env python3
"""Generate a concrete Cask from a release ZIP; never use placeholder checksums."""
import argparse
import hashlib
import re
from pathlib import Path


def render(repository: str, version: str, digest: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+", repository):
        raise ValueError("Expected GitHub owner/repository")
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Expected stable version X.Y.Z")
    if not re.fullmatch(r"[0-9a-f]{64}", digest):
        raise ValueError("Invalid SHA-256")
    return f'''cask "umamibar" do
  version "{version}"
  sha256 "{digest}"

  url "https://github.com/{repository}/releases/download/v#{{version}}/UmamiBar-#{{version}}-universal.zip"
  name "UmamiBar"
  desc "Native Umami analytics for your macOS menu bar"
  homepage "https://github.com/{repository}"

  depends_on macos: ">= :catalina"

  app "UmamiBar.app"

  zap trash: "~/Library/Preferences/app.umamibar.plist"

  caveats <<~EOS
    This development build is ad-hoc signed and is not notarized by Apple.
    macOS may prevent it from opening. No security settings are changed by this cask.
    Removing preferences does not delete the API key stored in macOS Keychain.
  EOS
end
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=Path("dist/umamibar.rb"))
    args = parser.parse_args()
    digest = hashlib.sha256(args.archive.read_bytes()).hexdigest()
    output = render(args.repository, args.version, digest)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(output)
    print(f"Generated {args.output} (SHA-256 {digest})")


if __name__ == "__main__":
    main()
