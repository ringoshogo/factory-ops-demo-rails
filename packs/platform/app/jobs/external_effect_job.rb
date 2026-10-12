# 外部のサービスへ作用するジョブの基底クラス（docs/adr/007 決定 4）。
# サブクラスは、登録の時機（enqueue_after_transaction_commit）と保証（external_effect）を自分のクラスに書く。
# 親から受け継いだ値のままにすると、読む人がジョブの保証を型から読めず、基底クラスの変更で黙って切り替わる
class ExternalEffectJob < ApplicationJob
  class MissingDeclaration < StandardError; end

  # at_least_once は確実な外部送信（A-2）、best_effort は撃ちっぱなし（B-1）
  GUARANTEES = %i[at_least_once best_effort].freeze

  class << self
    attr_reader :external_effect_guarantee

    def external_effect(guarantee)
      raise ArgumentError, "保証は #{GUARANTEES.join('・')} のどれか: #{guarantee.inspect}" unless GUARANTEES.include?(guarantee)

      @external_effect_guarantee = guarantee
    end

    def enqueue_after_transaction_commit=(value)
      @enqueue_timing_declared = true
      super
    end

    # 宣言を、このクラス自身が書いたか。親の宣言は数えない
    def declares_external_effect?
      instance_variable_defined?(:@external_effect_guarantee) && instance_variable_defined?(:@enqueue_timing_declared)
    end

    # クラスの本体を読み終えた時点で、宣言の書き忘れを例外にする。
    # inherited はクラスの本体より前に呼ばれるので、本体の終わり（:end）を待ってから確かめる。
    # Class.new で作る無名のクラスは :end を出さないので確かめない。待ち続けるトレースを残さないためである
    def inherited(subclass)
      super
      return if subclass.name.nil?

      trace = TracePoint.new(:end) do |point|
        next unless point.self.equal?(subclass)

        trace.disable
        unless subclass.declares_external_effect?
          raise MissingDeclaration, "#{subclass} は enqueue_after_transaction_commit と external_effect を自分のクラスに書く"
        end
      end
      trace.enable
    end
  end
end
