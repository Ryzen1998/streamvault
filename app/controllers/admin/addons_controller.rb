# frozen_string_literal: true

module Admin
  # Admin-only management of installed Stremio addons. Addons are the single
  # source of stream/catalog/meta sources; the playback layer only trusts the
  # hosts configured here.
  class AddonsController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!
    before_action :set_addon, only: [ :edit, :update, :destroy, :refresh ]

    def index
      @addons = Addon.ordered
    end

    def new
      @addon = Addon.new
    end

    def create
      @addon = Addon.new(addon_params)
      unless @addon.valid?
        return render :new, status: :unprocessable_entity
      end

      result = Addons::Client.new(url: @addon.url).fetch_manifest!
      if result.success?
        apply_manifest(@addon, result.data)
        if @addon.save
          redirect_to admin_addons_path, notice: "Addon added."
        else
          render :new, status: :unprocessable_entity
        end
      else
        @addon.errors.add(:url, result.error_message)
        render :new, status: :unprocessable_entity
      end
    end

    def update
      @addon.assign_attributes(addon_params)

      if @addon.url_changed? && @addon.valid?
        result = Addons::Client.new(url: @addon.url).fetch_manifest!
        unless result.success?
          @addon.errors.add(:url, result.error_message)
          return render :edit, status: :unprocessable_entity
        end
        apply_manifest(@addon, result.data)
      end

      if @addon.save
        redirect_to admin_addons_path, notice: "Addon updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @addon.destroy
      redirect_to admin_addons_path, notice: "Addon removed."
    end

    # Re-fetch the manifest to refresh name/id/types.
    def refresh
      result = Addons::Client.new(url: @addon.url).fetch_manifest!
      if result.success?
        apply_manifest(@addon, result.data)
        @addon.save
        redirect_to admin_addons_path, notice: "Manifest refreshed."
      else
        @addon.update_columns(last_error: result.error_message, last_checked_at: Time.current)
        redirect_to admin_addons_path, alert: "Refresh failed: #{result.error_message}"
      end
    end

    private

    def set_addon
      @addon = Addon.find(params[:id])
    end

    def addon_params
      params.require(:addon).permit(:url, :name, :enabled, :position, :trust_source_hosts)
    end

    def apply_manifest(addon, manifest)
      addon.name = manifest["name"].presence || addon.name
      addon.manifest_id = manifest["id"]
      addon.manifest_types = Array(manifest["types"])
      addon.last_checked_at = Time.current
      addon.last_error = nil
    end
  end
end
