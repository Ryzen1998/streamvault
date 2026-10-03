require 'rails_helper'

RSpec.describe StreamProvider, type: :service do
  let(:debrid) { Debrid::Account.new(service: "torbox", api_key: "tb_key") }

  around do |ex|
    old_provider = ENV["STREAM_PROVIDER"]
    old_comet = ENV["COMET_URL"]
    ex.run
  ensure
    ENV["STREAM_PROVIDER"] = old_provider
    ENV["COMET_URL"] = old_comet
  end

  describe '.providers' do
    it 'returns only Torrentio by default' do
      ENV["STREAM_PROVIDER"] = nil
      providers = described_class.providers(debrid: debrid)
      expect(providers.length).to eq(1)
      expect(providers.first).to be_a(Streams::TorrentioProvider)
    end

    it 'returns only Torrentio when explicitly set' do
      ENV["STREAM_PROVIDER"] = "torrentio"
      providers = described_class.providers(debrid: debrid)
      expect(providers.length).to eq(1)
      expect(providers.first).to be_a(Streams::TorrentioProvider)
    end

    it 'returns Comet + Torrentio when set to comet' do
      ENV["STREAM_PROVIDER"] = "comet"
      ENV["COMET_URL"] = "https://comet.example.com"

      providers = described_class.providers(debrid: debrid)
      expect(providers.length).to eq(2)
      expect(providers.first).to be_a(CometService)
      expect(providers.last).to be_a(Streams::TorrentioProvider)
    end

    it 'falls back to Torrentio when auto and Comet is not configured' do
      ENV["STREAM_PROVIDER"] = "auto"
      ENV["COMET_URL"] = nil

      providers = described_class.providers(debrid: debrid)
      expect(providers.length).to eq(1)
      expect(providers.first).to be_a(Streams::TorrentioProvider)
    end
  end

  describe '.resolve_base_urls' do
    it 'includes torrentio URLs by default' do
      ENV["STREAM_PROVIDER"] = nil
      urls = described_class.resolve_base_urls
      expect(urls).to include(Streams::TorrentioProvider::BASE_URL)
      expect(urls).to include('https://torrentio.strem.fun')
    end

    it 'includes comet URL when configured' do
      ENV["STREAM_PROVIDER"] = "comet"
      ENV["COMET_URL"] = "https://comet.example.com"
      urls = described_class.resolve_base_urls
      expect(urls).to include('https://comet.example.com')
    end

    it 'returns unique URLs' do
      ENV["STREAM_PROVIDER"] = "torrentio"
      urls = described_class.resolve_base_urls
      expect(urls).to eq(urls.uniq)
    end
  end

  describe 'with installed addons' do
    before do
      create(:addon, url: "https://aiostreams.example.com/manifest.json")
    end

    it 'uses installed addons as the only providers' do
      providers = described_class.providers(debrid: debrid)

      expect(providers.length).to eq(1)
      expect(providers.first).to be_a(Streams::StremioAddonProvider)
      expect(providers.first.base_url).to eq("https://aiostreams.example.com")
    end

    it 'returns addon base URLs for origin validation' do
      expect(described_class.resolve_base_urls).to include("https://aiostreams.example.com")
    end

    it 'treats addon hosts as direct origins' do
      expect(described_class.direct_origin?("https://aiostreams.example.com/api/v1/proxy/x")).to be(true)
      expect(described_class.direct_origin?("https://torrentio.strem.fun/resolve/x")).to be(false)
    end

    it 'includes operator-supplied stream source hosts' do
      ENV["STREAM_SOURCE_HOSTS"] = "stremthru.example.xyz"

      expect(described_class.resolve_base_urls).to include("https://stremthru.example.xyz")
      expect(described_class.direct_origin?("https://stremthru.example.xyz/stremio/torz/x")).to be(true)
    ensure
      ENV.delete("STREAM_SOURCE_HOSTS")
    end
  end
end
