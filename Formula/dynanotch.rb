# Homebrew formula for DynaNotch. The repository is its own tap:
#
#   brew tap tanim-ics/dyna-notch https://github.com/tanim-ics/dyna-notch.git
#   brew install --HEAD dynanotch
#
# Builds from source with build.sh (no tests, no install), so the app keeps the stable ad-hoc signature that lets
# macOS permissions survive upgrades. There is no notarised download, which is why this is a formula and not a cask.
class Dynanotch < Formula
  desc "Dynamic Island for the Mac notch"
  homepage "https://github.com/tanim-ics/dyna-notch"
  license :cannot_represent
  head "https://github.com/tanim-ics/dyna-notch.git", branch: "main"

  depends_on xcode: ["16.0", :build]
  depends_on macos: :sonoma

  # build.sh gives the adapter dylib an @rpath ID; keeping it stops Homebrew from rewriting (and so unsealing) the
  # signed app bundle.
  preserve_rpath

  def install
    # SwiftPM cannot nest its own sandbox inside Homebrew's build sandbox.
    ENV["DYNANOTCH_SWIFTPM_FLAGS"] = "--disable-sandbox"
    system "./build.sh", "--skip-tests", "--no-install"
    prefix.install "build/DynaNotch.app"
    # Strip Gatekeeper quarantine so macOS does not block the ad-hoc-signed bundle on first open.
    system "xattr", "-cr", "#{prefix}/DynaNotch.app"
  end

  def caveats
    <<~EOS
      DynaNotch.app was installed to:
        #{opt_prefix}/DynaNotch.app

      Link it into /Applications, clear Gatekeeper quarantine, and start it:
        ln -sfn #{opt_prefix}/DynaNotch.app /Applications/DynaNotch.app
        xattr -cr /Applications/DynaNotch.app
        open /Applications/DynaNotch.app

      The `xattr -cr` step is required because macOS Gatekeeper blocks ad-hoc-signed
      apps that arrive via Homebrew. If macOS still shows "cannot be opened" after that,
      go to System Settings → Privacy & Security and click "Open Anyway".

      After `brew upgrade --fetch-HEAD dynanotch`, quit DynaNotch, then repeat the
      `xattr -cr` and `open` commands above.
    EOS
  end

  test do
    app = prefix/"DynaNotch.app"
    assert_path_exists app/"Contents/MacOS/DynaNotch"
    system "codesign", "--verify", "--strict", app
  end
end
