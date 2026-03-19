defmodule ScientiaCognita.StorageBehaviour do
  @callback upload(key :: String.t(), binary :: binary(), opts :: keyword()) ::
              {:ok, any()} | {:error, term()}
end
