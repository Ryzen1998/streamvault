# frozen_string_literal: true

module Admin
  # Admin-only account management: create accounts, grant or revoke admin,
  # disable access, reset passwords. Admins can't demote, disable or remove
  # themselves, which also guarantees at least one enabled admin remains.
  class UsersController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!
    before_action :set_user, only: [ :edit, :update, :destroy, :reset_password ]

    def index
      @users = User.order(:created_at)
      @summaries = Playback::AccountSummaries.for(@users)
      @issued_password = flash[:issued_password]
    end

    def new
      @user = User.new
    end

    def create
      @user = User.new(create_params)
      chosen_password = params.dig(:user, :password).presence
      @user.password = @user.password_confirmation = chosen_password || generated_password

      if @user.save
        issue_password(@user, @user.password) unless chosen_password
        redirect_to admin_users_path, notice: "Created #{@user.email}."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      @user.assign_attributes(update_params.except(:disabled))
      if update_params.key?(:disabled)
        disable = ActiveModel::Type::Boolean.new.cast(update_params[:disabled])
        @user.disabled_at = disable ? (@user.disabled_at || Time.current) : nil
      end

      if self_lockout?
        @user.errors.add(:base, "You can't remove your own admin access or disable your own account.")
        return render :edit, status: :unprocessable_entity
      end

      if @user.save
        redirect_to admin_users_path, notice: "Updated #{@user.email}."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def reset_password
      password = generated_password
      @user.update!(password: password, password_confirmation: password)
      issue_password(@user, password)
      redirect_to admin_users_path, notice: "Password reset for #{@user.email}."
    end

    def destroy
      return redirect_to admin_users_path, alert: "You can't remove your own account." if @user == current_user

      @user.destroy
      redirect_to admin_users_path, notice: "Removed #{@user.email}."
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def create_params
      params.require(:user).permit(:email, :display_name, :admin)
    end

    def update_params
      params.require(:user).permit(:display_name, :admin, :disabled)
    end

    def self_lockout?
      return false unless @user == current_user

      (@user.admin_changed? && !@user.admin?) || (@user.disabled_at_changed? && @user.disabled?)
    end

    # Shown once on the next page in a box that stays put (regular flash
    # messages fade after a few seconds).
    def issue_password(user, password)
      flash[:issued_password] = { "email" => user.email, "password" => password }
    end

    def generated_password
      SecureRandom.base58(16)
    end
  end
end
