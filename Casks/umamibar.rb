cask "umamibar" do
  version "0.1.4"
  sha256 "b8da1da4294b3f7f572d1f5ed0f9cd10c5bc0542343020ca0ecbf76928a7d4bc"

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
