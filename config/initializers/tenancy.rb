# 接続プールから接続を貸し出すたびに、セッションの app.tenant_id を空にする（docs/architecture/data-model.md「RLS」）。
# 前の利用者がセッションの SET で残したテナントを、テナントを設定しない次の利用者が引き継がないようにする
ActiveSupport.on_load(:active_record_postgresqladapter) do
  set_callback(:checkout, :after) { |connection| Tenancy.reset!(connection) }
end
