cask "glance" do
  version "1.0.0"
  sha256 "e7aa562fc928556b8593261f4adf6baf75da4ac8dcc395e25672853c90e0802f"

  url "https://github.com/AllanChen/TempIamges/releases/download/v#{version}/Glance-#{version}.dmg"
  name "Glance"
  desc "macOS menu bar tool for quick text and media preview"
  homepage "https://github.com/AllanChen/TempIamges"

  depends_on macos: ">= :monterey"

  app "Glance.app"
end
