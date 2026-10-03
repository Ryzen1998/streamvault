require "rails_helper"

RSpec.describe Addons::CatalogSource do
  subject(:source) { described_class.new(registry: [ entry ]) }

  let(:entry) do
    Addons::Registry::Entry.new(url: "https://addon.example.com/manifest.json", name: "Test Addon", reference: "addon-1")
  end

  def stub_json(url, body, status: 200)
    stub_request(:get, url).to_return(
      status: status,
      body: body.to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  before do
    stub_json("https://addon.example.com/manifest.json", {
      "id" => "org.test", "name" => "Test",
      "resources" => %w[catalog stream], "types" => %w[movie series],
      "catalogs" => [
        { "type" => "movie", "id" => "top", "name" => "Top Movies" },
        { "type" => "series", "id" => "shows", "name" => "Shows" },
        { "type" => "tv", "id" => "channels", "name" => "Channels" }
      ]
    })
    stub_json("https://addon.example.com/catalog/movie/top.json",
      { "metas" => [ { "id" => "tt1", "name" => "One", "poster" => "https://img/1.jpg" } ] })
    stub_json("https://addon.example.com/catalog/series/shows.json",
      { "metas" => [ { "id" => "tt2", "name" => "Two" } ] })
  end

  describe "#rows" do
    it "builds one row per supported catalog" do
      rows = source.rows

      expect(rows.map { |row| row[:title] }).to contain_exactly("Top Movies", "Shows")
      expect(rows.find { |row| row[:title] == "Top Movies" }[:items].first[:imdb_id]).to eq("tt1")
      expect(rows.find { |row| row[:title] == "Shows" }[:type]).to eq("show")
    end

    it "describes the catalog source for the row" do
      row = source.rows.find { |candidate| candidate[:title] == "Top Movies" }

      expect(row[:source]).to include(
        "provider" => "addon", "reference" => "addon-1", "catalog_id" => "top"
      )
    end

    it "skips unsupported catalog types" do
      expect(source.rows.map { |row| row[:title] }).not_to include("Channels")
    end

    it "returns [] when a catalog request fails" do
      stub_json("https://addon.example.com/catalog/movie/top.json", {}, status: 500)
      stub_json("https://addon.example.com/catalog/series/shows.json", {}, status: 500)

      expect(source.rows).to eq([])
    end
  end

  describe "#meta" do
    it "returns the first successful addon meta" do
      stub_json("https://addon.example.com/meta/movie/tt1.json", { "meta" => { "id" => "tt1", "name" => "One" } })

      result = source.meta("tt1", "movie")
      expect(result).to be_success
      expect(result.data["name"]).to eq("One")
    end

    it "returns failure when no addon can serve the id" do
      stub_json("https://addon.example.com/meta/movie/tt404.json", {}, status: 404)

      expect(source.meta("tt404", "movie")).to be_failure
    end
  end

  describe "#find_entry" do
    it "finds an entry by reference" do
      expect(source.find_entry("addon-1")).to eq(entry)
    end

    it "returns nil for unknown or blank references" do
      expect(source.find_entry("nope")).to be_nil
      expect(source.find_entry(nil)).to be_nil
    end
  end

  describe "#page" do
    it "requests the given offset and normalizes items" do
      stub_json("https://addon.example.com/catalog/movie/top/skip=20.json",
        { "metas" => [ { "id" => "tt9", "name" => "Nine" } ] })

      result = source.page(entry: entry, type: "movie", catalog_id: "top", skip: 20)

      expect(result).to be_success
      expect(result.data.map { |item| item[:imdb_id] }).to eq([ "tt9" ])
    end
  end

  describe "#search" do
    before do
      stub_json("https://addon.example.com/manifest.json", {
        "id" => "org.test", "name" => "Test", "resources" => %w[catalog], "types" => %w[movie series],
        "catalogs" => [
          { "type" => "movie", "id" => "tmdb.top", "extra" => [ { "name" => "search", "isRequired" => true } ] },
          { "type" => "series", "id" => "legacy", "extraSupported" => [ "search" ] },
          { "type" => "movie", "id" => "popular", "extra" => [ { "name" => "genre" } ] }
        ]
      })
    end

    it "searches catalogs that support it and keeps IMDb titles" do
      stub_json("https://addon.example.com/catalog/movie/tmdb.top/search=the+matrix.json", { "metas" => [
        { "id" => "tt0133093", "name" => "The Matrix" },
        { "id" => "kitsu:123", "name" => "Anime Matrix" },
        { "id" => "tmdb:999", "imdb_id" => "tt0234215", "name" => "The Matrix Reloaded" }
      ] })
      stub_json("https://addon.example.com/catalog/series/legacy/search=the+matrix.json", { "metas" => [
        { "id" => "tt0133093", "name" => "The Matrix" }
      ] })

      results = source.search("the matrix")

      expect(results.map { |item| [ item[:imdb_id], item[:type] ] })
        .to contain_exactly([ "tt0133093", "movie" ], [ "tt0234215", "movie" ], [ "tt0133093", "show" ])
      expect(WebMock).not_to have_requested(:get, %r{catalog/movie/popular})
    end

    it "does nothing for a blank query" do
      expect(source.search(" ")).to eq([])
      expect(WebMock).not_to have_requested(:get, %r{/catalog/})
    end
  end
end
