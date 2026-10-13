module Platform
  # デモの世界を作る公開 API（DemoWorld・Partnerships::Onboarding・Inventory::Stocks.set_safety_stock）を動かしてよいか。
  # 本番の環境では、DEMO_WORLD_ENABLED=1 を渡したプロセスでだけ許す。公開の配置は、この変数を毎日の作り直しにだけ渡し、
  # Web とワーカーには渡さない。本物の本番に、デモの手元の値でテナントとユーザーを作らないためである（docs/adr/009 決定 4）
  module DemoWorldGate
    def self.open? = !Rails.env.production? || ENV["DEMO_WORLD_ENABLED"] == "1"
  end
end
