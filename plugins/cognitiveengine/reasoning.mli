(* Reasoning engine stubs for PLN and MOSES integration *)

open Hypergraph

(** Probabilistic Logic Network (PLN) rule types *)
type pln_rule =
  | DeductionRule
  | InductionRule
  | AbductionRule
  | ModusPonens
  | ModusTollens
  | Inheritance
  | Similarity

(** Truth values for PLN *)
type truth_value = {
  strength : float;
  confidence : float;
}

(** PLN inference result *)
type pln_inference = {
  conclusion : uuid;
  premises : uuid list;
  rule : pln_rule;
  truth_value : truth_value;
  inference_time : float;
}

(** MOSES (Meta-Optimizing Semantic Evolutionary Search) parameters *)
type moses_config = {
  population_size : int;
  generations : int;
  mutation_rate : float;
  crossover_rate : float;
  fitness_threshold : float;
}

(** MOSES individual (program representation) *)
type moses_individual = {
  id : uuid;
  program : string;
  fitness : float;
  complexity : int;
  generation : int;
}

(** MOSES population *)
type moses_population = {
  individuals : moses_individual list;
  generation : int;
  best_fitness : float;
  config : moses_config;
}

(** PLN reasoning engine *)
type pln_engine = {
  atomspace : atomspace;
  inference_history : pln_inference list ref;
  rule_weights : (pln_rule, float) Hashtbl.t;
}

(** MOSES optimization engine *)
type moses_engine = {
  atomspace : atomspace;
  population : moses_population ref;
  fitness_function : string -> float;
  config : moses_config;
}

(** Create PLN reasoning engine *)
val create_pln_engine : atomspace -> pln_engine

(** Create MOSES optimization engine *)
val create_moses_engine : atomspace -> moses_config -> (string -> float) -> moses_engine

(** Perform PLN inference *)
val perform_pln_inference : pln_engine -> pln_rule -> uuid list -> pln_inference option

(** Apply PLN rule to premises *)
val apply_pln_rule : pln_engine -> pln_rule -> uuid list -> truth_value option

(** Get PLN inference history *)
val get_pln_inference_history : pln_engine -> pln_inference list

(** Initialize MOSES population *)
val initialize_moses_population : moses_engine -> unit

(** Evolve MOSES population *)
val evolve_moses_population : moses_engine -> unit

(** Get best MOSES individual *)
val get_best_moses_individual : moses_engine -> moses_individual option

(** Evaluate MOSES individual *)
val evaluate_moses_individual : moses_engine -> moses_individual -> float

(** Create random MOSES individual *)
val create_random_moses_individual : moses_config -> int -> moses_individual

(** Mutate MOSES individual *)
val mutate_moses_individual : moses_individual -> float -> moses_individual

(** Crossover two MOSES individuals *)
val crossover_moses_individuals : moses_individual -> moses_individual -> moses_individual * moses_individual

(** Default truth value *)
val default_truth_value : truth_value

(** Combine truth values *)
val combine_truth_values : truth_value -> truth_value -> truth_value

(** Calculate inference confidence *)
val calculate_inference_confidence : pln_rule -> uuid list -> pln_engine -> float
