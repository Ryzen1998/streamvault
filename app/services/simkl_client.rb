# frozen_string_literal: true

# Simkl API client (https://api.simkl.org). Accounts link with Simkl's PIN
# flow, which needs only the app's client id: the user enters a short code at
# simkl.com/pin and the app polls for the access token. Tokens never expire;
# users revoke them in Simkl's connected-apps settings.
class SimklClient
  BASE_URL = ENV.fetch("SIMKL_API_BASE_URL", "https://api.simkl.com")

  Pin = Struct.new(:user_code, :verification_url, :expires_in, :interval, keyword_init: true)

  def self.client_id
    ENV["SIMKL_CLIENT_ID"].to_s.strip
  end

  def self.configured?
    client_id.present?
  end

  def initialize(access_token: nil, connection: nil)
    @connection = connection || Faraday.new(url: BASE_URL) do |faraday|
      faraday.request :json
      faraday.response :json
      faraday.adapter Faraday.default_adapter
      faraday.options.timeout = 15
      faraday.options.open_timeout = 5
      faraday.headers["simkl-api-key"] = self.class.client_id
      faraday.headers["User-Agent"] = "StreamVault"
      faraday.headers["Authorization"] = "Bearer #{access_token}" if access_token.present?
    end
  end

  def request_pin
    response = @connection.get("oauth/pin", client_id: self.class.client_id)
    body = response.body
    return failure(response) unless response.success? && body.is_a?(Hash) && body["user_code"].present?

    ServiceResult.success(Pin.new(
      user_code: body["user_code"],
      verification_url: body["verification_url"].presence || "https://simkl.com/pin/",
      expires_in: body["expires_in"].to_i.positive? ? body["expires_in"].to_i : 900,
      interval: body["interval"].to_i.clamp(5, 60)
    ))
  rescue Faraday::Error => e
    ServiceResult.failure("Could not reach Simkl (#{e.class.name.demodulize})")
  end

  # Success with the access token once the user has entered the code;
  # failure (:pending) while they haven't.
  def pin_status(user_code)
    response = @connection.get("oauth/pin/#{ERB::Util.url_encode(user_code)}", client_id: self.class.client_id)
    body = response.body
    return ServiceResult.success(body["access_token"]) if response.success? && body.is_a?(Hash) && body["result"] == "OK" && body["access_token"].present?
    return ServiceResult.failure(body["message"].presence || "Authorization pending", :pending) if response.success?

    failure(response)
  rescue Faraday::Error => e
    ServiceResult.failure("Could not reach Simkl (#{e.class.name.demodulize})")
  end

  # The linked account's display name.
  def username
    response = @connection.post("users/settings")
    return failure(response) unless response.success? && response.body.is_a?(Hash)

    ServiceResult.success(response.body.dig("user", "name").presence || "Simkl user")
  rescue Faraday::Error => e
    ServiceResult.failure("Could not reach Simkl (#{e.class.name.demodulize})")
  end

  # POST /sync/history: { movies: [...], shows: [...] }
  def add_to_history(movies: [], shows: [])
    response = @connection.post("sync/history", { movies: movies, shows: shows })
    response.success? ? ServiceResult.success(response.body) : failure(response)
  rescue Faraday::Error => e
    ServiceResult.failure("Could not reach Simkl (#{e.class.name.demodulize})")
  end

  private

  def failure(response)
    code = response.body["error"] if response.body.is_a?(Hash)
    message = if code == "client_id_failed"
      "Simkl rejected this server's client id. Ask an admin to check SIMKL_CLIENT_ID."
    elsif response.status == 401
      "Simkl rejected the access token"
    end
    ServiceResult.failure(message || code.presence || "Simkl request failed (HTTP #{response.status})", response.status)
  end
end
