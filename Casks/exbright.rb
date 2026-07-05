cask "exbright" do
  version "1.2.1"
  sha256 "ef31f7e0feb4423d34838cc857403a2071e2e0bd6afd42d3b1235f228f94a379"

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
