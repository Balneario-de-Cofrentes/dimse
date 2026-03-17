defmodule Dimse.Command.Fields do
  @moduledoc """
  DIMSE command field constants.

  The CommandField element (0000,0100) identifies which DIMSE operation a
  command set represents. These constants are defined in PS3.7 Annex E.

  ## Command Fields

  | Value  | Name             | Type     |
  |--------|------------------|----------|
  | 0x0001 | C-STORE-RQ       | Request  |
  | 0x8001 | C-STORE-RSP      | Response |
  | 0x0020 | C-FIND-RQ        | Request  |
  | 0x8020 | C-FIND-RSP       | Response |
  | 0x0021 | C-MOVE-RQ        | Request  |
  | 0x8021 | C-MOVE-RSP       | Response |
  | 0x0010 | C-GET-RQ         | Request  |
  | 0x8010 | C-GET-RSP        | Response |
  | 0x0030 | C-ECHO-RQ        | Request  |
  | 0x8030 | C-ECHO-RSP       | Response |
  | 0x0100 | N-EVENT-REPORT-RQ | Request |
  | 0x8100 | N-EVENT-REPORT-RSP | Response |
  | 0x0110 | N-GET-RQ         | Request  |
  | 0x8110 | N-GET-RSP        | Response |
  | 0x0120 | N-SET-RQ         | Request  |
  | 0x8120 | N-SET-RSP        | Response |
  | 0x0130 | N-ACTION-RQ      | Request  |
  | 0x8130 | N-ACTION-RSP     | Response |
  | 0x0140 | N-CREATE-RQ      | Request  |
  | 0x8140 | N-CREATE-RSP     | Response |
  | 0x0150 | N-DELETE-RQ      | Request  |
  | 0x8150 | N-DELETE-RSP     | Response |
  | 0x0FFF | C-CANCEL-RQ      | Request  |
  """

  # DIMSE-C
  @c_store_rq 0x0001
  @c_store_rsp 0x8001
  @c_find_rq 0x0020
  @c_find_rsp 0x8020
  @c_move_rq 0x0021
  @c_move_rsp 0x8021
  @c_get_rq 0x0010
  @c_get_rsp 0x8010
  @c_echo_rq 0x0030
  @c_echo_rsp 0x8030
  @c_cancel_rq 0x0FFF

  # DIMSE-N
  @n_event_report_rq 0x0100
  @n_event_report_rsp 0x8100
  @n_get_rq 0x0110
  @n_get_rsp 0x8110
  @n_set_rq 0x0120
  @n_set_rsp 0x8120
  @n_action_rq 0x0130
  @n_action_rsp 0x8130
  @n_create_rq 0x0140
  @n_create_rsp 0x8140
  @n_delete_rq 0x0150
  @n_delete_rsp 0x8150

  @doc "C-STORE-RQ command field value (0x0001)."
  def c_store_rq, do: @c_store_rq

  @doc "C-STORE-RSP command field value (0x8001)."
  def c_store_rsp, do: @c_store_rsp

  @doc "C-FIND-RQ command field value (0x0020)."
  def c_find_rq, do: @c_find_rq

  @doc "C-FIND-RSP command field value (0x8020)."
  def c_find_rsp, do: @c_find_rsp

  @doc "C-MOVE-RQ command field value (0x0021)."
  def c_move_rq, do: @c_move_rq

  @doc "C-MOVE-RSP command field value (0x8021)."
  def c_move_rsp, do: @c_move_rsp

  @doc "C-GET-RQ command field value (0x0010)."
  def c_get_rq, do: @c_get_rq

  @doc "C-GET-RSP command field value (0x8010)."
  def c_get_rsp, do: @c_get_rsp

  @doc "C-ECHO-RQ command field value (0x0030)."
  def c_echo_rq, do: @c_echo_rq

  @doc "C-ECHO-RSP command field value (0x8030)."
  def c_echo_rsp, do: @c_echo_rsp

  @doc "C-CANCEL-RQ command field value (0x0FFF)."
  def c_cancel_rq, do: @c_cancel_rq

  @doc "N-EVENT-REPORT-RQ command field value (0x0100)."
  def n_event_report_rq, do: @n_event_report_rq

  @doc "N-EVENT-REPORT-RSP command field value (0x8100)."
  def n_event_report_rsp, do: @n_event_report_rsp

  @doc "N-GET-RQ command field value (0x0110)."
  def n_get_rq, do: @n_get_rq

  @doc "N-GET-RSP command field value (0x8110)."
  def n_get_rsp, do: @n_get_rsp

  @doc "N-SET-RQ command field value (0x0120)."
  def n_set_rq, do: @n_set_rq

  @doc "N-SET-RSP command field value (0x8120)."
  def n_set_rsp, do: @n_set_rsp

  @doc "N-ACTION-RQ command field value (0x0130)."
  def n_action_rq, do: @n_action_rq

  @doc "N-ACTION-RSP command field value (0x8130)."
  def n_action_rsp, do: @n_action_rsp

  @doc "N-CREATE-RQ command field value (0x0140)."
  def n_create_rq, do: @n_create_rq

  @doc "N-CREATE-RSP command field value (0x8140)."
  def n_create_rsp, do: @n_create_rsp

  @doc "N-DELETE-RQ command field value (0x0150)."
  def n_delete_rq, do: @n_delete_rq

  @doc "N-DELETE-RSP command field value (0x8150)."
  def n_delete_rsp, do: @n_delete_rsp

  @doc "Returns true if the command field value represents a request."
  @spec request?(integer()) :: boolean()
  def request?(field), do: Bitwise.band(field, 0x8000) == 0

  @doc "Returns true if the command field value represents a response."
  @spec response?(integer()) :: boolean()
  def response?(field), do: Bitwise.band(field, 0x8000) != 0
end
