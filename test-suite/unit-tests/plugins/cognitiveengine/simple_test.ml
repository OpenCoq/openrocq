(* Simple unit tests for cognitive engine plugin without external dependencies *)

open Cognitiveengine_plugin.Hypergraph
open Cognitiveengine_plugin.Taskscheduler
open Cognitiveengine_plugin.Ecan
open Cognitiveengine_plugin.Cognitiveengine

let assert_equal expected actual msg =
  if expected <> actual then
    failwith (Printf.sprintf "Assertion failed: %s. Expected %s but got %s" 
      msg (string_of_float expected) (string_of_float actual))

let assert_bool condition msg =
  if not condition then
    failwith (Printf.sprintf "Assertion failed: %s" msg)

let test_atomspace_creation () =
  let atomspace = create_atomspace () in
  assert_equal 0.0 (float_of_int (Hashtbl.length atomspace.nodes)) "AtomSpace should start with 0 nodes";
  assert_equal 0.0 (float_of_int (Hashtbl.length atomspace.links)) "AtomSpace should start with 0 links";
  assert_equal 0.0 (float_of_int (Hashtbl.length atomspace.tensors)) "AtomSpace should start with 0 tensors";
  Printf.printf "✓ AtomSpace creation test passed\n"

let test_node_operations () =
  let atomspace = create_atomspace () in
  let node = add_node atomspace "test_node" in
  assert_bool (node.name = "test_node") "Node name should be 'test_node'";
  assert_equal 1.0 (float_of_int (Hashtbl.length atomspace.nodes)) "Should have 1 node after adding";
  
  let retrieved_node = get_node atomspace node.id in
  assert_bool (retrieved_node <> None) "Should be able to retrieve node";
  
  let updated_node = { node with name = "updated_node" } in
  update_node atomspace node.id updated_node;
  
  let retrieved_updated = get_node atomspace node.id in
  let updated_name = match retrieved_updated with Some n -> n.name | None -> "" in
  assert_bool (updated_name = "updated_node") "Node name should be updated";
  
  let deleted = delete_node atomspace node.id in
  assert_bool deleted "Node deletion should succeed";
  assert_equal 0.0 (float_of_int (Hashtbl.length atomspace.nodes)) "Should have 0 nodes after deletion";
  Printf.printf "✓ Node operations test passed\n"

let test_link_operations () =
  let atomspace = create_atomspace () in
  let node1 = add_node atomspace "node1" in
  let node2 = add_node atomspace "node2" in
  let link = add_link atomspace [node1.id] [node2.id] "test_link" in
  
  assert_bool (link.link_type = "test_link") "Link type should be 'test_link'";
  assert_equal 1.0 (float_of_int (Hashtbl.length atomspace.links)) "Should have 1 link after adding";
  
  let retrieved_link = get_link atomspace link.id in
  assert_bool (retrieved_link <> None) "Should be able to retrieve link";
  
  let deleted = delete_link atomspace link.id in
  assert_bool deleted "Link deletion should succeed";
  assert_equal 0.0 (float_of_int (Hashtbl.length atomspace.links)) "Should have 0 links after deletion";
  Printf.printf "✓ Link operations test passed\n"

let test_task_scheduler () =
  let scheduler = create_scheduler 4 in
  assert_equal 4.0 (float_of_int scheduler.max_concurrent_tasks) "Scheduler should allow 4 concurrent tasks";
  assert_equal 0.0 (float_of_int (Hashtbl.length scheduler.tasks)) "Scheduler should start with 0 tasks";
  
  let task = add_task scheduler "test_task" High "Test description" 10.0 [] [] in
  assert_bool (task.name = "test_task") "Task name should be 'test_task'";
  assert_bool (task.priority = High) "Task priority should be High";
  assert_bool (task.state = Pending) "Task state should be Pending";
  assert_equal 1.0 (float_of_int (Hashtbl.length scheduler.tasks)) "Should have 1 task after adding";
  Printf.printf "✓ Task scheduler test passed\n"

let test_ecan () =
  let atomspace = create_atomspace () in
  let allocator = create_ecan_allocator atomspace default_ecan_config in
  assert_bool (allocator.atomspace == atomspace) "ECAN should reference the correct AtomSpace";
  assert_equal default_ecan_config.attention_budget !(allocator.current_budget) "Budget should match config";
  
  let node = add_node atomspace "test_node" in
  let initial_sti = node.attention.sti in
  update_attention_on_access allocator node.id 0.1;
  
  let updated_node = get_node atomspace node.id in
  let final_sti = match updated_node with Some n -> n.attention.sti | None -> 0.0 in
  assert_bool (final_sti > initial_sti) "STI should increase after access";
  Printf.printf "✓ ECAN test passed\n"

let test_cognitive_engine () =
  let engine = create_cognitive_engine () in
  assert_equal 0.0 (float_of_int (Hashtbl.length engine.atomspace.nodes)) "Engine should start with 0 nodes";
  assert_equal 0.0 (float_of_int (Hashtbl.length engine.atomspace.links)) "Engine should start with 0 links";
  
  let concept_id = add_concept engine "test_concept" in
  assert_bool (concept_id > 0) "Concept ID should be positive";
  
  let concept_ids = query_concepts engine "test_concept" in
  assert_equal 1.0 (float_of_int (List.length concept_ids)) "Should find 1 concept";
  assert_bool ((List.hd concept_ids) = concept_id) "Should return the correct concept ID";
  
  let concept_id2 = add_concept engine "test_concept2" in
  let relation_id = add_relationship engine concept_id concept_id2 "test_relation" in
  assert_bool (relation_id > 0) "Relation ID should be positive";
  Printf.printf "✓ Cognitive engine test passed\n"

let test_scheme_export () =
  let engine = create_cognitive_engine () in
  let concept_id = add_concept engine "test_concept" in
  let concept_id2 = add_concept engine "test_concept2" in
  let _ = add_relationship engine concept_id concept_id2 "test_relation" in
  
  let scheme_code = export_to_scheme engine in
  assert_bool (String.length scheme_code > 0) "Exported scheme should not be empty";
  Printf.printf "✓ Scheme export test passed\n"

let run_all_tests () =
  Printf.printf "Running Cognitive Engine Tests...\n\n";
  
  try
    test_atomspace_creation ();
    test_node_operations ();
    test_link_operations ();
    test_task_scheduler ();
    test_ecan ();
    test_cognitive_engine ();
    test_scheme_export ();
    
    Printf.printf "\n🎉 All tests passed! Cognitive Engine is working correctly.\n"
  with
  | Failure msg -> 
    Printf.printf "\n❌ Test failed: %s\n" msg;
    exit 1
  | e -> 
    Printf.printf "\n💥 Unexpected error: %s\n" (Printexc.to_string e);
    exit 1

let () = run_all_tests ()