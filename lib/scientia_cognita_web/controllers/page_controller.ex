defmodule ScientiaCognitaWeb.PageController do
  use ScientiaCognitaWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
