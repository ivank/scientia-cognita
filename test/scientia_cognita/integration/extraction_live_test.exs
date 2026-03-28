defmodule ScientiaCognita.Integration.ExtractionLiveTest do
  @moduledoc """
  Live integration tests for the full strip → Gemini extraction pipeline.
  These call the real Gemini API and require GEMINI_API_KEY to be set.

  Excluded from the default test run. Run with:

      mix test --include live test/scientia_cognita/integration/extraction_live_test.exs

  Or run all live tests:

      mix test --include live
  """

  use ScientiaCognita.DataCase

  @moduletag :live

  alias ScientiaCognita.{Gemini, HTMLStripper}
  alias ScientiaCognita.Workers.ExtractPageWorker

  @nasa_html File.read!("test/fixtures/nasa_hubble_page.html")
  @nasa_url "https://science.nasa.gov/mission/hubble/hubble-news/hubble-social-media/35-years-of-hubble-images/"

  @livescience_html File.read!("test/fixtures/livescience_page.html")
  @livescience_url "https://www.livescience.com/100-best-science-photos-of-2020.html"

  # ---------------------------------------------------------------------------
  # NASA Hubble gallery
  # ---------------------------------------------------------------------------

  describe "NASA Hubble gallery extraction" do
    test "classifies as gallery" do
      result = extract!(@nasa_html, @nasa_url)
      assert result["is_gallery"] == true
    end

    test "extracts all 40 items" do
      result = extract!(@nasa_html, @nasa_url)
      items = result["items"] || []

      assert length(items) == 40,
             "Expected 40 items, got #{length(items)}"
    end

    test "all items have absolute image URLs" do
      items = extract!(@nasa_html, @nasa_url) |> Map.get("items", [])

      bad =
        Enum.reject(items, fn i ->
          is_binary(i["image_url"]) and String.starts_with?(i["image_url"], "http")
        end)

      assert bad == [],
             "Items with missing/relative URLs: #{inspect(Enum.map(bad, & &1["title"]))}"
    end

    test "all items have non-empty descriptions" do
      items = extract!(@nasa_html, @nasa_url) |> Map.get("items", [])

      no_desc =
        Enum.filter(items, fn i ->
          is_nil(i["description"]) or String.trim(i["description"]) == ""
        end)

      assert no_desc == [],
             "#{length(no_desc)} items missing descriptions: #{inspect(Enum.map(no_desc, & &1["title"]))}"
    end

    test "all descriptions within 500 character limit" do
      items = extract!(@nasa_html, @nasa_url) |> Map.get("items", [])

      too_long =
        Enum.filter(items, fn i ->
          is_binary(i["description"]) and String.length(i["description"]) > 500
        end)

      assert too_long == [],
             "#{length(too_long)} descriptions exceed 500 chars"
    end

    test "sample item has correct title and description content" do
      items = extract!(@nasa_html, @nasa_url) |> Map.get("items", [])

      # First item should be the deployment photo
      first = List.first(items)
      assert first["title"] =~ ~r/Hubble|deployment/i
      assert first["description"] =~ ~r/Hubble|telescope|1990/i
    end
  end

  # ---------------------------------------------------------------------------
  # LiveScience 100 best photos
  # ---------------------------------------------------------------------------

  describe "LiveScience gallery extraction" do
    test "classifies as gallery" do
      result = extract!(@livescience_html, @livescience_url)
      assert result["is_gallery"] == true
    end

    test "extracts at least 95 items (100-item article)" do
      items = extract!(@livescience_html, @livescience_url) |> Map.get("items", [])

      assert length(items) >= 95,
             "Expected ≥95 items, got #{length(items)}"
    end

    test "all items have absolute image URLs" do
      items = extract!(@livescience_html, @livescience_url) |> Map.get("items", [])

      bad =
        Enum.reject(items, fn i ->
          is_binary(i["image_url"]) and String.starts_with?(i["image_url"], "http")
        end)

      assert bad == [],
             "Items with missing/relative URLs: #{inspect(Enum.take(Enum.map(bad, & &1["title"]), 5))}"
    end

    test "at least 90% of items have non-empty descriptions" do
      items = extract!(@livescience_html, @livescience_url) |> Map.get("items", [])
      total = length(items)

      with_desc =
        Enum.count(items, fn i ->
          is_binary(i["description"]) and String.trim(i["description"]) != ""
        end)

      pct = if total > 0, do: Float.round(with_desc / total * 100, 1), else: 0.0

      assert with_desc >= trunc(total * 0.9),
             "Only #{with_desc}/#{total} (#{pct}%) items have descriptions"
    end
  end

  # ---------------------------------------------------------------------------
  # Helper
  # ---------------------------------------------------------------------------

  defp extract!(html, url) do
    clean = HTMLStripper.strip(html)
    prompt = ExtractPageWorker.build_extract_prompt(clean, url)
    schema = ExtractPageWorker.extract_schema()

    assert {:ok, result} = Gemini.generate_structured(prompt, schema, []),
           "Gemini call failed"

    result
  end
end
