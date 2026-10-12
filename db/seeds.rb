# デモの世界を作る（README.md「開発環境」）。同じ DB で 2 回目を流しても何も作らず、同じアカウントを表示する。
# 本番の環境では DemoWorld が例外で止まる
result = DemoWorld.build(namespace: "", variant: :seed)

puts "デモのアカウント（パスワードはどれも #{result.accounts.first.password}）"
result.accounts.each { |account| puts "  #{account.persona.ljust(22)} #{account.email}" }
