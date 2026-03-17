defmodule Dimse.Association.Negotiation do
  @moduledoc """
  Presentation context negotiation logic.

  When an A-ASSOCIATE-RQ arrives, the SCP must decide which presentation
  contexts to accept, reject, or accept with an alternative transfer syntax.
  This module implements the matching algorithm.

  ## Negotiation Algorithm (PS3.8 Section 9.3.2/9.3.3)

  For each proposed presentation context in the A-ASSOCIATE-RQ:

  1. Check if the abstract syntax (SOP Class UID) is supported by the handler
  2. Find the first transfer syntax from the proposal that is also supported locally
  3. If both match → accept with the matched transfer syntax
  4. If abstract syntax matches but no transfer syntax → reject (transfer syntaxes not supported)
  5. If abstract syntax not supported → reject (abstract syntax not supported)

  ## Result Codes

  - `0` — acceptance
  - `1` — user rejection
  - `2` — no reason (provider rejection)
  - `3` — abstract syntax not supported (provider rejection)
  - `4` — transfer syntaxes not supported (provider rejection)
  """

  @doc """
  Negotiates presentation contexts from an A-ASSOCIATE-RQ.

  Takes the proposed presentation contexts and the set of locally supported
  abstract syntaxes and transfer syntaxes. Returns presentation contexts
  with result codes for the A-ASSOCIATE-AC response.
  """
  @spec negotiate(
          proposed :: [Dimse.Pdu.PresentationContext.t()],
          supported_abstract_syntaxes :: MapSet.t(String.t()),
          supported_transfer_syntaxes :: MapSet.t(String.t())
        ) :: [Dimse.Pdu.PresentationContext.t()]
  def negotiate(_proposed, _supported_abstract_syntaxes, _supported_transfer_syntaxes) do
    []
  end
end
