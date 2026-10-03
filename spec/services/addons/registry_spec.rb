require "rails_helper"

RSpec.describe Addons::Registry do
  around do |example|
    old_hosts = ENV["STREAM_SOURCE_HOSTS"]
    old_addons = ENV["STREMIO_ADDONS"]
    old_trust = ENV["STREAM_SOURCE_TRUST"]
    example.run
  ensure
    ENV["STREAM_SOURCE_HOSTS"] = old_hosts
    ENV["STREMIO_ADDONS"] = old_addons
    ENV["STREAM_SOURCE_TRUST"] = old_trust
  end

  describe ".entries" do
    it "builds entries from enabled addons" do
      create(:addon, url: "https://addon.example.com/manifest.json", name: "Addon")
      create(:addon, :disabled, url: "https://off.example.com/manifest.json")

      hosts = described_class.entries.map(&:host)
      expect(hosts).to include("addon.example.com")
      expect(hosts).not_to include("off.example.com")
    end

    it "falls back to STREMIO_ADDONS when no addons are stored" do
      ENV["STREMIO_ADDONS"] = "https://env.example.com/manifest.json"

      expect(described_class.entries.map(&:host)).to include("env.example.com")
    end
  end

  describe ".proxy_hosts" do
    it "parses bare hosts and URLs from STREAM_SOURCE_HOSTS" do
      ENV["STREAM_SOURCE_HOSTS"] = "stremthru.example.xyz, https://tb-cdn.pw "

      expect(described_class.proxy_hosts).to contain_exactly("stremthru.example.xyz", "tb-cdn.pw")
    end

    it "returns an empty list when unset" do
      ENV.delete("STREAM_SOURCE_HOSTS")

      expect(described_class.proxy_hosts).to eq([])
    end
  end

  describe ".configured?" do
    it "is true when an addon is installed" do
      create(:addon)

      expect(described_class.configured?).to be(true)
    end

    it "is false with no addons" do
      expect(described_class.configured?).to be(false)
    end
  end

  describe ".open_trust?" do
    it "is false by default" do
      expect(described_class.open_trust?).to be(false)
    end

    it "is true when an enabled addon opts in" do
      create(:addon, trust_source_hosts: true)

      expect(described_class.open_trust?).to be(true)
    end

    it "is false when only a disabled addon opts in" do
      create(:addon, :disabled, trust_source_hosts: true)

      expect(described_class.open_trust?).to be(false)
    end

    it "is true when STREAM_SOURCE_TRUST=any" do
      ENV["STREAM_SOURCE_TRUST"] = "any"

      expect(described_class.open_trust?).to be(true)
    end
  end
end
