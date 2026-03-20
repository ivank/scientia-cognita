defmodule ScientiaCognita.GeminiBehaviour do
  @moduledoc "Callback spec for Gemini AI client, used for dependency injection in workers."

  @callback generate_structured(prompt :: String.t(), schema :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @callback generate_structured_with_image(
              prompt :: String.t(),
              image_binary :: binary(),
              schema :: map(),
              opts :: keyword()
            ) :: {:ok, map()} | {:error, term()}
end
