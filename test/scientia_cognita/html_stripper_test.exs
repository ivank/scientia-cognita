defmodule ScientiaCognita.HTMLStripperTest do
  use ExUnit.Case, async: true

  alias ScientiaCognita.HTMLStripper

  # ---------------------------------------------------------------------------
  # Attribute filtering
  # ---------------------------------------------------------------------------

  describe "attribute filtering" do
    test "preserves class attributes (needed for LLM structural context)" do
      result = HTMLStripper.strip("<div class=\"gallery\"><p class=\"caption\">Text</p></div>")
      assert result =~ "class=\"gallery\""
      assert result =~ "class=\"caption\""
    end

    test "removes id attributes" do
      result = HTMLStripper.strip("<div id=\"main\"><p id=\"text\">Content</p></div>")
      refute result =~ " id="
    end

    test "removes style attributes" do
      result = HTMLStripper.strip("<div style=\"display:none\"><p style=\"color:red\">Content</p></div>")
      refute result =~ " style="
    end

    test "removes event handler attributes" do
      html = "<div><button data-x=\"y\">Click</button></div>"
      result = HTMLStripper.strip(html)
      refute result =~ "onclick"
    end

    test "preserves href on anchors" do
      html = "<body><a href=\"https://example.com\" class=\"link\">Click</a></body>"
      result = HTMLStripper.strip(html)
      assert result =~ "href=\"https://example.com\""
    end

    test "preserves src, alt, srcset on images" do
      html = "<body><img src=\"https://example.com/img.jpg\" alt=\"Test\" srcset=\"img 2x\" id=\"hero\"></body>"
      result = HTMLStripper.strip(html)
      assert result =~ "src=\"https://example.com/img.jpg\""
      assert result =~ "alt=\"Test\""
      assert result =~ "srcset="
      refute result =~ " id="
    end

    test "preserves data-src and data-srcset on images (lazy loading)" do
      html = "<body><img data-src=\"https://example.com/lazy.jpg\" data-srcset=\"https://example.com/lazy@2x.jpg 2x\"></body>"
      result = HTMLStripper.strip(html)
      assert result =~ "data-src="
      assert result =~ "data-srcset="
    end

    test "preserves aria-hidden and aria-label globally" do
      html = "<div aria-hidden=\"true\"><button aria-label=\"Close\">X</button></div>"
      result = HTMLStripper.strip(html)
      assert result =~ "aria-hidden=\"true\""
      assert result =~ "aria-label=\"Close\""
    end
  end

  # ---------------------------------------------------------------------------
  # Element removal
  # ---------------------------------------------------------------------------

  describe "element removal" do
    test "removes script tags and content" do
      html = "<html><body><script>var x = 1;</script><p>Content</p></body></html>"
      result = HTMLStripper.strip(html)
      refute result =~ "<script"
      refute result =~ "var x"
      assert result =~ "Content"
    end

    test "removes source elements (srcset bloat inside picture)" do
      html = """
      <html><body>
        <picture>
          <source type="image/webp" srcset="a.webp 1200w, b.webp 800w"/>
          <img src="a.jpg" alt="Photo"/>
        </picture>
      </body></html>
      """

      result = HTMLStripper.strip(html)
      refute result =~ "<source"
      assert result =~ "src=\"a.jpg\""
    end

    test "removes svg elements and all descendants" do
      html = "<html><body><svg><path d=\"M 0 0\"/></svg><p>After</p></body></html>"
      result = HTMLStripper.strip(html)
      refute result =~ "<svg"
      refute result =~ "<path"
      assert result =~ "After"
    end

    test "removes HTML comments" do
      html = "<html><body><!-- comment --><p>Content</p></body></html>"
      result = HTMLStripper.strip(html)
      refute result =~ "<!--"
      assert result =~ "Content"
    end

    test "removes head content, keeps body" do
      html = "<html><head><title>Page</title><meta charset=\"utf-8\"></head><body><p>Body</p></body></html>"
      result = HTMLStripper.strip(html)
      refute result =~ "<title>"
      refute result =~ "<meta"
      assert result =~ "Body"
    end

    test "does NOT remove aria-hidden elements (gallery slides use this)" do
      html = """
      <html><body>
        <div aria-hidden="true"><img src="slide.jpg" alt="Slide"/></div>
        <div>Visible</div>
      </body></html>
      """

      result = HTMLStripper.strip(html)
      assert result =~ "src=\"slide.jpg\""
      assert result =~ "Visible"
    end
  end

  # ---------------------------------------------------------------------------
  # Structural preservation for LLM
  # ---------------------------------------------------------------------------

  describe "structural context preservation" do
    test "keeps sibling content div class alongside figure for LLM association" do
      html = """
      <html><body>
        <div class="gallery-item">
          <figure><img src="img.jpg" alt="Photo"/></figure>
          <div class="gallery-item-caption">
            <h2>Title</h2>
            <p>Description text here.</p>
          </div>
        </div>
      </body></html>
      """

      result = HTMLStripper.strip(html)
      assert result =~ "class=\"gallery-item\""
      assert result =~ "class=\"gallery-item-caption\""
      assert result =~ "Description text here."
      assert result =~ "src=\"img.jpg\""
    end

    test "preserves figcaption content" do
      html = """
      <html><body>
        <figure>
          <img src="img.jpg" alt="A photo"/>
          <figcaption>This is the caption. <span class="credit">&#169; Author</span></figcaption>
        </figure>
      </body></html>
      """

      result = HTMLStripper.strip(html)
      assert result =~ "This is the caption."
      assert result =~ "Author"
    end
  end

  # ---------------------------------------------------------------------------
  # Size constraints
  # ---------------------------------------------------------------------------

  describe "size limits" do
    test "truncates output at custom max_bytes" do
      long_html = "<html><body>" <> String.duplicate("<p>word</p>", 10_000) <> "</body></html>"
      result = HTMLStripper.strip(long_html, 1_000)
      assert byte_size(result) <= 1_000
    end

    test "default limit is 300KB" do
      long_html = "<html><body>" <> String.duplicate("<p>word</p>", 100_000) <> "</body></html>"
      result = HTMLStripper.strip(long_html)
      assert byte_size(result) <= 300_000
    end
  end

  # ---------------------------------------------------------------------------
  # Real-page fixtures (fast, offline, no Gemini)
  # ---------------------------------------------------------------------------

  @nasa_html File.read!("test/fixtures/nasa_hubble_page.html")
  @livescience_html File.read!("test/fixtures/livescience_page.html")

  describe "NASA Hubble fixture" do
    test "all 40 gallery figures present after stripping" do
      result = HTMLStripper.strip(@nasa_html)
      fig_count = length(Regex.scan(~r/<figure/, result))
      assert fig_count >= 40, "Expected ≥40 figures, got #{fig_count}"
    end

    test "fits within 300KB limit" do
      result = HTMLStripper.strip(@nasa_html)
      assert byte_size(result) < 300_000
    end

    test "preserves scrapbook-item-content class for LLM association" do
      result = HTMLStripper.strip(@nasa_html)
      assert result =~ "hds-scrapbook-item-content",
             "Class name must survive stripping so Gemini can associate descriptions with images"
    end

    test "preserves description text adjacent to images" do
      result = HTMLStripper.strip(@nasa_html)
      assert result =~ "school-bus-sized",
             "Description paragraph text must survive stripping"
    end

    test "no source elements remain" do
      result = HTMLStripper.strip(@nasa_html)
      refute result =~ "<source", "source elements cause srcset bloat and should be removed"
    end
  end

  describe "LiveScience fixture" do
    test "all 101 gallery figures present after stripping" do
      result = HTMLStripper.strip(@livescience_html)
      fig_count = length(Regex.scan(~r/<figure/, result))
      assert fig_count >= 100, "Expected ≥100 figures, got #{fig_count}"
    end

    test "fits within 300KB limit" do
      result = HTMLStripper.strip(@livescience_html)
      assert byte_size(result) < 300_000
    end

    test "preserves description text in alt attributes" do
      result = HTMLStripper.strip(@livescience_html)
      assert result =~ "crabeater seals",
             "Alt attribute description text must survive stripping"
    end

    test "preserves post-figure paragraph descriptions" do
      result = HTMLStripper.strip(@livescience_html)
      assert result =~ "Underwater Photographer of the Year",
             "Post-figure paragraph descriptions must survive stripping"
    end
  end
end
