defmodule ScientiaCognita.PhotosTest do
  use ScientiaCognita.DataCase

  alias ScientiaCognita.Photos

  import ScientiaCognita.AccountsFixtures
  import ScientiaCognita.CatalogFixtures

  setup do
    user = user_fixture()
    source = source_fixture()
    catalog = catalog_fixture()
    item = item_fixture(source)
    %{user: user, catalog: catalog, item: item}
  end

  describe "get_export_for_user/2" do
    test "returns nil when no export exists", %{user: user, catalog: catalog} do
      assert Photos.get_export_for_user(user, catalog) == nil
    end

    test "returns the export when it exists", %{user: user, catalog: catalog} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      assert Photos.get_export_for_user(user, catalog).id == export.id
    end
  end

  describe "get_or_create_export/2" do
    test "creates a new export if none exists", %{user: user, catalog: catalog} do
      assert {:ok, export} = Photos.get_or_create_export(user, catalog)
      assert export.user_id == user.id
      assert export.catalog_id == catalog.id
      assert export.status == "pending"
    end

    test "returns existing export without creating a duplicate", %{user: user, catalog: catalog} do
      {:ok, export1} = Photos.get_or_create_export(user, catalog)
      {:ok, export2} = Photos.get_or_create_export(user, catalog)
      assert export1.id == export2.id
    end
  end

  describe "set_export_status/3" do
    test "updates the export status", %{user: user, catalog: catalog} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, updated} = Photos.set_export_status(export, "running")
      assert updated.status == "running"
    end

    test "stores optional fields like album_id and album_url", %{user: user, catalog: catalog} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, updated} = Photos.set_export_status(export, "running", album_id: "abc123", album_url: "https://photos.google.com/album/abc123")
      assert updated.album_id == "abc123"
      assert updated.album_url == "https://photos.google.com/album/abc123"
    end
  end

  describe "set_item_uploaded/2 and list_uploaded_item_ids/1" do
    test "marks an item as uploaded and includes it in the id list", %{user: user, catalog: catalog, item: item} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, _} = Photos.set_item_uploaded(export, item)
      assert item.id in Photos.list_uploaded_item_ids(export)
    end

    test "does not include failed items in uploaded id list", %{user: user, catalog: catalog, item: item} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, _} = Photos.set_item_failed(export, item, "upload error")
      refute item.id in Photos.list_uploaded_item_ids(export)
    end
  end

  describe "set_item_failed/3" do
    test "records the error message on the export item", %{user: user, catalog: catalog, item: item} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, export_item} = Photos.set_item_failed(export, item, "timeout")
      assert export_item.status == "failed"
      assert export_item.error == "timeout"
    end

    test "updating a failed item to uploaded works (upsert)", %{user: user, catalog: catalog, item: item} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, _} = Photos.set_item_failed(export, item, "first attempt failed")
      {:ok, _} = Photos.set_item_uploaded(export, item)
      assert item.id in Photos.list_uploaded_item_ids(export)
    end
  end

  describe "list_export_item_statuses/1" do
    test "returns a map of item_id to status/error", %{user: user, catalog: catalog, item: item} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      {:ok, _} = Photos.set_item_failed(export, item, "oops")
      statuses = Photos.list_export_item_statuses(export)
      assert statuses[item.id] == %{status: "failed", error: "oops"}
    end

    test "returns empty map when no items tracked", %{user: user, catalog: catalog} do
      {:ok, export} = Photos.get_or_create_export(user, catalog)
      assert Photos.list_export_item_statuses(export) == %{}
    end
  end
end
