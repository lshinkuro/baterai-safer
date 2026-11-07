class BateraiSafer < Formula
  desc "Menu bar battery charge limiter for Apple Silicon Macs"
  homepage "https://github.com/lshinkuro/baterai-safer"
  url "https://github.com/lshinkuro/baterai-safer/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "SHA256_PLACEHOLDER"
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
