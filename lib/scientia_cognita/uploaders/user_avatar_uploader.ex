defmodule ScientiaCognita.Uploaders.UserAvatarUploader do
  @moduledoc """
  Waffle uploader for user profile avatars.
  Stored at avatars/{user_id}/avatar.jpg, overwritten on each refresh.
  """

  use Waffle.Definition

  @versions [:original]

  def storage_dir(_version, {_file, user}), do: "avatars/#{user.id}"
  def acl(_version, _), do: :public_read

  def bucket do
    Application.get_env(:scientia_cognita, :storage)[:bucket] || "scientia-cognita"
  end
end
