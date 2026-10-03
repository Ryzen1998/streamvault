module ApplicationHelper
  # Encrypted stand-in for a listed stream; its resolve URL embeds the debrid key.
  def stream_selection_token(stream)
    StreamSelection.issue(user: current_user, candidate: stream)
  end

  # Rough viewing time from saved playback positions: "12h 5m", "45m".
  def watch_time(seconds)
    hours, minutes = (seconds.to_i / 60).divmod(60)
    hours.positive? ? "#{hours}h #{minutes}m" : "#{minutes}m"
  end

  def player_time(seconds)
    total_seconds = seconds.to_f
    return "0:00" unless total_seconds.finite? && total_seconds.positive?

    total_seconds = total_seconds.floor
    hours = total_seconds / 3600
    minutes = (total_seconds % 3600) / 60
    seconds = total_seconds % 60

    if hours.positive?
      "#{hours}:#{minutes.to_s.rjust(2, '0')}:#{seconds.to_s.rjust(2, '0')}"
    else
      "#{minutes}:#{seconds.to_s.rjust(2, '0')}"
    end
  end
end
