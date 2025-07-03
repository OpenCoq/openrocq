(* Unit tests for cognitive engine plugin *)

open OUnit2
open Cognitiveengine_plugin.Hypergraph
open Cognitiveengine_plugin.Taskscheduler
open Cognitiveengine_plugin.Ecan
open Cognitiveengine_plugin.Reasoning
open Cognitiveengine_plugin.Cognitiveengine

(* Test AtomSpace operations *)
let test_atomspace_creation _ =
  let atomspace = create_atomspace () in
  assert_equal 0 (Hashtbl.length atomspace.nodes);
  assert_equal 0 (Hashtbl.length atomspace.links);
  assert_equal 0 (Hashtbl.length atomspace.tensors)

let test_node_operations _ =
  let atomspace = create_atomspace () in
  let node = add_node atomspace "test_node" in
  assert_equal "test_node" node.name;
  assert_equal 1 (Hashtbl.length atomspace.nodes);

  let retrieved_node = get_node atomspace node.id in
  assert_equal (Some node) retrieved_node;

  let updated_node = { node with name = "updated_node" } in
  update_node atomspace node.id updated_node;

  let retrieved_updated = get_node atomspace node.id in
  assert_equal "updated_node" (match retrieved_updated with Some n -> n.name | None -> "");

  let deleted = delete_node atomspace node.id in
  assert_equal true deleted;
  assert_equal 0 (Hashtbl.length atomspace.nodes)

let test_link_operations _ =
  let atomspace = create_atomspace () in
  let node1 = add_node atomspace "node1" in
  let node2 = add_node atomspace "node2" in
  let link = add_link atomspace [node1.id] [node2.id] "test_link" in

  assert_equal "test_link" link.link_type;
  assert_equal 1 (Hashtbl.length atomspace.links);

  let retrieved_link = get_link atomspace link.id in
  assert_equal (Some link) retrieved_link;

  let deleted = delete_link atomspace link.id in
  assert_equal true deleted;
  assert_equal 0 (Hashtbl.length atomspace.links)

(* Test Task Scheduler *)
let test_task_scheduler_creation _ =
  let scheduler = create_scheduler 4 in
  assert_equal 4 scheduler.max_concurrent_tasks;
  assert_equal 0 (Hashtbl.length scheduler.tasks)

let test_task_operations _ =
  let scheduler = create_scheduler 2 in
  let task = add_task scheduler "test_task" High "Test description" 10.0 [] [] in

  assert_equal "test_task" task.name;
  assert_equal High task.priority;
  assert_equal Pending task.state;
  assert_equal 1 (Hashtbl.length scheduler.tasks);

  update_task_state scheduler task.id Running;
  let updated_task = get_task scheduler task.id in
  assert_equal Running (match updated_task with Some t -> t.state | None -> Failed);

  let (pending, running, completed, failed, cancelled) = get_task_statistics scheduler in
  assert_equal 0 pending;
  assert_equal 1 running;
  assert_equal 0 completed

(* Test ECAN *)
let test_ecan_creation _ =
  let atomspace = create_atomspace () in
  let allocator = create_ecan_allocator atomspace default_ecan_config in
  assert_equal atomspace allocator.atomspace;
  assert_equal default_ecan_config.attention_budget !(allocator.current_budget)

let test_attention_operations _ =
  let atomspace = create_atomspace () in
  let allocator = create_ecan_allocator atomspace default_ecan_config in
  let node = add_node atomspace "test_node" in

  let initial_sti = node.attention.sti in
  update_attention_on_access allocator node.id 0.1;

  let updated_node = get_node atomspace node.id in
  let final_sti = match updated_node with Some n -> n.attention.sti | None -> 0.0 in
  assert_bool "STI should increase" (final_sti > initial_sti)

(* Test PLN Reasoning *)
let test_pln_engine_creation _ =
  let atomspace = create_atomspace () in
  let engine = create_pln_engine atomspace in
  assert_equal atomspace engine.atomspace;
  assert_equal 0 (List.length !(engine.inference_history))

let test_pln_inference _ =
  let atomspace = create_atomspace () in
  let engine = create_pln_engine atomspace in
  let node1 = add_node atomspace "premise1" in
  let node2 = add_node atomspace "premise2" in

  let inference = perform_pln_inference engine DeductionRule [node1.id; node2.id] in
  assert_bool "Inference should succeed" (inference <> None);
  assert_equal 1 (List.length !(engine.inference_history))

(* Test Cognitive Engine *)
let test_cognitive_engine_creation _ =
  let engine = create_cognitive_engine () in
  assert_equal 0 (Hashtbl.length engine.atomspace.nodes);
  assert_equal 0 (Hashtbl.length engine.atomspace.links)

let test_cognitive_engine_operations _ =
  let engine = create_cognitive_engine () in
  let concept_id = add_concept engine "test_concept" in
  assert_bool "Concept ID should be positive" (concept_id > 0);

  let concept_ids = query_concepts engine "test_concept" in
  assert_equal 1 (List.length concept_ids);
  assert_equal concept_id (List.hd concept_ids);

  let concept_id2 = add_concept engine "test_concept2" in
  let relation_id = add_relationship engine concept_id concept_id2 "test_relation" in
  assert_bool "Relation ID should be positive" (relation_id > 0);

  let stats = get_engine_statistics engine in
  let node_count = Hashtbl.find stats "node_count" in
  assert_equal 2.0 node_count

let test_scheme_export _ =
  let engine = create_cognitive_engine () in
  let concept_id = add_concept engine "test_concept" in
  let concept_id2 = add_concept engine "test_concept2" in
  let relation_id = add_relationship engine concept_id concept_id2 "test_relation" in

  let scheme_code = export_to_scheme engine in
  assert_bool "Should contain nodes definition" (String.contains scheme_code "nodes");
  assert_bool "Should contain links definition" (String.contains scheme_code "links");
  assert_bool "Should contain test_concept" (String.contains scheme_code "test_concept")

(* Test Suite *)
let suite = "Cognitive Engine Tests" >::: [
  "test_atomspace_creation" >:: test_atomspace_creation;
  "test_node_operations" >:: test_node_operations;
  "test_link_operations" >:: test_link_operations;
  "test_task_scheduler_creation" >:: test_task_scheduler_creation;
  "test_task_operations" >:: test_task_operations;
  "test_ecan_creation" >:: test_ecan_creation;
  "test_attention_operations" >:: test_attention_operations;
  "test_pln_engine_creation" >:: test_pln_engine_creation;
  "test_pln_inference" >:: test_pln_inference;
  "test_cognitive_engine_creation" >:: test_cognitive_engine_creation;
  "test_cognitive_engine_operations" >:: test_cognitive_engine_operations;
  "test_scheme_export" >:: test_scheme_export;
]

let () = run_test_tt_main suite
