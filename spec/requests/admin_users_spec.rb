require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:user) { create(:user, email: "viewer@example.com") }

  describe "access" do
    it "redirects non-admins" do
      sign_in user
      get admin_users_path
      expect(response).to redirect_to(root_path)
    end
  end

  describe "GET /admin/users" do
    before { sign_in admin }

    it "lists accounts with what each has watched" do
      create(:playback_progress, :movie, user: user, imdb_id: "tt1375666", progress_seconds: 7_000, duration_seconds: 7_200)
      create(:playback_progress, :movie, user: user, imdb_id: "tt0816692", progress_seconds: 600, duration_seconds: 7_200)

      get admin_users_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("viewer@example.com", "2h 6m watched", "1 title finished", "last watched")
    end
  end

  describe "POST /admin/users" do
    before { sign_in admin }

    it "creates an account with a generated password shown once" do
      post admin_users_path, params: { user: { email: "new@example.com", display_name: "New", admin: "0", password: "" } }

      created = User.find_by!(email: "new@example.com")
      expect(response).to redirect_to(admin_users_path)
      follow_redirect!
      password = response.body[%r{<code[^>]*>([^<]+)</code>}, 1]
      expect(created.valid_password?(password)).to be(true)

      get admin_users_path
      expect(response.body).not_to include(password)
    end

    it "uses a chosen password without echoing it" do
      post admin_users_path, params: { user: { email: "chosen@example.com", password: "chosen-password-1" } }

      expect(User.find_by!(email: "chosen@example.com").valid_password?("chosen-password-1")).to be(true)
      follow_redirect!
      expect(response.body).not_to include("chosen-password-1")
    end

    it "rejects invalid accounts" do
      post admin_users_path, params: { user: { email: "not-an-email" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /admin/users/:id" do
    before { sign_in admin }

    it "grants admin and disables another account" do
      patch admin_user_path(user), params: { user: { admin: "1", disabled: "1" } }

      expect(response).to redirect_to(admin_users_path)
      expect(user.reload).to have_attributes(admin: true)
      expect(user).to be_disabled
    end

    it "re-enables a disabled account" do
      user.update!(disabled_at: 1.day.ago)

      patch admin_user_path(user), params: { user: { disabled: "0" } }

      expect(user.reload).not_to be_disabled
    end

    it "won't let admins demote or disable themselves" do
      patch admin_user_path(admin), params: { user: { admin: "0" } }
      expect(response).to have_http_status(:unprocessable_entity)

      patch admin_user_path(admin), params: { user: { disabled: "1" } }
      expect(response).to have_http_status(:unprocessable_entity)

      expect(admin.reload).to have_attributes(admin: true, disabled_at: nil)
    end
  end

  describe "POST /admin/users/:id/reset_password" do
    it "sets and shows a new password once" do
      sign_in admin

      post reset_password_admin_user_path(user)
      follow_redirect!

      password = response.body[%r{<code[^>]*>([^<]+)</code>}, 1]
      expect(user.reload.valid_password?(password)).to be(true)
    end
  end

  describe "DELETE /admin/users/:id" do
    before { sign_in admin }

    it "removes another account" do
      delete admin_user_path(user)

      expect(User.exists?(user.id)).to be(false)
    end

    it "won't remove your own account" do
      delete admin_user_path(admin)

      expect(flash[:alert]).to include("own account")
      expect(User.exists?(admin.id)).to be(true)
    end
  end

  describe "disabled accounts" do
    it "can't sign in" do
      user.update!(disabled_at: Time.current)

      post user_session_path, params: { user: { email: user.email, password: "password123" } }

      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:alert]).to include("disabled")
    end

    it "lose their open session on the next request" do
      sign_in user
      user.update!(disabled_at: Time.current)

      get root_path

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
