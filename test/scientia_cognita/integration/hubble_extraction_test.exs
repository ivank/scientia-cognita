defmodule ScientiaCognita.Integration.HubbleExtractionTest do
  @moduledoc """
  Live integration test for the Gemini direct-extraction pipeline.

  Skipped by default. Run explicitly with:

      mix test --include live test/scientia_cognita/integration/hubble_extraction_test.exs

  Requires GEMINI_API_KEY to be set in the environment.
  """

  use ScientiaCognita.DataCase

  @moduletag :live

  alias ScientiaCognita.{Gemini, HTMLStripper}
  alias ScientiaCognita.Workers.ExtractPageWorker

  @raw_html File.read!("test/fixtures/hubble_page.html")
  @source_url "https://science.nasa.gov/mission/hubble/hubble-news/hubble-social-media/35-years-of-hubble-images/"

  describe "Gemini direct extraction on Hubble fixture" do
    test "classifies as gallery and extracts 40 items with image URLs" do
      clean_html = HTMLStripper.strip(@raw_html)
      prompt = ExtractPageWorker.build_extract_prompt(clean_html, @source_url)
      schema = ExtractPageWorker.extract_schema()

      assert {:ok, result} = Gemini.generate_structured(prompt, schema, [])

      assert result["is_gallery"] == true,
             "Expected is_gallery=true, got: #{inspect(result)}"

      items = result["items"] || []

      assert length(items) == 40,
             "Expected 40 items, got #{length(items)}"

      assert Enum.all?(items, fn item ->
               is_binary(item["image_url"]) and String.starts_with?(item["image_url"], "http")
             end),
             "All items must have absolute image_url"

      assert Enum.all?(items, fn item ->
               is_nil(item["description"]) or
                 String.length(item["description"]) <= 300
             end),
             "All descriptions must be <= 300 characters"

      IO.puts("""

      Gemini extraction for Hubble page:
        items found:       #{length(items)}
        gallery_title:     #{result["gallery_title"]}
        next_page_url:     #{result["next_page_url"]}
        sample image_url:  #{get_in(items, [Access.at(0), "image_url"])}
        sample title:      #{get_in(items, [Access.at(0), "title"])}
      """)
    end
  end
end
