defmodule ScientiaCognita.GeminiBehaviour do
  @callback generate_structured(prompt :: String.t(), schema :: map(), opts :: keyword()) ::
              {:ok, map()} | {:error, term()}

  @callback generate_structured_with_image(
              prompt :: String.t(),
              image_binary :: binary(),
              schema :: map(),
              opts :: keyword()
            ) :: {:ok, map()} | {:error, term()}
end
