cask "umamibar" do
  version "0.1.6"
  sha256 "c905bf03b5d24ffba1800df4944dc0575b1506a08390a772035371c7f8bf7de6"

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
