class BateraiSafer < Formula
  desc "Menu bar battery charge limiter for Apple Silicon Macs"
  homepage "https://github.com/lshinkuro/baterai-safer"
  url "https://github.com/lshinkuro/baterai-safer.git", tag: "v0.6.5", revision: "88aff2446d308436c8a4006c10c8255ade13bbca"
  license "MIT"
  head "https://github.com/lshinkuro/baterai-safer.git", branch: "main"

  depends_on arch: :arm64
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    system "scripts/bundle.sh", version.to_s
    prefix.install ".build/Baterai Safer.app"
    bin.install_symlink prefix/"Baterai Safer.app/Contents/MacOS/baterai-safer"
  end

  def caveats
    <<~EOS
      Supaya muncul di Launchpad/Spotlight:
        ln -sf "#{opt_prefix}/Baterai Safer.app" /Applications/

      Sebelum uninstall, kembalikan pengisian normal:
        sudo baterai-safer uninstall-daemon
    EOS
  end

  service do
    # Run from inside the bundle so macOS shows "Baterai Safer" (and its icon) in permission prompts.
    run [opt_prefix/"Baterai Safer.app/Contents/MacOS/baterai-safer"]
    keep_alive false
  end

  test do
    assert_match "selftest ok", shell_output("#{bin}/baterai-safer selftest")
  end
end
