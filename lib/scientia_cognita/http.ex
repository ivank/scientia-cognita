defmodule ScientiaCognita.Http do
  @moduledoc "Real HTTP client wrapping Req. Implements HttpBehaviour."

  @behaviour ScientiaCognita.HttpBehaviour

  @impl true
  def get(url, opts \\ []) do
    case Req.get(url, opts) do
      # Headers are kept in Req format: %{header_name => [value, ...]}
      {:ok, %{status: status, body: body, headers: headers}} ->
        {:ok, %{status: status, body: body, headers: headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
