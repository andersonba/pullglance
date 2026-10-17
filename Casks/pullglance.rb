# Homebrew cask for Pullglance, served from this repository as a tap:
#   brew tap andersonba/pullglance https://github.com/andersonba/pullglance
#   brew install --cask andersonba/pullglance/pullglance
# `version` and `sha256` are written by Scripts/release.sh from the zip it uploads to the release.
cask "pullglance" do
  version "0.3.0"
  sha256 "b7effa65fa649a32fc37283778c22a91d6de8bcd0265b33e80f1f03a7796cf86"

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
