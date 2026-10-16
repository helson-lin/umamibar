cask "umamibar" do
  version "0.1.1"
  sha256 "20329054e585cee30038dca3eea75111a1fa6dc12027ed9b2ae13caf7c4e06f4"

  url "https://github.com/helson-lin/umamibar/releases/download/v#{version}/UmamiBar-#{version}-universal.zip"
  name "UmamiBar"
  desc "Native Umami analytics for your macOS menu bar"
  homepage "https://github.com/helson-lin/umamibar"

  depends_on macos: ">= :catalina"

  app "UmamiBar.app"

  zap trash: "~/Library/Preferences/app.umamibar.plist"

  caveats <<~EOS
    This release is Developer ID signed and notarized by Apple.
    macOS may prevent it from opening. No security settings are changed by this cask.
    Removing preferences does not delete the API key stored in macOS Keychain.
  EOS
end
