(* Core hypergraph data structures for cognitive engine *)

(** Unique identifiers for hypergraph elements *)
type uuid = int

(** Attention values for elements in the hypergraph *)
type attention_value = {
  sti : float;  (* Short-term importance *)
  lti : float;  (* Long-term importance *)
  vlti : float; (* Very long-term importance *)
}

(** Basic hypergraph node *)
type node = {
  id : uuid;
  name : string;
  attention : attention_value;
  confidence : float;
  created_at : float;
  updated_at : float;
}

(** Hypergraph link connecting multiple nodes *)
type link = {
  id : uuid;
  source_nodes : uuid list;
  target_nodes : uuid list;
  link_type : string;
  attention : attention_value;
  confidence : float;
  created_at : float;
  updated_at : float;
}

(** Tensor for representing complex relationships *)
type tensor = {
  id : uuid;
  dimensions : int array;
  data : float array;
  shape : int list;
  attention : attention_value;
  created_at : float;
  updated_at : float;
}

(** AtomSpace-like container for hypergraph elements *)
type atomspace = {
  nodes : (uuid, node) Hashtbl.t;
  links : (uuid, link) Hashtbl.t;
  tensors : (uuid, tensor) Hashtbl.t;
  next_id : uuid ref;
}

(** Create a new empty atomspace *)
val create_atomspace : unit -> atomspace

(** CRUD operations for nodes *)
val add_node : atomspace -> string -> node
val get_node : atomspace -> uuid -> node option
val update_node : atomspace -> uuid -> node -> unit
val delete_node : atomspace -> uuid -> bool

(** CRUD operations for links *)
val add_link : atomspace -> uuid list -> uuid list -> string -> link
val get_link : atomspace -> uuid -> link option
val update_link : atomspace -> uuid -> link -> unit
val delete_link : atomspace -> uuid -> bool

(** CRUD operations for tensors *)
val add_tensor : atomspace -> int array -> float array -> int list -> tensor
val get_tensor : atomspace -> uuid -> tensor option
val update_tensor : atomspace -> uuid -> tensor -> unit
val delete_tensor : atomspace -> uuid -> bool

(** Query operations *)
val find_nodes_by_name : atomspace -> string -> node list
val find_links_by_type : atomspace -> string -> link list
val get_connected_nodes : atomspace -> uuid -> uuid list

(** Attention allocation *)
val normalize_attention : atomspace -> unit
val decay_attention : atomspace -> float -> unit
val get_top_sti_elements : atomspace -> int -> (uuid * float) list
