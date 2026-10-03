class ApplicationController < ActionController::Base
  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes

  helper_method :signups_enabled?, :admin_user?, :addons_configured?, :debrid_configured?, :streaming_source_available?

  # Whether new user self-registration is enabled via ENV
  def signups_enabled?
    ENV["ENABLE_SIGNUPS"] == "true"
  end

  # True when the signed-in user holds the admin role. Used to gate the
  # addon management UI (only operators configure addons).
  def admin_user?
    user_signed_in? && current_user.admin?
  end

  # Whether any Stremio addon is installed. When true, streams come from the
  # addon, which resolves its own debrid links.
  def addons_configured?
    Addons::Registry.configured?
  end

  # Whether an admin has configured the instance-wide debrid account.
  def debrid_configured?
    @debrid_configured = Debrid.configured? if @debrid_configured.nil?
    @debrid_configured
  end

  # Whether playback can start at all: an addon is installed or an admin has
  # configured the debrid account. Users never supply keys themselves.
  def streaming_source_available?
    addons_configured? || debrid_configured?
  end


  # Rescue from record not found
  rescue_from ActiveRecord::RecordNotFound do |exception|
    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, alert: "Record not found." }
      format.json { render json: { error: "Not found" }, status: :not_found }
    end
  end

  private

  # Authorization guard for admin-only controllers.
  def require_admin!
    return if admin_user?

    redirect_to root_path, alert: "You are not authorized to access that page."
  end
end
