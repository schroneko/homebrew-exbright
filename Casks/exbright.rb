cask "exbright" do
  version "1.2.3"
  sha256 "971f31c9bd0fa200788de901a8c8fbf4b1925b2286d04411f08edea3349e1258"

  url "https://github.com/schroneko/homebrew-exbright/releases/download/v#{version}/Exbright-#{version}.zip"
  name "Exbright"
  desc "Menu bar app for controlling external display brightness"
  homepage "https://github.com/schroneko/homebrew-exbright"

  app "Exbright.app"

  postflight_steps do
    run "/usr/bin/xattr",
        args: ["-dr", "com.apple.quarantine", "/Applications/Exbright.app"],
        sudo: false
  end

  uninstall quit: "app.externalbrightness.ExternalBrightness"

  zap trash: [
    "~/Library/Preferences/app.externalbrightness.ExternalBrightness.plist",
  ]
end
