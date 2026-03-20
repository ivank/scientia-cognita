defmodule ScientiaCognita.HttpBehaviour do
  @moduledoc "Callback spec for HTTP GET client, used for dependency injection in workers."

  @callback get(url :: String.t(), opts :: keyword()) ::
              {:ok, %{status: integer(), body: any(), headers: %{optional(String.t()) => [String.t()]}}}
              | {:error, term()}
end
