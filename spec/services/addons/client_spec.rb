require "rails_helper"

RSpec.describe Addons::Client do
  let(:base) { "https://addon.example.com" }
  subject(:client) { described_class.new(url: "#{base}/manifest.json") }

  def stub_json(url, body, status: 200)
    stub_request(:get, url).to_return(
      status: status,
      body: body.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  describe ".normalize_base_url" do
    it "strips /manifest.json and trailing slashes" do
      expect(described_class.normalize_base_url("https://a.example/manifest.json")).to eq("https://a.example")
      expect(described_class.normalize_base_url("https://a.example/stremio/u/p/")).to eq("https://a.example/stremio/u/p")
    end

    it "preserves config path segments" do
      expect(described_class.normalize_base_url("https://a.example/stremio/uuid/pw/manifest.json"))
        .to eq("https://a.example/stremio/uuid/pw")
    end
  end

  describe "#manifest" do
    it "fetches and returns the manifest" do
      stub_json("#{base}/manifest.json", { "id" => "org.test", "name" => "Test", "types" => %w[movie series] })

      expect(client.manifest_id).to eq("org.test")
      expect(client.manifest_name).to eq("Test")
      expect(client.supports_type?("show")).to be(true)
      expect(client.supports_type?("movie")).to be(true)
    end

    it "returns an empty hash when the manifest request fails" do
      stub_json("#{base}/manifest.json", { "error" => "nope" }, status: 500)

      expect(client.manifest).to eq({})
    end
  end

  describe "#fetch_manifest!" do
    it "returns failure without an id" do
      stub_json("#{base}/manifest.json", { "name" => "no id" })

      expect(client.fetch_manifest!).to be_failure
    end

    it "returns success with a valid manifest" do
      stub_json("#{base}/manifest.json", { "id" => "org.test", "name" => "Test" })

      result = client.fetch_manifest!
      expect(result).to be_success
      expect(result.data["id"]).to eq("org.test")
    end
  end

  describe "#streams" do
    it "requests the movie path" do
      stub_json("#{base}/stream/movie/tt1375666.json", { "streams" => [ { "url" => "#{base}/p/1" } ] })

      result = client.streams("tt1375666", "movie")
      expect(result).to be_success
      expect(result.data.length).to eq(1)
    end

    it "requests the episode path for shows" do
      stub_json("#{base}/stream/series/tt123:1:2.json", { "streams" => [] })

      result = client.streams("tt123", "show", season: 1, episode: 2)
      expect(result).to be_success
      expect(result.data).to eq([])
    end

    it "returns an empty list on 404" do
      stub_request(:get, "#{base}/stream/movie/tt999.json").to_return(status: 404)

      expect(client.streams("tt999", "movie")).to be_success
      expect(client.streams("tt999", "movie").data).to eq([])
    end

    it "returns failure on a server error" do
      stub_request(:get, "#{base}/stream/movie/tt999.json").to_return(status: 500)

      expect(client.streams("tt999", "movie")).to be_failure
    end

    it "fails without an imdb id" do
      expect(client.streams("", "movie")).to be_failure
    end
  end

  describe "#catalog" do
    it "fetches catalog entries" do
      stub_json("#{base}/catalog/movie/top.json", { "metas" => [ { "id" => "tt1", "name" => "One" } ] })

      result = client.catalog("movie", "top")
      expect(result).to be_success
      expect(result.data.first["id"]).to eq("tt1")
    end

    it "includes skip and genre as extra arguments" do
      stub_request(:get, "#{base}/catalog/movie/top/genre=Action&skip=20.json")
        .to_return(status: 200, body: { "metas" => [] }.to_json, headers: { "Content-Type" => "application/json" })

      expect(client.catalog("movie", "top", skip: 20, genre: "Action")).to be_success
    end
  end

  describe "#meta" do
    it "fetches meta" do
      stub_json("#{base}/meta/movie/tt1375666.json", { "meta" => { "id" => "tt1375666", "name" => "Inception" } })

      result = client.meta("movie", "tt1375666")
      expect(result).to be_success
      expect(result.data["name"]).to eq("Inception")
    end
  end
end
