cask "exbright" do
  version "1.2.0"
  sha256 "54aa740e873a7de8f084e7b33505627fb14c5fec85257f7998c4305ffb63143c"

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
