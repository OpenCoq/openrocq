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

(** Create a new task scheduler *)
val create_scheduler : int -> task_scheduler

(** Add a new task to the scheduler *)
val add_task : task_scheduler -> string -> priority -> string -> float -> string list -> int list -> cognitive_task

(** Get a task by ID *)
val get_task : task_scheduler -> int -> cognitive_task option

(** Update task state *)
val update_task_state : task_scheduler -> int -> task_state -> unit

(** Get next ready task *)
val get_next_ready_task : task_scheduler -> cognitive_task option

(** Schedule and execute ready tasks *)
val schedule_tasks : task_scheduler -> unit

(** Get tasks by state *)
val get_tasks_by_state : task_scheduler -> task_state -> cognitive_task list

(** Get task statistics *)
val get_task_statistics : task_scheduler -> (int * int * int * int * int)

(** Check if task dependencies are satisfied *)
val dependencies_satisfied : task_scheduler -> int -> bool

(** Cancel a task *)
val cancel_task : task_scheduler -> int -> bool

(** Get task execution time *)
val get_task_execution_time : cognitive_task -> float option
