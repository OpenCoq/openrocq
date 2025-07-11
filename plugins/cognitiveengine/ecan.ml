(* Economic Attention Network (ECAN) module *)

open Hypergraph

(** Helper function to take first n elements from list *)
let rec take n lst =
  if n <= 0 then []
  else
    match lst with
    | [] -> []
    | h :: t -> h :: take (n - 1) t

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
let default_ecan_config = {
  min_sti = 0.0;
  max_sti = 1.0;
  sti_decay_rate = 0.01;
  lti_decay_rate = 0.005;
  vlti_decay_rate = 0.001;
  forgetting_threshold = 0.1;
  attention_budget = 100.0;
  spreading_factor = 0.2;
}

(** Create ECAN allocator *)
let create_ecan_allocator atomspace config =
  {
    config;
    atomspace;
    attention_events = ref [];
    current_budget = ref config.attention_budget;
  }

(** Get current timestamp *)
let current_time () = Unix.gettimeofday ()

(** Calculate importance score *)
let calculate_importance_score attention =
  attention.sti *. 0.5 +. attention.lti *. 0.3 +. attention.vlti *. 0.2

(** Update attention values based on usage *)
let update_attention_on_access allocator node_id boost_amount =
  match get_node allocator.atomspace node_id with
  | Some node ->
    let new_sti = min allocator.config.max_sti (node.attention.sti +. boost_amount) in
    let new_attention = { node.attention with sti = new_sti } in
    let updated_node = { node with attention = new_attention } in
    update_node allocator.atomspace node_id updated_node;

    (* Record attention event *)
    let event = {
      source = node_id;
      target = node_id;
      amount = boost_amount;
      event_type = "access_boost";
      timestamp = current_time ();
    } in
    allocator.attention_events := event :: !(allocator.attention_events)
  | None -> ()

(** Spread attention from source to connected nodes *)
let spread_attention allocator source_id spread_amount =
  let connected_nodes = get_connected_nodes allocator.atomspace source_id in
  let num_connected = List.length connected_nodes in

  if num_connected > 0 then
    let amount_per_node = spread_amount *. allocator.config.spreading_factor /. (float_of_int num_connected) in

    List.iter (fun target_id ->
      match get_node allocator.atomspace target_id with
      | Some target_node ->
        let new_sti = min allocator.config.max_sti (target_node.attention.sti +. amount_per_node) in
        let new_attention = { target_node.attention with sti = new_sti } in
        let updated_node = { target_node with attention = new_attention } in
        update_node allocator.atomspace target_id updated_node;

        (* Record attention event *)
        let event = {
          source = source_id;
          target = target_id;
          amount = amount_per_node;
          event_type = "spread";
          timestamp = current_time ();
        } in
        allocator.attention_events := event :: !(allocator.attention_events)
      | None -> ()
    ) connected_nodes

(** Perform attention decay *)
let decay_attention_values allocator =
  Hashtbl.iter (fun id (node : Hypergraph.node) ->
    let decayed_sti = max allocator.config.min_sti (node.attention.sti *. (1.0 -. allocator.config.sti_decay_rate)) in
    let decayed_lti = max allocator.config.min_sti (node.attention.lti *. (1.0 -. allocator.config.lti_decay_rate)) in
    let decayed_vlti = max allocator.config.min_sti (node.attention.vlti *. (1.0 -. allocator.config.vlti_decay_rate)) in

    let new_attention = {
      sti = decayed_sti;
      lti = decayed_lti;
      vlti = decayed_vlti;
    } in

    let updated_node = { node with attention = new_attention } in
    Hypergraph.update_node allocator.atomspace id updated_node
  ) allocator.atomspace.nodes

(** Get elements ready for forgetting *)
let get_forgettable_elements allocator =
  let forgettable = ref [] in
  Hashtbl.iter (fun id (node : Hypergraph.node) ->
    let importance = calculate_importance_score node.attention in
    if importance < allocator.config.forgetting_threshold then
      forgettable := id :: !forgettable
  ) allocator.atomspace.nodes;
  !forgettable

(** Perform forgetting of low-attention elements *)
let perform_forgetting allocator =
  let forgettable = get_forgettable_elements allocator in
  List.iter (fun id ->
    ignore (delete_node allocator.atomspace id)
  ) forgettable

(** Get attention focus (high STI elements) *)
let get_attention_focus allocator n =
  let elements = ref [] in
  Hashtbl.iter (fun id (node : Hypergraph.node) ->
    elements := (id, node.attention.sti) :: !elements
  ) allocator.atomspace.nodes;

  let sorted = List.sort (fun (_, a) (_, b) -> Float.compare b a) !elements in
  let top_n = take n sorted in
  List.map fst top_n

(** Redistribute attention budget *)
let redistribute_attention_budget allocator =
  let total_attention = ref 0.0 in
  Hashtbl.iter (fun _ (node : Hypergraph.node) ->
    total_attention := !total_attention +. node.attention.sti
  ) allocator.atomspace.nodes;

  if !total_attention > 0.0 then
    let scale_factor = allocator.config.attention_budget /. !total_attention in
    Hashtbl.iter (fun id (node : Hypergraph.node) ->
      let scaled_sti = node.attention.sti *. scale_factor in
      let new_attention = { node.attention with sti = scaled_sti } in
      let updated_node = { node with attention = new_attention } in
      Hypergraph.update_node allocator.atomspace id updated_node
    ) allocator.atomspace.nodes

(** Get attention statistics *)
let get_attention_statistics allocator =
  let total_sti = ref 0.0 in
  let total_lti = ref 0.0 in
  let total_vlti = ref 0.0 in
  let node_count = ref 0 in

  Hashtbl.iter (fun _ (node : Hypergraph.node) ->
    total_sti := !total_sti +. node.attention.sti;
    total_lti := !total_lti +. node.attention.lti;
    total_vlti := !total_vlti +. node.attention.vlti;
    incr node_count
  ) allocator.atomspace.nodes;

  (!total_sti, !total_lti, !total_vlti, !node_count)

(** Process attention events *)
let process_attention_events allocator =
  (* Clean up old events (keep only recent ones) *)
  let current_time = current_time () in
  let cutoff_time = current_time -. 3600.0 in (* Keep events from last hour *)

  let recent_events = List.filter (fun event ->
    event.timestamp >= cutoff_time
  ) !(allocator.attention_events) in

  allocator.attention_events := recent_events
