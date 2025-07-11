(* Meta-cognition introspection capabilities *)

open Hypergraph
open Taskscheduler
open Ecan
open Reasoning

(** Helper function to take first n elements from list *)
let rec take n lst =
  if n <= 0 then []
  else
    match lst with
    | [] -> []
    | h :: t -> h :: take (n - 1) t

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

(** Get current timestamp *)
let current_time () = Unix.gettimeofday ()

(** Create default meta-cognitive state *)
let default_metacognitive_state () =
  {
    current_focus = [];
    active_strategies = ["default"];
    performance_metrics = Hashtbl.create 16;
    cognitive_load = 0.0;
    confidence_level = 0.5;
    last_introspection = current_time ();
    introspection_frequency = 60.0; (* 1 minute *)
  }

(** Create meta-cognitive engine *)
let create_metacognitive_engine atomspace task_scheduler ecan_allocator pln_engine =
  {
    atomspace;
    task_scheduler;
    ecan_allocator;
    pln_engine;
    state = ref (default_metacognitive_state ());
    introspection_history = ref [];
  }

(** Calculate cognitive load *)
let calculate_cognitive_load engine =
  let (pending, running, _, _, _) = get_task_statistics engine.task_scheduler in
  let task_load = (float_of_int (pending + running)) /. 100.0 in
  let (total_sti, _, _, node_count) = get_attention_statistics engine.ecan_allocator in
  let attention_load = total_sti /. (float_of_int node_count) in
  let inference_load = float_of_int (List.length (get_pln_inference_history engine.pln_engine)) /. 100.0 in

  (task_load +. attention_load +. inference_load) /. 3.0

(** Calculate confidence level *)
let calculate_confidence_level engine =
  let (_, _, completed, failed, _) = get_task_statistics engine.task_scheduler in
  let total_tasks = completed + failed in
  if total_tasks > 0 then
    float_of_int completed /. float_of_int total_tasks
  else
    0.5

(** Perform self-monitoring *)
let perform_self_monitoring engine =
  let current_state = !(engine.state) in
  let metrics = Hashtbl.create 8 in

  Hashtbl.add metrics "cognitive_load" (calculate_cognitive_load engine);
  Hashtbl.add metrics "confidence_level" (calculate_confidence_level engine);
  Hashtbl.add metrics "active_nodes" (float_of_int (Hashtbl.length engine.atomspace.nodes));
  Hashtbl.add metrics "active_tasks" (let (_, running, _, _, _) = get_task_statistics engine.task_scheduler in float_of_int running);

  let insights = [
    "Monitoring cognitive processes";
    "Tracking system performance";
    "Observing attention allocation";
  ] in

  let recommendations = [
    "Continue monitoring";
    "Adjust attention if needed";
    "Optimize task scheduling";
  ] in

  {
    process = SelfMonitoring;
    insights;
    recommendations;
    metrics;
    timestamp = current_time ();
  }

(** Perform self-evaluation *)
let perform_self_evaluation engine =
  let metrics = Hashtbl.create 8 in
  let (pending, running, completed, failed, cancelled) = get_task_statistics engine.task_scheduler in

  Hashtbl.add metrics "task_success_rate" (if (completed + failed) > 0 then float_of_int completed /. float_of_int (completed + failed) else 0.0);
  Hashtbl.add metrics "task_completion_efficiency" (if (completed + failed + cancelled) > 0 then float_of_int completed /. float_of_int (completed + failed + cancelled) else 0.0);

  let insights = [
    "Evaluating task performance";
    "Analyzing success patterns";
    "Identifying improvement areas";
  ] in

  let recommendations = [
    "Focus on high-success strategies";
    "Optimize failed task patterns";
    "Improve task scheduling";
  ] in

  {
    process = SelfEvaluation;
    insights;
    recommendations;
    metrics;
    timestamp = current_time ();
  }

(** Perform self-reflection *)
let perform_self_reflection engine =
  let metrics = Hashtbl.create 8 in
  let inference_history = get_pln_inference_history engine.pln_engine in

  Hashtbl.add metrics "inference_count" (float_of_int (List.length inference_history));
  Hashtbl.add metrics "average_inference_confidence" (
    if List.length inference_history > 0 then
      let total_confidence = List.fold_left (fun acc inf -> acc +. inf.truth_value.confidence) 0.0 inference_history in
      total_confidence /. float_of_int (List.length inference_history)
    else 0.0
  );

  let insights = [
    "Reflecting on reasoning patterns";
    "Analyzing inference quality";
    "Identifying cognitive biases";
  ] in

  let recommendations = [
    "Improve inference accuracy";
    "Diversify reasoning strategies";
    "Reduce cognitive biases";
  ] in

  {
    process = SelfReflection;
    insights;
    recommendations;
    metrics;
    timestamp = current_time ();
  }

(** Select cognitive strategy *)
let select_cognitive_strategy engine current_context =
  let cognitive_load = calculate_cognitive_load engine in
  let confidence_level = calculate_confidence_level engine in

  if cognitive_load > 0.8 then
    "reduce_complexity"
  else if confidence_level < 0.3 then
    "increase_exploration"
  else if confidence_level > 0.8 then
    "exploit_knowledge"
  else
    "balanced_approach"

(** Manage cognitive goals *)
let manage_cognitive_goals engine current_goals =
  let cognitive_load = calculate_cognitive_load engine in
  let (pending, running, _, _, _) = get_task_statistics engine.task_scheduler in

  if cognitive_load > 0.9 then
    (* Reduce goals when overloaded *)
    take (max 1 (List.length current_goals / 2)) current_goals
  else if cognitive_load < 0.3 && pending < 2 then
    (* Add more goals when underutilized *)
    current_goals @ ["explore_new_domains"; "optimize_performance"]
  else
    current_goals

(** Control attention allocation *)
let control_attention_allocation engine =
  let (total_sti, _, _, _) = get_attention_statistics engine.ecan_allocator in
  if total_sti > 1000.0 then
    redistribute_attention_budget engine.ecan_allocator
  else
    decay_attention_values engine.ecan_allocator

(** Control memory usage *)
let control_memory_usage engine =
  let node_count = Hashtbl.length engine.atomspace.nodes in
  if node_count > 10000 then
    perform_forgetting engine.ecan_allocator

(** Get current meta-cognitive state *)
let get_metacognitive_state engine =
  !(engine.state)

(** Update meta-cognitive state *)
let update_metacognitive_state engine new_state =
  engine.state := new_state

(** Get introspection history *)
let get_introspection_history engine =
  !(engine.introspection_history)

(** Trigger introspection cycle *)
let trigger_introspection_cycle engine =
  let current_time = current_time () in
  let current_state = !(engine.state) in

  if current_time -. current_state.last_introspection >= current_state.introspection_frequency then
    let monitoring_result = perform_self_monitoring engine in
    let evaluation_result = perform_self_evaluation engine in
    let reflection_result = perform_self_reflection engine in

    engine.introspection_history := monitoring_result :: evaluation_result :: reflection_result :: !(engine.introspection_history);

    let updated_state = {
      current_state with
      cognitive_load = calculate_cognitive_load engine;
      confidence_level = calculate_confidence_level engine;
      last_introspection = current_time;
    } in

    engine.state := updated_state;

    control_attention_allocation engine;
    control_memory_usage engine

(** Analyze performance trends *)
let analyze_performance_trends engine =
  let history = !(engine.introspection_history) in
  let recent_history = take (min 10 (List.length history)) history in

  let trends = ref [] in
  List.iter (fun result ->
    Hashtbl.iter (fun key value ->
      trends := (key, value) :: !trends
    ) result.metrics
  ) recent_history;

  !trends

(** Generate meta-cognitive insights *)
let generate_metacognitive_insights engine =
  let trends = analyze_performance_trends engine in
  let insights = ref [] in

  List.iter (fun (metric, value) ->
    match metric with
    | "cognitive_load" when value > 0.8 -> insights := "High cognitive load detected - consider reducing complexity" :: !insights
    | "confidence_level" when value < 0.3 -> insights := "Low confidence - increase exploration and validation" :: !insights
    | "task_success_rate" when value < 0.5 -> insights := "Low task success rate - review and optimize strategies" :: !insights
    | _ -> ()
  ) trends;

  !insights

(** Optimize cognitive processes *)
let optimize_cognitive_processes engine =
  let insights = generate_metacognitive_insights engine in
  let current_state = !(engine.state) in

  (* Apply optimizations based on insights *)
  List.iter (fun insight ->
    if String.contains insight "complexity" then
      schedule_tasks engine.task_scheduler
    else if String.contains insight "exploration" then
      let new_strategies = "exploratory" :: current_state.active_strategies in
      let updated_state = { current_state with active_strategies = new_strategies } in
      engine.state := updated_state
  ) insights
