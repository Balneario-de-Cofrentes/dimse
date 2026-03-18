alias Dimse.Pdu
alias Dimse.Pdu.{Encoder, Decoder}

# --- Build test data ---

pcs = [
  %Pdu.PresentationContext{
    id: 1,
    abstract_syntax: "1.2.840.10008.1.1",
    transfer_syntaxes: ["1.2.840.10008.1.2", "1.2.840.10008.1.2.1"]
  },
  %Pdu.PresentationContext{
    id: 3,
    abstract_syntax: "1.2.840.10008.5.1.4.1.1.2",
    transfer_syntaxes: ["1.2.840.10008.1.2", "1.2.840.10008.1.2.1"]
  },
  %Pdu.PresentationContext{
    id: 5,
    abstract_syntax: "1.2.840.10008.5.1.4.1.2.2.1",
    transfer_syntaxes: ["1.2.840.10008.1.2", "1.2.840.10008.1.2.1"]
  }
]

base_ui = %Pdu.UserInformation{
  max_pdu_length: 16_384,
  implementation_uid: "1.2.826.0.1.3680043.8.498.1",
  implementation_version: "DIMSE_0.7.0"
}

ext_neg_ui = %{
  base_ui
  | role_selections: [
      %Pdu.RoleSelection{
        sop_class_uid: "1.2.840.10008.1.1",
        scu_role: true,
        scp_role: false
      },
      %Pdu.RoleSelection{
        sop_class_uid: "1.2.840.10008.5.1.4.1.1.2",
        scu_role: true,
        scp_role: false
      }
    ],
    user_identity: %Pdu.UserIdentity{
      identity_type: 1,
      positive_response_requested: false,
      primary_field: "benchmark_user",
      secondary_field: ""
    }
}

associate_rq = %Pdu.AssociateRq{
  protocol_version: 1,
  called_ae_title: "REMOTE_SCP",
  calling_ae_title: "LOCAL_SCU",
  presentation_contexts: pcs,
  user_information: base_ui
}

associate_rq_ext = %{associate_rq | user_information: ext_neg_ui}

associate_ac = %Pdu.AssociateAc{
  protocol_version: 1,
  called_ae_title: "REMOTE_SCP",
  calling_ae_title: "LOCAL_SCU",
  presentation_contexts: [
    %Pdu.PresentationContext{id: 1, result: 0, transfer_syntaxes: ["1.2.840.10008.1.2"]},
    %Pdu.PresentationContext{id: 3, result: 0, transfer_syntaxes: ["1.2.840.10008.1.2"]},
    %Pdu.PresentationContext{id: 5, result: 0, transfer_syntaxes: ["1.2.840.10008.1.2"]}
  ],
  user_information: base_ui
}

# Small P-DATA (command only, ~80 bytes)
small_pdata = %Pdu.PDataTf{
  pdv_items: [
    %Pdu.PresentationDataValue{
      context_id: 1,
      is_command: true,
      is_last: true,
      data: :crypto.strong_rand_bytes(80)
    }
  ]
}

# Large P-DATA (data set, ~4KB)
large_pdata = %Pdu.PDataTf{
  pdv_items: [
    %Pdu.PresentationDataValue{
      context_id: 1,
      is_command: false,
      is_last: true,
      data: :crypto.strong_rand_bytes(4096)
    }
  ]
}

release_rq = %Pdu.ReleaseRq{}
abort = %Pdu.Abort{source: 2, reason: 0}

# Pre-encode for decode benchmarks
rq_binary = IO.iodata_to_binary(Encoder.encode(associate_rq))
rq_ext_binary = IO.iodata_to_binary(Encoder.encode(associate_rq_ext))
ac_binary = IO.iodata_to_binary(Encoder.encode(associate_ac))
small_pdata_binary = IO.iodata_to_binary(Encoder.encode(small_pdata))
large_pdata_binary = IO.iodata_to_binary(Encoder.encode(large_pdata))

IO.puts("=== PDU sizes ===")
IO.puts("A-ASSOCIATE-RQ (plain):    #{byte_size(rq_binary)} bytes")
IO.puts("A-ASSOCIATE-RQ (ext-neg):  #{byte_size(rq_ext_binary)} bytes")
IO.puts("A-ASSOCIATE-AC:            #{byte_size(ac_binary)} bytes")
IO.puts("P-DATA small:              #{byte_size(small_pdata_binary)} bytes")
IO.puts("P-DATA large:              #{byte_size(large_pdata_binary)} bytes")
IO.puts("")

Benchee.run(
  %{
    "encode A-ASSOCIATE-RQ (plain)" => fn -> Encoder.encode(associate_rq) end,
    "encode A-ASSOCIATE-RQ (ext-neg)" => fn -> Encoder.encode(associate_rq_ext) end,
    "encode A-ASSOCIATE-AC (3 contexts)" => fn -> Encoder.encode(associate_ac) end,
    "encode P-DATA small (80B)" => fn -> Encoder.encode(small_pdata) end,
    "encode P-DATA large (4KB)" => fn -> Encoder.encode(large_pdata) end,
    "encode Release-RQ" => fn -> Encoder.encode(release_rq) end,
    "encode Abort" => fn -> Encoder.encode(abort) end,
    "decode A-ASSOCIATE-RQ (plain)" => fn -> Decoder.decode(rq_binary) end,
    "decode A-ASSOCIATE-RQ (ext-neg)" => fn -> Decoder.decode(rq_ext_binary) end,
    "decode A-ASSOCIATE-AC (3 contexts)" => fn -> Decoder.decode(ac_binary) end,
    "decode P-DATA small (80B)" => fn -> Decoder.decode(small_pdata_binary) end,
    "decode P-DATA large (4KB)" => fn -> Decoder.decode(large_pdata_binary) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  print: [configuration: false]
)
