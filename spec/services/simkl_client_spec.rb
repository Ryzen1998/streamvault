require "rails_helper"

RSpec.describe SimklClient do
  around { |example| with_simkl_client_id("app-client-id") { example.run } }

  def stub_simkl(method, path, body, status: 200)
    stub_request(method, "https://api.simkl.com/#{path}")
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  it "is configured only with a client id" do
    expect(described_class).to be_configured
    with_simkl_client_id("") { expect(described_class).not_to be_configured }
  end

  describe "#request_pin" do
    it "returns the code to show the user" do
      stub_simkl(:get, "oauth/pin?client_id=app-client-id",
        { result: "OK", user_code: "AB12C", verification_url: "https://simkl.com/pin/", expires_in: 900, interval: 5 })

      pin = described_class.new.request_pin.data

      expect(pin).to have_attributes(user_code: "AB12C", verification_url: "https://simkl.com/pin/", expires_in: 900, interval: 5)
    end
  end

  it "explains a rejected client id" do
    stub_simkl(:get, "oauth/pin?client_id=app-client-id", { error: "client_id_failed" }, status: 412)

    expect(described_class.new.request_pin.error_message).to include("SIMKL_CLIENT_ID")
  end

  describe "#pin_status" do
    it "reports pending until approved" do
      stub_simkl(:get, "oauth/pin/AB12C?client_id=app-client-id", { result: "KO", message: "Authorization pending" })

      result = described_class.new.pin_status("AB12C")

      expect(result).to be_failure
      expect(result.error_code).to eq(:pending)
    end

    it "returns the access token once approved" do
      stub_simkl(:get, "oauth/pin/AB12C?client_id=app-client-id", { result: "OK", access_token: "user-token" })

      expect(described_class.new.pin_status("AB12C").data).to eq("user-token")
    end
  end

  describe "#add_to_history" do
    it "sends the app key, the user's token and the titles" do
      request = stub_request(:post, "https://api.simkl.com/sync/history")
        .with(
          headers: { "simkl-api-key" => "app-client-id", "Authorization" => "Bearer user-token" },
          body: { movies: [ { ids: { imdb: "tt1375666" } } ], shows: [] }.to_json
        )
        .to_return(status: 201, body: { added: { movies: 1 } }.to_json, headers: { "Content-Type" => "application/json" })

      result = described_class.new(access_token: "user-token").add_to_history(movies: [ { ids: { imdb: "tt1375666" } } ])

      expect(result).to be_success
      expect(request).to have_been_requested
    end

    it "explains a revoked token" do
      stub_simkl(:post, "sync/history", { error: "user_token_failed" }, status: 401)

      result = described_class.new(access_token: "revoked").add_to_history(movies: [])

      expect(result.error_message).to eq("Simkl rejected the access token")
    end
  end
end
