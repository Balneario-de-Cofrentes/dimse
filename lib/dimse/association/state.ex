defmodule Dimse.Association.State do
  @moduledoc """
  Association state struct carried by the `Dimse.Association` GenServer.

  Tracks everything needed during the lifetime of a DICOM association:
  socket, negotiated contexts, message assembly buffers, and counters.

  See PS3.8 Section 9.2 for the Upper Layer state machine specification.
  """

  @type phase :: :idle | :negotiating | :established | :releasing | :closed

  @type t :: %__MODULE__{
          phase: phase(),
          socket: :inet.socket() | nil,
          transport: module() | nil,
          remote_ae_title: String.t() | nil,
          local_ae_title: String.t() | nil,
          max_pdu_length: pos_integer(),
          negotiated_contexts: %{pos_integer() => {String.t(), String.t()}},
          implementation_uid: String.t() | nil,
          implementation_version: String.t() | nil,
          pdu_buffer: binary(),
          current_dimse_message: term(),
          association_id: String.t(),
          started_at: integer(),
          bytes_received: non_neg_integer(),
          bytes_sent: non_neg_integer(),
          handler: module() | nil,
          config: Dimse.Association.Config.t() | nil,
          pending_request: GenServer.from() | nil,
          pending_release: GenServer.from() | nil,
          artim_timer: reference() | nil
        }

  defstruct phase: :idle,
            socket: nil,
            transport: nil,
            remote_ae_title: nil,
            local_ae_title: nil,
            max_pdu_length: 16_384,
            negotiated_contexts: %{},
            implementation_uid: nil,
            implementation_version: nil,
            pdu_buffer: <<>>,
            current_dimse_message: nil,
            association_id: "",
            started_at: 0,
            bytes_received: 0,
            bytes_sent: 0,
            handler: nil,
            config: nil,
            pending_request: nil,
            pending_release: nil,
            artim_timer: nil
end
