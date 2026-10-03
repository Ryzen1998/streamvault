require "rails_helper"

RSpec.describe Addons::MetaAdapter do
  describe ".summary" do
    it "normalizes a catalog preview" do
      meta = {
        "id" => "tt1375666", "type" => "movie", "name" => "Inception",
        "poster" => "https://img/p.jpg", "releaseInfo" => "2010", "imdbRating" => "8.8"
      }

      expect(described_class.summary(meta, "movie")).to include(
        imdb_id: "tt1375666", title: "Inception", year: "2010",
        type: "movie", poster_url: "https://img/p.jpg", imdb_rating: "8.8"
      )
    end

    it "maps series to show" do
      expect(described_class.summary({ "id" => "tt1", "name" => "S" }, "series")[:type]).to eq("show")
    end

    it "returns nil for non-hash input" do
      expect(described_class.summary(nil, "movie")).to be_nil
    end
  end

  describe ".metadata" do
    let(:meta) do
      {
        "id" => "tt0903747", "name" => "Breaking Bad", "releaseInfo" => "2008",
        "description" => "A chemistry teacher...", "genres" => %w[Crime Drama],
        "cast" => [ "Bryan Cranston" ], "imdbRating" => "9.5", "runtime" => "PT49M",
        "videos" => [
          {
            "id" => "tt0903747:1:1", "season" => 1, "episode" => 1,
            "name" => "Pilot", "released" => "2008-01-20", "runtime" => "PT58M"
          }
        ]
      }
    end

    it "normalizes metadata and episodes" do
      data = described_class.metadata(meta, "series")

      expect(data[:type]).to eq("show")
      expect(data[:genre]).to eq("Crime, Drama")
      expect(data[:actors]).to eq("Bryan Cranston")
      expect(data[:runtime_seconds]).to eq(49 * 60)
      expect(data[:total_seasons]).to eq(1)
      expect(data[:episodes].first).to include(
        season: 1, episode: 1, title: "Pilot", runtime_seconds: 58 * 60
      )
    end
  end

  describe ".parse_runtime_seconds" do
    it "parses ISO-8601, hours/minutes, and plain minutes" do
      expect(described_class.parse_runtime_seconds("PT1H30M")).to eq(5400)
      expect(described_class.parse_runtime_seconds("2h 15m")).to eq(8100)
      expect(described_class.parse_runtime_seconds("120")).to eq(7200)
      expect(described_class.parse_runtime_seconds(nil)).to be_nil
    end
  end
end
