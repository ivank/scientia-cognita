defmodule ScientiaCognita.Workers.DeleteAlbumWorkerTest do
  use ScientiaCognita.DataCase
  use Oban.Testing, repo: ScientiaCognita.Repo

  import ScientiaCognita.AccountsFixtures
  import ScientiaCognita.CatalogFixtures

  alias ScientiaCognita.Workers.DeleteAlbumWorker
  alias ScientiaCognita.Photos

  # NOTE: The HTTP call to Google Photos cannot be unit-tested here without a
  # mock adapter (Bypass or Req.Test plug). The test below covers the
  # authorization guard only. The full deletion flow is verified via manual
  # smoke test.

  test "rejects job if export does not belong to the requesting user" do
    owner = user_fixture()
    attacker = user_fixture()
    catalog = catalog_fixture()
    {:ok, export} = Photos.get_or_create_export(owner, catalog)
    {:ok, export} = Photos.set_export_status(export, "done", album_id: "abc", album_url: "https://photos.google.com/album/abc")

    # attacker passes their own user_id but owner's export_id
    assert {:error, :unauthorized} =
      perform_job(DeleteAlbumWorker, %{photo_export_id: export.id, user_id: attacker.id})
  end
end
