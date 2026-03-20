defmodule ScientiaCognita.HTMLStripper do
  @moduledoc """
  Strips an HTML document down to clean semantic content suitable for
  passing to an LLM (Gemini) for structured data extraction.

  Removes: scripts, styles, nav, header, footer, ads, all non-essential attributes.
  Keeps: class/id on all elements; href on <a>; src/srcset/alt on <img>/<figure>.
  """

  @remove_selectors ~w(
    script style noscript iframe
    nav header footer aside
    [role=navigation] [role=banner] [role=contentinfo]
    .nav .navbar .menu .sidebar .footer .header .ad .ads .advertisement
    form button input select textarea
    [aria-hidden=true]
  )

  # Attributes kept per tag. The special key "*" applies to all tags.
  @keep_attrs %{
    "*" => ["class", "id"],
    "a" => ["href", "class", "id"],
    "figure" => ["src", "alt", "srcset", "class", "id"],
    "img" => ["src", "alt", "srcset", "class", "id"]
  }

  @doc """
  Parses `html`, removes noise elements and non-content attributes,
  and returns a clean HTML string trimmed to at most `max_bytes` bytes.
  """
  def strip(html, max_bytes \\ 300_000) do
    case Floki.parse_document(html) do
      {:ok, tree} ->
        cleaned =
          Enum.reduce(@remove_selectors, tree, fn selector, acc ->
            Floki.filter_out(acc, selector)
          end)
          |> clean_attributes()
          |> Floki.raw_html()

        binary_part(cleaned, 0, min(byte_size(cleaned), max_bytes))

      {:error, _} ->
        ""
    end
  end

  defp clean_attributes(tree) do
    global = Map.get(@keep_attrs, "*", [])

    Floki.traverse_and_update(tree, fn
      {tag, attrs, children} ->
        allowed = global ++ Map.get(@keep_attrs, tag, [])
        kept = Enum.filter(attrs, fn {name, _} -> name in allowed end)
        {tag, kept, children}

      other ->
        other
    end)
  end
end
