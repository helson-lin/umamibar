cask "umamibar" do
  version "0.1.0"
  sha256 "759f928ebff076f74fab693154e3a07e7a11cf5e1d68c9cd0d0d7a5c4b33ba81"

  url "https://github.com/helson-lin/umamibar/releases/download/v#{version}/UmamiBar-#{version}-universal.zip"
  name "UmamiBar"
  desc "Native Umami analytics for your macOS menu bar"
  homepage "https://github.com/helson-lin/umamibar"

  depends_on macos: ">= :catalina"

  app "UmamiBar.app"

  zap trash: "~/Library/Preferences/app.umamibar.plist"

  caveats <<~EOS
    This development build is ad-hoc signed and is not notarized by Apple.
    macOS may prevent it from opening. No security settings are changed by this cask.
    Removing preferences does not delete the API key stored in macOS Keychain.
  EOS
end
