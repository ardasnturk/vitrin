# Homebrew cask for Vitrin for Mac.
#
#   brew tap ardasnturk/vitrin https://github.com/ardasnturk/vitrin
#   brew install --cask vitrin
#
# `version` and `sha256` are updated by apps/VitrinMac/scripts/prepare-release.sh.
cask "vitrin" do
  version "2.3.0"
  sha256 "f3355f7b0454bccbbeebfa75a0775eea02f19c0a516d9719b3a70cb7e53a4e6c"

  url "https://github.com/ardasnturk/vitrin/releases/download/v#{version}/Vitrin-#{version}.dmg"
  name "Vitrin"
  desc "App Store Connect panel and store listing pipeline"
  homepage "https://vitrin.ardasnturk.com"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"

  app "Vitrin.app"

  uninstall quit: "com.jastech.vitrin"

  zap trash: [
    "~/Library/Application Support/Vitrin",
    "~/Library/Caches/com.jastech.vitrin",
    "~/Library/HTTPStorages/com.jastech.vitrin",
    "~/Library/Preferences/com.jastech.vitrin.plist",
    "~/Library/Saved Application State/com.jastech.vitrin.savedState",
  ]

  caveats <<~EOS
    App Store Connect needs the asc CLI and your own API key or asc login; the app can
    install asc for you. The store listing pipeline also needs Node.js 22+ and Claude Code.
      https://vitrin.ardasnturk.com
  EOS
end
