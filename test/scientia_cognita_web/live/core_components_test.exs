# test/scientia_cognita_web/live/core_components_test.exs
defmodule ScientiaCognitaWeb.CoreComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  import ScientiaCognitaWeb.CoreComponents, only: [user_initials: 1, page_header: 1, empty_state: 1, status_badge: 1, item_card: 1]

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

  describe "empty_state/1" do
    test "renders icon and title" do
      html = render_component(&empty_state/1, %{icon: "hero-photo", title: "No items", subtitle: nil, action: []})
      assert html =~ "No items"
      assert html =~ "hero-photo"
    end

    test "renders subtitle when provided" do
      html = render_component(&empty_state/1, %{icon: "hero-photo", title: "No items", subtitle: "Add some items.", action: []})
      assert html =~ "Add some items."
    end

    test "omits subtitle when nil" do
      html = render_component(&empty_state/1, %{icon: "hero-photo", title: "No items", subtitle: nil, action: []})
      refute html =~ "text-xs text-neutral"
    end

    test "omits action wrapper when no action given" do
      html = render_component(&empty_state/1, %{icon: "hero-photo", title: "No items", subtitle: nil, action: []})
      refute html =~ "mt-4 flex justify-center"
    end
  end

  describe "status_badge_class/1 via status_badge component" do
    test "pending → badge-ghost" do
      html = render_component(&status_badge/1, %{status: "pending", size: "sm"})
      assert html =~ "badge-ghost"
    end

    test "fetching → badge-warning animate-pulse" do
      html = render_component(&status_badge/1, %{status: "fetching", size: "sm"})
      assert html =~ "badge-warning"
      assert html =~ "animate-pulse"
    end

    test "extracting → badge-warning animate-pulse" do
      html = render_component(&status_badge/1, %{status: "extracting", size: "sm"})
      assert html =~ "badge-warning"
      assert html =~ "animate-pulse"
    end

    test "items_loading → badge-info animate-pulse" do
      html = render_component(&status_badge/1, %{status: "items_loading", size: "sm"})
      assert html =~ "badge-info"
      assert html =~ "animate-pulse"
    end

    test "done → badge-success" do
      html = render_component(&status_badge/1, %{status: "done", size: "sm"})
      assert html =~ "badge-success"
      refute html =~ "animate-pulse"
    end

    test "ready → badge-success" do
      html = render_component(&status_badge/1, %{status: "ready", size: "sm"})
      assert html =~ "badge-success"
    end

    test "failed → badge-error" do
      html = render_component(&status_badge/1, %{status: "failed", size: "sm"})
      assert html =~ "badge-error"
    end

    test "discarded → badge-warning (no pulse)" do
      html = render_component(&status_badge/1, %{status: "discarded", size: "sm"})
      assert html =~ "badge-warning"
      refute html =~ "animate-pulse"
    end

    test "downloading → badge-info (no pulse)" do
      html = render_component(&status_badge/1, %{status: "downloading", size: "sm"})
      assert html =~ "badge-info"
      refute html =~ "animate-pulse"
    end

    test "thumbnail → badge-info animate-pulse" do
      html = render_component(&status_badge/1, %{status: "thumbnail", size: "sm"})
      assert html =~ "badge-info"
      assert html =~ "animate-pulse"
    end

    test "analyze → badge-info animate-pulse" do
      html = render_component(&status_badge/1, %{status: "analyze", size: "sm"})
      assert html =~ "badge-info"
      assert html =~ "animate-pulse"
    end

    test "resize → badge-info animate-pulse" do
      html = render_component(&status_badge/1, %{status: "resize", size: "sm"})
      assert html =~ "badge-info"
      assert html =~ "animate-pulse"
    end

    test "render → badge-info animate-pulse" do
      html = render_component(&status_badge/1, %{status: "render", size: "sm"})
      assert html =~ "badge-info"
      assert html =~ "animate-pulse"
    end

    test "owner → badge-accent font-semibold" do
      html = render_component(&status_badge/1, %{status: "owner", size: "sm"})
      assert html =~ "badge-accent"
      assert html =~ "font-semibold"
    end

    test "admin → badge-primary" do
      html = render_component(&status_badge/1, %{status: "admin", size: "sm"})
      assert html =~ "badge-primary"
    end

    test "unknown → badge-ghost" do
      html = render_component(&status_badge/1, %{status: "nonexistent_status", size: "sm"})
      assert html =~ "badge-ghost"
    end
  end

  describe "item_card/1" do
    @item %{id: 1, title: "Test Item", author: "Alice", thumbnail_image: nil, final_image: nil}
    @item_no_author %{id: 2, title: "No Author", author: nil, thumbnail_image: nil, final_image: nil}

    test "renders item title" do
      html = render_component(&item_card/1, %{item: @item, id: nil, on_remove: nil, on_click: nil, failed: false, uploaded: false})
      assert html =~ "Test Item"
    end

    test "renders author when present" do
      html = render_component(&item_card/1, %{item: @item, id: nil, on_remove: nil, on_click: nil, failed: false, uploaded: false})
      assert html =~ "Alice"
    end

    test "omits author paragraph when author is nil" do
      html = render_component(&item_card/1, %{item: @item_no_author, id: nil, on_remove: nil, on_click: nil, failed: false, uploaded: false})
      refute html =~ "text-base-content/50"
    end

    test "applies ring-error when failed" do
      html = render_component(&item_card/1, %{item: @item, id: nil, on_remove: nil, on_click: nil, failed: true, uploaded: false})
      assert html =~ "ring-2 ring-error"
    end
  end
end
