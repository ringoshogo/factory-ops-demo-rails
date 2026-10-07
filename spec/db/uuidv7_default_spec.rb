require "rails_helper"

RSpec.describe "主キーの既定値" do
  let(:connection) { ActiveRecord::Base.connection }

  it "tenants.id の既定値が uuidv7() である" do
    default = connection.select_value(<<~SQL)
      SELECT column_default FROM information_schema.columns
      WHERE table_name = 'tenants' AND column_name = 'id'
    SQL

    expect(default).to eq("uuidv7()")
  end

  it "作った行の id が UUID バージョン 7 である" do
    version = connection.select_value(<<~SQL)
      INSERT INTO tenants (code, name, partner_code, created_at, updated_at)
      VALUES ('t1', 'テナント1', 'p1', now(), now())
      RETURNING uuid_extract_version(id)
    SQL

    expect(version).to eq(7)
  end
end
