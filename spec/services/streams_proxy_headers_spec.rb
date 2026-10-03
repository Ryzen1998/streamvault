require "rails_helper"

RSpec.describe Streams::ProxyHeaders do
  it "canonicalizes names and keeps safe headers" do
    result = described_class.sanitize("user-agent" => "Stremio", "X-API-KEY" => "abc")

    expect(result).to eq("User-Agent" => "Stremio", "X-Api-Key" => "abc")
  end

  it "drops transport and hop-by-hop headers" do
    result = described_class.sanitize(
      "Host" => "evil",
      "Range" => "bytes=0-5",
      "Content-Length" => "10",
      "X-Forwarded-For" => "1.2.3.4",
      "User-Agent" => "ok"
    )

    expect(result).to eq("User-Agent" => "ok")
  end

  it "rejects CR/LF, NUL, invalid names, and oversized values" do
    result = described_class.sanitize(
      "X-Evil" => "a\r\nInjected: 1",
      "X-Nul" => "a\0b",
      "Bad Name" => "x",
      "X-Big" => "a" * 5000,
      "X-Ok" => "yes"
    )

    expect(result).to eq("X-Ok" => "yes")
  end

  it "caps the header count" do
    raw = 30.times.to_h { |index| [ "X-Header-#{index}", "v" ] }

    expect(described_class.sanitize(raw).size).to eq(described_class::MAX_HEADERS)
  end

  it "returns an empty hash for non-hash input" do
    expect(described_class.sanitize(nil)).to eq({})
    expect(described_class.sanitize("nope")).to eq({})
  end
end
