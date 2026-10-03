require "rails_helper"

RSpec.describe ResolvedSource do
  let(:user) { create(:user) }
  let!(:debrid_account) { create(:debrid_account, api_key: "rd_instance_key") }

  around do |example|
    Rails.cache.clear
    example.run
  end

  it "trusts configured addon hosts" do
    create(:addon, url: "https://aiostreams.example.com/manifest.json")

    source = described_class.new(url: "https://aiostreams.example.com/api/v1/proxy/e.x.y/file.mkv")
    expect(source.url).to include("aiostreams.example.com")
  end

  it "rejects hosts that are not configured addons or known debrid hosts" do
    expect {
      described_class.new(url: "https://evil.example.com/file.mkv")
    }.to raise_error(described_class::Invalid)
  end

  it "does not send the RealDebrid key to addon hosts" do
    create(:addon, url: "https://aiostreams.example.com/manifest.json")
    source = described_class.new(url: "https://aiostreams.example.com/api/v1/proxy/e.x.y/file.mkv")

    expect(source.request_headers).to eq({})
  end

  it "sends the instance RealDebrid key to RealDebrid hosts" do
    source = described_class.new(url: "https://download.real-debrid.com/d/abc/file.mkv")

    expect(source.request_headers).to include("Authorization" => "Bearer rd_instance_key")
  end

  it "does not send a key to RealDebrid hosts when the instance uses TorBox" do
    debrid_account.update!(service: "torbox", api_key: "tb_instance_key")
    source = described_class.new(url: "https://download.real-debrid.com/d/abc/file.mkv")

    expect(source.request_headers).to eq({})
  end

  it "trusts TorBox CDN hosts without sending them a key" do
    debrid_account.update!(service: "torbox", api_key: "tb_instance_key")
    source = described_class.new(url: "https://store-031.weur.tb-cdn.st/dld/abc-123")

    expect(source.request_headers).to eq({})
  end

  it "trusts operator-supplied stream source hosts" do
    ENV["STREAM_SOURCE_HOSTS"] = "stremthru.example.xyz,tb-cdn.pw"
    source = described_class.new(url: "https://nexus-1.tb-cdn.pw/dld/abc")

    expect(source.url).to include("tb-cdn.pw")
  ensure
    ENV.delete("STREAM_SOURCE_HOSTS")
  end

  describe "upstream request headers" do
    before { create(:addon, url: "https://aiostreams.example.com/manifest.json") }

    let(:url) { "https://aiostreams.example.com/api/v1/proxy/e.x.y/file.mkv" }

    it "sanitizes stored headers" do
      source = described_class.new(url: url, upstream_headers: { "Host" => "evil", "User-Agent" => "ok" })

      expect(source.upstream_headers).to eq("User-Agent" => "ok")
    end

    it "includes upstream headers in request_headers" do
      source = described_class.new(url: url, upstream_headers: { "User-Agent" => "Stremio" })

      expect(source.request_headers).to eq("User-Agent" => "Stremio")
    end

    it "round-trips upstream headers through the source token" do
      token = described_class.issue(
        user: user,
        url: url,
        filename: "file.mkv",
        upstream_headers: { "User-Agent" => "Stremio" }
      )

      restored = described_class.resolve(token: token, user: user, verify_dns: false)
      expect(restored.upstream_headers).to eq("User-Agent" => "Stremio")
      expect(restored.request_headers).to eq("User-Agent" => "Stremio")
    end

    it "adds the RealDebrid bearer on top of upstream headers for RealDebrid hosts" do
      source = described_class.new(
        url: "https://download.real-debrid.com/d/abc/file.mkv",
        upstream_headers: { "User-Agent" => "Stremio" }
      )

      expect(source.request_headers).to include(
        "User-Agent" => "Stremio",
        "Authorization" => "Bearer rd_instance_key"
      )
    end
  end

  describe "with open trust enabled" do
    around do |example|
      ENV["STREAM_SOURCE_TRUST"] = "any"
      example.run
    ensure
      ENV.delete("STREAM_SOURCE_TRUST")
    end

    it "accepts an arbitrary public HTTPS host" do
      source = described_class.new(url: "https://stremthru.example.xyz/stremio/torz/abc")

      expect(source.url).to include("stremthru.example.xyz")
    end

    it "still rejects non-HTTPS URLs" do
      expect {
        described_class.new(url: "http://stremthru.example.xyz/x")
      }.to raise_error(described_class::Invalid)
    end
  end

  describe ".public_url?" do
    it "rejects loopback and private hosts" do
      expect(described_class.public_url?("http://127.0.0.1/x")).to be(false)
      expect(described_class.public_url?("http://10.0.0.5/x")).to be(false)
    end

    it "rejects non-http URLs and unresolvable hosts" do
      expect(described_class.public_url?("ftp://example.com/x")).to be(false)
      expect(described_class.public_url?("https://does-not-exist.invalid/x")).to be(false)
    end

    it "accepts a public address" do
      allow(Addrinfo).to receive(:getaddrinfo)
        .and_return([ double(ip_address: "93.184.216.34") ])

      expect(described_class.public_url?("https://example.com/x")).to be(true)
    end
  end
end
