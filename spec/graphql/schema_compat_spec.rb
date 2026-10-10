# スキーマの互換の判定が、非推奨を経ない破壊的変更を落とし、例外の一覧に書いた変更だけを通すことを確かめる
# （docs/architecture/graphql-schema.md「スキーマの変更と非推奨」）
require "open3"
require "tmpdir"
require "fileutils"
require_relative "../../lib/schema_compat"

RSpec.describe SchemaCompat do
  let(:fixtures) { File.expand_path("../fixtures/graphql/schema_compat", __dir__) }
  let(:base) { head("base") }

  def head(name) = File.read(File.join(fixtures, "#{name}.graphql"))

  def check(name, exceptions: "[]")
    described_class.check(base_sdl: base, head_sdl: head(name), exceptions: described_class.load_exceptions(exceptions))
  end

  # [変更のクラス名, 座標, 通すか] の組
  def verdicts(name, **options) = check(name, **options).verdicts.map { [ _1.change, _1.path, _1.passed ] }

  describe "削除の変更は、比較器の重大度を見ずに、基準で非推奨だったかで決める" do
    it "非推奨でないフィールドの削除を落とす" do
      expect(verdicts("field_removed")).to eq([ [ "FieldRemoved", "Order.note", false ] ])
      expect(check("field_removed")).not_to be_passed
    end

    it "非推奨でない enum の値の削除を、出力にだけ使う enum でも落とす（比較器は非破壊に分類する）" do
      expect(verdicts("output_enum_value_removed")).to eq([ [ "EnumValueRemoved", "OrderStage.SHIPPED", false ] ])
    end

    it "非推奨でない enum の値の削除を、入力に使う enum で落とす" do
      expect(verdicts("input_enum_value_removed")).to eq([ [ "EnumValueRemoved", "OrderStatus.CLOSED", false ] ])
    end

    it "非推奨のフィールドの削除を通す（比較器は破壊に分類する）" do
      expect(verdicts("deprecated_field_removed")).to eq([ [ "FieldRemoved", "Order.memo", true ] ])
      expect(check("deprecated_field_removed")).to be_passed
    end

    it "非推奨の引数の削除を通す" do
      expect(verdicts("deprecated_argument_removed")).to eq([ [ "FieldArgumentRemoved", "Query.order.includeDrafts", true ] ])
    end

    it "非推奨の入力項目の削除を通す" do
      expect(verdicts("deprecated_input_field_removed")).to eq([ [ "InputFieldRemoved", "PlaceOrderInput.priority", true ] ])
    end

    it "非推奨の enum の値の削除を、入力に使う enum でも出力にだけ使う enum でも通す" do
      expect(verdicts("deprecated_enum_values_removed")).to contain_exactly(
        [ "EnumValueRemoved", "OrderStatus.ARCHIVED", true ],
        [ "EnumValueRemoved", "OrderStage.LOST", true ]
      )
    end

    it "型の削除は、基準でその型を返すフィールドがすべて非推奨なら通す" do
      expect(verdicts("type_removed_with_deprecated_references")).to contain_exactly(
        [ "FieldRemoved", "Query.legacyOrder", true ],
        [ "TypeRemoved", "LegacyOrder", true ]
      )
    end

    it "型の削除は、基準でその型を返す非推奨でないフィールドが 1 つでもあれば落とす" do
      result = check("type_removed_with_live_reference")

      expect(result.verdicts.map { [ _1.change, _1.path, _1.passed ] }).to contain_exactly(
        [ "FieldRemoved", "Order.shipment", false ],
        [ "FieldRemoved", "Order.legacyShipment", true ],
        [ "TypeRemoved", "Shipment", false ]
      )
      reason = result.verdicts.find { _1.change == "TypeRemoved" }.reason
      expect(reason).to include("Order.shipment")
      expect(reason).not_to include("Order.legacyShipment")
    end

    it "型の削除は、その型を含む union を返す非推奨でないフィールドがあれば落とす" do
      result = check("union_member_type_removed")

      expect(result.verdicts.map { [ _1.change, _1.path, _1.passed ] }).to contain_exactly(
        [ "UnionMemberRemoved", "SearchHit", false ],
        [ "TypeRemoved", "Notice", false ]
      )
      expect(result.verdicts.find { _1.change == "TypeRemoved" }.reason).to include("Query.search")
    end
  end

  describe "型の変更は、比較器が非破壊とするものだけを通す" do
    it "フィールドの型の変更を落とす" do
      expect(verdicts("field_type_changed")).to eq([ [ "FieldTypeChanged", "Order.code", false ] ])
    end

    it "非推奨のフィールドでも、型の変更を落とす" do
      expect(verdicts("deprecated_field_type_changed")).to eq([ [ "FieldTypeChanged", "Order.legacyAmount", false ] ])
    end

    it "出力の型を null 可から非 null にする変更を通す" do
      expect(verdicts("output_made_non_null")).to eq([ [ "FieldTypeChanged", "Order.note", true ] ])
    end
  end

  describe "必須の引数・入力項目の追加を落とす" do
    it "必須の引数の追加を落とす" do
      expect(verdicts("required_argument_added")).to eq([ [ "FieldArgumentAdded", "Query.orders.limit", false ] ])
    end

    it "必須の入力項目の追加を落とす" do
      expect(verdicts("required_input_field_added")).to eq([ [ "InputFieldAdded", "PlaceOrderInput.dueOn", false ] ])
    end
  end

  it "危険な変更（出力の enum の値の追加）は、一覧に出して通す" do
    result = check("enum_value_added")

    expect(result.verdicts.map { [ _1.change, _1.path, _1.passed ] }).to eq([ [ "EnumValueAdded", "OrderStage.CANCELLED", true ] ])
    expect(result.report).to include("EnumValueAdded").and include("OrderStage.CANCELLED")
  end

  describe "例外の一覧" do
    it "落とした変更と同じクラス名と座標の行があれば通し、理由を結果に出す" do
      exceptions = <<~YAML
        - change: FieldTypeChanged
          path: Order.code
          reason: 伝票番号を数値に統一する
      YAML

      result = check("field_type_changed", exceptions:)

      expect(result).to be_passed
      expect(result.verdicts.first.reason).to include("伝票番号を数値に統一する")
      expect(result.unmatched_exceptions).to be_empty
    end

    it "非推奨でないフィールドの削除を、例外の行で通す" do
      exceptions = <<~YAML
        - change: FieldRemoved
          path: Order.note
          reason: 備考に他社の担当者の連絡先が入っていた
      YAML

      expect(verdicts("field_removed", exceptions:)).to eq([ [ "FieldRemoved", "Order.note", true ] ])
    end

    it "クラス名か座標の違う行は、その変更を通さず、どの変更にも当たらない行として警告に出す" do
      exceptions = <<~YAML
        - change: FieldTypeChanged
          path: Order.note
          reason: クラス名が違う
        - change: FieldRemoved
          path: Order.code
          reason: 座標が違う
      YAML

      result = check("field_removed", exceptions:)

      expect(result).not_to be_passed
      expect(result.unmatched_exceptions.map(&:reason)).to eq(%w[クラス名が違う 座標が違う])
      expect(result.report).to include("どの変更にも当たらない例外の行")
    end

    it "どの変更にも当たらない行は警告に出すだけで、通る変更の結果を変えない" do
      exceptions = <<~YAML
        - change: FieldRemoved
          path: Order.amount
          reason: 前の PR で消した
      YAML

      result = check("deprecated_field_removed", exceptions:)

      expect(result).to be_passed
      expect(result.unmatched_exceptions.map(&:path)).to eq([ "Order.amount" ])
    end

    it "reason が空の行があれば、読み込みで失敗する" do
      [ "", "  ", nil ].each do |reason|
        exceptions = YAML.dump([ { "change" => "FieldRemoved", "path" => "Order.note", "reason" => reason } ])

        expect { described_class.load_exceptions(exceptions) }.to raise_error(SchemaCompat::InvalidExceptions, /reason/)
      end
    end

    it "空のファイルは、行の無い一覧として読む" do
      expect(described_class.load_exceptions("# 行が無い\n")).to eq([])
    end
  end

  describe "bin/check-schema-compat" do
    let(:script) { File.expand_path("../../bin/check-schema-compat", __dir__) }

    around do |example|
      Dir.mktmpdir do |dir|
        @repo = dir
        example.run
      end
    end

    def git(*args) = Open3.capture3("git", "-c", "user.name=spec", "-c", "user.email=spec@example.com", *args, chdir: @repo).tap { |_out, err, status| raise err unless status.success? }

    def write(path, content)
      FileUtils.mkdir_p(File.dirname(File.join(@repo, path)))
      File.write(File.join(@repo, path), content)
    end

    def commit_base(files)
      git("init", "-q", "-b", "main")
      files.each { |path, content| write(path, content) }
      write("README", "base")
      git("add", "-A")
      git("commit", "-q", "-m", "base")
    end

    def run_script(env = {}) = Open3.capture3({ "BASE_REF" => "main", "GITHUB_STEP_SUMMARY" => nil }.merge(env), script, chdir: @repo)

    it "基準に schema.graphql が無いときは失敗する" do
      commit_base({})
      write("schema.graphql", base)

      out, err, status = run_script

      expect(status.success?).to be(false)
      expect(out + err).to include("main に schema.graphql が無い")
    end

    it "落とす変更があれば失敗し、結果を標準出力と GITHUB_STEP_SUMMARY に書く" do
      commit_base("schema.graphql" => base)
      write("schema.graphql", head("field_removed"))
      summary = File.join(@repo, "summary.md")

      out, _err, status = run_script("GITHUB_STEP_SUMMARY" => summary)

      expect(status.success?).to be(false)
      expect(out).to include("FieldRemoved").and include("Order.note")
      expect(File.read(summary)).to include("FieldRemoved").and include("Order.note")
    end

    it "通す変更だけなら成功し、例外の一覧を docs/graphql/breaking-changes.yml から読む" do
      commit_base("schema.graphql" => base)
      write("schema.graphql", head("field_removed"))
      write("docs/graphql/breaking-changes.yml", <<~YAML)
        - change: FieldRemoved
          path: Order.note
          reason: 備考に他社の担当者の連絡先が入っていた
      YAML

      out, err, status = run_script

      expect([ err, status.success? ]).to eq([ "", true ])
      expect(out).to include("備考に他社の担当者の連絡先が入っていた")
    end
  end
end
