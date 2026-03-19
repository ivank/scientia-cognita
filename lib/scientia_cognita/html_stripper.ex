defmodule ScientiaCognita.HTMLStripper do
  @moduledoc """
  Strips an HTML document down to clean semantic content suitable for
  passing to an LLM (Gemini) for structured data extraction.

  Removes: scripts, styles, nav, header, footer, ads, all non-essential attributes.
  Keeps: content tags with href/src/alt only.
  """

  @remove_selectors ~w(
    script style noscript iframe
    nav header footer aside
    [role=navigation] [role=banner] [role=contentinfo]
    .nav .navbar .menu .sidebar .footer .header .ad .ads .advertisement
    form button input select textarea
    [aria-hidden=true]
  )

  @keep_attrs %{
    "a" => ["href"],
    "img" => ["src", "alt"]
  }

  @doc """
  Parses `html`, removes noise elements and non-content attributes,
  and returns a clean HTML string trimmed to at most `max_bytes` bytes.
  """
  def strip(html, max_bytes \\ 80_000) do
    case Floki.parse_document(html) do
      {:ok, tree} ->
        cleaned =
          Enum.reduce(@remove_selectors, tree, fn selector, acc ->
            Floki.filter_out(acc, selector)
          end)
          |> clean_attributes()
          |> Floki.raw_html()

        # Truncate to avoid overflowing Gemini's context window
        binary_part(cleaned, 0, min(byte_size(cleaned), max_bytes))

      {:error, _} ->
        ""
    end
  end

  defp clean_attributes(tree) do
    Floki.traverse_and_update(tree, fn
      {tag, attrs, children} ->
        kept =
          case Map.get(@keep_attrs, tag) do
            nil -> []
            allowed -> Enum.filter(attrs, fn {name, _} -> name in allowed end)
          end

        {tag, kept, children}

      other ->
        other
    end)
  end
end
