require "rails_helper"

RSpec.describe "Simkl", type: :request do
  let(:user) { create(:user) }

  around { |example| with_simkl_client_id("app-client-id") { example.run } }

  before { sign_in user }

  def stub_simkl(method, path, body, status: 200)
    stub_request(method, "https://api.simkl.com/#{path}")
      .to_return(status: status, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  def start_pairing
    stub_simkl(:get, "oauth/pin?client_id=app-client-id",
      { result: "OK", user_code: "AB12C", verification_url: "https://simkl.com/pin/", expires_in: 900, interval: 5 })
    post simkl_path
  end

  it "offers linking in Settings" do
    get settings_path

    expect(response.body).to include("Link Simkl")
  end

  it "hides Simkl when the server has no client id" do
    with_simkl_client_id("") do
      get settings_path
      expect(response.body).not_to include("Link Simkl")

      post simkl_path
      expect(response).to redirect_to(settings_path)
    end
  end

  it "shows the pairing code after starting" do
    start_pairing

    expect(response).to redirect_to(simkl_path)
    follow_redirect!
    expect(response.body).to include("AB12C", "simkl.com/pin")
  end

  it "keeps waiting while the code isn't approved" do
    start_pairing
    stub_simkl(:get, "oauth/pin/AB12C?client_id=app-client-id", { result: "KO", message: "Authorization pending" })

    get status_simkl_path(format: :json)

    expect(response.parsed_body).to eq("state" => "pending")
    expect(user.reload.simkl_connection).to be_nil
  end

  it "links the account once approved and sends earlier titles" do
    start_pairing
    stub_simkl(:get, "oauth/pin/AB12C?client_id=app-client-id", { result: "OK", access_token: "user-token" })
    stub_simkl(:post, "users/settings", { user: { name: "Ash" }, account: { id: 51 } })

    expect { get status_simkl_path(format: :json) }.to have_enqueued_job(SimklHistorySyncJob).with(user.id)

    expect(response.parsed_body).to eq("state" => "connected")
    expect(user.reload.simkl_connection).to have_attributes(access_token: "user-token", username: "Ash")
  end

  it "reports an expired code" do
    get status_simkl_path(format: :json)

    expect(response.parsed_body).to eq("state" => "expired")
  end

  it "syncs and unlinks a linked account" do
    create(:simkl_connection, user: user)

    expect { post sync_simkl_path }.to have_enqueued_job(SimklHistorySyncJob).with(user.id)

    delete simkl_path
    expect(user.reload.simkl_connection).to be_nil
  end

  it "imports the Simkl watchlist into the Wishlist" do
    create(:simkl_connection, user: user)
    stub_simkl(:post, "sync/activities", { movies: { plantowatch: "2026-10-01T10:00:00Z" }, tv_shows: { plantowatch: nil } })
    stub_simkl(:get, "sync/all-items/movies/plantowatch",
      { movies: [ { movie: { title: "Dune: Part Two", year: 2024, ids: { imdb: "tt15239678" } } } ] })

    post import_watchlist_simkl_path

    expect(flash[:notice]).to include("Added 1 title")
    expect(user.collection_entries.wishlist.pluck(:imdb_id)).to eq([ "tt15239678" ])
  end

  it "never shows the access token" do
    create(:simkl_connection, user: user, access_token: "SECRET_SIMKL_TOKEN")

    get settings_path

    expect(response.body).to include("Simkl Tester")
    expect(response.body).not_to include("SECRET_SIMKL_TOKEN")
  end
end
