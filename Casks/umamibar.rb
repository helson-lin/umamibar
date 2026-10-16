cask "umamibar" do
  version "0.1.2"
  sha256 "e05e36bf619b60b5b3756ca2b9b0760f8dc0752e083239fe38f67daa252e7dc8"

  url "https://github.com/helson-lin/umamibar/releases/download/v#{version}/UmamiBar-#{version}-universal.zip"
  name "UmamiBar"
  desc "Native Umami analytics for your macOS menu bar"
  homepage "https://github.com/helson-lin/umamibar"

  depends_on :macos

  app "UmamiBar.app"

  zap trash: "~/Library/Preferences/app.umamibar.plist"

  caveats <<~EOS
    This release is Developer ID signed and notarized by Apple.
    macOS may prevent it from opening. No security settings are changed by this cask.
    Removing preferences does not delete the API key stored in macOS Keychain.
  EOS
end
