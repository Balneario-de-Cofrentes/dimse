defmodule Dimse.Association.Negotiation do
  @moduledoc """
  Presentation context negotiation logic.

  When an A-ASSOCIATE-RQ arrives, the SCP must decide which presentation
  contexts to accept, reject, or accept with an alternative transfer syntax.
  This module implements the matching algorithm.

  ## Result Codes (PS3.8 Section 9.3.3.2)

  - `0` — acceptance
  - `1` — user rejection
  - `2` — no reason (provider rejection)
  - `3` — abstract syntax not supported (provider rejection)
  - `4` — transfer syntaxes not supported (provider rejection)
  """

  alias Dimse.Pdu

  @acceptance 0
  @abstract_syntax_not_supported 3
  @transfer_syntaxes_not_supported 4

  @doc """
  Negotiates presentation contexts from an A-ASSOCIATE-RQ.

  Returns presentation contexts with result codes for the A-ASSOCIATE-AC response,
  plus a map of `%{context_id => {abstract_syntax, transfer_syntax}}` for accepted contexts.
  """
  @spec negotiate(
          proposed :: [Pdu.PresentationContext.t()],
          supported_abstract_syntaxes :: MapSet.t(String.t()),
          supported_transfer_syntaxes :: MapSet.t(String.t())
        ) :: {[Pdu.PresentationContext.t()], %{pos_integer() => {String.t(), String.t()}}}
  def negotiate(proposed, supported_abstract_syntaxes, supported_transfer_syntaxes) do
    {results, accepted_map} =
      Enum.reduce(proposed, {[], %{}}, fn pc, {results, accepted} ->
        {result_pc, new_accepted} =
          negotiate_one(pc, supported_abstract_syntaxes, supported_transfer_syntaxes, accepted)

        {results ++ [result_pc], new_accepted}
      end)

    {results, accepted_map}
  end

  defp negotiate_one(pc, supported_as, supported_ts, accepted) do
    cond do
      not MapSet.member?(supported_as, pc.abstract_syntax) ->
        result = %Pdu.PresentationContext{
          id: pc.id,
          result: @abstract_syntax_not_supported,
          transfer_syntaxes: []
        }

        {result, accepted}

      true ->
        case find_matching_ts(pc.transfer_syntaxes || [], supported_ts) do
          nil ->
            result = %Pdu.PresentationContext{
              id: pc.id,
              result: @transfer_syntaxes_not_supported,
              transfer_syntaxes: []
            }

            {result, accepted}

          matched_ts ->
            result = %Pdu.PresentationContext{
              id: pc.id,
              result: @acceptance,
              transfer_syntaxes: [matched_ts]
            }

            new_accepted = Map.put(accepted, pc.id, {pc.abstract_syntax, matched_ts})
            {result, new_accepted}
        end
    end
  end

  defp find_matching_ts(proposed_list, supported_set) do
    Enum.find(proposed_list, fn ts -> MapSet.member?(supported_set, ts) end)
  end
end
