# Homebrew Cask

`umamibar.rb` is generated from a published release ZIP and its SHA-256. It is added here by the release workflow's Homebrew update PR. Before the first release, no installable Cask is present; a placeholder checksum would produce a broken installation.

This source repository also serves as a tap:

```sh
brew tap helson-lin/umamibar https://github.com/helson-lin/umamibar
brew install --cask helson-lin/umamibar/umamibar
```

Use these commands after the first release and Cask PR are published/merged. See [release documentation](../docs/RELEASING.md).
