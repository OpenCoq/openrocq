(* Main cognitive engine plugin interface *)

open Hypergraph
open Taskscheduler
open Ecan
open Reasoning
open Metacognition

(** Main cognitive engine *)
type cognitive_engine = {
  atomspace : atomspace;
  task_scheduler : task_scheduler;
  ecan_allocator : ecan_allocator;
  pln_engine : pln_engine;
  moses_engine : moses_engine option;
  metacognitive_engine : metacognitive_engine;
}

(** Create a new cognitive engine *)
val create_cognitive_engine : unit -> cognitive_engine

(** Add a concept to the atomspace *)
val add_concept : cognitive_engine -> string -> uuid

(** Add a relationship between concepts *)
val add_relationship : cognitive_engine -> uuid -> uuid -> string -> uuid

(** Query concepts by name *)
val query_concepts : cognitive_engine -> string -> uuid list

(** Perform reasoning inference *)
val perform_reasoning : cognitive_engine -> pln_rule -> uuid list -> pln_inference option

(** Schedule a cognitive task *)
val schedule_cognitive_task : cognitive_engine -> string -> priority -> string -> float -> cognitive_task

(** Update attention for concept *)
val update_concept_attention : cognitive_engine -> uuid -> float -> unit

(** Get attention focus *)
val get_cognitive_focus : cognitive_engine -> int -> uuid list

(** Trigger meta-cognitive cycle *)
val trigger_metacognitive_cycle : cognitive_engine -> unit

(** Get engine statistics *)
val get_engine_statistics : cognitive_engine -> (string, float) Hashtbl.t

(** Export to Scheme format *)
val export_to_scheme : cognitive_engine -> string

(** Import from Scheme format *)
val import_from_scheme : cognitive_engine -> string -> unit

(** Get engine status *)
val get_engine_status : cognitive_engine -> string

(** Shutdown engine *)
val shutdown_engine : cognitive_engine -> unit
