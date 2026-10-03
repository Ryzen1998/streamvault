require 'rails_helper'

RSpec.describe ExternalSubtitleService do
  before do
    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end

  after do
    described_class.subdl_provider = nil
    described_class.addon_provider = nil
    Rails.cache = @original_cache
  end

  describe ".extract_subtitles" do
    it "downloads, caches, and windows SRT subtitles as WebVTT" do
      provider = instance_double(SubdlSubtitleProvider)
      allow(provider).to receive(:download).and_return(
        ServiceResult.success(<<~SRT)
          1
          00:00:01,000 --> 00:00:02,000
          Too early

          2
          00:00:31,000 --> 00:00:33,000
          Hello <i>there</i>

          3
          00:01:40,000 --> 00:01:42,000
          Too late
        SRT
      )
      described_class.subdl_provider = provider
      stream_id = described_class.stream_id("subdl", "/subtitle/123/456")

      result = described_class.extract_subtitles(stream_id, start_seconds: 30, duration_seconds: 10)

      expect(result.status).to eq(:ok)
      expect(result.source).to eq("subdl")
      expect(result.cue_count).to eq(1)
      expect(result.vtt).to include("WEBVTT")
      expect(result.vtt).to include("00:00:31.000 --> 00:00:33.000")
      expect(result.vtt).to include("Hello there")
      expect(result.vtt).not_to include("Too early")
      expect(result.vtt).not_to include("Too late")

      described_class.extract_subtitles(stream_id, start_seconds: 30, duration_seconds: 10)
      expect(provider).to have_received(:download).once
    end

    it "returns an empty window when the external subtitle has no nearby cues" do
      provider = instance_double(SubdlSubtitleProvider)
      allow(provider).to receive(:download).and_return(
        ServiceResult.success("1\n00:10:00,000 --> 00:10:02,000\nLater\n")
      )
      described_class.subdl_provider = provider
      stream_id = described_class.stream_id("subdl", "/subtitle/123/456")

      result = described_class.extract_subtitles(stream_id, start_seconds: 30, duration_seconds: 10)

      expect(result.status).to eq(:empty_window)
      expect(result.source).to eq("subdl")
    end

    it "rejects malformed external stream identifiers" do
      result = described_class.extract_subtitles("external:subdl:not-base64-^", start_seconds: 0)

      expect(result.status).to eq(:invalid_stream)
    end

    it "extracts subtitles from addon tracks through the addon provider" do
      provider = instance_double(Addons::SubtitleSource)
      allow(provider).to receive(:download).with("signed-token").and_return(
        ServiceResult.success("WEBVTT\n\n00:00:31.000 --> 00:00:33.000\nFrom an addon\n")
      )
      described_class.addon_provider = provider

      result = described_class.extract_subtitles(described_class.stream_id("addon", "signed-token"), start_seconds: 30, duration_seconds: 10)

      expect(result.status).to eq(:ok)
      expect(result.vtt).to include("From an addon")
      expect(result.source).to eq("addon")
    end

    it "rejects unknown providers" do
      result = described_class.extract_subtitles(described_class.stream_id("other", "x"), start_seconds: 0)

      expect(result.status).to eq(:unsupported_track)
    end
  end

  describe ".search" do
    it "combines SubDL and addon tracks" do
      subdl = instance_double(SubdlSubtitleProvider, search: [ { index: "external:subdl:a", source: "subdl" } ])
      addon = instance_double(Addons::SubtitleSource, search: [ { index: "external:addon:b", source: "addon" } ])
      described_class.subdl_provider = subdl
      described_class.addon_provider = addon

      tracks = described_class.search(imdb_id: "tt1375666", type: "movie", preferred_languages: [ "ENG" ])

      expect(tracks.map { |track| track[:source] }).to contain_exactly("subdl", "addon")
      expect(addon).to have_received(:search).with(hash_including(imdb_id: "tt1375666", type: "movie"))
    end
  end
end
