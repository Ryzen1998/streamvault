require "rails_helper"

RSpec.describe "Admin::Debrid", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }
  let(:torbox_user_url) { "https://api.torbox.app/v1/api/user/me" }

  def stub_torbox_key(status: 200, body: { success: true, data: { email: "admin@example.com" } })
    stub_request(:get, torbox_user_url)
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  describe "GET /admin/debrid" do
    it "redirects unauthenticated users" do
      get admin_debrid_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects non-admin users" do
      sign_in user
      get admin_debrid_path
      expect(response).to redirect_to(root_path)
    end

    it "shows the configured service without exposing the key" do
      create(:debrid_account, :torbox, api_key: "SECRET_TB_KEY", verified_at: 1.hour.ago)
      sign_in admin

      get admin_debrid_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("TorBox", "Verified")
      expect(response.body).not_to include("SECRET_TB_KEY")
    end
  end

  describe "PATCH /admin/debrid" do
    before { sign_in admin }

    it "saves and verifies a TorBox key" do
      stub_torbox_key

      patch admin_debrid_path, params: { debrid_account: { service: "torbox", api_key: "tb_key" } }

      expect(response).to redirect_to(admin_debrid_path)
      expect(flash[:notice]).to include("verified")
      account = DebridAccount.current
      expect(account).to have_attributes(service: "torbox", api_key: "tb_key", last_error: nil)
      expect(account.verified_at).to be_present
      expect(Debrid.current.service).to eq("torbox")
    end

    it "saves a key the service rejects, flagging it as unverified" do
      stub_torbox_key(status: 403, body: { success: false, error: "BAD_TOKEN", detail: "Invalid API token." })

      patch admin_debrid_path, params: { debrid_account: { service: "torbox", api_key: "bad_key" } }

      expect(flash[:alert]).to include("Invalid API token.")
      expect(DebridAccount.current).to have_attributes(verified_at: nil, last_error: "Invalid API token.")
    end

    it "keeps the current key when the field is left blank" do
      create(:debrid_account, :torbox, api_key: "tb_key")
      stub_torbox_key

      patch admin_debrid_path, params: { debrid_account: { service: "torbox", api_key: "" } }

      expect(DebridAccount.current.api_key).to eq("tb_key")
      expect(DebridAccount.count).to eq(1)
    end

    it "requires a new key when switching service" do
      create(:debrid_account, :torbox, api_key: "tb_key")

      patch admin_debrid_path, params: { debrid_account: { service: "realdebrid", api_key: "" } }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(DebridAccount.current.reload).to have_attributes(service: "torbox", api_key: "tb_key")
    end

    it "rejects non-admins" do
      sign_in user

      patch admin_debrid_path, params: { debrid_account: { service: "torbox", api_key: "tb_key" } }

      expect(response).to redirect_to(root_path)
      expect(DebridAccount.count).to eq(0)
    end
  end

  describe "DELETE /admin/debrid" do
    it "removes the account" do
      create(:debrid_account, :torbox)
      sign_in admin

      delete admin_debrid_path

      expect(response).to redirect_to(admin_debrid_path)
      expect(DebridAccount.count).to eq(0)
    end
  end

  describe "subscription expiry" do
    it "shows the plan and paid-until date" do
      create(:debrid_account, :torbox, plan: "Pro", expires_at: Time.zone.parse("2027-01-15 12:00"), verified_at: 1.hour.ago)
      sign_in admin

      get admin_debrid_path

      expect(response.body).to include("Pro plan", "paid until January 15, 2027")
    end

    it "warns admins on every page when the subscription is about to lapse" do
      create(:debrid_account, :torbox, expires_at: 3.days.from_now)
      stub_request(:get, %r{v3-cinemeta\.strem\.io}).to_return(status: 200, body: "{}", headers: { "Content-Type" => "application/json" })
      sign_in admin

      get stats_path

      expect(response.body).to include("TorBox subscription ends", "Streaming stops for everyone")
    end

    it "doesn't warn regular users or admins with plenty of time left" do
      create(:debrid_account, :torbox, expires_at: 3.days.from_now)
      sign_in user
      get stats_path
      expect(response.body).not_to include("Streaming stops for everyone")

      DebridAccount.current.update!(expires_at: 60.days.from_now)
      sign_in admin
      get stats_path
      expect(response.body).not_to include("Streaming stops for everyone")
    end
  end
end
