require "rails_helper"

RSpec.describe "Admin::Addons", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user) }

  def stub_manifest(body, status: 200)
    stub_request(:get, "https://addon.example.com/manifest.json").to_return(
      status: status,
      body: body.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  describe "GET /admin/addons" do
    it "redirects unauthenticated users" do
      get admin_addons_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it "redirects non-admin users" do
      sign_in user
      get admin_addons_path
      expect(response).to redirect_to(root_path)
    end

    it "allows admins" do
      sign_in admin
      get admin_addons_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /admin/addons" do
    before { sign_in admin }

    it "creates an addon after validating the manifest" do
      stub_manifest({ "id" => "org.test", "name" => "Test Addon", "types" => %w[movie series] })

      expect {
        post admin_addons_path, params: { addon: { url: "https://addon.example.com/manifest.json" } }
      }.to change(Addon, :count).by(1)

      addon = Addon.last
      expect(addon.name).to eq("Test Addon")
      expect(addon.manifest_id).to eq("org.test")
      expect(addon.manifest_types).to eq(%w[movie series])
    end

    it "rejects an unreachable manifest" do
      stub_manifest({ "error" => "nope" }, status: 500)

      expect {
        post admin_addons_path, params: { addon: { url: "https://addon.example.com/manifest.json" } }
      }.not_to change(Addon, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "rejects an invalid URL" do
      expect {
        post admin_addons_path, params: { addon: { url: "not a url" } }
      }.not_to change(Addon, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /admin/addons/:id" do
    before { sign_in admin }

    it "toggles the trust playback hosts flag" do
      addon = create(:addon, trust_source_hosts: false)

      patch admin_addon_path(addon), params: { addon: { trust_source_hosts: "1" } }

      expect(addon.reload.trust_source_hosts).to be(true)
      expect(response).to redirect_to(admin_addons_path)
    end

    it "does not require a manifest refetch when the URL is unchanged" do
      addon = create(:addon, name: "Unchanged")

      patch admin_addon_path(addon), params: { addon: { name: "Renamed" } }

      expect(addon.reload.name).to eq("Renamed")
    end
  end

  describe "DELETE /admin/addons/:id" do
    before { sign_in admin }

    it "removes the addon" do
      addon = create(:addon)

      expect {
        delete admin_addon_path(addon)
      }.to change(Addon, :count).by(-1)
    end
  end

  describe "POST /admin/addons/:id/refresh" do
    before { sign_in admin }

    it "refreshes manifest metadata" do
      addon = create(:addon, url: "https://addon.example.com/manifest.json", name: "Old")
      stub_manifest({ "id" => "org.test", "name" => "New Name", "types" => %w[movie] })

      post refresh_admin_addon_path(addon)

      expect(addon.reload.name).to eq("New Name")
      expect(response).to redirect_to(admin_addons_path)
    end
  end
end
