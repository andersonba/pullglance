# Homebrew cask for Pullglance, served from this repository as a tap:
#   brew tap andersonba/pullglance https://github.com/andersonba/pullglance
#   brew install --cask andersonba/pullglance/pullglance
# `version` and `sha256` are written by Scripts/release.sh from the zip it uploads to the release.
cask "pullglance" do
  version "0.2.0"
  sha256 "ab1ccb18ffa04d6f4ce06aa99793a13e049eba216d8420b3630def722331ab5e"

  url "https://github.com/andersonba/pullglance/releases/download/v#{version}/Pullglance.zip"
  name "Pullglance"
  desc "Pull requests and review requests at a glance, in the menu bar"
  homepage "https://github.com/andersonba/pullglance"

  depends_on macos: :sequoia
  depends_on arch: :arm64
  depends_on formula: "gh"

  # The app updates itself (Sparkle); a plain `brew upgrade` leaves a copy the app already updated alone.
  auto_updates true

  app "Pullglance.app"

  uninstall quit: "com.andersonba.pullglance"

  zap trash: [
    "~/Library/Caches/com.andersonba.pullglance",
    "~/Library/Logs/Pullglance",
    "~/Library/Preferences/com.andersonba.pullglance.plist",
  ]
end
