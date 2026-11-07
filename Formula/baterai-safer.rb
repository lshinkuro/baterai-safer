# Baterai Safer is now Poni. This formula stays so existing installs keep upgrading: it builds Poni,
# and keeps "Baterai Safer.app" and the baterai-safer command as links, because the helper daemon
# and v0.6.10's updater use those paths. New installs: brew install poni.
class BateraiSafer < Formula
  desc "Now called Poni (brew install poni)"
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
    prefix.install_symlink "Poni.app" => "Baterai Safer.app"
    bin.install_symlink prefix/"Poni.app/Contents/MacOS/baterai-safer"
    bin.install_symlink prefix/"Poni.app/Contents/MacOS/baterai-safer" => "poni"
  end

  def caveats
    <<~EOS
      Baterai Safer sekarang bernama Poni. Aplikasi tetap terupdate lewat formula ini.

      Supaya muncul di Launchpad/Spotlight:
        ln -sf "#{opt_prefix}/Poni.app" /Applications/

      Sebelum uninstall, kembalikan pengisian normal:
        sudo poni uninstall-daemon
    EOS
  end

  service do
    run [opt_prefix/"Poni.app/Contents/MacOS/baterai-safer"]
    keep_alive false
  end

  test do
    assert_match "selftest ok", shell_output("#{bin}/poni selftest")
  end
end
