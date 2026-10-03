# frozen_string_literal: true

module Admin
  # Admin-only management of the instance-wide debrid account (TorBox or
  # RealDebrid). Every user streams through it; users never see the key.
  class DebridController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    def show
      @account = DebridAccount.current || DebridAccount.new(service: Debrid::SERVICES.keys.first)
      @environment_account = Debrid.from_environment
    end

    def update
      @account = DebridAccount.current || DebridAccount.new
      @account.service = debrid_params[:service]
      new_key = debrid_params[:api_key].to_s.strip
      if new_key.present?
        @account.api_key = new_key
      elsif @account.service_changed?
        # A key belongs to one service; switching service needs a new key.
        @account.api_key = nil
      end

      unless @account.valid?
        @environment_account = Debrid.from_environment
        return render :show, status: :unprocessable_entity
      end

      result = @account.to_debrid.verify
      @account.apply_verification(result)
      @account.save!

      if result.success?
        redirect_to admin_debrid_path, notice: "#{@account.service_name} account saved and verified."
      else
        redirect_to admin_debrid_path, alert: "#{@account.service_name} account saved, but the key could not be verified: #{result.error_message}"
      end
    end

    def destroy
      DebridAccount.destroy_all
      redirect_to admin_debrid_path, notice: "Debrid account removed."
    end

    private

    def debrid_params
      params.require(:debrid_account).permit(:service, :api_key)
    end
  end
end
