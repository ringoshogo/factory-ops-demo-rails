require_relative "matrix_world"

# 操作者のいない入口の公開 API が、所有の条件を RLS に任せていないことを単体で確かめる補助
# （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」、docs/guides/testing.md「行列テストとの分担」）。
# RLS は他社の行を隠すので、公開 API から所有の条件を外しても単体は落ちない。入口の行列と同じポリシー（MatrixCrossRead）を
# グループの前に足して後に外し、example の中で cross_read! を呼んだときだけ、他社の行も SELECT で見えるようにする。
# 書き込みのポリシーは開かないので、他社の行は INSERT すれば RLS の違反になり、UPDATE と DELETE の対象にならない
RSpec.shared_context "RLS の SELECT を開く" do
  MatrixCrossRead.share(self)

  def cross_read! = MatrixCrossRead.on!
end
