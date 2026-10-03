require "rails_helper"

RSpec.describe Addons::SubtitleSource do
  let(:base) { "https://subs.example.com" }
  let(:manifest) do
    { "id" => "org.subs", "name" => "OpenSubtitles v3", "types" => %w[movie series],
      "resources" => [ "subtitles" ], "idPrefixes" => [ "tt" ] }
  end
  let(:registry) { double("registry", entries: [ Addons::Registry::Entry.new(url: "#{base}/manifest.json", name: "OpenSubtitles v3", reference: "1") ]) }

  subject(:source) { described_class.new(registry: registry) }

  def stub_json(url, body)
    stub_request(:get, url).to_return(status: 200, body: body.to_json, headers: { "Content-Type" => "application/json" })
  end

  before do
    Rails.cache.clear
    stub_json("#{base}/manifest.json", manifest)
  end

  describe "#search" do
    let(:subtitles) do
      [
        { "id" => "1", "url" => "https://subs5.strem.io/en/1.srt", "lang" => "eng" },
        { "id" => "2", "url" => "https://subs5.strem.io/en/2.srt", "lang" => "eng" },
        { "id" => "3", "url" => "https://subs5.strem.io/fr/3.srt", "lang" => "fre" },
        { "id" => "4", "url" => "https://subs5.strem.io/de/4.srt", "lang" => "ger" },
        { "id" => "5", "url" => "https://subs5.strem.io/xx/5.srt", "lang" => "xyz" },
        { "id" => "6", "url" => "https://subs5.strem.io/en/1.srt", "lang" => "eng" }
      ]
    end

    it "lists tracks in the account's languages, preferred language first" do
      stub_json("#{base}/subtitles/movie/tt1375666.json", { "subtitles" => subtitles })

      tracks = source.search(imdb_id: "tt1375666", type: "movie", preferred_languages: %w[FRENCH ENG], default_language: "ENG")

      expect(tracks.map { |track| track[:language] }).to eq(%w[ENG ENG FRENCH])
      expect(tracks.first).to include(label: "English · OpenSubtitles v3", source: "addon", external: true, text_supported: true)
    end

    it "keeps subtitle URLs out of the track sent to the browser" do
      stub_json("#{base}/subtitles/movie/tt1375666.json", { "subtitles" => subtitles })

      track = source.search(imdb_id: "tt1375666", type: "movie", preferred_languages: %w[ENG]).first

      expect(track.to_json).not_to include("strem.io")
      expect(track[:index]).to start_with("external:addon:")
    end

    it "asks for the episode and passes the filename hint" do
      request = stub_json("#{base}/subtitles/series/tt0903747:1:2/filename=Breaking.Bad.S01E02.mkv.json", { "subtitles" => [] })

      source.search(imdb_id: "tt0903747", type: "show", season: 1, episode: 2, filename: "Breaking.Bad.S01E02.mkv", preferred_languages: %w[ENG])

      expect(request).to have_been_requested
    end

    it "skips addons that don't serve subtitles" do
      stub_json("#{base}/manifest.json", manifest.merge("resources" => [ "stream" ]))

      expect(source.search(imdb_id: "tt1375666", type: "movie", preferred_languages: %w[ENG])).to eq([])
      expect(WebMock).not_to have_requested(:get, %r{/subtitles/})
    end
  end

  describe "#download" do
    def token_for(url)
      ApplicationToken.issue({ "url" => url }, purpose: described_class::TOKEN_PURPOSE, expires_in: 1.hour)
    end

    before { allow(ResolvedSource).to receive(:public_url?).and_return(true) }

    it "downloads the listed file and converts legacy encodings to UTF-8" do
      stub_request(:get, "https://subs5.strem.io/fr/3.srt")
        .to_return(status: 200, body: "1\n00:00:01,000 --> 00:00:02,000\nD\xE9j\xE0 vu\n".b)

      result = source.download(token_for("https://subs5.strem.io/fr/3.srt"))

      expect(result).to be_success
      expect(result.data).to include("Déjà vu")
    end

    it "follows redirects, checking every hop" do
      stub_request(:get, "https://subs5.strem.io/en/1.srt")
        .to_return(status: 302, headers: { "Location" => "https://cdn.subs.example/1.srt" })
      stub_request(:get, "https://cdn.subs.example/1.srt").to_return(status: 200, body: "WEBVTT\n")

      expect(source.download(token_for("https://subs5.strem.io/en/1.srt")).data).to eq("WEBVTT\n")
      expect(ResolvedSource).to have_received(:public_url?).with("https://cdn.subs.example/1.srt")
    end

    it "refuses private addresses" do
      allow(ResolvedSource).to receive(:public_url?).with("http://169.254.169.254/latest").and_return(false)

      expect(source.download(token_for("http://169.254.169.254/latest"))).to be_failure
      expect(WebMock).not_to have_requested(:get, "http://169.254.169.254/latest")
    end

    it "rejects ids it didn't issue" do
      expect(source.download("forged").error_message).to eq("Invalid subtitle link")
    end
  end
end
