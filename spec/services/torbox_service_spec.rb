require "rails_helper"

RSpec.describe TorboxService do
  let(:user_url) { "https://api.torbox.app/v1/api/user/me" }

  it "verifies a valid key" do
    stub_request(:get, user_url)
      .with(headers: { "Authorization" => "Bearer tb_key" })
      .to_return(status: 200, body: { success: true, data: { email: "admin@example.com" } }.to_json,
        headers: { "Content-Type" => "application/json" })

    result = described_class.new("tb_key").verify_key

    expect(result).to be_success
    expect(result.data).to include("email" => "admin@example.com")
  end

  it "reports TorBox's error detail for a rejected key" do
    stub_request(:get, user_url)
      .to_return(status: 403, body: { success: false, error: "BAD_TOKEN", detail: "Invalid API token." }.to_json,
        headers: { "Content-Type" => "application/json" })

    result = described_class.new("bad_key").verify_key

    expect(result).to be_failure
    expect(result.error_message).to eq("Invalid API token.")
  end

  it "contains timeouts" do
    allow_any_instance_of(Faraday::Connection).to receive(:get).and_raise(Faraday::TimeoutError)

    expect(described_class.new("tb_key").verify_key.error_message).to eq("Request timed out")
  end

  it "contains connection failures" do
    stub_request(:get, user_url).to_timeout

    expect(described_class.new("tb_key").verify_key.error_message).to eq("Could not connect to TorBox")
  end
end
