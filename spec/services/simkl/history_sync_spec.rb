require "rails_helper"

RSpec.describe Simkl::HistorySync do
  let(:user) { create(:user) }
  let(:connection) { create(:simkl_connection, user: user) }
  let(:client) { instance_double(SimklClient) }
  let(:watched_at) { Time.utc(2026, 10, 1, 20, 0, 0) }

  subject(:sync) { described_class.new(connection, client: client) }

  let!(:finished_movie) do
    create(:playback_progress, :movie, user: user, imdb_id: "tt1375666", title: "Inception",
      progress_seconds: 7_100, duration_seconds: 7_200, watched_at: watched_at)
  end
  let!(:finished_episode) do
    create(:playback_progress, :episode, user: user, imdb_id: "tt0903747", title: "Breaking Bad",
      season_number: 1, episode_number: 2, progress_seconds: 2_900, duration_seconds: 2_940, watched_at: watched_at)
  end
  let!(:unfinished_movie) do
    create(:playback_progress, :movie, user: user, imdb_id: "tt0816692", progress_seconds: 600, duration_seconds: 7_200)
  end

  it "adds finished titles to Simkl history and marks them sent" do
    allow(client).to receive(:add_to_history).and_return(ServiceResult.success({}))

    result = sync.call

    expect(result.data).to eq(2)
    expect(client).to have_received(:add_to_history).with(
      movies: [ { title: "Inception", ids: { imdb: "tt1375666" }, watched_at: "2026-10-01T20:00:00Z" } ],
      shows: [ {
        title: "Breaking Bad",
        ids: { imdb: "tt0903747" },
        seasons: [ { number: 1, episodes: [ { number: 2, watched_at: "2026-10-01T20:00:00Z" } ] } ]
      } ]
    )
    expect(finished_movie.reload.simkl_synced_at).to be_present
    expect(unfinished_movie.reload.simkl_synced_at).to be_nil
    expect(connection.reload).to have_attributes(last_error: nil)
    expect(connection.last_synced_at).to be_present
  end

  it "never sends a title twice" do
    allow(client).to receive(:add_to_history).and_return(ServiceResult.success({}))
    sync.call

    sync.call

    expect(client).to have_received(:add_to_history).once
  end

  it "keeps titles pending and records the error when Simkl fails" do
    allow(client).to receive(:add_to_history).and_return(ServiceResult.failure("Simkl rejected the access token"))

    expect(sync.call).to be_failure
    expect(finished_movie.reload.simkl_synced_at).to be_nil
    expect(connection.reload.last_error).to eq("Simkl rejected the access token")
  end
end
