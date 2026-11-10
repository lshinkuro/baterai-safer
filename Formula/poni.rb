class Poni < Formula
  desc "Notch & menu bar for Apple Silicon Macs: battery limiter, focus, meetings, notes"
  homepage "https://github.com/lshinkuro/poni"
  url "https://github.com/lshinkuro/poni.git", tag: "v0.18.0", revision: "b11c4ab406bffe7dde59161419a285a5e08a131d"
  license "MIT"
  head "https://github.com/lshinkuro/poni.git", branch: "main"

  depends_on arch: :arm64
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    system "scripts/bundle.sh", version.to_s
    prefix.install ".build/Poni.app"
    bin.install_symlink prefix/"Poni.app/Contents/MacOS/baterai-safer" => "poni"
  end

  def caveats
    <<~EOS
      Supaya muncul di Launchpad/Spotlight:
        ln -sf "#{opt_prefix}/Poni.app" /Applications/

      Sebelum uninstall, kembalikan pengisian normal:
        sudo poni uninstall-daemon
    EOS
  end

  service do
    # Run from inside the bundle so macOS shows "Poni" (and its icon) in permission prompts.
    run [opt_prefix/"Poni.app/Contents/MacOS/baterai-safer"]
    keep_alive false
  end

  test do
    assert_match "selftest ok", shell_output("#{bin}/poni selftest")
  end
end
