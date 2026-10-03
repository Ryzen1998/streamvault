# frozen_string_literal: true

module Catalog
  # Single entry point for browse/metadata reads. Prefers installed Stremio
  # addons and silently falls back to Cinemeta so the UI never breaks when an
  # addon is empty, slow, or misconfigured.
  class Resolver
    CINEMETA_ROWS = {
      popular: [ "Popular Movies", "movie", "top", nil ],
      trending: [ "Trending Movies", "movie", "year", Date.current.year.to_s ],
      popular_shows: [ "Popular Shows", "show", "top", nil ],
      trending_shows: [ "Trending Shows", "show", "year", Date.current.year.to_s ]
    }.freeze

    DEFAULT_PAGE_SIZE = 24
    MAX_PAGE_SIZE = 100

    def initialize(cinemeta: Catalog::CinemetaClient.new, addons: Addons::CatalogSource.new, logger: Rails.logger)
      @cinemeta = cinemeta
      @addons = addons
      @logger = logger
    end

    # [{ title:, type:, items: [...], source: {...} }] — addon catalogs first,
    # Cinemeta fallback.
    def home_rows(limit: 20)
      rows = safely { @addons.rows(limit: limit) }
      return rows if rows.present?

      cinemeta_rows(limit: limit)
    end

    # Addon meta first, Cinemeta fallback. Never raises.
    def metadata(imdb_id, type)
      return ServiceResult.failure("IMDB ID is required") if imdb_id.blank?

      result = safely { @addons.meta(imdb_id, type) }
      return result if result&.success?

      @cinemeta.metadata(imdb_id, type)
    end

    # Searchable addon catalogs first, then Cinemeta, one entry per title.
    # Cinemeta alone when no addon can search or all of them fail.
    def search(query)
      addon_search = Thread.new { safely { @addons.search(query) } }
      cinemeta = @cinemeta.search(query)
      addon_results = Array(addon_search.value)
      return cinemeta if addon_results.empty?

      merged = addon_results + (cinemeta.success? ? cinemeta.data : [])
      ServiceResult.success(merged.uniq { |item| [ item[:type], item[:imdb_id] ] })
    end

    # One page of a catalog.
    # → ServiceResult<{ items:, has_more:, page:, size:, next_size:, title: }>
    def catalog_page(provider:, reference:, type:, catalog_id:, genre:, page:, size:, title:)
      return ServiceResult.failure("Catalog not specified") if type.blank? || catalog_id.blank?

      page = [ page.to_i, 1 ].max
      size = size.to_i.clamp(1, MAX_PAGE_SIZE)
      skip = (page - 1) * size

      if provider.to_s == "addon"
        addon_page(reference: reference, type: type, catalog_id: catalog_id, genre: genre, skip: skip, page: page, size: size, title: title)
      else
        cinemeta_page(type: type, catalog_id: catalog_id, genre: genre, skip: skip, page: page, size: size, title: title)
      end
    end

    private

    def addon_page(reference:, type:, catalog_id:, genre:, skip:, page:, size:, title:)
      entry = @addons.find_entry(reference)
      return ServiceResult.failure("Catalog not found") unless entry

      result = @addons.page(entry: entry, type: type, catalog_id: catalog_id, skip: skip, genre: genre, max: MAX_PAGE_SIZE)
      return ServiceResult.failure(result.error_message) if result.failure?

      items = result.data
      ServiceResult.success(
        items: items,
        has_more: items.any?,
        page: page,
        size: size,
        next_size: items.length.positive? ? items.length : size,
        title: title
      )
    end

    def cinemeta_page(type:, catalog_id:, genre:, skip:, page:, size:, title:)
      # Over-request by one to know whether another page exists.
      result = @cinemeta.catalog(type, catalog_id, genre: genre, limit: size + 1, skip: skip)
      return ServiceResult.failure(result.error_message) if result.failure?

      items = result.data
      ServiceResult.success(
        items: items.first(size),
        has_more: items.length > size,
        page: page,
        size: size,
        next_size: size,
        title: title
      )
    end

    def safely
      yield
    rescue StandardError => e
      @logger.warn("[Catalog::Resolver] #{e.class}: #{e.message}")
      nil
    end

    def cinemeta_rows(limit:)
      results = HomeCatalogService.new(@cinemeta, limit: limit).call
      CINEMETA_ROWS.filter_map do |key, (title, type, catalog_id, genre)|
        result = results[key]
        next unless result&.success? && result.data.any?

        {
          title: title,
          type: type,
          items: result.data,
          source: { "provider" => "cinemeta", "catalog_id" => catalog_id, "genre" => genre }
        }
      end
    end
  end
end
