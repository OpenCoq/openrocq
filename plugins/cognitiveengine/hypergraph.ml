(* Core hypergraph data structures for cognitive engine *)

(** Helper function to take first n elements from list *)
let rec take n lst =
  if n <= 0 then []
  else
    match lst with
    | [] -> []
    | h :: t -> h :: take (n - 1) t

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
let create_atomspace () = {
  nodes = Hashtbl.create 1024;
  links = Hashtbl.create 1024;
  tensors = Hashtbl.create 256;
  next_id = ref 1;
}

(** Generate a new unique ID *)
let next_uuid atomspace =
  let id = !(atomspace.next_id) in
  atomspace.next_id := id + 1;
  id

(** Get current timestamp *)
let current_time () = Unix.gettimeofday ()

(** Default attention value *)
let default_attention = { sti = 0.5; lti = 0.5; vlti = 0.5 }

(** CRUD operations for nodes *)
let add_node atomspace name =
  let id = next_uuid atomspace in
  let now = current_time () in
  let node = {
    id;
    name;
    attention = default_attention;
    confidence = 1.0;
    created_at = now;
    updated_at = now;
  } in
  Hashtbl.add atomspace.nodes id node;
  node

let get_node atomspace id =
  Hashtbl.find_opt atomspace.nodes id

let update_node atomspace id node =
  let updated_node = { node with updated_at = current_time () } in
  Hashtbl.replace atomspace.nodes id updated_node

let delete_node atomspace id =
  match Hashtbl.find_opt atomspace.nodes id with
  | Some _ -> Hashtbl.remove atomspace.nodes id; true
  | None -> false

(** CRUD operations for links *)
let add_link atomspace source_nodes target_nodes link_type =
  let id = next_uuid atomspace in
  let now = current_time () in
  let link = {
    id;
    source_nodes;
    target_nodes;
    link_type;
    attention = default_attention;
    confidence = 1.0;
    created_at = now;
    updated_at = now;
  } in
  Hashtbl.add atomspace.links id link;
  link

let get_link atomspace id =
  Hashtbl.find_opt atomspace.links id

let update_link atomspace id link =
  let updated_link = { link with updated_at = current_time () } in
  Hashtbl.replace atomspace.links id updated_link

let delete_link atomspace id =
  match Hashtbl.find_opt atomspace.links id with
  | Some _ -> Hashtbl.remove atomspace.links id; true
  | None -> false

(** CRUD operations for tensors *)
let add_tensor atomspace dimensions data shape =
  let id = next_uuid atomspace in
  let now = current_time () in
  let tensor = {
    id;
    dimensions;
    data;
    shape;
    attention = default_attention;
    created_at = now;
    updated_at = now;
  } in
  Hashtbl.add atomspace.tensors id tensor;
  tensor

let get_tensor atomspace id =
  Hashtbl.find_opt atomspace.tensors id

let update_tensor atomspace id tensor =
  let updated_tensor = { tensor with updated_at = current_time () } in
  Hashtbl.replace atomspace.tensors id updated_tensor

let delete_tensor atomspace id =
  match Hashtbl.find_opt atomspace.tensors id with
  | Some _ -> Hashtbl.remove atomspace.tensors id; true
  | None -> false

(** Query operations *)
let find_nodes_by_name atomspace name =
  let result = ref [] in
  Hashtbl.iter (fun _ node ->
    if String.equal node.name name then
      result := node :: !result
  ) atomspace.nodes;
  !result

let find_links_by_type atomspace link_type =
  let result = ref [] in
  Hashtbl.iter (fun _ link ->
    if String.equal link.link_type link_type then
      result := link :: !result
  ) atomspace.links;
  !result

let get_connected_nodes atomspace node_id =
  let result = ref [] in
  Hashtbl.iter (fun _ link ->
    if List.mem node_id link.source_nodes then
      result := link.target_nodes @ !result
    else if List.mem node_id link.target_nodes then
      result := link.source_nodes @ !result
  ) atomspace.links;
  List.sort_uniq compare !result

(** Attention allocation *)
let normalize_attention atomspace =
  let total_sti = ref 0.0 in
  let total_lti = ref 0.0 in
  let total_vlti = ref 0.0 in

  (* Calculate totals *)
  Hashtbl.iter (fun _ node ->
    total_sti := !total_sti +. node.attention.sti;
    total_lti := !total_lti +. node.attention.lti;
    total_vlti := !total_vlti +. node.attention.vlti;
  ) atomspace.nodes;

  (* Normalize *)
  if !total_sti > 0.0 then
    Hashtbl.iter (fun id node ->
      let normalized_attention = {
        sti = node.attention.sti /. !total_sti;
        lti = node.attention.lti /. !total_lti;
        vlti = node.attention.vlti /. !total_vlti;
      } in
      let updated_node = { node with attention = normalized_attention } in
      update_node atomspace id updated_node
    ) atomspace.nodes

let decay_attention atomspace decay_rate =
  Hashtbl.iter (fun id node ->
    let decayed_attention = {
      sti = node.attention.sti *. (1.0 -. decay_rate);
      lti = node.attention.lti *. (1.0 -. decay_rate);
      vlti = node.attention.vlti *. (1.0 -. decay_rate);
    } in
    let updated_node = { node with attention = decayed_attention } in
    update_node atomspace id updated_node
  ) atomspace.nodes

let get_top_sti_elements atomspace n =
  let elements = ref [] in
  Hashtbl.iter (fun _ node ->
    elements := (node.id, node.attention.sti) :: !elements
  ) atomspace.nodes;
  let sorted = List.sort (fun (_, a) (_, b) -> Float.compare b a) !elements in
  take n sorted
