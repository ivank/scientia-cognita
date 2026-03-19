defmodule ScientiaCognita.Gemini do
  @moduledoc """
  Thin wrapper around the Gemini REST API using Req.
  Configured via :scientia_cognita, :gemini with keys :api_key and :model.
  """

  @base_url "https://generativelanguage.googleapis.com/v1beta/models"

  @doc """
  Sends a text-only prompt to Gemini. Returns `{:ok, text}` or `{:error, reason}`.
  """
  def generate(prompt, opts \\ []) do
    {api_key, model} = config()

    response_mime =
      if Keyword.get(opts, :json_mode, false), do: "application/json", else: "text/plain"

    body = %{
      contents: [%{parts: [%{text: prompt}]}],
      generationConfig: %{responseMimeType: response_mime}
    }

    request(model, api_key, body)
  end

  @doc """
  Sends a text prompt with a `responseSchema`, forcing the model to return
  a JSON object that conforms exactly to the schema.

  `schema` is an Elixir map following the OpenAPI subset supported by Gemini:
  types are uppercase strings — `"STRING"`, `"NUMBER"`, `"INTEGER"`,
  `"BOOLEAN"`, `"ARRAY"`, `"OBJECT"`. Use `nullable: true` for optional fields.

  Returns `{:ok, decoded_map}` or `{:error, reason}`.
  """
  def generate_structured(prompt, schema, _opts \\ []) do
    {api_key, model} = config()

    body = %{
      contents: [%{parts: [%{text: prompt}]}],
      generationConfig: %{
        responseMimeType: "application/json",
        responseSchema: schema
      }
    }

    with {:ok, text} <- request(model, api_key, body) do
      Jason.decode(text)
    end
  end

  @doc """
  Multimodal version of `generate_structured/3` — text prompt plus an inline image.
  Returns `{:ok, decoded_map}` or `{:error, reason}`.
  """
  def generate_structured_with_image(prompt, image_binary, schema, opts \\ []) do
    {api_key, model} = config()
    mime_type = Keyword.get(opts, :mime_type, "image/jpeg")

    body = %{
      contents: [
        %{
          parts: [
            %{inline_data: %{mime_type: mime_type, data: Base.encode64(image_binary)}},
            %{text: prompt}
          ]
        }
      ],
      generationConfig: %{
        responseMimeType: "application/json",
        responseSchema: schema
      }
    }

    with {:ok, text} <- request(model, api_key, body) do
      Jason.decode(text)
    end
  end

  @doc """
  Sends a multimodal prompt — text plus an inline image.
  Returns `{:ok, text}` or `{:error, reason}`.
  """
  def generate_with_image(prompt, image_binary, opts \\ []) do
    {api_key, model} = config()
    mime_type = Keyword.get(opts, :mime_type, "image/jpeg")

    response_mime =
      if Keyword.get(opts, :json_mode, false), do: "application/json", else: "text/plain"

    body = %{
      contents: [
        %{
          parts: [
            %{inline_data: %{mime_type: mime_type, data: Base.encode64(image_binary)}},
            %{text: prompt}
          ]
        }
      ],
      generationConfig: %{responseMimeType: response_mime}
    }

    request(model, api_key, body)
  end

  # ---------------------------------------------------------------------------

  defp config do
    cfg = Application.get_env(:scientia_cognita, :gemini, [])
    api_key = Keyword.get(cfg, :api_key) || System.get_env("GEMINI_API_KEY", "")
    model = Keyword.get(cfg, :model, "gemini-2.0-flash-lite")
    {api_key, model}
  end

  defp request(model, api_key, body) do
    Req.post(
      "#{@base_url}/#{model}:generateContent",
      params: [key: api_key],
      json: body,
      receive_timeout: 60_000
    )
    |> case do
      {:ok, %{status: 200, body: body}} ->
        text =
          body
          |> get_in(["candidates", Access.at(0), "content", "parts", Access.at(0), "text"])

        {:ok, text}

      {:ok, %{status: status, body: body}} ->
        {:error, "Gemini API error #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
