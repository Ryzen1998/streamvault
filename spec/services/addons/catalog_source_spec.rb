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
end
