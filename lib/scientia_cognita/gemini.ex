defmodule ScientiaCognita.Gemini do
  @moduledoc """
  Thin wrapper around the Gemini REST API using Req.
  Configured via :scientia_cognita, :gemini with keys :api_key and :model.
  """

  @base_url "https://generativelanguage.googleapis.com/v1beta/models"

  @doc """
  Sends a text prompt to Gemini and returns the text response.

  ## Options
    * `:json_mode` - when true, instructs Gemini to return valid JSON
  """
  def generate(prompt, opts \\ []) do
    config = Application.get_env(:scientia_cognita, :gemini, [])
    api_key = Keyword.get(config, :api_key) || System.get_env("GEMINI_API_KEY")
    model = Keyword.get(config, :model, "gemini-2.0-flash-lite")

    response_mime =
      if Keyword.get(opts, :json_mode, false),
        do: "application/json",
        else: "text/plain"

    body = %{
      contents: [%{parts: [%{text: prompt}]}],
      generationConfig: %{responseMimeType: response_mime}
    }

    Req.post(
      "#{@base_url}/#{model}:generateContent",
      params: [key: api_key],
      json: body
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

  @doc """
  Sends a prompt and parses the response as JSON.
  """
  def generate_json(prompt) do
    with {:ok, text} <- generate(prompt, json_mode: true),
         {:ok, decoded} <- Jason.decode(text) do
      {:ok, decoded}
    end
  end
end
