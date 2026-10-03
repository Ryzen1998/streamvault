require "rails_helper"

RSpec.describe Debrid do
  around do |example|
    previous = ENV.to_h.slice("DEBRID_SERVICE", "DEBRID_API_KEY")
    ENV.delete("DEBRID_SERVICE")
    ENV.delete("DEBRID_API_KEY")
    example.run
  ensure
    ENV.delete("DEBRID_SERVICE")
    ENV.delete("DEBRID_API_KEY")
    previous.each { |name, value| ENV[name] = value }
  end

  it "is not configured without an account or environment fallback" do
    expect(described_class.current).to be_nil
    expect(described_class).not_to be_configured
  end

  it "uses the admin-managed account" do
    create(:debrid_account, :torbox, api_key: "tb_key")

    expect(described_class.current).to have_attributes(service: "torbox", api_key: "tb_key", name: "TorBox")
  end

  it "falls back to the environment variables" do
    ENV["DEBRID_SERVICE"] = "TorBox"
    ENV["DEBRID_API_KEY"] = "env_key"

    expect(described_class.current).to have_attributes(service: "torbox", api_key: "env_key")
  end

  it "prefers the admin-managed account over the environment" do
    ENV["DEBRID_SERVICE"] = "realdebrid"
    ENV["DEBRID_API_KEY"] = "env_key"
    create(:debrid_account, :torbox, api_key: "tb_key")

    expect(described_class.current.service).to eq("torbox")
  end

  it "ignores an unsupported environment service" do
    ENV["DEBRID_SERVICE"] = "alldebrid"
    ENV["DEBRID_API_KEY"] = "env_key"

    expect(described_class.current).to be_nil
  end

  describe Debrid::Account do
    let(:account) { described_class.new(service: "torbox", api_key: "tb_key") }

    it "fingerprints the account without revealing the key" do
      expect(account.fingerprint).to start_with("torbox-")
      expect(account.fingerprint).not_to include("tb_key")
    end

    it "redacts the key from text" do
      expect(account.redact("/torbox=tb_key/stream")).to eq("/torbox=[REDACTED]/stream")
    end

    it "verifies TorBox keys against TorBox" do
      stub_request(:get, "https://api.torbox.app/v1/api/user/me")
        .with(headers: { "Authorization" => "Bearer tb_key" })
        .to_return(status: 200, body: { success: true, data: { email: "admin@example.com" } }.to_json,
          headers: { "Content-Type" => "application/json" })

      expect(account.verify).to be_success
    end

    it "reads the TorBox plan and paid-until date" do
      stub_request(:get, "https://api.torbox.app/v1/api/user/me")
        .to_return(status: 200, body: { success: true, data: { plan: 2, premium_expires_at: "2026-11-01T00:00:00Z" } }.to_json,
          headers: { "Content-Type" => "application/json" })

      expect(account.verify.data).to eq(plan: "Pro", expires_at: Time.zone.parse("2026-11-01T00:00:00Z"))
    end

    it "reads the RealDebrid account type and expiration" do
      realdebrid = described_class.new(service: "realdebrid", api_key: "rd_key")
      stub_request(:get, "https://api.real-debrid.com/rest/1.0/user")
        .to_return(status: 200, body: { type: "premium", expiration: "2026-10-05T10:00:00.000Z" }.to_json,
          headers: { "Content-Type" => "application/json" })

      expect(realdebrid.verify.data).to eq(plan: "Premium", expires_at: Time.zone.parse("2026-10-05T10:00:00Z"))
    end
  end
end
