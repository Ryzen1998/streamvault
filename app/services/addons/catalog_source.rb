# frozen_string_literal: true

module Addons
  # Reads catalogs and metadata from the installed Stremio addons.
  #
  # Home rows are built from each addon's declared `catalogs`; if an addon
  # exposes no catalogs (many, including a default AIOStreams config, don't)
  # the caller falls back to another source.
  class CatalogSource
    MAX_ROWS = 8
    MAX_SEARCH_CATALOGS = 6

    def initialize(registry: nil, logger: Rails.logger, cache: Rails.cache)
      @entries = registry || Addons::Registry.entries
      @logger = logger
      @cache = cache
    end

    # Returns [{ title:, type:, items: [summary, ...] }] for every usable
    # addon catalog, up to MAX_ROWS.
    def rows(limit: 20)
      pairs = catalog_pairs
      return [] if pairs.empty?

      pairs.first(MAX_ROWS).map do |pair|
        Thread.new { build_row(pair, limit) }
      end.map(&:value).compact
    rescue StandardError => e
      @logger.warn("[Addons::CatalogSource] rows failed: #{e.class}: #{e.message}")
      []
    end

    # Searches every addon catalog that declares a `search` extra, in parallel.
    # Only IMDb-keyed titles are kept, since playback and tracking use IMDb ids.
    def search(query)
      return [] if query.blank?

      pairs = catalog_pairs.select { |pair| searchable?(pair[:catalog]) }.first(MAX_SEARCH_CATALOGS)
      pairs.map { |pair| Thread.new { search_catalog(pair, query) } }
        .flat_map(&:value)
        .uniq { |item| [ item[:type], item[:imdb_id] ] }
    end

    # First addon that can serve metadata for the id wins.
    def meta(imdb_id, type)
      @entries.each do |entry|
        result = client_for(entry).meta(type, imdb_id)
        return result if result.success?
      end
      ServiceResult.failure("Metadata not found")
    end

    def find_entry(reference)
      return nil if reference.blank?

      @entries.find { |entry| entry.reference == reference }
    end

    # One page of an addon catalog. `skip` is the offset; the addon decides the
    # page size, so callers should advance by the returned item count.
    def page(entry:, type:, catalog_id:, skip: 0, genre: nil, max: 100)
      result = client_for(entry).catalog(type, catalog_id, skip: skip, genre: genre)
      return result if result.failure?

      items = result.data.filter_map { |meta| Addons::MetaAdapter.summary(meta, type) }
        .reject { |item| item[:imdb_id].blank? || item[:title].blank? }
      ServiceResult.success(items.first(max))
    end

    private

    def catalog_pairs
      @entries.flat_map do |entry|
        client = client_for(entry)
        client.catalogs.filter_map do |catalog|
          type = supported_type(catalog["type"])
          next unless type

          { client: client, entry: entry, catalog: catalog, type: type, addon_name: entry.name }
        end
      end
    end

    def build_row(pair, limit)
      result = pair[:client].catalog(pair[:type], pair[:catalog]["id"])
      return nil unless result.success?

      items = result.data.filter_map { |meta| Addons::MetaAdapter.summary(meta, pair[:type]) }
        .reject { |item| item[:imdb_id].blank? || item[:title].blank? }
      return nil if items.empty?

      { title: row_title(pair), type: pair[:type], items: items.first(limit), source: row_source(pair) }
    rescue StandardError => e
      @logger.warn("[Addons::CatalogSource] catalog row failed: #{e.class}: #{e.message}")
      nil
    end

    def search_catalog(pair, query)
      result = pair[:client].catalog(pair[:type], pair[:catalog]["id"], search: query)
      return [] unless result.success?

      result.data.filter_map { |meta| Addons::MetaAdapter.summary(meta, pair[:type]) }
        .select { |item| item[:title].present? && item[:imdb_id].match?(ContentRef::IMDB_ID_PATTERN) }
    rescue StandardError => e
      @logger.warn("[Addons::CatalogSource] search failed: #{e.class}: #{e.message}")
      []
    end

    # Catalog extras come as `extra: [{ "name": "search" }]`, or the legacy
    # `extraSupported: ["search"]`.
    def searchable?(catalog)
      names = Array(catalog["extra"]).filter_map { |extra| extra["name"] if extra.is_a?(Hash) }
      (names + Array(catalog["extraSupported"])).map(&:to_s).include?("search")
    end

    def row_source(pair)
      {
        "provider" => "addon",
        "reference" => pair[:entry].reference,
        "catalog_id" => pair[:catalog]["id"],
        "genre" => pair[:catalog]["genre"]
      }
    end

    def row_title(pair)
      pair[:catalog]["name"].presence || pair[:addon_name].presence || "Catalog"
    end

    # Only movie/series catalogs map onto StreamVault's content types.
    def supported_type(type)
      case type.to_s
      when "movie" then "movie"
      when "series", "show" then "show"
      end
    end

    def client_for(entry)
      @clients ||= {}
      @clients[entry.base_url] ||= entry.client(logger: @logger, cache: @cache)
    end
  end
end
