defmodule Dimse.Pdu.Decoder do
  @moduledoc """
  Decodes DICOM PDU binaries into `Dimse.Pdu` structs.

  Implements the binary wire format defined in PS3.8 Section 9.3. Each PDU type
  has a fixed header (1 byte type + 1 byte reserved + 4 byte length) followed by
  a type-specific payload.

  Uses Elixir binary pattern matching for direct translation of the PDU format
  tables in the DICOM standard.

  ## Usage

      {:ok, pdu, rest} = Dimse.Pdu.Decoder.decode(binary)
      {:incomplete, binary} = Dimse.Pdu.Decoder.decode(partial_binary)
      {:error, reason} = Dimse.Pdu.Decoder.decode(invalid_binary)

  The decoder handles incomplete reads by returning `{:incomplete, buffer}` so
  the caller can accumulate more data before retrying.
  """

  alias Dimse.Pdu

  @doc """
  Decodes the next PDU from the given binary.

  Returns:
    - `{:ok, pdu_struct, rest}` — successfully decoded PDU with remaining bytes
    - `{:incomplete, binary}` — not enough data, caller should buffer and retry
    - `{:error, reason}` — malformed or unknown PDU type
  """
  @spec decode(binary()) ::
          {:ok, struct(), binary()} | {:incomplete, binary()} | {:error, term()}
  # Need at least 6 bytes for header
  def decode(data) when byte_size(data) < 6, do: {:incomplete, data}

  # Check if we have the full payload
  def decode(<<_type, 0x00, length::32, payload::binary>> = data)
      when byte_size(payload) < length do
    {:incomplete, data}
  end

  # A-ASSOCIATE-RQ (type 0x01) — PS3.8 Section 9.3.2
  def decode(<<0x01, 0x00, length::32, payload::binary-size(length), rest::binary>>) do
    case parse_associate_rq(payload) do
      {:ok, pdu} -> {:ok, pdu, rest}
      {:error, _} = err -> err
    end
  end

  # A-ASSOCIATE-AC (type 0x02) — PS3.8 Section 9.3.3
  def decode(<<0x02, 0x00, length::32, payload::binary-size(length), rest::binary>>) do
    case parse_associate_ac(payload) do
      {:ok, pdu} -> {:ok, pdu, rest}
      {:error, _} = err -> err
    end
  end

  # A-ASSOCIATE-RJ (type 0x03) — PS3.8 Section 9.3.4
  def decode(<<0x03, 0x00, 4::32, 0x00, result, source, reason, rest::binary>>) do
    {:ok, %Pdu.AssociateRj{result: result, source: source, reason: reason}, rest}
  end

  # P-DATA-TF (type 0x04) — PS3.8 Section 9.3.5
  def decode(<<0x04, 0x00, length::32, payload::binary-size(length), rest::binary>>) do
    case parse_pdv_items(payload, []) do
      {:ok, items} -> {:ok, %Pdu.PDataTf{pdv_items: items}, rest}
      {:error, _} = err -> err
    end
  end

  # A-RELEASE-RQ (type 0x05) — PS3.8 Section 9.3.6
  def decode(<<0x05, 0x00, 4::32, _reserved::32, rest::binary>>) do
    {:ok, %Pdu.ReleaseRq{}, rest}
  end

  # A-RELEASE-RP (type 0x06) — PS3.8 Section 9.3.7
  def decode(<<0x06, 0x00, 4::32, _reserved::32, rest::binary>>) do
    {:ok, %Pdu.ReleaseRp{}, rest}
  end

  # A-ABORT (type 0x07) — PS3.8 Section 9.3.8
  def decode(<<0x07, 0x00, 4::32, 0x00, 0x00, source, reason, rest::binary>>) do
    {:ok, %Pdu.Abort{source: source, reason: reason}, rest}
  end

  # Unknown PDU type
  def decode(<<type, 0x00, _length::32, _::binary>>) do
    {:error, {:unknown_pdu_type, type}}
  end

  def decode(<<_::binary>>), do: {:error, :malformed_pdu}

  ## A-ASSOCIATE-RQ parser

  defp parse_associate_rq(
         <<version::16, _reserved::16, called::binary-size(16), calling::binary-size(16),
           _reserved2::binary-size(32), items::binary>>
       ) do
    case parse_variable_items(items) do
      {:ok, parsed} ->
        {:ok,
         %Pdu.AssociateRq{
           protocol_version: version,
           called_ae_title: String.trim(called),
           calling_ae_title: String.trim(calling),
           application_context: parsed[:application_context],
           presentation_contexts: parsed[:presentation_contexts] || [],
           user_information: parsed[:user_information]
         }}

      {:error, _} = err ->
        err
    end
  end

  defp parse_associate_rq(_), do: {:error, :malformed_associate_rq}

  ## A-ASSOCIATE-AC parser

  defp parse_associate_ac(
         <<version::16, _reserved::16, called::binary-size(16), calling::binary-size(16),
           _reserved2::binary-size(32), items::binary>>
       ) do
    case parse_variable_items(items) do
      {:ok, parsed} ->
        {:ok,
         %Pdu.AssociateAc{
           protocol_version: version,
           called_ae_title: String.trim(called),
           calling_ae_title: String.trim(calling),
           application_context: parsed[:application_context],
           presentation_contexts: parsed[:presentation_contexts] || [],
           user_information: parsed[:user_information]
         }}

      {:error, _} = err ->
        err
    end
  end

  defp parse_associate_ac(_), do: {:error, :malformed_associate_ac}

  ## Variable items parser (for A-ASSOCIATE-RQ/AC)

  defp parse_variable_items(data) do
    parse_variable_items(data, %{presentation_contexts: []})
  end

  defp parse_variable_items(<<>>, acc), do: {:ok, acc}

  # Application Context Item (0x10)
  defp parse_variable_items(
         <<0x10, 0x00, len::16, uid::binary-size(len), rest::binary>>,
         acc
       ) do
    parse_variable_items(rest, Map.put(acc, :application_context, uid))
  end

  # Presentation Context Item - RQ (0x20)
  defp parse_variable_items(
         <<0x20, 0x00, len::16, item_data::binary-size(len), rest::binary>>,
         acc
       ) do
    case parse_presentation_context_rq(item_data) do
      {:ok, pc} ->
        contexts = acc[:presentation_contexts] ++ [pc]
        parse_variable_items(rest, Map.put(acc, :presentation_contexts, contexts))

      {:error, _} = err ->
        err
    end
  end

  # Presentation Context Item - AC (0x21)
  defp parse_variable_items(
         <<0x21, 0x00, len::16, item_data::binary-size(len), rest::binary>>,
         acc
       ) do
    case parse_presentation_context_ac(item_data) do
      {:ok, pc} ->
        contexts = acc[:presentation_contexts] ++ [pc]
        parse_variable_items(rest, Map.put(acc, :presentation_contexts, contexts))

      {:error, _} = err ->
        err
    end
  end

  # User Information Item (0x50)
  defp parse_variable_items(
         <<0x50, 0x00, len::16, ui_data::binary-size(len), rest::binary>>,
         acc
       ) do
    case parse_user_information(ui_data) do
      {:ok, ui} -> parse_variable_items(rest, Map.put(acc, :user_information, ui))
      {:error, _} = err -> err
    end
  end

  # Skip unknown items
  defp parse_variable_items(<<_type, 0x00, len::16, _data::binary-size(len), rest::binary>>, acc) do
    parse_variable_items(rest, acc)
  end

  defp parse_variable_items(_, _acc), do: {:error, :malformed_variable_items}

  ## Presentation Context parsers

  defp parse_presentation_context_rq(<<id, 0x00, 0x00, 0x00, sub_items::binary>>) do
    case parse_syntax_items(sub_items) do
      {:ok, abstract, transfers} ->
        {:ok,
         %Pdu.PresentationContext{
           id: id,
           abstract_syntax: abstract,
           transfer_syntaxes: transfers
         }}

      {:error, _} = err ->
        err
    end
  end

  defp parse_presentation_context_rq(_), do: {:error, :malformed_presentation_context}

  defp parse_presentation_context_ac(<<id, 0x00, result, 0x00, sub_items::binary>>) do
    case parse_syntax_items(sub_items) do
      {:ok, _abstract, transfers} ->
        {:ok,
         %Pdu.PresentationContext{
           id: id,
           result: result,
           transfer_syntaxes: transfers
         }}

      {:error, _} = err ->
        err
    end
  end

  defp parse_presentation_context_ac(_), do: {:error, :malformed_presentation_context}

  defp parse_syntax_items(data), do: parse_syntax_items(data, nil, [])

  defp parse_syntax_items(<<>>, abstract, transfers), do: {:ok, abstract, transfers}

  # Abstract Syntax (0x30)
  defp parse_syntax_items(
         <<0x30, 0x00, len::16, uid::binary-size(len), rest::binary>>,
         _abstract,
         transfers
       ) do
    parse_syntax_items(rest, uid, transfers)
  end

  # Transfer Syntax (0x40)
  defp parse_syntax_items(
         <<0x40, 0x00, len::16, uid::binary-size(len), rest::binary>>,
         abstract,
         transfers
       ) do
    parse_syntax_items(rest, abstract, transfers ++ [uid])
  end

  defp parse_syntax_items(_, _, _), do: {:error, :malformed_syntax_items}

  ## User Information parser

  defp parse_user_information(data), do: parse_user_info_items(data, %Pdu.UserInformation{})

  defp parse_user_info_items(<<>>, ui), do: {:ok, ui}

  # Max Length (0x51)
  defp parse_user_info_items(<<0x51, 0x00, 4::16, length::32, rest::binary>>, ui) do
    parse_user_info_items(rest, %{ui | max_pdu_length: length})
  end

  # Implementation Class UID (0x52)
  defp parse_user_info_items(
         <<0x52, 0x00, len::16, uid::binary-size(len), rest::binary>>,
         ui
       ) do
    parse_user_info_items(rest, %{ui | implementation_uid: uid})
  end

  # Implementation Version Name (0x55)
  defp parse_user_info_items(
         <<0x55, 0x00, len::16, version::binary-size(len), rest::binary>>,
         ui
       ) do
    parse_user_info_items(rest, %{ui | implementation_version: version})
  end

  # Skip unknown user info sub-items
  defp parse_user_info_items(<<_type, 0x00, len::16, _data::binary-size(len), rest::binary>>, ui) do
    parse_user_info_items(rest, ui)
  end

  defp parse_user_info_items(_, _), do: {:error, :malformed_user_information}

  ## P-DATA-TF PDV items parser

  defp parse_pdv_items(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp parse_pdv_items(<<pdv_length::32, rest::binary>>, acc)
       when byte_size(rest) >= pdv_length do
    # pdv_length includes context_id (1) + flags (1) + data
    data_length = pdv_length - 2
    <<context_id, flags, data::binary-size(data_length), remaining::binary>> = rest

    pdv = %Pdu.PresentationDataValue{
      context_id: context_id,
      is_command: Bitwise.band(flags, 0x01) != 0,
      is_last: Bitwise.band(flags, 0x02) != 0,
      data: data
    }

    parse_pdv_items(remaining, [pdv | acc])
  end

  defp parse_pdv_items(_, _), do: {:error, :malformed_pdv}
end
