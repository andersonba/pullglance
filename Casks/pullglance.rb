# Homebrew cask for Pullglance, served from this repository as a tap:
#   brew tap andersonba/pullglance https://github.com/andersonba/pullglance
#   brew install --cask andersonba/pullglance/pullglance
# `version` and `sha256` are written by Scripts/release.sh from the zip it uploads to the release.
cask "pullglance" do
  version "0.1.1"
  sha256 "0f5546f970fd86b2607f95414704e15239c9e627b422a9e2ddfafcf0118c7ded"

  url "https://github.com/andersonba/pullglance/releases/download/v#{version}/Pullglance.zip"
  name "Pullglance"
  desc "Pull requests and review requests at a glance, in the menu bar"
  homepage "https://github.com/andersonba/pullglance"

  depends_on macos: :sequoia
  depends_on arch: :arm64
  depends_on formula: "gh"

  app "Pullglance.app"

  uninstall quit: "com.andersonba.pullglance"

  zap trash: [
    "~/Library/Caches/com.andersonba.pullglance",
    "~/Library/Logs/Pullglance",
    "~/Library/Preferences/com.andersonba.pullglance.plist",
  ]
end
