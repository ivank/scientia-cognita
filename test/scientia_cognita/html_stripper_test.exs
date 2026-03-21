defmodule ScientiaCognita.HTMLStripperTest do
  use ExUnit.Case, async: true

  alias ScientiaCognita.HTMLStripper

  @hubble_html File.read!("test/fixtures/hubble_page.html")

  describe "attribute filtering" do
    test "removes class attributes from all elements" do
      html = ~s(<div class="gallery"><p class="caption">Text</p></div>)
      result = HTMLStripper.strip(html)
      refute result =~ ~r/class=/
    end

    test "removes id attributes from all elements" do
      html = ~s(<div id="main"><p id="text">Content</p></div>)
      result = HTMLStripper.strip(html)
      refute result =~ ~r/id=/
    end

    test "preserves href on anchors" do
      html = ~s(<body><a href="https://example.com" class="link">Click</a></body>)
      result = HTMLStripper.strip(html)
      assert result =~ ~s(href="https://example.com")
      refute result =~ ~r/class=/
    end

    test "preserves src, alt, srcset on images" do
      html = ~s(<body><img src="https://example.com/img.jpg" alt="Test" srcset="img 2x" class="photo"></body>)
      result = HTMLStripper.strip(html)
      assert result =~ ~s(src="https://example.com/img.jpg")
      assert result =~ ~s(alt="Test")
      assert result =~ "srcset="
      refute result =~ ~r/class=/
    end

    test "preserves data-src and data-srcset on images (lazy loading)" do
      html = ~s(<body><img data-src="https://example.com/lazy.jpg" data-srcset="https://example.com/lazy@2x.jpg 2x"></body>)
      result = HTMLStripper.strip(html)
      assert result =~ "data-src="
      assert result =~ "data-srcset="
    end
  end

  describe "element removal" do
    test "removes script tags" do
      html = "<html><body><script>alert('x')</script><p>Content</p></body></html>"
      result = HTMLStripper.strip(html)
      refute result =~ "<script"
      assert result =~ "Content"
    end

    test "removes svg elements and all descendants" do
      html = "<html><body><svg><path d='M 0 0'/><use href='#icon'/></svg><p>After</p></body></html>"
      result = HTMLStripper.strip(html)
      refute result =~ "<svg"
      refute result =~ "<path"
      refute result =~ "<use"
      assert result =~ "After"
    end

    test "removes HTML comments" do
      html = "<html><body><!-- This is a comment --><p>Content</p></body></html>"
      result = HTMLStripper.strip(html)
      refute result =~ "<!--"
      assert result =~ "Content"
    end

    test "removes head content, keeps body" do
      html = "<html><head><title>Page</title><meta charset='utf-8'><link rel='stylesheet'></head><body><p>Body</p></body></html>"
      result = HTMLStripper.strip(html)
      refute result =~ "<title>"
      refute result =~ "<meta"
      refute result =~ "<link"
      assert result =~ "Body"
    end
  end

  describe "Hubble fixture" do
    test "strips hubble_page.html to under 100KB" do
      result = HTMLStripper.strip(@hubble_html)
      assert byte_size(result) < 100_000,
             "Expected stripped HTML < 100KB, got #{byte_size(result)} bytes"
    end
  end
end
