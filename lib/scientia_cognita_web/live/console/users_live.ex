defmodule ScientiaCognitaWeb.Console.UsersLive do
  use ScientiaCognitaWeb, :live_view

  on_mount {ScientiaCognitaWeb.UserAuth, :require_console_user}

  alias ScientiaCognita.Accounts
  alias ScientiaCognita.Accounts.User

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <div>
          <h1 class="text-2xl font-bold">Users</h1>
          <p class="text-base-content/60 mt-1">{length(@users)} registered accounts</p>
        </div>
      </div>

      <div class="card bg-base-200">
        <div class="overflow-x-auto">
          <table class="table table-zebra">
            <thead>
              <tr>
                <th>Email</th>
                <th>Role</th>
                <th>Joined</th>
                <th>Confirmed</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              <tr :for={user <- @users} id={"user-#{user.id}"}>
                <td class="font-mono text-sm">{user.email}</td>
                <td><.role_badge role={user.role} /></td>
                <td class="text-sm text-base-content/60">
                  {Calendar.strftime(user.inserted_at, "%b %d, %Y")}
                </td>
                <td>
                  <span :if={user.confirmed_at} class="badge badge-success badge-sm">confirmed</span>
                  <span :if={!user.confirmed_at} class="badge badge-warning badge-sm">pending</span>
                </td>
                <td>
                  <button
                    :if={can_change_role?(@current_scope.user, user)}
                    class="btn btn-ghost btn-xs"
                    phx-click="open_role_modal"
                    phx-value-user-id={user.id}
                  >
                    Change role
                  </button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>

    <%!-- Role change modal --%>
    <div
      :if={@modal_user}
      class="modal modal-open"
      phx-key="Escape"
      phx-window-keydown="close_modal"
    >
      <div class="modal-box">
        <h3 class="font-bold text-lg">Change Role</h3>
        <p class="text-sm text-base-content/60 mt-1 mb-4">
          Update role for <span class="font-mono font-semibold">{@modal_user.email}</span>
        </p>

        <form phx-submit="set_role">
          <input type="hidden" name="user_id" value={@modal_user.id} />

          <div class="form-control">
            <label class="label">
              <span class="label-text">New role</span>
            </label>
            <select name="role" class="select select-bordered w-full">
              <option
                :for={role <- allowed_roles(@current_scope.user)}
                value={role}
                selected={role == @modal_user.role}
              >
                {role}
              </option>
            </select>
          </div>

          <div class="modal-action">
            <button type="button" class="btn btn-ghost" phx-click="close_modal">
              Cancel
            </button>
            <button type="submit" class="btn btn-primary">
              Save
            </button>
          </div>
        </form>
      </div>
      <div class="modal-backdrop" phx-click="close_modal"></div>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, users: Accounts.list_users(), modal_user: nil)}
  end

  @impl true
  def handle_event("open_role_modal", %{"user-id" => user_id}, socket) do
    user = Accounts.get_user!(user_id)
    {:noreply, assign(socket, :modal_user, user)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, assign(socket, :modal_user, nil)}
  end

  def handle_event("set_role", %{"user_id" => user_id, "role" => new_role}, socket) do
    actor = socket.assigns.current_scope.user
    target = Accounts.get_user!(user_id)

    case Accounts.set_role(actor, target, new_role) do
      {:ok, _updated} ->
        {:noreply,
         socket
         |> assign(users: Accounts.list_users(), modal_user: nil)
         |> put_flash(:info, "Role updated to #{new_role} for #{target.email}")}

      {:error, :last_owner} ->
        {:noreply,
         socket
         |> put_flash(:error, "Cannot demote the last owner.")
         |> assign(:modal_user, nil)}

      {:error, :unauthorized} ->
        {:noreply,
         socket
         |> put_flash(:error, "You are not authorised to assign that role.")
         |> assign(:modal_user, nil)}

      {:error, changeset} ->
        {:noreply,
         socket
         |> put_flash(:error, "Error: #{inspect(changeset.errors)}")
         |> assign(:modal_user, nil)}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp role_badge(assigns) do
    ~H"""
    <span class={"badge badge-sm #{role_class(@role)}"}>
      {@role}
    </span>
    """
  end

  defp role_class("owner"), do: "badge-accent font-semibold"
  defp role_class("admin"), do: "badge-primary"
  defp role_class(_), do: "badge-ghost"

  # Roles the actor can assign
  defp allowed_roles(%User{role: "owner"}), do: User.roles()
  defp allowed_roles(%User{role: "admin"}), do: ["user", "admin"]
  defp allowed_roles(_), do: []

  # Only show "Change role" button if actor can do anything useful for that target
  defp can_change_role?(%User{role: "owner"} = actor, target),
    do: actor.id != target.id || target.role != "owner"

  defp can_change_role?(%User{role: "admin"}, %User{role: role}),
    do: role in ["user", "admin"]

  defp can_change_role?(_, _), do: false
end
