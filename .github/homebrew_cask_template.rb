cask "flclash" do
  version "VERSION"

  sha256 "UNIVERSAL_SHA256"
  url "https://github.com/chen08209/FlClash/releases/download/v#{version}/FlClash-#{version}-macos-universal.pkg"

  name "FlClash"
  desc "Multi-platform proxy client based on ClashMeta"
  homepage "https://github.com/chen08209/FlClash"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on :macos

  pkg "FlClash-#{version}-macos-universal.pkg"

  uninstall quit:    "com.follow.clash",
            pkgutil: "com.follow.clash"

  zap trash: [
    "~/Library/Application Support/com.follow.clash",
    "~/Library/Caches/com.follow.clash",
    "~/Library/Preferences/com.follow.clash.plist",
    "~/Library/Saved Application State/com.follow.clash.savedState",
  ]
end
