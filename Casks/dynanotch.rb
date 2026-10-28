# Homebrew cask for DynaNotch. The repository is its own tap:
#
#   brew tap tanim-ics/dyna-notch https://github.com/tanim-ics/dyna-notch.git
#   brew install --cask tanim-ics/dyna-notch/dynanotch
#
# The zip comes from scripts/release.sh (which also fills in version and sha256). The app is ad hoc signed with a
# stable identifier requirement, not notarised, so the postflight clears the download quarantine — otherwise
# Gatekeeper refuses to open it.
cask "dynanotch" do
  version "3.2.0"
  sha256 "2b626d2d20f8fe0980c8a1cf31dac7aa92d79b4825c510287f0f5b5b68d88814"

  url "https://github.com/tanim-ics/dyna-notch/releases/download/v#{version}/DynaNotch-#{version}.zip"
  name "DynaNotch"
  desc "Dynamic Island for the notch"
  homepage "https://github.com/tanim-ics/dyna-notch"

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
