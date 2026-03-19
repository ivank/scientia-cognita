defmodule ScientiaCognita.HttpBehaviour do
  @callback get(url :: String.t(), opts :: keyword()) ::
              {:ok, %{status: integer(), body: any(), headers: map()}}
              | {:error, term()}
end
