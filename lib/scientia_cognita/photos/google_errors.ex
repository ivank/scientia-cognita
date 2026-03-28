defmodule ScientiaCognita.Photos.GoogleErrors do
  @moduledoc """
  Maps raw Google Photos API error strings and HTTP status codes to
  user-friendly messages. Falls back to the original error string
  when no pattern matches.
  """

  @patterns [
    {~r/UNAUTHENTICATED|401|invalid.creden|token.expir/i,
     "Your Google account connection has expired. Please reconnect Google Photos."},
    {~r/PERMISSION_DENIED|403|forbidden/i,
     "Google Photos access was denied. Please reconnect and grant the required permissions."},
    {~r/RESOURCE_EXHAUSTED|429|quota.exceed/i,
     "Google Photos rate limit reached. Please try again in a few minutes."},
    {~r/NOT_FOUND|404/i,
     "The requested Google Photos resource was not found."},
    {~r/INTERNAL|500|503|UNAVAILABLE|unavailable/i,
     "Google Photos is temporarily unavailable. Please try again later."},
    {~r/INVALID_ARGUMENT|400/i,
     "There was a problem with the request. Please try again."}
  ]

  @doc """
  Returns a user-friendly error message for a raw API error string.
  Falls back to the original string when no pattern matches.
  """
  def translate(raw) when is_binary(raw) do
    case Enum.find(@patterns, fn {regex, _msg} -> Regex.match?(regex, raw) end) do
      {_regex, msg} -> msg
      nil -> raw
    end
  end

  def translate(raw), do: to_string(raw)
end
