# Bullet の N+1 の検出から外す関連（docs/architecture/graphql-schema.md「ページングと N+1」）。
# 外してよいのは、件数が 1 に決まっている誤検知（1 件のレコードを引いてから関連をたどる、など）だけで、本当の N+1 を黙らせない。
# 行は { type:, class_name:, association:, reason: } で書き、reason にその関連の件数が 1 に決まる理由を書く
module BulletSafelist
  ENTRIES = [].freeze

  KEYS = %i[type class_name association reason].freeze

  def self.apply!(entries = ENTRIES)
    entries.each do |entry|
      raise ArgumentError, "Bullet の許可リストの行の項目は type・class_name・association・reason の 4 つに限る: #{entry}" unless entry.keys.sort == KEYS.sort
      raise ArgumentError, "Bullet の許可リストの行に reason が無い: #{entry}" if entry[:reason].blank?

      Bullet.add_safelist(entry.except(:reason))
    end
  end
end
