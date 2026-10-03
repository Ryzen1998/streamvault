require "rails_helper"

RSpec.describe Simkl::WatchlistImport do
  let(:user) { create(:user) }
  let(:connection) { create(:simkl_connection, user: user) }
  let(:client) { instance_double(SimklClient) }

  subject(:import) { described_class.new(connection, client: client) }

  def activities(movies:, shows:)
    ServiceResult.success("movies" => { "plantowatch" => movies }, "tv_shows" => { "plantowatch" => shows })
  end

  let(:movie_items) do
    [
      { "movie" => { "title" => "Dune: Part Two", "year" => 2024, "poster" => "12/12abc", "ids" => { "imdb" => "tt15239678" } } },
      { "movie" => { "title" => "No IMDb", "ids" => { "simkl" => 1 } } }
    ]
  end
  let(:show_items) do
    [ { "show" => { "title" => "Severance", "year" => 2022, "ids" => { "imdb" => "tt11280740" } } } ]
  end

  it "reads both lists in full on the first import and adds IMDb titles to the Wishlist" do
    allow(client).to receive(:activities).and_return(activities(movies: "2026-10-01T10:00:00Z", shows: "2026-10-02T10:00:00Z"))
    allow(client).to receive(:plan_to_watch).with("movies", date_from: nil).and_return(ServiceResult.success(movie_items))
    allow(client).to receive(:plan_to_watch).with("shows", date_from: nil).and_return(ServiceResult.success(show_items))

    expect(import.call.data).to eq(2)

    expect(user.collection_entries.wishlist.pluck(:imdb_id, :content_type)).to contain_exactly(
      [ "tt15239678", "movie" ], [ "tt11280740", "show" ]
    )
    expect(user.collection_entries.find_by(imdb_id: "tt15239678").poster_url)
      .to eq("https://wsrv.nl/?url=https://simkl.in/posters/12/12abc_ca.webp")
    expect(connection.reload.watchlist_activities).to eq("movies" => "2026-10-01T10:00:00Z", "shows" => "2026-10-02T10:00:00Z")
  end

  it "afterwards asks only for lists that changed, since the saved time" do
    connection.update!(watchlist_activities: { "movies" => "2026-10-01T10:00:00Z", "shows" => "2026-10-02T10:00:00Z" })
    allow(client).to receive(:activities).and_return(activities(movies: "2026-10-03T08:00:00Z", shows: "2026-10-02T10:00:00Z"))
    allow(client).to receive(:plan_to_watch).with("movies", date_from: "2026-10-01T10:00:00Z").and_return(ServiceResult.success([]))

    import.call

    expect(client).to have_received(:plan_to_watch).once
    expect(connection.reload.watchlist_activities["movies"]).to eq("2026-10-03T08:00:00Z")
  end

  it "leaves titles already in the Library alone" do
    create(:collection_entry, user: user, imdb_id: "tt15239678", list_state: :library)
    allow(client).to receive(:activities).and_return(activities(movies: "2026-10-01T10:00:00Z", shows: nil))
    allow(client).to receive(:plan_to_watch).with("movies", date_from: nil).and_return(ServiceResult.success(movie_items))

    expect(import.call.data).to eq(0)
    expect(user.collection_entries.find_by(imdb_id: "tt15239678")).to be_library
  end

  it "records Simkl errors without saving progress" do
    allow(client).to receive(:activities).and_return(ServiceResult.failure("Simkl rejected the access token"))

    expect(import.call).to be_failure
    expect(connection.reload).to have_attributes(last_error: "Simkl rejected the access token", watchlist_activities: nil)
  end
end
