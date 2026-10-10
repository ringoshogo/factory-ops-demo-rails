require "open3"

# rubocop-rails は bin/* を RuboCop の対象から外すので、bin/ の Ruby のスクリプトのコメントの規約は、Cop を名指しして確かめる
# （docs/guides/comments.md「機械で止めるもの」）。シェルのスクリプトは Cop が読めないので見ない
RSpec.describe "bin/ の Ruby のスクリプトのコメント" do
  root = File.expand_path("../..", __dir__)
  scripts = Dir[File.join(root, "bin/*")].sort.select do |path|
    File.file?(path) && File.open(path, &:gets).to_s.match?(/\A#!.*\bruby\b/)
  end

  it "Ruby のスクリプトを拾う" do
    expect(scripts.map { |path| File.basename(path) }).to include("check-open-items", "test-layers", "check-schema-compat")
  end

  it "経緯・マイルストーンの番号・予定を書かない" do
    output, status = Open3.capture2e(File.join(root, "bin/rubocop"), "--only", "FactoryOps/NoHistoryComment", "--format", "emacs", *scripts, chdir: root)

    expect(status).to be_success, output
  end
end
