# 公開 API が relation もモデルも返さないことを、全 spec の流れで確かめるガード
# （docs/guides/packs-and-packwerk.md「公開 API を出す」、docs/architecture/graphql-schema.md「1 回のリクエストがたどる道」3）。
# packs/*/app/public/**/*.rb が定義する定数の公開の特異メソッドと Page#values の戻り値を、配列・Hash（キーと値）・Set・
# Data の項目・OperationResult の value までたどり、ActiveRecord::Relation か ActiveRecord::Base の子孫のインスタンスがあれば例外にする。
# relation を受け取った側は unscope・rewhere・update_all で scope と書き込みの入口を越えられ、モデルは書き換えられるからである。
# SqlSubquery と Arel のノードは relation でもモデルでもないので通す。
#
# 確かめるのは spec が呼んだメソッドだけで、どの spec も呼ばない公開 API は確かめの外になる。呼ばれなかったものは、
# 全件の終わりに一覧を出すだけで落とさない。spec を流した範囲によって一覧が変わるからである。
#
# 確かめない種類の定数：
# - Data の値のクラスとイベントの型（Contracts::Event.define）：値そのもので、特異メソッドは作り方（from_payload など）だけである
# - policy（ApplicationPolicy の子孫）：relation_scope は relation を受け取って返すのが役目で、同じパッケージの Scope だけが使う
# - ジョブ（ActiveJob::Base の子孫）と例外のクラス：公開 API の戻り値を返す入口ではない
#
# メソッドごとの TracePoint（:return）で戻り値を読み、メソッドを prepend で包まない。rspec-mocks は部分の二重の引数を
# object.method(name) で引いたメソッドの引数の形で確かめるので（spec/spec_helper.rb の verify_partial_doubles、
# rspec-mocks 3.13.8 の lib/rspec/mocks/method_reference.rb）、包むと引数の形が (*args, **kwargs, &block) になり、
# スタブの引数の数の誤りが黙って通る。TracePoint はメソッドの定義を変えない。スタブしたメソッドは元のメソッドを呼ばないので、
# スタブの戻り値は確かめない。
module PublicApiReturns
  # Exception から継ぐ。呼ぶ側の rescue StandardError（ジョブの retry_on など）に拾われると、違反が黙って消えるからである。
  # RSpec の期待の失敗（RSpec::Expectations::ExpectationNotMetError）と同じ形である
  class Violation < Exception; end

  PATTERN = "packs/*/app/public/**/*.rb"

  @traces = {}
  @called = Set.new

  class << self
    attr_reader :called
  end

  # 手元では起動の時に読み込まず、CI では読み込む（config/environments/test.rb の eager_load）。どちらでも同じに動くよう、
  # ファイルのパスから Zeitwerk が期待する名前（zeitwerk 2.8.3 の lib/zeitwerk/loader.rb の cpath_expected_at）で定数を引く
  def self.install!(root = Rails.root)
    targets(root).each { |label, method| watch(label, method) }
    watch("Page#values", Page.instance_method(:values))
  end

  # 「定数.メソッド」ごとの、確かめる Method
  def self.targets(root = Rails.root)
    Dir[File.join(root, PATTERN)].sort.flat_map do |path|
      constant = Object.const_get(Rails.autoloaders.main.cpath_expected_at(path))
      defined_in(constant, path).reject { unchecked?(_1) }.flat_map do |mod|
        mod.singleton_methods(false).filter_map do |name|
          method = mod.method(name)
          [ "#{mod.name}.#{name}", method ] if method.source_location&.first == path
        end
      end
    end.to_h
  end

  # ファイルが定義する定数：パスが名指しする定数と、同じファイルが中に定義するモジュール
  def self.defined_in(constant, path)
    nested = constant.constants(false).filter_map do |name|
      value = constant.const_get(name)
      value if value.is_a?(Module) && Object.const_source_location(value.name)&.first == path
    end
    [ constant, *nested.flat_map { defined_in(_1, path) } ]
  end

  def self.unchecked?(constant)
    return false unless constant.is_a?(Class)

    constant < Data || constant < ApplicationPolicy || constant < ActiveJob::Base || constant < Exception
  end

  # label の名前で、method（Method か UnboundMethod）の戻り値を確かめる
  def self.watch(label, method)
    @traces[label] = TracePoint.new(:return) do |trace|
      @called << label
      check!(label, trace.return_value)
    end.tap { _1.enable(target: method) }
  end

  def self.unwatch(label) = @traces.delete(label)&.disable

  def self.check!(label, value)
    case value
    when ActiveRecord::Relation, ActiveRecord::Base
      raise Violation, "#{label} が #{value.class.name} を返した。公開 API は relation もモデルも返さない"
    when OperationResult then check!(label, value.value)
    when Hash then value.each { |key, each| [ key, each ].each { check!(label, _1) } }
    when Array, Set then value.each { check!(label, _1) }
    when Data then value.to_h.each_value { check!(label, _1) }
    end
    nil
  end

  def self.watched = @traces.keys

  # 全件の流れで一度も呼ばれなかった「定数.メソッド」
  def self.uncalled = @traces.keys.reject { @called.include?(_1) }.sort
end
