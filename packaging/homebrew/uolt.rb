# Homebrew formula for UOLT. Copy this into your tap repository
# (github.com/thooams/homebrew-tap as Formula/uolt.rb), then:
#
#   brew install thooams/tap/uolt
#
# The binaries install as `uolt-<name>` (e.g. uolt-cat), so they never silently
# shadow your system coreutils. To use them as a POSIX shadow, put symlinks
# without the prefix earlier on your PATH (see the project README).
class Uolt < Formula
  desc "34 Unix tools in x86_64 assembly: no libc, no heap, direct syscalls"
  homepage "https://github.com/thooams/uolt"
  url "https://github.com/thooams/uolt/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "9cfdbdefa998abff76ad3e58f8dce1102ae3632b38568c2a6d4458cdb4d21520"
  license "MIT"

  # The sources are x86_64 assembly; arm64 is planned but not supported yet.
  on_arm do
    odie "uolt is x86_64-only for now (arm64 is planned)"
  end

  # macOS uses the clang from the Command Line Tools; on Linux, pull in clang.
  on_linux do
    depends_on "llvm" => :build
  end

  def install
    system "make"
    Dir["build/uolt-*"].each { |f| bin.install f }
    bin.install_symlink "uolt-test" => "uolt-["
  end

  test do
    assert_equal "hello", shell_output("#{bin}/uolt-echo hello").strip
    assert_equal "3", shell_output("printf 'a b c\\n' | #{bin}/uolt-wc -w").strip
    system "#{bin}/uolt-true"
  end
end
