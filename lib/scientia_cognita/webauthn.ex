defmodule ScientiaCognita.WebAuthnBehaviour do
  @moduledoc "Callback spec for WebAuthn operations — used for Mox injection in tests."

  @callback new_registration_challenge(opts :: keyword()) :: Wax.Challenge.t()
  @callback new_authentication_challenge(opts :: keyword()) :: Wax.Challenge.t()
  @callback register(binary(), binary(), Wax.Challenge.t()) ::
              {:ok, {Wax.AuthenticatorData.t(), any()}} | {:error, any()}
  @callback authenticate(binary(), binary(), binary(), binary(), Wax.Challenge.t(), list()) ::
              {:ok, Wax.AuthenticatorData.t()} | {:error, any()}
end

defmodule ScientiaCognita.WebAuthn do
  @moduledoc "Production WebAuthn implementation — delegates all calls to the `Wax` library."

  @behaviour ScientiaCognita.WebAuthnBehaviour

  @impl true
  defdelegate new_registration_challenge(opts), to: Wax

  @impl true
  defdelegate new_authentication_challenge(opts), to: Wax

  @impl true
  defdelegate register(attestation_object, client_data_json, challenge), to: Wax

  @impl true
  defdelegate authenticate(
                credential_id,
                auth_data,
                sig,
                client_data_json,
                challenge,
                credentials
              ),
              to: Wax
end
