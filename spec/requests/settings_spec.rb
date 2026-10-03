require 'rails_helper'

RSpec.describe "Settings", type: :request do
  let(:user) { create(:user) }

  before do
    stub_request(:get, /www\.omdbapi\.com/)
      .to_return(status: 200, body: { "Response" => "False" }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe "GET /settings" do
    context "when not authenticated" do
      it "redirects to login" do
        get settings_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "when authenticated" do
      before { sign_in user }

      it "returns success" do
        get settings_path
        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "PATCH /settings" do
    before { sign_in user }

    it "ignores debrid keys submitted by users" do
      patch settings_path, params: { user: { realdebrid_api_key: "user_key", preferred_languages: [ "ENG" ] } }

      expect(response).to redirect_to(settings_path)
      expect(DebridAccount.count).to eq(0)
    end

    it "updates preferred languages" do
      patch settings_path, params: { user: { preferred_languages: [ "ENG", "FRENCH" ] } }
      expect(response).to redirect_to(settings_path)
      expect(user.reload.preferred_languages).to include("ENG", "FRENCH")
    end
  end

  describe "debrid key handling" do
    it "offers users no debrid key field" do
      sign_in user
      get settings_path

      expect(response.body).not_to include("api_key")
      expect(response.body).not_to include(admin_debrid_path)
    end

    it "links admins to the debrid admin page without leaking the instance key" do
      create(:debrid_account, :torbox, api_key: "SECRET_KEY_DO_NOT_LEAK")
      sign_in create(:user, :admin)
      get settings_path

      expect(response.body).to include(admin_debrid_path)
      expect(response.body).not_to include("SECRET_KEY_DO_NOT_LEAK")
    end
  end
end
