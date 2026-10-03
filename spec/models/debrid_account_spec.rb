require "rails_helper"

RSpec.describe DebridAccount do
  it "encrypts the API key at rest" do
    account = create(:debrid_account, :torbox, api_key: "tb_secret_key")

    expect(account.reload.api_key).to eq("tb_secret_key")
    raw_value = DebridAccount.connection.select_value("SELECT api_key FROM debrid_accounts WHERE id = #{account.id}")
    expect(raw_value).not_to include("tb_secret_key")
  end

  it "only accepts supported services" do
    expect(build(:debrid_account, service: "alldebrid")).not_to be_valid
    expect(build(:debrid_account, service: "torbox")).to be_valid
    expect(build(:debrid_account, service: "realdebrid")).to be_valid
  end

  it "requires an API key" do
    expect(build(:debrid_account, api_key: "")).not_to be_valid
  end

  it "does not expose the key when inspected" do
    account = create(:debrid_account, :torbox, api_key: "tb_secret_key")

    expect(account.inspect).not_to include("tb_secret_key")
    expect(account.to_debrid.inspect).not_to include("tb_secret_key")
  end
end
