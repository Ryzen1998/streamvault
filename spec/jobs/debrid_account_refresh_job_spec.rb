require "rails_helper"

RSpec.describe DebridAccountRefreshJob do
  def stub_torbox(status:, body:)
    stub_request(:get, "https://api.torbox.app/v1/api/user/me")
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "records the current plan and expiry" do
    account = create(:debrid_account, :torbox)
    stub_torbox(status: 200, body: { success: true, data: { plan: 1, premium_expires_at: "2026-10-08T00:00:00Z" } })

    described_class.perform_now

    expect(account.reload).to have_attributes(plan: "Essential", expires_at: Time.zone.parse("2026-10-08T00:00:00Z"), last_error: nil)
    expect(account.verified_at).to be_present
  end

  it "keeps the last known expiry when the check fails" do
    account = create(:debrid_account, :torbox, plan: "Pro", expires_at: 20.days.from_now)
    stub_torbox(status: 403, body: { success: false, detail: "Invalid API token." })

    described_class.perform_now

    expect(account.reload).to have_attributes(plan: "Pro", last_error: "Invalid API token.", verified_at: nil)
    expect(account.expires_at).to be_present
  end

  it "does nothing without an account" do
    expect { described_class.perform_now }.not_to raise_error
  end
end
