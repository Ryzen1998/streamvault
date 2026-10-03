require "rails_helper"

RSpec.describe Playback::WatchStats do
  let(:user) { create(:user) }
  let(:today) { Date.new(2026, 10, 3) }

  subject(:stats) { described_class.new(user, today: today).call }

  it "is empty without playback" do
    expect(stats).to be_empty
    expect(stats.activity.size).to eq(30)
    expect(stats.activity.map(&:count).uniq).to eq([ 0 ])
  end

  it "totals watch time and finished titles with the completion policy" do
    create(:playback_progress, :movie, user: user, progress_seconds: 6_900, duration_seconds: 7_200, watched_at: today.to_time)
    create(:playback_progress, :movie, user: user, progress_seconds: 600, duration_seconds: 7_200, watched_at: today.to_time)
    create(:playback_progress, :episode, user: user, imdb_id: "tt0903747", episode_number: 1,
      progress_seconds: 2_900, duration_seconds: 2_940, watched_at: today.to_time)

    expect(stats).to have_attributes(
      titles_count: 3,
      watched_seconds: 10_400,
      movies_finished: 1,
      episodes_finished: 1,
      in_progress_count: 1,
      shows_count: 1
    )
  end

  it "counts activity on the day each title was last watched" do
    create(:playback_progress, user: user, watched_at: (today - 1).to_time + 12.hours)
    create(:playback_progress, user: user, watched_at: (today - 1).to_time + 13.hours)
    create(:playback_progress, user: user, watched_at: (today - 40).to_time)

    activity = stats.activity.to_h { |day| [ day.date, day.count ] }

    expect(activity[today - 1]).to eq(2)
    expect(activity.values.sum).to eq(2)
    expect(stats.activity.last.date).to eq(today)
  end

  it "ranks shows by episodes watched" do
    2.times { |index| create(:playback_progress, :episode, user: user, imdb_id: "tt0903747", title: "Breaking Bad", episode_number: index + 1) }
    create(:playback_progress, :episode, user: user, imdb_id: "tt0944947", title: "Game of Thrones")

    expect(stats.top_shows.map { |show| [ show.title, show.episodes_watched ] })
      .to eq([ [ "Breaking Bad", 2 ], [ "Game of Thrones", 1 ] ])
  end

  it "only counts the account's own playback" do
    create(:playback_progress, user: create(:user))

    expect(stats).to be_empty
  end
end
