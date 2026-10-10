require "yaml"

# context-map.md「疎結合を守る規則」の依存の向きの表と、各パッケージの package.yml の dependencies を一致させる。
# 表の括弧の注記（PublishedCatalog だけ）は依存先の名前から外して比べる。注記の範囲は
# spec/packwerk/purchasing_uses_only_published_catalog_spec.rb が守る
module DependencyTable
  ROOT = "."
  HEADER = "| パッケージ | 依存してよい先 |"

  # 表の行を { パッケージ => 依存先の集合 } にする。「すべて」はルートパッケージ以外のすべてのパッケージ、「なし」は空にする
  def self.parse(markdown, packages:)
    rows = markdown.lines.drop_while { _1.chomp != HEADER }.drop(2).take_while { _1.start_with?("|") }
    rows.each_with_object({}) do |row, table|
      names, targets = row.split("|").map(&:strip).reject(&:empty?)
      dependencies = dependencies_of(targets, packages:)
      package_names(names).each do |name|
        raise ArgumentError, "表の行が重複している: #{name}" if table.key?(name)

        table[name] = dependencies
      end
    end
  end

  def self.package_names(cell)
    cell == "ルートパッケージ" ? [ ROOT ] : cell.scan(/`([^`]+)`/).flatten.map { "packs/#{_1}" }
  end

  def self.dependencies_of(cell, packages:)
    case cell
    when "すべて" then packages.to_set - [ ROOT ]
    when "なし" then Set.new
    else cell.gsub(/（[^）]*）/, "").scan(/`([^`]+)`/).flatten.map { "packs/#{_1}" }.to_set
    end
  end

  # { パッケージ => package.yml の dependencies の集合 }。ルートパッケージは "." で表す
  def self.declared(root)
    files = [ "package.yml", *Dir.glob("packs/*/package.yml", base: root).sort ]
    files.to_h do |path|
      name = File.dirname(path)
      [ name, (YAML.load_file(File.join(root, path)) || {}).fetch("dependencies", []).to_set ]
    end
  end
end

RSpec.describe "依存の向きの表と package.yml" do
  let(:root) { File.expand_path("../..", __dir__) }
  let(:declared) { DependencyTable.declared(root) }

  it "context-map.md の表のパッケージと依存先が、各 package.yml の dependencies と一致する" do
    markdown = File.read(File.join(root, "docs/architecture/context-map.md"))

    table = DependencyTable.parse(markdown, packages: declared.keys)

    expect(table.keys).to match_array(declared.keys)
    expect(table).to eq(declared)
  end

  it "表の括弧の注記を依存先から外し、「すべて」と「なし」と、1 つのセルの複数のパッケージを読む" do
    markdown = <<~MARKDOWN
      #{DependencyTable::HEADER}
      |---|---|
      | `purchasing` | `platform`、`sales`（`PublishedCatalog` だけ） |
      | `partnerships`・`contracts` | `platform` だけ |
      | `platform` | なし |
      | ルートパッケージ | すべて |

      | 別の表 | 列 |
    MARKDOWN
    packages = %w[. packs/purchasing packs/partnerships packs/contracts packs/platform packs/sales]

    expect(DependencyTable.parse(markdown, packages:)).to eq(
      "packs/purchasing" => Set["packs/platform", "packs/sales"],
      "packs/partnerships" => Set["packs/platform"],
      "packs/contracts" => Set["packs/platform"],
      "packs/platform" => Set[],
      "." => Set["packs/purchasing", "packs/partnerships", "packs/contracts", "packs/platform", "packs/sales"]
    )
  end

  it "同じパッケージの行が 2 つあれば失敗する" do
    markdown = <<~MARKDOWN
      #{DependencyTable::HEADER}
      |---|---|
      | `platform` | なし |
      | `partnerships`・`platform` | なし |
    MARKDOWN

    expect { DependencyTable.parse(markdown, packages: %w[. packs/platform packs/partnerships]) }
      .to raise_error(ArgumentError, /packs\/platform/)
  end
end
