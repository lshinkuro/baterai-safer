class Poni < Formula
  desc "Notch & menu bar for Apple Silicon Macs: battery limiter, focus, meetings, notes"
  homepage "https://github.com/lshinkuro/poni"
  url "https://github.com/lshinkuro/poni.git", tag: "v0.7.0", revision: "8cf00a2ff032385e72a0a994c4c6cec3ba8995e1"
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
