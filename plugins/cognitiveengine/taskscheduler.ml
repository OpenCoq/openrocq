(* Task scheduling module for cognitive engine *)

(** Task priorities *)
type priority = Low | Medium | High | Critical

(** Task states *)
type task_state = Pending | Running | Completed | Failed | Cancelled

(** Cognitive task definition *)
type cognitive_task = {
  id : int;
  name : string;
  priority : priority;
  state : task_state;
  description : string;
  created_at : float;
  started_at : float option;
  completed_at : float option;
  dependencies : int list;
  estimated_duration : float;
  actual_duration : float option;
  resource_requirements : string list;
}

(** Task scheduler *)
type task_scheduler = {
  tasks : (int, cognitive_task) Hashtbl.t;
  ready_queue : int Queue.t;
  running_tasks : int list ref;
  completed_tasks : int list ref;
  next_task_id : int ref;
  max_concurrent_tasks : int;
}

(** Get current timestamp *)
let current_time () = Unix.gettimeofday ()

(** Create a new task scheduler *)
let create_scheduler max_concurrent =
  {
    tasks = Hashtbl.create 256;
    ready_queue = Queue.create ();
    running_tasks = ref [];
    completed_tasks = ref [];
    next_task_id = ref 1;
    max_concurrent_tasks = max_concurrent;
  }

(** Generate next task ID *)
let next_task_id scheduler =
  let id = !(scheduler.next_task_id) in
  scheduler.next_task_id := id + 1;
  id

(** Add a new task to the scheduler *)
let add_task scheduler name priority description estimated_duration resource_requirements dependencies =
  let id = next_task_id scheduler in
  let task = {
    id;
    name;
    priority;
    state = Pending;
    description;
    created_at = current_time ();
    started_at = None;
    completed_at = None;
    dependencies;
    estimated_duration;
    actual_duration = None;
    resource_requirements;
  } in
  Hashtbl.add scheduler.tasks id task;
  task

(** Get a task by ID *)
let get_task scheduler id =
  Hashtbl.find_opt scheduler.tasks id

(** Update task state *)
let update_task_state scheduler id new_state =
  match Hashtbl.find_opt scheduler.tasks id with
  | Some task ->
    let updated_task =
      let now = current_time () in
      match new_state with
      | Running -> { task with state = new_state; started_at = Some now }
      | Completed | Failed | Cancelled ->
        let actual_duration = match task.started_at with
          | Some start_time -> Some (now -. start_time)
          | None -> None
        in
        { task with state = new_state; completed_at = Some now; actual_duration }
      | _ -> { task with state = new_state }
    in
    Hashtbl.replace scheduler.tasks id updated_task;
    (* Update running and completed task lists *)
    begin match new_state with
    | Running ->
      scheduler.running_tasks := id :: !(scheduler.running_tasks)
    | Completed | Failed | Cancelled ->
      scheduler.running_tasks := List.filter (fun x -> x <> id) !(scheduler.running_tasks);
      scheduler.completed_tasks := id :: !(scheduler.completed_tasks)
    | _ -> ()
    end
  | None -> ()

(** Check if task dependencies are satisfied *)
let dependencies_satisfied scheduler task_id =
  match Hashtbl.find_opt scheduler.tasks task_id with
  | Some task ->
    List.for_all (fun dep_id ->
      match Hashtbl.find_opt scheduler.tasks dep_id with
      | Some dep_task -> dep_task.state = Completed
      | None -> false
    ) task.dependencies
  | None -> false

(** Priority to numeric value for comparison *)
let priority_to_int = function
  | Low -> 1
  | Medium -> 2
  | High -> 3
  | Critical -> 4

(** Get next ready task *)
let get_next_ready_task scheduler =
  let ready_tasks = ref [] in
  Hashtbl.iter (fun _ task ->
    if task.state = Pending && dependencies_satisfied scheduler task.id then
      ready_tasks := task :: !ready_tasks
  ) scheduler.tasks;

  (* Sort by priority (highest first) *)
  let sorted_tasks = List.sort (fun a b ->
    compare (priority_to_int b.priority) (priority_to_int a.priority)
  ) !ready_tasks in

  match sorted_tasks with
  | task :: _ -> Some task
  | [] -> None

(** Schedule and execute ready tasks *)
let schedule_tasks scheduler =
  let current_running = List.length !(scheduler.running_tasks) in
  let available_slots = scheduler.max_concurrent_tasks - current_running in

  let rec schedule_next count =
    if count < available_slots then
      match get_next_ready_task scheduler with
      | Some task ->
        update_task_state scheduler task.id Running;
        schedule_next (count + 1)
      | None -> ()
  in
  schedule_next 0

(** Get tasks by state *)
let get_tasks_by_state scheduler state =
  let result = ref [] in
  Hashtbl.iter (fun _ task ->
    if task.state = state then
      result := task :: !result
  ) scheduler.tasks;
  !result

(** Get task statistics *)
let get_task_statistics scheduler =
  let pending = List.length (get_tasks_by_state scheduler Pending) in
  let running = List.length (get_tasks_by_state scheduler Running) in
  let completed = List.length (get_tasks_by_state scheduler Completed) in
  let failed = List.length (get_tasks_by_state scheduler Failed) in
  let cancelled = List.length (get_tasks_by_state scheduler Cancelled) in
  (pending, running, completed, failed, cancelled)

(** Cancel a task *)
let cancel_task scheduler id =
  match Hashtbl.find_opt scheduler.tasks id with
  | Some task when task.state = Pending || task.state = Running ->
    update_task_state scheduler id Cancelled;
    true
  | _ -> false

(** Get task execution time *)
let get_task_execution_time task =
  task.actual_duration
