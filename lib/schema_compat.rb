# GraphQL のスキーマの互換の判定（docs/architecture/graphql-schema.md「スキーマの変更と非推奨」）。
# 基準の SDL と作業中の SDL を graphql-schema_comparator で比べ、変更ごとに通すか落とすかを決める。
# 変更は、比較器の変更のクラス名（FieldRemoved など）と座標（変更の path。PurchaseOrder.lines の形）で識別する。
#
# 比較器は開発とテストのグループにだけあるので、このファイルはアプリに読み込ませない（config/application.rb の autoload_lib）。
# bin/check-schema-compat と spec が require する
require "graphql/schema_comparator"
require "yaml"

module SchemaCompat
  class InvalidExceptions < StandardError; end

  REMOVALS = %w[FieldRemoved FieldArgumentRemoved InputFieldRemoved EnumValueRemoved TypeRemoved].freeze
  TYPE_CHANGES = %w[FieldTypeChanged FieldArgumentTypeChanged InputFieldTypeChanged].freeze
  # 比較器は、既定値の無い非 null の引数・入力項目の追加だけを破壊に分類する
  ADDITIONS = %w[FieldArgumentAdded InputFieldAdded].freeze
  # 比較器は既定値の変更をすべて危険に分類するが、非 null の引数・入力項目から既定値を外す変更は必須の追加と同じく既存の問い合わせを壊す
  DEFAULT_CHANGES = %w[FieldArgumentDefaultChanged InputFieldDefaultChanged].freeze

  Allowance = Data.define(:change, :path, :reason)
  Verdict = Data.define(:change, :path, :message, :passed, :reason)

  Result = Data.define(:verdicts, :unmatched_exceptions) do
    def passed? = verdicts.all?(&:passed)

    def report
      lines = [ "## GraphQL スキーマの互換", "" ]
      if verdicts.empty?
        lines << "スキーマに変更は無い。"
      else
        lines += [ "| 判定 | 変更 | 座標 | 内容 | 理由 |", "|---|---|---|---|---|" ]
        lines += verdicts.map { |v| "| #{v.passed ? '通す' : '落とす'} | #{v.change} | `#{v.path}` | #{cell(v.message)} | #{cell(v.reason)} |" }
      end
      unless unmatched_exceptions.empty?
        lines += [ "", "どの変更にも当たらない例外の行（docs/graphql/breaking-changes.yml から消す）:", "" ]
        lines += unmatched_exceptions.map { |row| "- #{row.change} `#{row.path}`：#{cell(row.reason)}" }
      end
      lines += [ "", passed? ? "落とす変更は無い。" : "落とす変更がある。非推奨を経てから消すか、例外の一覧に理由を書く。" ]
      lines.join("\n") + "\n"
    end

    private

    def cell(text) = text.to_s.gsub("|", "\\|").gsub("\n", " ")
  end

  module_function

  # 例外の一覧（docs/graphql/breaking-changes.yml）の YAML を読む。行の無いファイルは空の一覧になる
  def load_exceptions(yaml)
    rows = YAML.safe_load(yaml.to_s) || []
    raise InvalidExceptions, "例外の一覧は行の配列で書く" unless rows.is_a?(Array)

    rows.each_with_index.map do |row, index|
      raise InvalidExceptions, "#{index + 1} 行目が change・path・reason を持つハッシュでない" unless row.is_a?(Hash)

      values = %w[change path reason].to_h { |key| [ key, row[key].to_s.strip ] }
      blank = values.select { |_key, value| value.empty? }.keys
      raise InvalidExceptions, "#{index + 1} 行目の #{blank.join('・')} が空" unless blank.empty?

      Allowance.new(change: values["change"], path: values["path"], reason: values["reason"])
    end
  end

  def check(base_sdl:, head_sdl:, exceptions:)
    base = GraphQL::Schema.from_definition(base_sdl)
    changes = GraphQL::SchemaComparator.compare(base, GraphQL::Schema.from_definition(head_sdl)).changes

    verdicts = changes.map do |change|
      name = change_name(change)
      passed, reason = judge(name, change, base)
      allowance = exceptions.find { |row| row.change == name && row.path == change.path } unless passed
      passed, reason = true, "例外の一覧で通す：#{allowance.reason}" if allowance
      Verdict.new(change: name, path: change.path, message: change.message, passed:, reason:)
    end

    unmatched = exceptions.reject do |row|
      changes.any? { |change| change_name(change) == row.change && change.path == row.path }
    end
    Result.new(verdicts:, unmatched_exceptions: unmatched)
  end

  def change_name(change) = change.class.name.split("::").last

  # 先に当たった規則で決める。削除は比較器の重大度より先に見る。
  # 比較器は出力にだけ使う enum の値の削除を非破壊に分類するので、重大度を先に見ると非推奨を経ない削除が通る
  def judge(name, change, base)
    if REMOVALS.include?(name)
      judge_removal(name, change, base)
    elsif TYPE_CHANGES.include?(name)
      change.non_breaking? ? [ true, "クライアントを壊さない型の変更" ] : [ false, "型の変更は非推奨を経ても通さない" ]
    elsif (ADDITIONS.include?(name) && change.breaking?) || (DEFAULT_CHANGES.include?(name) && required?(default_target(change)))
      [ false, "必須の引数・入力項目の追加と、既定値を外して必須にする変更は、非推奨を経ても通さない" ]
    elsif change.breaking?
      [ false, "破壊的変更" ]
    else
      [ true, change.dangerous? ? "危険な変更" : "非破壊の変更" ]
    end
  end

  def default_target(change) = change.respond_to?(:new_argument) ? change.new_argument : change.new_field

  def required?(argument) = argument.type.non_null? && !argument.default_value?

  def judge_removal(name, change, base)
    if name == "TypeRemoved"
      live = live_references(base, change.removed_type.graphql_name)
      return [ true, "基準でこの型を返すか受け取るフィールドと引数がすべて非推奨" ] if live.empty?

      return [ false, "基準で非推奨でない参照がある：#{live.join('、')}" ]
    end

    removed = case name
    when "FieldRemoved", "InputFieldRemoved" then change.field
    when "FieldArgumentRemoved" then change.argument
    when "EnumValueRemoved" then change.enum_value
    end
    removed.deprecation_reason ? [ true, "基準で非推奨" ] : [ false, "基準で非推奨でない。先に非推奨にする" ]
  end

  # 基準のスキーマで、型 type_name を返すか受け取る、非推奨でないフィールド・引数・入力項目の座標。
  # union とインターフェースを返すフィールドは、その型を返しうるので参照に数える。
  # 非推奨のフィールドの引数は、フィールドと一緒に消せるので数えない
  def live_references(base, type_name)
    returns = ->(type) do
      unwrapped = type.unwrap
      unwrapped.graphql_name == type_name ||
        (unwrapped.kind.abstract? && base.possible_types(unwrapped).any? { _1.graphql_name == type_name })
    end

    base.types.values.reject(&:introspection?).flat_map do |owner|
      case owner.kind.name
      when "OBJECT", "INTERFACE"
        owner.fields.values.flat_map do |field|
          next [] if field.deprecation_reason

          own = returns.(field.type) ? [ field.path ] : []
          own + field.arguments.values.select { |arg| arg.type.unwrap.graphql_name == type_name && !arg.deprecation_reason }.map(&:path)
        end
      when "INPUT_OBJECT"
        owner.arguments.values.select { |arg| arg.type.unwrap.graphql_name == type_name && !arg.deprecation_reason }.map(&:path)
      else
        []
      end
    end
  end
end
