defmodule ScientiaCognita.UploaderBehaviour do
  @moduledoc "Callback spec for the Waffle uploader — used for Mox injection in workers."

  @callback store(any()) :: {:ok, any()} | {:error, term()}
  @callback url(any()) :: String.t()
end
