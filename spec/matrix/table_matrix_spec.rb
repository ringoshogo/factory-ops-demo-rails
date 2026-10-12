require "rails_helper"
require_relative "../support/matrix_world"
require_relative "table_expectations"

# テナントの表ごとに、ペルソナが生 SQL で読める行と、相手の名義で書けないことを確かめる。
# アプリのロールで動くので、RLS のポリシーそのものを確かめる（docs/architecture/context-map.md「テナントと所有」）
RSpec.describe "表の行列" do
  let(:connection) { ActiveRecord::Base.lease_connection }
  MatrixWorld.share_per_file(self)

  it "テナントの表すべてに期待値がある" do
    expect(MatrixExpectations::TABLES.keys).to match_array(MatrixWorld.tenant_tables)
  end

  it "期待値に書いたペルソナはすべて世界にいる" do
    personas = MatrixExpectations::TABLES.values.flat_map { |reads| reads.keys + reads.values.flat_map(&:keys) }

    expect(personas - MatrixWorld::PERSONAS).to be_empty
  end

  it "テナントの表すべてに、その表の行を作る factory がある" do
    missing = MatrixWorld.tenant_tables.reject do |table|
      factory = FactoryBot.factories.registered?(MatrixWorld.factory_name(table)) &&
        FactoryBot.factories.find(MatrixWorld.factory_name(table))
      factory && factory.build_class.table_name == table
    end

    expect(missing).to be_empty
  end

  it "書き換えの権限を外した表は、テナントの表である" do
    expect(MatrixExpectations::APPEND_ONLY - MatrixWorld.tenant_tables).to be_empty
  end

  MatrixExpectations::TABLES.each do |table, reads|
    append_only = MatrixExpectations::APPEND_ONLY.include?(table)

    describe table do
      let(:quoted_table) { connection.quote_table_name(table) }

      def owner_of_row(id)
        connection.select_value("SELECT owner_tenant_id FROM #{quoted_table} WHERE id = $1", "Matrix", [ id ])
      end

      # 自社の行を写し、ID と所有テナントだけを変えた行を、RETURNING を付けずに INSERT する。factory の INSERT は RETURNING を付けるので、
      # 新しい行が SELECT のポリシーでも拒まれ、書き込みのポリシーの WITH CHECK を緩めても同じ例外で落ちる。RETURNING の無い INSERT は
      # WITH CHECK だけが拒む
      def insert_copy_owned_by(owner_tenant_id, source_id)
        connection.exec_query(<<~SQL, "Matrix", [ owner_tenant_id, source_id ])
          INSERT INTO #{quoted_table}
          SELECT (jsonb_populate_record(NULL::#{quoted_table},
            to_jsonb(source) || jsonb_build_object('id', uuidv7(), 'owner_tenant_id', $1::uuid))).*
          FROM #{quoted_table} source WHERE source.id = $2
        SQL
      end

      MatrixWorld::PERSONAS.each do |persona|
        others = MatrixWorld::PERSONAS - [ persona ]
        partner_reads = reads.fetch(persona, {})

        it "#{persona} が読めるのは、自社の行#{partner_reads.map { |owner, count| "と #{owner} の #{count} 件" }.join}" do
          visible = world.as(persona) do
            connection.select_rows("SELECT owner_tenant_id, count(*) FROM #{quoted_table} GROUP BY 1").to_h
          end.transform_keys { |tenant_id| world.persona_of(tenant_id) }

          expect(visible[persona]).to be_positive
          expect(visible.except(persona)).to eq(partner_reads)
        end

        it "#{persona} は相手の名義で INSERT できない" do
          others.each do |other|
            expect {
              world.as(persona) { FactoryBot.create(MatrixWorld.factory_name(table), owner_tenant_id: world.tenants[other]) }
            }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
            expect {
              world.as(persona) { insert_copy_owned_by(world.tenants[other], world.row(table, persona).id) }
            }.to raise_error(ActiveRecord::StatementInvalid, /row-level security/)
          end
        end

        it "#{persona} の UPDATE・DELETE は相手の行に届かない" do
          others.each do |other|
            id = world.row(table, other).id
            if append_only
              expect { world.as(persona) { connection.exec_update("UPDATE #{quoted_table} SET id = id WHERE id = $1", "Matrix", [ id ]) } }
                .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
              expect { world.as(persona) { connection.exec_delete("DELETE FROM #{quoted_table} WHERE id = $1", "Matrix", [ id ]) } }
                .to raise_error(ActiveRecord::StatementInvalid, /permission denied/)
            else
              world.as(persona) do
                expect(connection.exec_update("UPDATE #{quoted_table} SET id = id WHERE id = $1", "Matrix", [ id ])).to eq(0)
                expect(connection.exec_delete("DELETE FROM #{quoted_table} WHERE id = $1", "Matrix", [ id ])).to eq(0)
              end
            end
            expect(world.as(other) { owner_of_row(id) }).to eq(world.tenants[other])
          end
        end

        it "#{persona} は自社の行を相手の名義へ書き換えられない" do
          id = world.row(table, persona).id
          others.each do |other|
            expect {
              world.as(persona) do
                connection.exec_update("UPDATE #{quoted_table} SET owner_tenant_id = $1 WHERE id = $2", "Matrix",
                  [ world.tenants[other], id ])
              end
            }.to raise_error(ActiveRecord::StatementInvalid, MatrixExpectations::REWRITE_REJECTED_BY_TRIGGER.fetch(table) do
              append_only ? /permission denied/ : /row-level security/
            end)
          end
        end
      end
    end
  end
end
