defmodule ScientiaCognita.HTMLStripper do
  @moduledoc """
  Strips an HTML document down to clean semantic content suitable for
  passing to an LLM (Gemini) for structured data extraction.

  Removes: <head>, scripts, styles, SVG and all descendants, nav, header,
  footer, ads, aria-hidden elements, HTML comments, all class/id attributes.
  Keeps: href on <a>; src/srcset/alt/data-src/data-srcset on <img>/<figure>/<source>.
  """

  @remove_selectors ~w(
    script style noscript iframe
    nav header footer aside
    [role=navigation] [role=banner] [role=contentinfo]
    .nav .navbar .menu .sidebar .footer .header .ad .ads .advertisement
    form button input select textarea
    [aria-hidden=true]
    svg
  )

  @keep_attrs %{
    "*" => [],
    "a" => ["href"],
    "source" => ["srcset", "media", "type"],
    "figure" => ["src", "alt", "srcset", "data-src", "data-srcset"],
    "img" => ["src", "alt", "srcset", "data-src", "data-srcset", "data-lazy-src"]
  }

  @doc """
  Parses `html`, extracts body content, removes noise elements, strips
  non-content attributes, removes HTML comments, and returns clean HTML
  trimmed to at most `max_bytes` bytes (default 80KB).
  """
  def strip(html, max_bytes \\ 80_000) do
    case Floki.parse_document(html) do
      {:ok, tree} ->
        body = extract_body(tree)

        cleaned =
          Enum.reduce(@remove_selectors, body, fn selector, acc ->
            Floki.filter_out(acc, selector)
          end)
          |> remove_comments()
          |> clean_attributes()
          |> Floki.raw_html()

        binary_part(cleaned, 0, min(byte_size(cleaned), max_bytes))

      {:error, _} ->
        ""
    end
  end

  defp extract_body(tree) do
    case Floki.find(tree, "body") do
      [{"body", _attrs, children} | _] -> children
      _ -> tree
    end
  end

  defp remove_comments(tree) do
    Floki.traverse_and_update(tree, fn
      {:comment, _} -> nil
      other -> other
    end)
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
