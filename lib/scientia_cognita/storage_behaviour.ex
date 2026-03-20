defmodule ScientiaCognita.StorageBehaviour do
  @moduledoc "Callback spec for storage upload, used for dependency injection in workers."

  @callback upload(key :: String.t(), binary :: binary(), opts :: keyword()) ::
              {:ok, any()} | {:error, term()}
end
