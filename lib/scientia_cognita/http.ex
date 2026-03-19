defmodule ScientiaCognita.Http do
  @behaviour ScientiaCognita.HttpBehaviour

  @impl true
  def get(url, opts \\ []) do
    case Req.get(url, opts) do
      {:ok, %{status: status, body: body, headers: headers}} ->
        {:ok, %{status: status, body: body, headers: headers}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
