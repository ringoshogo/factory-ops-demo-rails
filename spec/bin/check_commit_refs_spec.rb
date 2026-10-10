# 台帳と証跡に書いた commit の SHA が HEAD の祖先であることを、bin/check-commit-refs が確かめる（docs/guides/dev-cycle.md「機械で守ること」）
require "open3"
require "tmpdir"
require "fileutils"

RSpec.describe "bin/check-commit-refs" do
  let(:script) { File.expand_path("../../bin/check-commit-refs", __dir__) }

  around do |example|
    Dir.mktmpdir do |dir|
      @root = File.join(dir, "repo")
      git("init", "-q", "-b", "main", @root, root: dir)
      example.run
    end
  end

  def git(*args, root: @root)
    out, status = Open3.capture2e("git", "-C", root, "-c", "user.name=spec", "-c", "user.email=spec@example.com", *args)
    raise out unless status.success?

    out.strip
  end

  def commit(message)
    File.write(File.join(@root, "#{message}.txt"), message)
    git("add", "-A")
    git("commit", "-q", "-m", message)
    git("rev-parse", "--short", "HEAD")
  end

  def write_ledger(text)
    FileUtils.mkdir_p(File.join(@root, "docs/plans"))
    File.write(File.join(@root, "docs/plans/open-items.md"), text)
    git("add", "-A")
    git("commit", "-q", "-m", "ledger")
  end

  def run_check(root = @root)
    Open3.capture3(script, "--root", root)
  end

  it "HEAD の祖先の commit を指す SHA を通す" do
    sha = commit("first")
    write_ledger("| OI-01 | closed | 内容 | 出どころ | M16 | 直した（`#{sha}`） |\n")

    out, err, status = run_check
    expect(err).to eq("")
    expect(status).to be_success
    expect(out).to include("1 件")
  end

  it "どのブランチにも無い SHA と、HEAD の祖先でない commit の SHA を落とす" do
    commit("first")
    git("switch", "-q", "-c", "side")
    side = commit("side")
    git("switch", "-q", "main")
    write_ledger("載せ直す前の `#{side}` と、無い `deadbee`\n")

    _out, err, status = run_check
    expect(status).not_to be_success
    expect(err).to include("#{side} が HEAD の祖先ではない", "deadbee が commit として見つからない")
  end

  it "履歴が浅い clone では、確かめずに失敗する" do
    sha = commit("first")
    commit("second")
    write_ledger("`#{sha}`\n")
    shallow = File.join(File.dirname(@root), "shallow")
    git("clone", "-q", "--depth", "1", "file://#{@root}", shallow, root: File.dirname(@root))

    _out, err, status = run_check(shallow)
    expect(status).not_to be_success
    expect(err).to include("履歴が浅い")
  end
end
