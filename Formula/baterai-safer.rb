class BateraiSafer < Formula
  desc "Menu bar battery charge limiter for Apple Silicon Macs"
  homepage "https://github.com/lshinkuro/baterai-safer"
  url "https://github.com/lshinkuro/baterai-safer/archive/refs/tags/v0.2.0.tar.gz"
  sha256 "2a18e72bf1e90597994d094394c30d546196afdf1bbf7a467ab4f9d5bcc36493"
  license "MIT"
  head "https://github.com/lshinkuro/baterai-safer.git", branch: "main"

  depends_on arch: :arm64
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/baterai-safer"
  end

  service do
    run [opt_bin/"baterai-safer"]
    keep_alive false
  end

  test do
    assert_match "selftest ok", shell_output("#{bin}/baterai-safer selftest")
  end
end
