require_relative "matrix_world"

# 操作者のいない入口の公開 API が、所有の条件を RLS に任せていないことを単体で確かめる補助
# （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」、docs/guides/testing.md「行列テストとの分担」）。
# RLS は他社の行を隠すので、公開 API から所有の条件を外しても単体は落ちない。入口の行列と同じポリシー（MatrixCrossRead）を
# グループの前に足して後に外し、example の中で cross_read! を呼んだときだけ、他社の行を SELECT で見えるようにし、
# UPDATE と SELECT ... FOR UPDATE の対象に入れる。他社の行を書いた後の行は owner_write の WITH CHECK に当たるので、
# 所有の条件を外した公開 API は例外になる。INSERT と DELETE のポリシーは開かないので、他社の名義の INSERT は RLS の違反になり、
# 他社の行は DELETE の対象にならない
RSpec.shared_context "RLS の SELECT と UPDATE を開く" do
  MatrixCrossRead.share(self)

  def cross_read! = MatrixCrossRead.on!

  # 他社の行を、開いたまま同じ接続で読み直した属性。設定が on の間は、他社の行を自社の名義に書き換える UPDATE が
  # owner_write の WITH CHECK を通るので、所有の列を含めて比べ、書き換えを捕まえる。所有ロールの接続は別の接続なので、
  # example のトランザクションの中で作った行と書き込みが見えない（spec/rails_helper.rb の use_transactional_fixtures）
  def reread(record) = record.class.find(record.id).attributes
end
