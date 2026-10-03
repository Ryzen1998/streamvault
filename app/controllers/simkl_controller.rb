# frozen_string_literal: true

# Links the signed-in account to its own Simkl account with Simkl's PIN flow,
# then keeps its Simkl history up to date (see Simkl::HistorySync).
class SimklController < ApplicationController
  before_action :authenticate_user!
  before_action :require_simkl!

  # Pairing page: shows the code and polls #status until Simkl approves.
  def show
    return redirect_to settings_path if current_user.simkl_connection

    @pin = pending_pin
    redirect_to settings_path, alert: "That Simkl code expired. Start again." unless @pin
  end

  def create
    result = SimklClient.new.request_pin
    return redirect_to settings_path, alert: result.error_message if result.failure?

    pin = result.data
    session[:simkl_pin] = {
      "user_code" => pin.user_code,
      "verification_url" => pin.verification_url,
      "interval" => pin.interval,
      "expires_at" => pin.expires_in.seconds.from_now.to_i
    }
    redirect_to simkl_path
  end

  # Polled by the pairing page (JSON); the "Check now" button uses HTML.
  def status
    state, message = pairing_state
    respond_to do |format|
      format.json { render json: { state: state, message: message }.compact }
      format.html do
        if state == "connected"
          redirect_to settings_path, notice: "Simkl linked."
        elsif state == "pending"
          redirect_to simkl_path, notice: "Not approved yet. Enter the code on Simkl, then check again."
        else
          redirect_to settings_path, alert: message || "That Simkl code expired. Start again."
        end
      end
    end
  end

  def sync
    return redirect_to settings_path, alert: "Link Simkl first." unless current_user.simkl_connection

    SimklHistorySyncJob.perform_later(current_user.id)
    redirect_to settings_path, notice: "Sending your finished titles to Simkl."
  end

  def destroy
    current_user.simkl_connection&.destroy
    session.delete(:simkl_pin)
    redirect_to settings_path, notice: "Simkl unlinked. You can also remove StreamVault under Connected apps on Simkl."
  end

  private

  def require_simkl!
    redirect_to settings_path, alert: "Simkl isn't set up on this server." unless SimklClient.configured?
  end

  def pending_pin
    pin = session[:simkl_pin]
    pin if pin.is_a?(Hash) && pin["expires_at"].to_i > Time.current.to_i
  end

  # → [state, message] where state is pending, connected, expired or error.
  def pairing_state
    return [ "connected" ] if current_user.simkl_connection

    pin = pending_pin
    return [ "expired" ] unless pin

    result = SimklClient.new.pin_status(pin["user_code"])
    return [ "pending" ] if result.failure? && result.error_code == :pending
    return [ "error", result.error_message ] if result.failure?

    link_account(result.data)
    [ "connected" ]
  end

  # Saves the token and sends titles finished before linking.
  def link_account(access_token)
    username = SimklClient.new(access_token: access_token).username
    connection = SimklConnection.find_or_initialize_by(user: current_user)
    connection.update!(access_token: access_token, username: username.success? ? username.data : nil, last_error: nil)
    session.delete(:simkl_pin)
    SimklHistorySyncJob.perform_later(current_user.id)
  end
end
