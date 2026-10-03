require "rails_helper"

RSpec.describe "Stats", type: :request do
  let(:user) { create(:user) }

  it "requires sign-in" do
    get stats_path
    expect(response).to redirect_to(new_user_session_path)
  end

  it "shows an empty state before anything is watched" do
    sign_in user
    get stats_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nothing watched yet")
  end

  it "shows the account's totals, activity chart and table view" do
    create(:playback_progress, :movie, user: user, progress_seconds: 7_100, duration_seconds: 7_200, watched_at: Time.current)
    create(:playback_progress, :episode, user: user, imdb_id: "tt0903747", title: "Breaking Bad",
      progress_seconds: 1_200, duration_seconds: 2_940, watched_at: Time.current)
    sign_in user

    get stats_path

    expect(response.body).to include("Time watched", "2h 18m", "Movies finished", "Activity, last 30 days",
      "Show as table", "Most watched shows", "Breaking Bad")
    expect(response.body).to include(%(aria-label="#{Time.zone.today.to_fs(:long)}: 2 titles"))
  end
end
