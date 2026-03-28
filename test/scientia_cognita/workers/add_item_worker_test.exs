defmodule ScientiaCognita.Workers.AddItemWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import ScientiaCognita.AccountsFixtures
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.Workers.AddItemWorker
  alias ScientiaCognita.Photos

  # NOTE: The HTTP calls to Google Photos cannot be unit-tested without a
  # mock HTTP adapter (Bypass or Req.Test). The tests below cover authorization
  # guards and Photos context integration only.

  setup do
    owner = user_fixture()
    source = source_fixture()
    catalog = catalog_fixture()
    item = item_fixture(source, %{final_image: "test.jpg"})
    {:ok, export} = Photos.get_or_create_export(owner, catalog)

    {:ok, export} =
      Photos.set_export_status(export, "done",
        album_id: "album-abc",
        album_url: "https://photos.google.com/album/album-abc"
      )

    %{owner: owner, catalog: catalog, item: item, export: export}
  end

  test "rejects job if export does not belong to the requesting user", %{
    export: export,
    item: item
  } do
    attacker = user_fixture()

    assert {:error, :unauthorized} =
             perform_job(AddItemWorker, %{
               export_id: export.id,
               item_id: item.id,
               user_id: attacker.id
             })
  end

  test "item remains untracked if job is rejected (no DB side-effects from auth failure)", %{
    export: export,
    item: item
  } do
    attacker = user_fixture()

    perform_job(AddItemWorker, %{
      export_id: export.id,
      item_id: item.id,
      user_id: attacker.id
    })

    assert Photos.get_export_item(export, item) == nil
  end
end
