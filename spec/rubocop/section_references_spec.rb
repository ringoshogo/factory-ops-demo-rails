require "open3"

# コメントや文書が「<文書>.md「<節>」」の形で指す節が、その文書の見出しにあることを確かめる（docs/guides/comments.md「書くこと」）。
# 見出しを変えた人が参照を直し忘れると、grep で根拠を引けなくなる。見出しは全体のほか、「：」で区切った前と後のどちらで指してもよい。
# ファイル名はバッククォートで囲んでもよい。ほかのリポジトリの文書（このリポジトリに無いディレクトリの下の文書）は確かめない。
# 同じ名前の文書が複数あれば（README.md と deploy/README.md）、パスの全体が一致する文書を指す。
# 証跡と台帳（docs/plans/）はその時点の記録なので見ない。Markdown のコードブロックと、拾い方の見本を持つこの spec は、悪い例を含むので見ない。
RSpec.describe "節の参照" do
  root = File.expand_path("../..", __dir__)
  reference = /([\w.\/-]+\.md)`?((?:「[^」]+」)+)/

  # 文書のパスから、その文書の見出しで指せる名前の一覧を引く
  section_names = lambda do |docs|
    docs.to_h do |path, text|
      names = text.lines(chomp: true).grep(/\A#+ /).flat_map do |line|
        heading = line.sub(/\A#+\s+/, "")
        [ heading, *heading.split("：") ]
      end
      [ path, names ]
    end
  end

  # 参照に書いた文書の名前（相対のパスや、docs/ を省いたパスでもよい）に当たる文書のパス。パスの全体が一致する文書があれば、それだけを返す
  documents_for = lambda do |doc, names|
    target = doc.sub(%r{\A(\.\./)+}, "")
    candidates = names.keys.select { |path| path == target || path.end_with?("/#{target}") }
    candidates.include?(target) ? [ target ] : candidates
  end

  # 参照を拾い、見出しに無い節を「ファイル:行 文書「節」」の形で返す
  broken_references = lambda do |files, names|
    directories = files.keys.filter_map { |path| path.split("/").first if path.include?("/") }.uniq
    files.flat_map do |path, text|
      in_fence = false
      text.each_line.with_index(1).flat_map do |line, lineno|
        if path.end_with?(".md") && line.start_with?("```")
          in_fence = !in_fence
          next []
        end
        next [] if in_fence

        line.scan(reference).flat_map do |doc, sections|
          segments = doc.delete_prefix("../").split("/")
          next [] if segments.size > 1 && !directories.include?(segments.first)

          candidates = documents_for.call(doc, names)
          next [ "#{path}:#{lineno} #{doc}（文書が無い）" ] if candidates.empty?

          known = candidates.flat_map { names[_1] }

          sections.scan(/「([^」]+)」/).flatten.reject { |section| known.include?(section) }
            .map { |section| "#{path}:#{lineno} #{doc}「#{section}」" }
        end
      end
    end
  end

  it "リポジトリの参照は、すべて実在の見出しを指す" do
    tracked, status = Open3.capture2("git", "-C", root, "ls-files", "-z")
    expect(status).to be_success

    texts = tracked.split("\0").reject { |path| path.start_with?("docs/plans/") || path == "spec/rubocop/section_references_spec.rb" }.filter_map do |path|
      full = File.join(root, path)
      next unless File.file?(full)

      text = File.binread(full).force_encoding(Encoding::UTF_8)
      [ path, text ] if text.valid_encoding? && !text.include?("\0")
    end.to_h
    docs = texts.select { |path, _| path.end_with?(".md") }

    expect(broken_references.call(texts, section_names.call(docs))).to be_empty
  end

  it "見出しに無い節・「：」の前後にも当たらない節・無い文書を拾い、コードブロックの中は見ない" do
    docs = { "docs/architecture/data-model.md" => "# データモデル\n\n## テナントの持ち方：全テーブルに共通の規則\n\n### 在庫（`inventory`）\n" }
    files = {
      "app/a.rb" => <<~RUBY,
        # 在庫の行（docs/architecture/data-model.md「在庫（`inventory`）」「全テーブルに共通の規則」「テナントの持ち方」）
        # 在庫の行（docs/architecture/data-model.md「在庫」）
        # 無い文書（docs/architecture/nothing.md「節」）と、ほかのリポジトリの文書（流用元の handbook/README.md「節」）
      RUBY
      "docs/guides/b.md" => "`data-model.md`「出荷」\n```ruby\n# ✗ data-model.md「状態は…」\n```\n"
    }

    expect(broken_references.call(files, section_names.call(docs))).to eq(
      [
        "app/a.rb:2 docs/architecture/data-model.md「在庫」",
        "app/a.rb:3 docs/architecture/nothing.md（文書が無い）",
        "docs/guides/b.md:1 data-model.md「出荷」"
      ]
    )
  end

  it "同じ名前の文書は、パスの全体が一致する文書の見出しで確かめる" do
    docs = { "README.md" => "# 説明\n\n## 開発環境\n", "deploy/README.md" => "# 配置\n\n## Secret\n" }
    files = {
      "app/a.rb" => "# README.md「開発環境」 deploy/README.md「Secret」\n# README.md「Secret」 deploy/README.md「開発環境」\n",
      "deploy/kustomization.yaml" => ""
    }

    expect(broken_references.call(files, section_names.call(docs))).to eq([ "app/a.rb:2 README.md「Secret」", "app/a.rb:2 deploy/README.md「開発環境」" ])
  end
end
