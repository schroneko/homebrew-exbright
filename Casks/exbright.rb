cask "exbright" do
  version "1.2.2"
  sha256 "7830423fa55ce63dcbbff7554d418f2b511bc93bfeff0396288ad56b8173dcae"

  url "https://github.com/schroneko/homebrew-exbright/releases/download/v#{version}/Exbright-#{version}.zip"
  name "Exbright"
  desc "Menu bar app for controlling external display brightness"
  homepage "https://github.com/schroneko/homebrew-exbright"

  app "Exbright.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "/Applications/Exbright.app"],
                   sudo: false
  end

  uninstall quit: "app.externalbrightness.ExternalBrightness"

  zap trash: [
    "~/Library/Preferences/app.externalbrightness.ExternalBrightness.plist",
  ]
end
