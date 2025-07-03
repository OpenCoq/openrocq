(* Economic Attention Network (ECAN) module *)

open Hypergraph

(** ECAN configuration parameters *)
type ecan_config = {
  min_sti : float;
  max_sti : float;
  sti_decay_rate : float;
  lti_decay_rate : float;
  vlti_decay_rate : float;
  forgetting_threshold : float;
  attention_budget : float;
  spreading_factor : float;
}

(** Attention spreading events *)
type attention_event = {
  source : uuid;
  target : uuid;
  amount : float;
  event_type : string;
  timestamp : float;
}

(** ECAN attention allocator *)
type ecan_allocator = {
  config : ecan_config;
  atomspace : atomspace;
  attention_events : attention_event list ref;
  current_budget : float ref;
}

(** Create default ECAN configuration *)
val default_ecan_config : ecan_config

(** Create ECAN allocator *)
val create_ecan_allocator : atomspace -> ecan_config -> ecan_allocator

(** Update attention values based on usage *)
val update_attention_on_access : ecan_allocator -> uuid -> float -> unit

(** Spread attention from source to connected nodes *)
val spread_attention : ecan_allocator -> uuid -> float -> unit

(** Perform attention decay *)
val decay_attention_values : ecan_allocator -> unit

(** Perform forgetting of low-attention elements *)
val perform_forgetting : ecan_allocator -> unit

(** Get attention focus (high STI elements) *)
val get_attention_focus : ecan_allocator -> int -> uuid list

(** Redistribute attention budget *)
val redistribute_attention_budget : ecan_allocator -> unit

(** Get attention statistics *)
val get_attention_statistics : ecan_allocator -> (float * float * float * int)

(** Process attention events *)
val process_attention_events : ecan_allocator -> unit

(** Calculate importance score *)
val calculate_importance_score : attention_value -> float

(** Get elements ready for forgetting *)
val get_forgettable_elements : ecan_allocator -> uuid list
