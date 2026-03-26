# test/scientia_cognita_web/live/core_components_test.exs
defmodule ScientiaCognitaWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  import ScientiaCognitaWeb.CoreComponents, only: [user_initials: 1, page_header: 1]

  describe "user_initials/1" do
    test "splits on dot — ivan.kerin@example.com → IK" do
      assert user_initials("ivan.kerin@example.com") == "IK"
    end

    test "splits on underscore — ivan_kerin@example.com → IK" do
      assert user_initials("ivan_kerin@example.com") == "IK"
    end

    test "no separator — ivantest@example.com → IV" do
      assert user_initials("ivantest@example.com") == "IV"
    end

    test "three segments — a.b.c@example.com → AB (only first two)" do
      assert user_initials("a.b.c@example.com") == "AB"
    end

    test "single character local part — a@example.com → AA" do
      assert user_initials("a@example.com") == "AA"
    end

    test "uppercases result" do
      assert user_initials("anna.brown@example.com") == "AB"
    end
  end

  describe "page_header/1" do
    test "renders title with font-serif-display class" do
      html = render_component(&page_header/1, %{title: "Dashboard", subtitle: nil, action: []})
      assert html =~ "Dashboard"
      assert html =~ "font-serif-display"
    end

    test "renders subtitle when provided" do
      html = render_component(&page_header/1, %{title: "Dashboard", subtitle: "Welcome", action: []})
      assert html =~ "Welcome"
    end

    test "omits subtitle when nil" do
      html = render_component(&page_header/1, %{title: "Dashboard", subtitle: nil, action: []})
      refute html =~ "<p"
    end

    test "omits action wrapper when no action given" do
      html = render_component(&page_header/1, %{title: "Dashboard", subtitle: nil, action: []})
      refute html =~ "shrink-0"
    end

    test "has mb-6 bottom margin" do
      html = render_component(&page_header/1, %{title: "Dashboard", subtitle: nil, action: []})
      assert html =~ "mb-6"
    end
  end
end
