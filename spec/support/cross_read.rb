require_relative "matrix_world"

# 操作者のいない入口の公開 API が、所有の条件を RLS に任せていないことを単体で確かめる補助
# （docs/architecture/graphql-schema.md「認可：宣言の無い型・リゾルバ・mutation は拒否する」、docs/guides/testing.md「行列テストとの分担」）。
# RLS は他社の行を隠すので、公開 API から所有の条件を外しても単体は落ちない。入口の行列と同じポリシー（MatrixCrossRead）を
# グループの前に足して後に外し、example の中で cross_read! を呼んだときだけ、他社の行も SELECT で見えるようにする。
# 書き込みのポリシーは開かないので、他社の行を書こうとすれば RLS の違反になる。
# rspec は before(:context) が失敗しても after(:context) を走らせるので、外すのは足し終えたときだけにする。
# 足すのに失敗したときに外すと、同じ DB に先に足した別の実行のポリシーを消す（MatrixWorld.share_per_file と同じ）
RSpec.shared_context "RLS の SELECT を開く" do
  before(:context) do
    MatrixCrossRead.add!
    @cross_read_added = true
  end
  after(:context) { MatrixCrossRead.remove! if @cross_read_added }

  def cross_read! = MatrixCrossRead.on!
end
