cask "exbright" do
  version "1.1.0"
  sha256 "67c2b20041cfba2c1c60b14910809fc7a450fd6e4f6fadb160f2d622ba038ca9"

  url "https://github.com/schroneko/homebrew-exbright/releases/download/v#{version}/ExternalBrightness-#{version}.zip"
  name "ExternalBrightness"
  desc "Menu bar app for controlling external display brightness"
  homepage "https://github.com/schroneko/homebrew-exbright"

  app "ExternalBrightness.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "/Applications/ExternalBrightness.app"],
                   sudo: false
  end

  uninstall quit: "app.externalbrightness.ExternalBrightness"

  zap trash: [
    "~/Library/Preferences/app.externalbrightness.ExternalBrightness.plist",
  ]
end
