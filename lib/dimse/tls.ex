defmodule Dimse.Tls do
  @moduledoc "TLS utility functions for DICOM Secure Transport (PS3.15 Annex B)."

  @doc "Normalizes TLS options for OTP :ssl (converts string paths to charlists)."
  @spec normalize_opts(keyword()) :: keyword()
  def normalize_opts(opts) when is_list(opts), do: Enum.map(opts, &normalize_opt/1)

  defp normalize_opt({key, value})
       when key in [:certfile, :keyfile, :cacertfile] and is_binary(value) do
    {key, to_charlist(value)}
  end

  defp normalize_opt(opt), do: opt
end
