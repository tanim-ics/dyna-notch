# Homebrew cask for DynaNotch. The repository is its own tap:
#
#   brew tap tanim-ics/dyna-notch https://github.com/tanim-ics/dyna-notch.git
#   brew install --cask tanim-ics/dyna-notch/dynanotch
#
# The zip comes from scripts/release.sh (which also fills in version and sha256). The app is ad hoc signed with a
# stable identifier requirement, not notarised, so the postflight clears the download quarantine — otherwise
# Gatekeeper refuses to open it.
cask "dynanotch" do
  version "3.3.0"
  sha256 "e76526d4e9fb0e812290ad060895a42e0ad9735c72683f81273efb9c360423b2"

  url "https://github.com/tanim-ics/dyna-notch/releases/download/v#{version}/DynaNotch-#{version}.zip"
  name "DynaNotch"
  desc "Dynamic Island for the notch"
  homepage "https://github.com/tanim-ics/dyna-notch"

  # DynaNotch updates itself (Settings → About → Updates); brew upgrade --greedy also works.
  auto_updates true
  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "DynaNotch.app"

  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/DynaNotch.app"]
  end

  uninstall quit: "com.tanim.dynanotch"

  zap trash: [
    "~/Library/Application Support/DynaNotch",
    "~/Library/Caches/com.tanim.dynanotch",
    "~/Library/HTTPStorages/com.tanim.dynanotch",
    "~/Library/Preferences/com.tanim.dynanotch.plist",
  ]

  caveats <<~EOS
    Start DynaNotch with:
      open -a DynaNotch
  EOS
end
