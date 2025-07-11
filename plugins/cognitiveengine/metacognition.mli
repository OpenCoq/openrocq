(* Meta-cognition introspection capabilities *)

open Hypergraph
open Taskscheduler
open Ecan
open Reasoning

(** Meta-cognitive process types *)
type metacognitive_process =
  | SelfMonitoring
  | SelfEvaluation
  | SelfReflection
  | StrategySelection
  | GoalManagement
  | AttentionControl
  | MemoryControl

(** Meta-cognitive state *)
type metacognitive_state = {
  current_focus : uuid list;
  active_strategies : string list;
  performance_metrics : (string, float) Hashtbl.t;
  cognitive_load : float;
  confidence_level : float;
  last_introspection : float;
  introspection_frequency : float;
}

(** Introspection result *)
type introspection_result = {
  process : metacognitive_process;
  insights : string list;
  recommendations : string list;
  metrics : (string, float) Hashtbl.t;
  timestamp : float;
}

(** Meta-cognitive engine *)
type metacognitive_engine = {
  atomspace : atomspace;
  task_scheduler : task_scheduler;
  ecan_allocator : ecan_allocator;
  pln_engine : pln_engine;
  state : metacognitive_state ref;
  introspection_history : introspection_result list ref;
}

(** Create meta-cognitive engine *)
val create_metacognitive_engine : atomspace -> task_scheduler -> ecan_allocator -> pln_engine -> metacognitive_engine

(** Perform self-monitoring *)
val perform_self_monitoring : metacognitive_engine -> introspection_result

(** Perform self-evaluation *)
val perform_self_evaluation : metacognitive_engine -> introspection_result

(** Perform self-reflection *)
val perform_self_reflection : metacognitive_engine -> introspection_result

(** Select cognitive strategy *)
val select_cognitive_strategy : metacognitive_engine -> string -> string

(** Manage cognitive goals *)
val manage_cognitive_goals : metacognitive_engine -> string list -> string list

(** Control attention allocation *)
val control_attention_allocation : metacognitive_engine -> unit

(** Control memory usage *)
val control_memory_usage : metacognitive_engine -> unit

(** Get current meta-cognitive state *)
val get_metacognitive_state : metacognitive_engine -> metacognitive_state

(** Update meta-cognitive state *)
val update_metacognitive_state : metacognitive_engine -> metacognitive_state -> unit

(** Get introspection history *)
val get_introspection_history : metacognitive_engine -> introspection_result list

(** Calculate cognitive load *)
val calculate_cognitive_load : metacognitive_engine -> float

(** Calculate confidence level *)
val calculate_confidence_level : metacognitive_engine -> float

(** Trigger introspection cycle *)
val trigger_introspection_cycle : metacognitive_engine -> unit

(** Analyze performance trends *)
val analyze_performance_trends : metacognitive_engine -> (string * float) list

(** Generate meta-cognitive insights *)
val generate_metacognitive_insights : metacognitive_engine -> string list

(** Optimize cognitive processes *)
val optimize_cognitive_processes : metacognitive_engine -> unit
