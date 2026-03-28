defmodule ScientiaCognitaWeb.PageControllerTest do
  use ScientiaCognitaWeb.ConnCase

  test "GET / renders catalog index", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Curated"
  end
end
