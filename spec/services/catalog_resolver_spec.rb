require "rails_helper"

RSpec.describe Catalog::Resolver do
  subject(:resolver) { described_class.new(cinemeta: cinemeta, addons: addons) }

  let(:cinemeta) { instance_double(Catalog::CinemetaClient) }
  let(:addons) { instance_double(Addons::CatalogSource) }

  describe "#home_rows" do
    it "prefers addon rows" do
      rows = [ { title: "Addon Row", type: "movie", items: [ { imdb_id: "tt1" } ] } ]
      allow(addons).to receive(:rows).and_return(rows)

      expect(resolver.home_rows).to eq(rows)
    end

    it "falls back to Cinemeta when addons return nothing" do
      allow(addons).to receive(:rows).and_return([])
      allow(cinemeta).to receive(:popular).and_return(ServiceResult.success([ { imdb_id: "tt1", title: "One" } ]))
      allow(cinemeta).to receive(:trending).and_return(ServiceResult.success([]))

      rows = resolver.home_rows

      expect(rows.map { |row| row[:title] }).to contain_exactly("Popular Movies", "Popular Shows")
    end

    it "falls back silently when the addon source raises" do
      allow(addons).to receive(:rows).and_raise(StandardError, "boom")
      allow(cinemeta).to receive(:popular).and_return(ServiceResult.success([]))
      allow(cinemeta).to receive(:trending).and_return(ServiceResult.success([]))

      expect(resolver.home_rows).to eq([])
    end
  end

  describe "#metadata" do
    it "prefers addon metadata" do
      allow(addons).to receive(:meta).and_return(ServiceResult.success({ imdb_id: "tt1", title: "Addon" }))

      expect(resolver.metadata("tt1", "movie").data[:title]).to eq("Addon")
    end

    it "falls back to Cinemeta when the addon has no metadata" do
      allow(addons).to receive(:meta).and_return(ServiceResult.failure("not found"))
      allow(cinemeta).to receive(:metadata).with("tt1", "movie")
        .and_return(ServiceResult.success({ imdb_id: "tt1", title: "Cinemeta" }))

      expect(resolver.metadata("tt1", "movie").data[:title]).to eq("Cinemeta")
    end

    it "falls back silently when the addon source raises" do
      allow(addons).to receive(:meta).and_raise(StandardError, "boom")
      allow(cinemeta).to receive(:metadata).with("tt1", "movie")
        .and_return(ServiceResult.success({ imdb_id: "tt1", title: "Cinemeta" }))

      expect(resolver.metadata("tt1", "movie").data[:title]).to eq("Cinemeta")
    end

    it "fails on a blank id" do
      expect(resolver.metadata("", "movie")).to be_failure
    end
  end

  describe "#search" do
    it "delegates to Cinemeta" do
      allow(cinemeta).to receive(:search).with("dune").and_return(ServiceResult.success([ { imdb_id: "tt1" } ]))

      expect(resolver.search("dune")).to be_success
    end
  end

  describe "#catalog_page" do
    it "pages an addon catalog, advancing by the returned count" do
      entry = Addons::Registry::Entry.new(url: "https://a.example/manifest.json", name: "A", reference: "1")
      allow(addons).to receive(:find_entry).with("1").and_return(entry)
      allow(addons).to receive(:page)
        .with(entry: entry, type: "movie", catalog_id: "top", skip: 20, genre: nil, max: 100)
        .and_return(ServiceResult.success([ { imdb_id: "tt1" } ]))

      result = resolver.catalog_page(
        provider: "addon", reference: "1", type: "movie", catalog_id: "top",
        genre: nil, page: 2, size: 20, title: "Top"
      )

      expect(result).to be_success
      expect(result.data[:items].length).to eq(1)
      expect(result.data[:next_size]).to eq(1)
      expect(result.data[:has_more]).to be(true)
    end

    it "over-requests Cinemeta to detect more pages" do
      allow(cinemeta).to receive(:catalog)
        .with("movie", "top", genre: nil, limit: 4, skip: 3)
        .and_return(ServiceResult.success([ { imdb_id: "a" }, { imdb_id: "b" }, { imdb_id: "c" }, { imdb_id: "d" } ]))

      result = resolver.catalog_page(
        provider: "cinemeta", reference: nil, type: "movie", catalog_id: "top",
        genre: nil, page: 2, size: 3, title: "Top"
      )

      expect(result.data[:items].length).to eq(3)
      expect(result.data[:has_more]).to be(true)
      expect(result.data[:next_size]).to eq(3)
    end

    it "fails when the addon reference is unknown" do
      allow(addons).to receive(:find_entry).and_return(nil)

      result = resolver.catalog_page(
        provider: "addon", reference: "missing", type: "movie", catalog_id: "top",
        genre: nil, page: 1, size: 24, title: nil
      )

      expect(result).to be_failure
    end

    it "fails without a catalog id" do
      expect(resolver.catalog_page(provider: "cinemeta", reference: nil, type: "movie", catalog_id: nil, genre: nil, page: 1, size: 24, title: nil)).to be_failure
    end
  end
end
