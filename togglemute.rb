# typed: true
# frozen_string_literal: true

cask "togglemute" do
  version "1.5"
  sha256 "f6c6c5627d2a1118088184e29eb1df9fa40afac0b5dab060196182fd002cad7d"

  url "https://github.com/satrik/toggleMute/releases/download/#{version}/toggleMute.zip"
  name "togglemute"
  desc "Touch Bar App to mute/unmute the microphone"
  homepage "https://github.com/satrik/toggleMute"

  license "MIT"

  livecheck do
    url :url
    regex(/v?\.?(\d+(?:\.\d+)+)/i)
    strategy :github_latest
  end

  depends_on macos: ">= :mojave"

  app "toggleMute.app"
end
