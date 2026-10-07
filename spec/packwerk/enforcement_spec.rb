require "open3"
require "fileutils"

# packwerk が依存違反とプライバシー違反を実際に検出することを、一時ファイルで違反を作って確かめる
RSpec.describe "packwerk の強制" do
  let(:root) { Pathname(__dir__).join("../..").expand_path }
  let(:created) { [] }

  after { created.each { |path| FileUtils.rm_rf(path) } }

  # 作ったファイルと、新しく作ったディレクトリの最上位を、後で消すために覚える
  def write_probe(path, source)
    file = root.join(path)
    created << (file.dirname.ascend.take_while { |dir| !dir.exist? }.last || file)
    FileUtils.mkdir_p(file.dirname)
    file.write(source)
    path
  end

  def packwerk_check(path)
    Open3.capture2e("bin/packwerk", "check", path, chdir: root.to_s)
  end

  before do
    write_probe("packs/inventory/app/public/inventory/packwerk_probe_public.rb", <<~RUBY)
      module Inventory
        class PackwerkProbePublic; end
      end
    RUBY
    write_probe("packs/inventory/app/models/inventory/packwerk_probe_private.rb", <<~RUBY)
      module Inventory
        class PackwerkProbePrivate; end
      end
    RUBY
  end

  it "依存を宣言した先の公開 API は参照できる" do
    path = write_probe("packs/sales/app/models/sales/packwerk_probe_allowed.rb", <<~RUBY)
      module Sales
        class PackwerkProbeAllowed
          def call = Inventory::PackwerkProbePublic
        end
      end
    RUBY

    output, status = packwerk_check(path)

    expect(status).to be_success, output
  end

  it "依存を宣言していない先を参照すると落ちる（purchasing → inventory）" do
    path = write_probe("packs/purchasing/app/models/purchasing/packwerk_probe_dependency.rb", <<~RUBY)
      module Purchasing
        class PackwerkProbeDependency
          def call = Inventory::PackwerkProbePublic
        end
      end
    RUBY

    output, status = packwerk_check(path)

    expect(status).not_to be_success
    expect(output).to include("Dependency violation: ::Inventory::PackwerkProbePublic")
    expect(output).not_to include("Privacy violation")
  end

  it "依存先でも公開 API でないクラスを参照すると落ちる（sales → inventory の非公開クラス）" do
    path = write_probe("packs/sales/app/models/sales/packwerk_probe_privacy.rb", <<~RUBY)
      module Sales
        class PackwerkProbePrivacy
          def call = Inventory::PackwerkProbePrivate
        end
      end
    RUBY

    output, status = packwerk_check(path)

    expect(status).not_to be_success
    expect(output).to include("Privacy violation: '::Inventory::PackwerkProbePrivate'")
    expect(output).not_to include("Dependency violation")
  end
end
