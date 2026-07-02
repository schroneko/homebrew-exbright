cask "exbright" do
  version "1.0.1"
  sha256 "d197147cb78a1ba37b7b2fd39f4ef93226d51cd319519f3fcf7e3054e533618f"

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
