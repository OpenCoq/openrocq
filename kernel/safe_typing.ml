(************************************************************************)
(*         *      The Rocq Prover / The Rocq Development Team           *)
(*  v      *         Copyright INRIA, CNRS and contributors             *)
(* <O___,, * (see version control and CREDITS file for authors & dates) *)
(*   \VV/  **************************************************************)
(*    //   *    This file is distributed under the terms of the         *)
(*         *     GNU Lesser General Public License Version 2.1          *)
(*         *     (see LICENSE file for the text of the license)         *)
(************************************************************************)

(* Created by Jean-Christophe Filliâtre as part of the rebuilding of
   Coq around a purely functional abstract type-checker, Dec 1999 *)

(* This file provides the entry points to the kernel type-checker. It
   defines the abstract type of well-formed environments and
   implements the rules that build well-formed environments.

   An environment is made of constants and inductive types (E), of
   section declarations (Delta), of local bound-by-index declarations
   (Gamma) and of universe constraints (C). Below E[Delta,Gamma] |-_C
   means that the tuple E, Delta, Gamma, C is a well-formed
   environment. Main rules are:

   empty_environment:

     ------
     [,] |-

   push_named_assum(a,T):

     E[Delta,Gamma] |-_G
     ------------------------
     E[Delta,Gamma,a:T] |-_G'

   push_named_def(a,t,T):

     E[Delta,Gamma] |-_G
     ---------------------------
     E[Delta,Gamma,a:=t:T] |-_G'

   add_constant(ConstantEntry(DefinitionEntry(c,t,T))):

     E[Delta,Gamma] |-_G
     ---------------------------
     E,c:=t:T[Delta,Gamma] |-_G'

   add_constant(ConstantEntry(ParameterEntry(c,T))):

     E[Delta,Gamma] |-_G
     ------------------------
     E,c:T[Delta,Gamma] |-_G'
   add_mind(Ind(Ind[Gamma_p](Gamma_I:=Gamma_C))):


     E[Delta,Gamma] |-_G
     ------------------------
     E,Ind[Gamma_p](Gamma_I:=Gamma_C)[Delta,Gamma] |-_G'

   etc.
*)

open Util
open Names
open Declarations
open Mod_declarations
open Constr
open Context.Named.Declaration

module NamedDecl = Context.Named.Declaration

(** {6 Safe environments }

  Fields of [safe_environment] :

  - [env] : the underlying environment (cf Environ)
  - [modpath] : the current module name
  - [modvariant] :
    * NONE before coqtop initialization
    * LIBRARY at toplevel of a compilation or a regular coqtop session
    * STRUCT (params,oldsenv) : inside a local module, with
      module parameters [params] and earlier environment [oldsenv]
    * SIG (params,oldsenv) : same for a local module type
  - [modresolver] : delta_resolver concerning the module content, that needs to
    be marshalled on disk. Its root must be [modpath].
  - [paramresolver] : delta_resolver in scope but not part of the library per
    se, that is from functor parameters and required libraries
  - [revstruct] : current module content, most recent declarations first
  - [modlabels] and [objlabels] : names defined in the current module,
      either for modules/modtypes or for constants/inductives.
      These fields could be deduced from [revstruct], but they allow faster
      name freshness checks.
 - [univ] : current universe constraints
 - [future_cst] : delayed opaque constants yet to be checked
 - [required] : names and digests of Require'd libraries since big-bang.
      This field will only grow
 - [loads] : list of libraries Require'd inside the current module.
      They will be propagated to the upper module level when
      the current module ends.
 - [local_retroknowledge]

*)

type vodigest =
  | Dvo_or_vi of Digest.t        (* The digest of the seg_lib part *)

let digest_match ~actual ~required =
  match actual, required with
  | Dvo_or_vi d1, Dvo_or_vi d2 -> String.equal d1 d2

type library_info = DirPath.t * vodigest

(** Functor and funsig parameters, most recent first *)
type module_parameters = (MBId.t * module_type_body) list

type permanent_flags = {
  rewrite_rules_allowed : bool;
}

module ParamResolver :
sig
  type t
  val empty : DirPath.t -> t
  val add_delta_resolver : ModPath.t -> Mod_subst.delta_resolver -> t -> t
  val constant_of_delta_kn : t -> KerName.t -> Constant.t
  val mind_of_delta_kn : t -> KerName.t -> MutInd.t
end =
struct
  type t = {
    root : DirPath.t;
    data : Mod_subst.delta_resolver ModPath.Map.t;
    (** Invariant: No [MPdot] in data *)
  }

  let empty root = {
    root = root;
    data = ModPath.Map.empty;
  }

  let rec head mp = match mp with
  | MPfile _ | MPbound _ -> mp
  | MPdot (mp, _) -> head mp

  let add_delta_resolver mp delta preso =
    let self = MPfile preso.root in
    let data =
      if ModPath.subpath self mp then
        match ModPath.Map.find_opt self preso.data with
        | None ->
          (* we were at toplevel *)
          ModPath.Map.add self delta preso.data
        | Some reso ->
          ModPath.Map.add self (Mod_subst.add_delta_resolver delta reso) preso.data
      else
        let () = match mp with
        | MPfile _ | MPbound _ -> ()
        | MPdot _ -> assert false
        in
        let () = assert (not (ModPath.Map.mem mp preso.data)) in
        ModPath.Map.add mp delta preso.data
    in
    { preso with data }

  let kn_of_delta preso kn =
    let head = head (KerName.modpath kn) in
    match ModPath.Map.find_opt head preso.data with
    | None -> kn
    | Some delta -> Mod_subst.kn_of_delta delta kn

  let constant_of_delta_kn preso kn = Constant.make kn (kn_of_delta preso kn)

  let mind_of_delta_kn preso kn = MutInd.make kn (kn_of_delta preso kn)

end

type compiled_library = {
  comp_name : DirPath.t;
  comp_mod : module_body;
  comp_univs : Univ.ContextSet.t;
  comp_qualities : Sorts.QVar.Set.t;
  comp_deps : library_info array;
  comp_flags : permanent_flags;
}

type reimport = compiled_library * Vmlibrary.on_disk * vodigest

type required_lib = {
  req_root : bool; (* true if a root of the dependency DAG *)
  req_digest : vodigest;
}

(** Part of the safe_env at a section opening time to be backtracked *)
type section_data = {
  rev_env : Environ.env;
  rev_univ : Univ.ContextSet.t;
  rev_qualities : Sorts.QVar.Set.t;
  rev_objlabels : Label.Set.t;
  rev_reimport : reimport list;
  rev_revstruct : structure_body;
  rev_paramresolver : ParamResolver.t;
}

module HandleMap = Opaqueproof.HandleMap

(** We rely on uniqueness of pointers to provide a simple implementation of
    kernel certificates. For this to work across processes, one needs the
    safe environments to be marshaled at the same time as their corresponding
    certificates and sharing to be preserved. *)
module Nonce :
sig
  type t
  val create : unit -> t
  val equal : t -> t -> bool
end =
struct
  type t = unit ref
  let create () = ref ()
  let equal x y = x == y
end

type safe_environment =
  { env : Environ.env;
    sections : section_data Section.t option;
    modpath : ModPath.t;
    modvariant : modvariant;
    modresolver : Mod_subst.delta_resolver;
    paramresolver : ParamResolver.t;
    revstruct : structure_body;
    modlabels : Label.Set.t;
    objlabels : Label.Set.t;
    univ : Univ.ContextSet.t;
    qualities : Sorts.QVar.Set.t ;
    future_cst : (Constant_typing.typing_context * safe_environment * Nonce.t) HandleMap.t;
    required : required_lib DirPath.Map.t;
    loads : (ModPath.t * module_body) list;
    local_retroknowledge : Retroknowledge.action list;
    opaquetab : Opaqueproof.opaquetab;
}

and modvariant =
  | NONE
  | LIBRARY
  | SIG of module_parameters * safe_environment (** saved env *)
  | STRUCT of module_parameters * safe_environment (** saved env *)

let rec library_dp_of_senv senv =
  match senv.modvariant with
  | NONE | LIBRARY -> ModPath.dp senv.modpath
  | SIG(_,senv) -> library_dp_of_senv senv
  | STRUCT(_,senv) -> library_dp_of_senv senv

let empty_environment =
  { env = Environ.empty_env;
    modpath = ModPath.dummy;
    modvariant = NONE;
    modresolver = Mod_subst.empty_delta_resolver ModPath.dummy;
    paramresolver = ParamResolver.empty DirPath.dummy;
    revstruct = [];
    modlabels = Label.Set.empty;
    objlabels = Label.Set.empty;
    sections = None;
    future_cst = HandleMap.empty;
    univ = Univ.ContextSet.empty;
    qualities = Sorts.QVar.Set.empty ;
    required = DirPath.Map.empty;
    loads = [];
    local_retroknowledge = [];
    opaquetab = Opaqueproof.empty_opaquetab;
}

let is_initial senv =
  match senv.revstruct, senv.modvariant with
  | [], NONE -> ModPath.equal senv.modpath ModPath.dummy
  | _ -> false

let sections_are_opened senv = not (Option.is_empty senv.sections)

let delta_of_senv senv = senv.modresolver

let constant_of_delta_kn_senv senv kn =
  let mp = KerName.modpath kn in
  if ModPath.subpath senv.modpath mp then Mod_subst.constant_of_delta_kn senv.modresolver kn
  else ParamResolver.constant_of_delta_kn senv.paramresolver kn

let mind_of_delta_kn_senv senv kn =
  let mp = KerName.modpath kn in
  if ModPath.subpath senv.modpath mp then Mod_subst.mind_of_delta_kn senv.modresolver kn
  else ParamResolver.mind_of_delta_kn senv.paramresolver kn

(** The safe_environment state monad *)

type safe_transformer0 = safe_environment -> safe_environment
type 'a safe_transformer = safe_environment -> 'a * safe_environment


(** {6 Typing flags } *)

let set_typing_flags c senv =
  let env = Environ.set_typing_flags c senv.env in
  if env == senv.env then senv
  else { senv with env }

let set_typing_flags flags senv =
  (* NB: we allow changing the conv_oracle inside sections because it
     doesn't matter for consistency. *)
  if Option.has_some senv.sections
  && not (Environ.same_flags flags
            {(Environ.typing_flags senv.env) with
             conv_oracle = flags.conv_oracle;
             share_reduction = flags.share_reduction;
            })
  then CErrors.user_err Pp.(str "Changing typing flags inside sections is not allowed.");
  set_typing_flags flags senv

let set_impredicative_set b senv =
  let flags = Environ.typing_flags senv.env in
  set_typing_flags { flags with impredicative_set = b } senv

let set_check_guarded b senv =
  let flags = Environ.typing_flags senv.env in
  set_typing_flags { flags with check_guarded = b } senv

let set_check_positive b senv =
  let flags = Environ.typing_flags senv.env in
  set_typing_flags { flags with check_positive = b } senv

let set_check_universes b senv =
  let flags = Environ.typing_flags senv.env in
  set_typing_flags { flags with check_universes = b } senv

let set_indices_matter indices_matter senv =
  set_typing_flags { (Environ.typing_flags senv.env) with indices_matter } senv

let set_share_reduction b senv =
  let flags = Environ.typing_flags senv.env in
  set_typing_flags { flags with share_reduction = b } senv

let set_VM b senv =
  let flags = Environ.typing_flags senv.env in
  set_typing_flags { flags with enable_VM = b } senv

let set_native_compiler b senv =
  let flags = Environ.typing_flags senv.env in
  set_typing_flags { flags with enable_native_compiler = b } senv

let set_allow_sprop b senv = { senv with env = Environ.set_allow_sprop b senv.env }

let set_rewrite_rules_allowed b senv =
  if b then { senv with env = Environ.allow_rewrite_rules senv.env }
  else senv

(* Temporary sets custom typing flags *)
let with_typing_flags ?typing_flags senv ~f =
  match typing_flags with
  | None -> f senv
  | Some typing_flags ->
    let orig_typing_flags = Environ.typing_flags senv.env in
    let res, senv = f (set_typing_flags typing_flags senv) in
    res, set_typing_flags orig_typing_flags senv

(** {6 Stm machinery } *)

module Certificate :
sig
  type t

  val make : safe_environment -> t

  val universes : t -> Univ.ContextSet.t

  (** Checks whether [dst] is a valid extension of [src], possibly adding universes and constraints. *)
  val safe_extend : src:t -> dst:t -> t option
end =
struct

type t = {
  certif_struc : Mod_declarations.structure_body;
  certif_univs : Univ.ContextSet.t;
}

let make senv = {
  certif_struc = senv.revstruct;
  certif_univs = senv.univ;
}

let is_suffix l suf = match l with
| [] -> false
| _ :: l -> l == suf

let safe_extend ~src ~dst =
  if is_suffix dst.certif_struc src.certif_struc then
    Some { certif_struc = dst.certif_struc;
           certif_univs = Univ.ContextSet.union src.certif_univs dst.certif_univs }
  else None

let universes c = c.certif_univs

end

type side_effect = {
  seff_certif : Certificate.t CEphemeron.key;
  seff_constant : Constant.t;
  seff_body : HConstr.t option * (Constr.t, Vmemitcodes.body_code option) Declarations.pconstant_body;
  seff_univs : Univ.ContextSet.t;
}
(* Invariant: For any senv, if [Certificate.safe_extend senv seff_certif] returns [Some certif'] then
   [senv + Certificate.universes certif' + (c.seff_constant -> seff_body)] is well-formed
   (if no univ inconsistency). *)

module SideEffects :
sig
  type t
  val repr : t -> side_effect list
  val empty : t
  val is_empty : t -> bool
  val add : side_effect -> t -> t
  val concat : t -> t -> t
end =
struct

module SeffOrd = struct
type t = side_effect
let compare e1 e2 =
  Constant.CanOrd.compare e1.seff_constant e2.seff_constant
end

module SeffSet = Set.Make(SeffOrd)

type t = { seff : side_effect list; elts : SeffSet.t }
(** Invariant: [seff] is a permutation of the elements of [elts] *)

let repr eff = eff.seff
let empty = { seff = []; elts = SeffSet.empty }
let is_empty { seff; elts } = List.is_empty seff && SeffSet.is_empty elts
let add x es =
  if SeffSet.mem x es.elts then es
  else { seff = x :: es.seff; elts = SeffSet.add x es.elts }
let concat xes yes =
  List.fold_right add xes.seff yes

end

type private_constants = SideEffects.t

let debug_print_private_constants seff =
  let open Pp in
  prlist_with_sep spc (fun seff -> Constant.print seff.seff_constant) (SideEffects.repr seff)

let side_effects_of_private_constants l =
  List.rev (SideEffects.repr l)

(* Only used to push in an Environ.env. *)
let lift_constant c =
  let body = match c.const_body with
  | OpaqueDef _ -> Undef None
  | Def _ | Undef _ | Primitive _ | Symbol _ as body -> body
  in
  { c with const_body = body }

let push_bytecode vmtab code =
  let open Vmemitcodes in
  let vmtab, code = match code with
  | None -> vmtab, None
  | Some (BCdefined (mask, code, patches)) ->
    let vmtab, index = Vmlibrary.add code vmtab in
    vmtab, Some (BCdefined (mask, index, patches))
  | Some BCconstant -> vmtab, Some BCconstant
  | Some (BCalias kn) -> vmtab, Some (BCalias kn)
  in
  vmtab, code

let push_private_constants env eff =
  let eff = side_effects_of_private_constants eff in
  let add_if_undefined env eff =
    if Environ.mem_constant eff.seff_constant env then env
    else
      let (_hbody, cb) = eff.seff_body in
      let vmtab, code = push_bytecode (Environ.vm_library env) cb.const_body_code in
      let cb = { cb with const_body_code = code } in
      let env = Environ.set_vm_library vmtab env in
      Environ.add_constant eff.seff_constant (lift_constant cb) env
  in
  List.fold_left add_if_undefined env eff

let empty_private_constants = SideEffects.empty
let is_empty_private_constants c = SideEffects.is_empty c
let concat_private = SideEffects.concat

let universes_of_private eff =
  let fold acc eff = Univ.ContextSet.union eff.seff_univs acc in
  List.fold_left fold Univ.ContextSet.empty (side_effects_of_private_constants eff)

let constants_of_private eff =
  let fold acc eff = eff.seff_constant :: acc in
  List.fold_left fold [] (side_effects_of_private_constants eff)

let env_of_safe_env senv = senv.env
let env_of_senv = env_of_safe_env

let structure_body_of_safe_env env = env.revstruct

let sections_of_safe_env senv = senv.sections

let rec is_modtype senv =
  match senv.modvariant with
  | STRUCT (_,senv) -> is_modtype senv
  | SIG _ -> true
  | NONE | LIBRARY -> false

let get_section = function
  | None -> CErrors.user_err Pp.(str "No open section.")
  | Some s -> s

let push_context_set ~strict cst senv =
  if Univ.ContextSet.is_empty cst then senv
  else
    let sections = Option.map (Section.push_constraints cst) senv.sections
    in
    { senv with
      env = Environ.push_context_set ~strict cst senv.env;
      univ = Univ.ContextSet.union cst senv.univ;
      sections }

let add_constraints cst senv =
  push_context_set ~strict:true cst senv

let push_quality_set qs senv =
  if Sorts.QVar.Set.is_empty qs then senv
  else
    let () = if is_modtype senv
      then CErrors.user_err (Pp.str "Cannot declare global sort qualities inside module types.")  ;
    in
    let sections = Option.map (Section.push_mono_qualities qs) senv.sections
    in
    { senv with
      env = Environ.push_quality_set qs senv.env ;
      qualities = Sorts.QVar.Set.union qs senv.qualities ;
      sections
    }

let is_curmod_library senv =
  match senv.modvariant with LIBRARY -> true | _ -> false

let is_joined_environment e = HandleMap.is_empty e.future_cst

(** {6 Various checks } *)

let exists_modlabel l senv = Label.Set.mem l senv.modlabels
let exists_objlabel l senv = Label.Set.mem l senv.objlabels

let check_modlabel l senv =
  if exists_modlabel l senv then Modops.error_existing_label l

let check_objlabel l senv =
  if exists_objlabel l senv then Modops.error_existing_label l

let check_objlabels ls senv =
  Label.Set.iter (fun l -> check_objlabel l senv) ls

(** Are we closing the right module / modtype ?
    No user error here, since the opening/ending coherence
    is now verified in [vernac_end_segment] *)

let check_current_label lab = function
  | MPdot (_,l) -> assert (Label.equal lab l)
  | _ -> assert false

let check_struct = function
  | STRUCT (params,oldsenv) -> params, oldsenv
  | NONE | LIBRARY | SIG _ -> assert false

let check_sig = function
  | SIG (params,oldsenv) -> params, oldsenv
  | NONE | LIBRARY | STRUCT _ -> assert false

let check_current_library dir senv = match senv.modvariant with
  | LIBRARY -> assert (ModPath.equal senv.modpath (MPfile dir))
  | NONE | STRUCT _ | SIG _ -> assert false (* cf Lib.end_compilation *)

(** When operating on modules, we're normally outside sections *)

let check_empty_context senv =
  assert (Environ.empty_context senv.env && Option.is_empty senv.sections)

(** When adding a parameter to the current module/modtype,
    it must have been freshly started *)

let check_empty_struct senv =
  assert (List.is_empty senv.revstruct
          && List.is_empty senv.loads)

(** When loading a library, its dependencies should be already there,
    with the correct digests. *)

let check_required current_libs needed =
  let check current (id, required) = match DirPath.Map.find_opt id current with
  | None ->
    CErrors.user_err Pp.(pr_sequence str ["Reference to unknown module"; DirPath.to_string id; "."])
  | Some { req_root; req_digest = actual } ->
    if not (digest_match ~actual ~required) then
      CErrors.user_err Pp.(pr_sequence str
        ["Inconsistent assumptions over module"; DirPath.to_string id; "."])
    else if req_root then
      (* the library is being transitively required, not a root anymore *)
      DirPath.Map.set id { req_root = false; req_digest = actual } current
    else
      (* nothing to do *)
      current
  in
  Array.fold_left check current_libs needed

(** When loading a library, the current flags should match
    those needed for the library *)

let check_flags_for_library lib senv =
  let { rewrite_rules_allowed } = lib.comp_flags in
  set_rewrite_rules_allowed rewrite_rules_allowed senv

(** {6 Insertion of section variables} *)

(** They are now typed before being added to the environment.
    Same as push_named, but check that the variable is not already
    there. Should *not* be done in Environ because tactics add temporary
    hypothesis many many times, and the check performed here would
    cost too much. *)

let safe_push_named d env =
  let id = NamedDecl.get_id d in
  let _ =
    try
      let _ = Environ.lookup_named id env in
      CErrors.user_err Pp.(pr_sequence str ["Identifier"; Id.to_string id; "already defined."])
    with Not_found -> () in
  Environ.push_named d env

let push_named_def (id,de) senv =
  let sections = get_section senv.sections in
  let c, r, typ = Constant_typing.infer_local_def senv.env id de in
  let d = LocalDef (Context.make_annot id r, c, typ) in
  let env'' = safe_push_named d senv.env in
  let sections = Section.push_local d sections in
  { senv with sections=Some sections; env = env'' }

let push_named_assum (x,t) senv =
  let sections = get_section senv.sections in
  let t, r = Constant_typing.infer_local_assum senv.env t in
  let d = LocalAssum (Context.make_annot x r, t) in
  let sections = Section.push_local d sections in
  let env'' = safe_push_named d senv.env in
  { senv with sections=Some sections; env = env'' }

let push_section_context uctx senv =
  let sections = get_section senv.sections in
  let sections = Section.push_local_universe_context uctx sections in
  let senv = { senv with sections=Some sections } in
  let qualities, ctx = UVars.UContext.to_context_set uctx in
  assert Sorts.QVar.Set.(is_empty (inter qualities senv.qualities));
  (* push_context checks freshness *)
  { senv with
    env = Environ.push_context ~strict:false uctx senv.env;
    univ = Univ.ContextSet.union ctx senv.univ ;
    qualities = Sorts.QVar.Set.union qualities senv.qualities }

(** {6 Insertion of new declarations to current environment } *)

let labels_of_mib mib =
  let add,get =
    let labels = ref Label.Set.empty in
    (fun id -> labels := Label.Set.add (Label.of_id id) !labels),
    (fun () -> !labels)
  in
  let visit_mip mip =
    add mip.mind_typename;
    Array.iter add mip.mind_consnames
  in
  Array.iter visit_mip mib.mind_packets;
  get ()

let add_retroknowledge pttc senv =
  { senv with
    env = Primred.add_retroknowledge senv.env pttc;
    local_retroknowledge = pttc::senv.local_retroknowledge }

(** A generic function for adding a new field in a same environment.
    It also performs the corresponding [add_constraints]. *)

type generic_name =
  | C of Constant.t
  | I of MutInd.t
  | R
  | M of ModPath.t
  | MT of ModPath.t

let add_field ((l,sfb) as field) gn senv =
  let mlabs,olabs = match sfb with
    | SFBmind mib ->
      let l = labels_of_mib mib in
      check_objlabels l senv; (Label.Set.empty,l)
    | SFBconst _ | SFBrules _ ->
      check_objlabel l senv; (Label.Set.empty, Label.Set.singleton l)
    | SFBmodule _ | SFBmodtype _ ->
      check_modlabel l senv; (Label.Set.singleton l, Label.Set.empty)
  in
  let env' = match sfb, gn with
    | SFBconst cb, C con -> Environ.add_constant con cb senv.env
    | SFBmind mib, I mind -> Environ.add_mind mind mib senv.env
    | SFBmodtype mtb, MT mp -> Environ.add_modtype mp mtb senv.env
    | SFBmodule mb, M mp -> Modops.add_module mp mb senv.env
    | SFBrules r, R -> Environ.add_rewrite_rules r.rewrules_rules senv.env
    | _ -> assert false
  in
  let sections = match senv.sections with
    | None -> None
    | Some sections ->
      match sfb, gn with
      | SFBconst cb, C con ->
        let poly = Declareops.constant_is_polymorphic cb in
        Some Section.(push_global ~poly env' (SecDefinition con) sections)
      | SFBmind mib, I mind ->
        let poly = Declareops.inductive_is_polymorphic mib in
        Some Section.(push_global ~poly env' (SecInductive mind) sections)
      | _, (M _ | MT _) -> Some sections
      | _ -> assert false
  in
  { senv with
    env = env';
    sections;
    revstruct = field :: senv.revstruct;
    modlabels = Label.Set.union mlabs senv.modlabels;
    objlabels = Label.Set.union olabs senv.objlabels }

(** Applying a certain function to the resolver of a safe environment *)

let update_resolver f senv = { senv with modresolver = f senv.modresolver }

type exported_opaque = {
  exp_handle : Opaqueproof.opaque_handle;
  exp_body : Constr.t;
  exp_univs : (int * int) option;
  (* Minimal amount of data needed to rebuild the private universes. We enforce
     in the API that private constants have no internal constraints. *)
}
type exported_private_constant = Constant.t * exported_opaque option

let repr_exported_opaque o =
  let priv = match o .exp_univs with
  | None -> Opaqueproof.PrivateMonomorphic ()
  | Some _ -> Opaqueproof.PrivatePolymorphic Univ.ContextSet.empty
  in
  (o.exp_handle, (o.exp_body, priv))

let set_vm_library lib senv =
  { senv with env = Environ.set_vm_library lib senv.env }

let push_const_bytecode senv cb =
  let vmtab, code = push_bytecode (Environ.vm_library senv.env) cb.const_body_code in
  let cb = { cb with const_body_code = code } in
  let senv = set_vm_library vmtab senv in
  senv, cb

let make_hbody = function
  | None -> None
  | Some hc -> Some (fun c ->
      assert (c == HConstr.self hc);
      snd @@ HConstr.hcons hc)

let add_constant_aux senv ?hbody (kn, cb) =
  let l = Constant.label kn in
  (* This is the only place where we hashcons the contents of a constant body *)
  let senv, cb = push_const_bytecode senv cb in
  let cb = if sections_are_opened senv then cb else
      Declareops.hcons_const_body ?hbody:(make_hbody hbody) cb
  in
  let senv' = add_field (l,SFBconst cb) (C kn) senv in
  let senv'' = match cb.const_body with
    | Undef (Some lev) ->
      update_resolver
        (Mod_subst.add_inline_delta_resolver (Constant.user kn) (lev,None)) senv'
    | _ -> senv'
  in
  senv''

let inline_side_effects env body side_eff =
  let open Constr in
  (** First step: remove the constants that are still in the environment *)
  let filter e =
    if Environ.mem_constant e.seff_constant env then None
    else Some e
  in
  (* CAVEAT: we assure that most recent effects come first *)
  let side_eff = List.map_filter filter (SideEffects.repr side_eff) in
  let sigs = List.rev_map (fun e -> e.seff_constant, e.seff_certif) side_eff in
  (** Most recent side-effects first in side_eff *)
  if List.is_empty side_eff then (body, Univ.ContextSet.empty, sigs, 0)
  else
    (** Second step: compute the lifts and substitutions to apply *)
    let cname c r = Context.make_annot (Name (Label.to_id (Constant.label c))) r in
    let fold (subst, var, ctx, args) { seff_constant = c; seff_body = (_hbody, cb); seff_univs = univs; _ } =
      let (b, opaque) = match cb.const_body with
      | Def b -> (b, false)
      | OpaqueDef b -> (b, true)
      | _ -> assert false
      in
      match cb.const_universes with
      | Monomorphic ->
        (** Abstract over the term at the top of the proof *)
        let ty = cb.const_type in
        let subst = Cmap_env.add c (Inr var) subst in
        let ctx = Univ.ContextSet.union ctx univs in
        (subst, var + 1, ctx, (cname c cb.const_relevance, b, ty, opaque) :: args)
      | Polymorphic _ ->
        let () = assert (Univ.ContextSet.is_empty univs) in
        (** Inline the term to emulate universe polymorphism *)
        let subst = Cmap_env.add c (Inl b) subst in
        (subst, var, ctx, args)
    in
    let (subst, len, ctx, args) = List.fold_left fold (Cmap_env.empty, 1, Univ.ContextSet.empty, []) side_eff in
    (** Third step: inline the definitions *)
    let rec subst_const i k t = match Constr.kind t with
    | Const (c, u) ->
      let data = try Some (Cmap_env.find c subst) with Not_found -> None in
      begin match data with
      | None -> t
      | Some (Inl b) ->
        (** [b] is closed but may refer to other constants *)
        subst_const i k (Vars.subst_instance_constr u b)
      | Some (Inr n) ->
        mkRel (k + n - i)
      end
    | Rel n ->
      (** Lift free rel variables *)
      if n <= k then t
      else mkRel (n + len - i - 1)
    | _ -> Constr.map_with_binders ((+) 1) (fun k t -> subst_const i k t) k t
    in
    let map_args i (na, b, ty, opaque) =
      (** Both the type and the body may mention other constants *)
      let ty = subst_const (len - i - 1) 0 ty in
      let b = subst_const (len - i - 1) 0 b in
      (na, b, ty, opaque)
    in
    let args = List.mapi map_args args in
    let body = subst_const 0 0 body in
    let fold_arg (na, b, ty, opaque) accu =
      if opaque then mkApp (mkLambda (na, ty, accu), [|b|])
      else mkLetIn (na, b, ty, accu)
    in
    let body = List.fold_right fold_arg args body in
    (body, ctx, sigs, len - 1)

let inline_private_constants env ((body, ctx), side_eff) =
  let body, ctx', _, _ = inline_side_effects env body side_eff in
  let ctx' = Univ.ContextSet.union ctx ctx' in
  (body, ctx')

let warn_failed_cert = CWarnings.create ~name:"failed-abstract-certificate"
    ~category:CWarnings.CoreCategories.tactics ~default:CWarnings.Disabled
    Pp.(fun kn ->
        str "Certificate for private constant " ++
        Label.print (Constant.label kn) ++
        str " failed.")

(* Given the list of signatures of side effects, checks if they match.
 * I.e. if they are ordered descendants of the current revstruct.
   Returns the universes needed to trust the side effects (None if they can't be trusted). *)
let check_signatures senv sl =
  let curmb = Certificate.make senv in
  let is_direct_ancestor accu (kn, mb) =
    match accu with
    | None -> None
    | Some curmb ->
        try
          let mb = CEphemeron.get mb in
          let mb = Certificate.safe_extend ~src:curmb ~dst:mb in
          let () = if Option.is_empty mb then warn_failed_cert kn in
          mb
        with CEphemeron.InvalidKey -> None in
  let sl = List.fold_left is_direct_ancestor (Some curmb) sl in
  match sl with
  | None ->
    None
  | Some mb ->
    let univs = Certificate.universes mb in
    Some (Univ.ContextSet.diff univs senv.univ)

type side_effect_declaration =
| DefinitionEff : Entries.definition_entry -> side_effect_declaration
| OpaqueEff : Constr.constr Entries.opaque_entry -> side_effect_declaration

let constant_entry_of_side_effect eff =
  let (_hbody, cb) = eff.seff_body in
  let open Entries in
  let univs =
    match cb.const_universes with
    | Monomorphic ->
      Monomorphic_entry
    | Polymorphic auctx ->
      Polymorphic_entry (UVars.AbstractContext.repr auctx)
  in
  let p =
    match cb.const_body with
    | OpaqueDef b -> b
    | Def b -> b
    | _ -> assert false in
  if Declareops.is_opaque cb then
  OpaqueEff {
    opaque_entry_body = p;
    opaque_entry_secctx = Context.Named.to_vars cb.const_hyps;
    opaque_entry_type = cb.const_type;
    opaque_entry_universes = univs;
  }
  else
  DefinitionEff {
    definition_entry_body = p;
    definition_entry_secctx = Some (Context.Named.to_vars cb.const_hyps);
    definition_entry_type = Some cb.const_type;
    definition_entry_universes = univs;
    definition_entry_inline_code = cb.const_inline_code }

let export_eff eff =
  (eff.seff_constant, eff.seff_body)

let is_empty_private = function
| Opaqueproof.PrivateMonomorphic ctx -> Univ.ContextSet.is_empty ctx
| Opaqueproof.PrivatePolymorphic ctx -> Univ.ContextSet.is_empty ctx

let compile_bytecode env cb =
  let code = Vmbytegen.compile_constant_body ~fail_on_error:false env cb.const_universes cb.const_body in
  { cb with const_body_code = code }

(* Special function to call when the body of an opaque definition is provided.
  It performs the type-checking of the body immediately. *)
let infer_direct_opaque ~sec_univs env ce =
  let cb, ctx = Constant_typing.infer_opaque ~sec_univs env ce in
  let body = ce.Entries.opaque_entry_body, Univ.ContextSet.empty in
  let handle _env c () = (c, Univ.ContextSet.empty, 0) in
  let (hbody, c, u) = Constant_typing.check_delayed handle ctx (body, ()) in
  (* No constraints can be generated, we set it empty everywhere *)
  let () = assert (is_empty_private u) in
  hbody, { cb with const_body = OpaqueDef c }

let export_side_effects senv eff =
  let sec_univs = Option.map Section.all_poly_univs senv.sections in
  let env = senv.env in
  let not_exists e = not (Environ.mem_constant e.seff_constant env) in
  let aux (acc,sl) e =
    if not (not_exists e) then acc, sl
    else e :: acc, (e.seff_constant, e.seff_certif) :: sl in
  let seff, signatures = List.fold_left aux ([],[]) (SideEffects.repr eff) in
  let trusted = check_signatures senv signatures in
  let push_seff env eff =
    let { seff_constant = kn; seff_body = (_hbody, cb); _ } = eff in
    let vmtab, code = push_bytecode (Environ.vm_library env) cb.const_body_code in
    let env = Environ.set_vm_library vmtab env in
    let cb = { cb with const_body_code = code } in
    let env = Environ.add_constant kn (lift_constant cb) env in
    env
  in
  match trusted with
  | Some univs ->
    univs, List.map export_eff seff
  | None ->
    let rec recheck_seff seff univs acc env = match seff with
      | [] -> univs, List.rev acc
      | eff :: rest ->
        let uctx = eff.seff_univs in
        let env = Environ.push_context_set ~strict:true uctx env in
        let univs = Univ.ContextSet.union uctx univs in
        let env, cb =
          let ce = constant_entry_of_side_effect eff in
          let hbody, cb = match ce with
            | DefinitionEff ce ->
              Constant_typing.infer_definition ~sec_univs env ce
            | OpaqueEff ce ->
              infer_direct_opaque ~sec_univs env ce
          in
          let cb = compile_bytecode env cb in
          let eff = { eff with seff_body = (hbody, cb) } in
          (push_seff env eff, export_eff eff)
        in
        recheck_seff rest univs (cb :: acc) env
    in
    recheck_seff seff Univ.ContextSet.empty [] env

let push_opaque_proof senv =
  let o, otab = Opaqueproof.create (library_dp_of_senv senv) senv.opaquetab in
  let senv = { senv with opaquetab = otab } in
  senv, o

let export_private_constants eff senv =
  let uctx, exported = export_side_effects senv eff in
  let senv = push_context_set ~strict:true uctx senv in
  let map senv (kn, (hbody, c)) = match c.const_body with
  | OpaqueDef body ->
    (* Don't care about the body, it has been checked by {!infer_direct_opaque} *)
    let senv, o = push_opaque_proof senv in
    let (_, _, _, h) = Opaqueproof.repr o in
    let univs = match c.const_universes with
    | Monomorphic -> None
    | Polymorphic auctx -> Some (UVars.AbstractContext.size auctx)
    in
    (* Hashcons now, before storing in the opaque table *)
    let _, body = match hbody with
    | None -> Constr.hcons body
    | Some hbody ->
      let () = assert (HConstr.self hbody == body) in
      HConstr.hcons hbody
    in
    let opaque = { exp_body = body; exp_handle = h; exp_univs = univs } in
    senv, (kn, { c with const_body = OpaqueDef o }, Some opaque, None)
  | Def _ | Undef _ | Primitive _ | Symbol _ as body ->
    (* Hashconsing is handled by {!add_constant_aux}, propagate hbody *)
    senv, (kn, { c with const_body = body }, None, hbody)
  in
  let senv, bodies = List.fold_left_map map senv exported in
  let exported = List.map (fun (kn, _, opaque, _) -> kn, opaque) bodies in
  (* No delayed constants to declare *)
  let fold senv (kn, cb, _, hbody) = add_constant_aux ?hbody senv (kn, cb) in
  let senv = List.fold_left fold senv bodies in
  exported, senv

let add_constant l decl senv =
  let kn = Constant.make2 senv.modpath l in
  let senv, (hbody, cb) =
    let sec_univs = Option.map Section.all_poly_univs senv.sections in
      match decl with
      | Entries.OpaqueEntry ce ->
        let senv, o = push_opaque_proof senv in
        let cb, ctx = Constant_typing.infer_opaque ~sec_univs senv.env ce in
        (* Push the delayed data in the environment *)
        let (_, _, _, i) = Opaqueproof.repr o in
        let nonce = Nonce.create () in
        let future_cst = HandleMap.add i (ctx, senv, nonce) senv.future_cst in
        let senv = { senv with future_cst } in
        senv, (None, { cb with const_body = OpaqueDef o })
      | Entries.DefinitionEntry entry ->
        senv, Constant_typing.infer_definition ~sec_univs senv.env entry
      | Entries.ParameterEntry entry ->
        senv, (None, Constant_typing.infer_parameter ~sec_univs senv.env entry)
      | Entries.PrimitiveEntry entry ->
        let senv = match entry with
        | { Entries.prim_entry_content = CPrimitives.OT_type t; _ } ->
          if sections_are_opened senv then CErrors.anomaly (Pp.str "Primitive type not allowed in sections");
          add_retroknowledge (Retroknowledge.Register_type(t,kn)) senv
        | _ -> senv in
        senv, (None, Constant_typing.infer_primitive senv.env entry)
      | Entries.SymbolEntry entry ->
        senv, (None, Constant_typing.infer_symbol senv.env entry)
  in
  let cb = compile_bytecode senv.env cb in
  let senv = add_constant_aux senv ?hbody (kn, cb) in
  kn, senv

let add_constant ?typing_flags l decl senv =
  with_typing_flags ?typing_flags senv ~f:(add_constant l decl)

type opaque_certificate = {
  opq_body : Constr.t;
  opq_univs : Univ.ContextSet.t Opaqueproof.delayed_universes;
  opq_handle : Opaqueproof.opaque_handle;
  opq_nonce : Nonce.t;
}

let check_opaque senv (i : Opaqueproof.opaque_handle) pf =
  let ty_ctx, trust, nonce =
    try HandleMap.find i senv.future_cst
    with Not_found ->
      CErrors.anomaly Pp.(str "Missing opaque with identifier " ++ int (Opaqueproof.repr_handle i))
  in
  let handle env body eff =
    let body, uctx, signatures, skip = inline_side_effects env body eff in
    let trusted = check_signatures trust signatures in
    let trusted, uctx = match trusted with
    | None -> 0, uctx
    | Some univs -> skip, Univ.ContextSet.union univs uctx
    in
    body, uctx, trusted
  in
  let (hbody, c, ctx) = Constant_typing.check_delayed handle ty_ctx pf in
  let _, c = match hbody with
    | Some hbody -> assert (c == HConstr.self hbody); HConstr.hcons hbody
    | None -> Constr.hcons c
  in
  let ctx = match ctx with
  | Opaqueproof.PrivateMonomorphic u ->
    Opaqueproof.PrivateMonomorphic (snd @@ Univ.ContextSet.hcons u)
  | Opaqueproof.PrivatePolymorphic u ->
    Opaqueproof.PrivatePolymorphic (snd @@ Univ.ContextSet.hcons u)
  in
  { opq_body = c; opq_univs = ctx; opq_handle = i; opq_nonce = nonce }

let fill_opaque { opq_univs = ctx; opq_handle = i; opq_nonce = n; _ } senv =
  let () = if not @@ HandleMap.mem i senv.future_cst then
    CErrors.anomaly Pp.(str "Missing opaque handle" ++ spc () ++ int (Opaqueproof.repr_handle i))
  in
  let _, _, nonce = HandleMap.find i senv.future_cst in
  let () =
    if not (Nonce.equal n nonce) then
      CErrors.anomaly  Pp.(str "Invalid opaque certificate")
  in
  (* TODO: Drop the the monomorphic constraints, they should really be internal
     but the higher levels use them haphazardly. *)
  let senv = match ctx with
  | Opaqueproof.PrivateMonomorphic ctx -> add_constraints ctx senv
  | Opaqueproof.PrivatePolymorphic _ -> senv
  in
  (* Mark the constant as having been checked *)
  { senv with future_cst = HandleMap.remove i senv.future_cst }

let is_filled_opaque i senv =
  let () = assert (Opaqueproof.mem_handle i senv.opaquetab) in
  not (HandleMap.mem i senv.future_cst)

let repr_certificate { opq_body = body; opq_univs = ctx; _ } =
  body, ctx

let check_constraints uctx = function
| Entries.Polymorphic_entry _ -> Univ.ContextSet.is_empty uctx
| Entries.Monomorphic_entry -> true

let add_private_constant l uctx decl senv : (Constant.t * private_constants) * safe_environment =
  let kn = Constant.make2 senv.modpath l in
  let senv = push_context_set ~strict:true uctx senv in
    let hbody, cb =
      let sec_univs = Option.map Section.all_poly_univs senv.sections in
      match decl with
      | OpaqueEff ce ->
        let () = assert (check_constraints uctx ce.Entries.opaque_entry_universes) in
        infer_direct_opaque ~sec_univs senv.env ce
      | DefinitionEff ce ->
        let () = assert (check_constraints uctx ce.Entries.definition_entry_universes) in
        Constant_typing.infer_definition ~sec_univs senv.env ce
    in
  let cb = compile_bytecode senv.env cb in
  let dcb = match cb.const_body with
  | Def _ as const_body -> { cb with const_body }
  | OpaqueDef _ ->
    (* We drop the body, to save the definition of an opaque and thus its
       hashconsing. It does not matter since this only happens inside a proof,
       and depending of the opaque status of the latter, this proof term will be
       either inlined or reexported. *)
    { cb with const_body = Undef None }
  | Undef _ | Primitive _ | Symbol _ -> assert false
  in
  let senv = add_constant_aux senv ?hbody (kn, dcb) in
  let eff =
    let from_env = CEphemeron.create (Certificate.make senv) in
    let eff = {
      seff_certif = from_env;
      seff_constant = kn;
      seff_body = (hbody, cb);
      seff_univs = uctx;
    } in
    SideEffects.add eff empty_private_constants
  in
  (kn, eff), senv

(** Rewrite rules *)

let add_rewrite_rules l rules senv =
  if Option.has_some senv.sections
  then CErrors.user_err Pp.(str "Adding rewrite rules not supported in sections.");
  (* TODO: Hashconsing? *)
  add_field (l, SFBrules rules) R senv

(** Insertion of inductive types *)

let check_mind mie lab =
  let open Entries in
  match mie.mind_entry_inds with
  | [] -> assert false (* empty inductive entry *)
  | oie::_ ->
    (* The label and the first inductive type name should match *)
    assert (Id.equal (Label.to_id lab) oie.mind_entry_typename)

let add_checked_mind kn mib senv =
  let mib =
    match mib.mind_hyps with [] -> Declareops.hcons_mind mib | _ -> mib
  in
  add_field (MutInd.label kn,SFBmind mib) (I kn) senv

let add_mind l mie senv =
  let () = check_mind mie l in
  let kn = MutInd.make2 senv.modpath l in
  let sec_univs = Option.map Section.all_poly_univs senv.sections in
  let mib, why_not_prim_record = Indtypes.check_inductive senv.env ~sec_univs kn mie in
  (* We still have to add the template monomorphic constraints, and only those
     ones. In all other cases, they are already part of the environment at this
     point. *)
  let senv = match mib.mind_template with
  | None -> senv
  | Some { template_context = ctx; template_defaults = u; _ } ->
    let qs, levels = UVars.Instance.levels u in
    assert (Sorts.Quality.Set.for_all (fun q -> Sorts.Quality.equal Sorts.Quality.qtype q) qs);
    let csts = UVars.AbstractContext.instantiate u ctx in
    push_context_set ~strict:true (levels,csts) senv
  in
  (kn, why_not_prim_record), add_checked_mind kn mib senv

let add_mind ?typing_flags l mie senv =
  with_typing_flags ?typing_flags senv ~f:(add_mind l mie)

(** Insertion of module types *)

let check_state senv =
  (Environ.universes senv.env, Conversion.checked_universes)

let vm_handler env univs c vmtab =
  let env = Environ.set_vm_library vmtab env in
  let code = Vmbytegen.compile_constant_body ~fail_on_error:false env univs (Def c) in
  let vmtab, code = push_bytecode vmtab code in
  vmtab, code

let vm_state senv =
  (Environ.vm_library senv.env, { Mod_typing.vm_handler })

let add_modtype l params_mte inl senv =
  let mp = MPdot(senv.modpath, l) in
  let state = check_state senv in
  let vmstate = vm_state senv in
  let mtb, _, vmtab = Mod_typing.translate_modtype state vmstate senv.env mp inl params_mte  in
  let senv = set_vm_library vmtab senv in
  let mtb = Mod_declarations.hcons_module_type mtb in
  let senv = add_field (l,SFBmodtype mtb) (MT mp) senv in
  mp, senv

(** full_add_module adds module with universes and constraints *)

let full_add_module mp mb senv =
  let dp = ModPath.dp mp in
  let linkinfo = Nativecode.link_info_of_dirpath dp in
  { senv with env = Modops.add_linked_module mp mb linkinfo senv.env }

(** Insertion of modules *)

let add_module l me inl senv =
  let mp = MPdot(senv.modpath, l) in
  let state = check_state senv in
  let vmstate = vm_state senv in
  let mb, _, vmtab = Mod_typing.translate_module state vmstate senv.env mp inl me in
  let senv = set_vm_library vmtab senv in
  let mb = Mod_declarations.hcons_module_body mb in
  let senv = add_field (l,SFBmodule mb) (M mp) senv in
  let senv = match mod_global_delta mb with
  | None -> senv
  | Some delta -> update_resolver (Mod_subst.add_delta_resolver delta) senv
  in
  (mp, mod_delta mb), senv

(** {6 Starting / ending interactive modules and module types } *)

let start_mod_modtype ~istype l senv =
  let () = check_modlabel l senv in
  let () = check_empty_context senv in
  let mp = MPdot(senv.modpath, l) in
  mp,
  {
    (* modified fields *)
    modpath = mp;
    modvariant = if istype then SIG ([], senv) else STRUCT ([],senv);

    (* carried over fields *)
    env = senv.env;
    future_cst = senv.future_cst;
    modresolver = Mod_subst.empty_delta_resolver mp;
    paramresolver = ParamResolver.add_delta_resolver senv.modpath senv.modresolver senv.paramresolver;
    univ = senv.univ;
    qualities = senv.qualities;
    required = senv.required;
    opaquetab = senv.opaquetab;
    sections = None; (* checked in check_empty_context *)

    (* module local fields *)
    revstruct = [];
    modlabels = Label.Set.empty;
    objlabels = Label.Set.empty;
    loads = [];
    local_retroknowledge = [];
  }

let start_module l senv = start_mod_modtype ~istype:false l senv

let start_modtype l senv = start_mod_modtype ~istype:true l senv

(** Adding parameters to the current module or module type.
    This module should have been freshly started. *)

let add_module_parameter mbid mte inl senv =
  let () = check_empty_struct senv in
  let mp = MPbound mbid in
  let state = check_state senv in
  let vmstate = vm_state senv in
  let mtb, _, vmtab = Mod_typing.translate_modtype state vmstate senv.env mp inl ([],mte) in
  let senv = set_vm_library vmtab senv in
  let senv = { senv with env = Modops.add_module_parameter mbid mtb senv.env } in
  let new_variant = match senv.modvariant with
    | STRUCT (params,oldenv) -> STRUCT ((mbid,mtb) :: params, oldenv)
    | SIG (params,oldenv) -> SIG ((mbid,mtb) :: params, oldenv)
    | _ -> assert false
  in
  let new_paramresolver = match mod_global_delta mtb with
  | None -> senv.paramresolver
  | Some delta -> ParamResolver.add_delta_resolver mp delta senv.paramresolver
  in
  mod_delta mtb,
  { senv with
    modvariant = new_variant;
    paramresolver = new_paramresolver }

let rec module_num_parameters senv =
  match senv.modvariant with
  | STRUCT (params,senv) -> List.length params :: module_num_parameters senv
  | SIG (params,senv) -> List.length params :: module_num_parameters senv
  | _ -> []

let rec module_is_modtype senv =
  match senv.modvariant with
  | STRUCT (_,senv) -> false :: module_is_modtype senv
  | SIG (_,senv) -> true :: module_is_modtype senv
  | _ -> []

let functorize params init =
  List.fold_left (fun e (mbid,mt) -> MoreFunctor(mbid,mt,e)) init params

let propagate_loads senv =
  List.fold_left
    (fun env (mp, mb) -> full_add_module mp mb env)
    senv
    (List.rev senv.loads)

(** Build the module body of the current module, taking in account
    a possible return type (_:T) *)

let build_module_body params restype senv =
  let struc = NoFunctor (List.rev senv.revstruct) in
  let restype' = Option.map (fun (ty,inl) -> (([],ty),inl)) restype in
  let state = check_state senv in
  let vmstate = vm_state senv in
  let mb, _, vmtab =
    Mod_typing.finalize_module state vmstate senv.env senv.modpath
      (struc, senv.modresolver) restype'
  in
  let senv = set_vm_library vmtab senv in
  let mb' = functorize_module params mb in
  set_retroknowledge mb' senv.local_retroknowledge

(** Returning back to the old pre-interactive-module environment,
    with one extra component and some updated fields
    (constraints, required, etc) *)

let allow_delayed_constants = ref false

let propagate_senv newdef newenv newresolver senv oldsenv =
  (* This asserts that after Paral-ITP, standard vo compilation is behaving
   * exctly as before: the same universe constraints are added to modules *)
  if not !allow_delayed_constants && not (HandleMap.is_empty senv.future_cst) then
    CErrors.anomaly ~label:"safe_typing"
      Pp.(str "True Future.t were created for opaque constants even if -async-proofs is off");
  { oldsenv with
    env = newenv;
    modresolver = newresolver;
    revstruct = newdef::oldsenv.revstruct;
    modlabels = Label.Set.add (fst newdef) oldsenv.modlabels;
    univ = senv.univ;
    qualities = senv.qualities ;
    future_cst = senv.future_cst;
    required = senv.required;
    loads = senv.loads@oldsenv.loads;
    local_retroknowledge =
      senv.local_retroknowledge@oldsenv.local_retroknowledge;
    opaquetab = senv.opaquetab;
  }

let end_module l restype senv =
  let mp = senv.modpath in
  let params, oldsenv = check_struct senv.modvariant in
  let () = check_current_label l mp in
  let () = check_empty_context senv in
  let mbids = List.rev_map fst params in
  let mb = build_module_body params restype senv in
  let newenv = Environ.set_universes (Environ.universes senv.env) oldsenv.env in
  let newenv = Environ.set_qualities (Environ.qualities senv.env) newenv in
  let newenv = if Environ.rewrite_rules_allowed senv.env then Environ.allow_rewrite_rules newenv else newenv in
  let newenv = Environ.set_vm_library (Environ.vm_library senv.env) newenv in
  let senv' = propagate_loads { senv with env = newenv } in
  let newenv = Modops.add_module mp mb senv'.env in
  let newresolver = match mod_global_delta mb with
  | None -> oldsenv.modresolver
  | Some delta -> Mod_subst.add_delta_resolver delta oldsenv.modresolver
  in
  (mp, mbids, mod_delta mb),
  propagate_senv (l,SFBmodule mb) newenv newresolver senv' oldsenv

let build_mtb = Mod_declarations.make_module_type

let end_modtype l senv =
  let mp = senv.modpath in
  let params, oldsenv = check_sig senv.modvariant in
  let () = check_current_label l mp in
  let () = check_empty_context senv in
  let mbids = List.rev_map fst params in
  let newenv = Environ.set_universes (Environ.universes senv.env) oldsenv.env in
  let newenv = if Environ.rewrite_rules_allowed senv.env then Environ.allow_rewrite_rules newenv else newenv in
  let newenv = Environ.set_vm_library (Environ.vm_library senv.env) newenv in
  let senv' = propagate_loads {senv with env=newenv} in
  let auto_tb = functorize params (NoFunctor (List.rev senv.revstruct)) in
  let mtb = build_mtb auto_tb senv.modresolver in
  let newenv = Environ.add_modtype mp mtb senv'.env in
  let newresolver = oldsenv.modresolver in
  (mp,mbids),
  propagate_senv (l,SFBmodtype mtb) newenv newresolver senv' oldsenv

(** {6 Inclusion of module or module type } *)

let add_include me is_module inl senv =
  let open Mod_typing in
  let mp_sup = senv.modpath in
  let state = check_state senv in
  let vmstate = vm_state senv in
  let sign,(),resolver, _, vmtab =
    translate_mse_include is_module state vmstate senv.env mp_sup inl me
  in
  let senv = set_vm_library vmtab senv in
  (* Include Self support  *)
  let struc = NoFunctor (List.rev senv.revstruct) in
  let mb = build_mtb struc senv.modresolver in
  let rec compute_sign sign resolver =
    match sign with
    | MoreFunctor(mbid,mtb,str) ->
      let state = check_state senv in
      let env = Modops.add_module mp_sup (module_body_of_type mb) senv.env in
      let (_ : UGraph.t) = Subtyping.check_subtypes state env mp_sup (MPbound mbid) mtb in
      let mpsup_delta =
        Modops.inline_delta_resolver senv.env inl mp_sup mbid mtb senv.modresolver
      in
      let subst = Mod_subst.map_mbid mbid mp_sup mpsup_delta in
      let resolver = Mod_subst.subst_codom_delta_resolver subst resolver in
      compute_sign (Modops.subst_signature subst mp_sup str) resolver
    | NoFunctor str -> resolver, str
  in
  let resolver, str = compute_sign sign resolver in
  let senv = update_resolver (Mod_subst.add_delta_resolver resolver) senv in
  let add senv ((l,elem) as field) =
    let new_name = match elem with
      | SFBconst _ ->
        C (Mod_subst.constant_of_delta_kn resolver (KerName.make mp_sup l))
      | SFBmind _ ->
        I (Mod_subst.mind_of_delta_kn resolver (KerName.make mp_sup l))
      | SFBrules _ -> R
      | SFBmodule _ -> M (MPdot (mp_sup, l))
      | SFBmodtype _ -> MT (MPdot (mp_sup, l))
    in
    add_field field new_name senv
  in
  resolver, List.fold_left add senv str

(** {6 Libraries, i.e. compiled modules } *)

let dirpath_of_library lib = lib.comp_name

let module_of_library lib = lib.comp_mod

let univs_of_library lib = lib.comp_univs

(** FIXME: MS: remove?*)
let current_modpath senv = senv.modpath
let current_dirpath senv = Names.ModPath.dp (current_modpath senv)

let start_library dir senv =
  (* When starting a library, the current environment should be initial
     i.e. only composed of Require's *)
  (* XXX is it really possible / should be allowed to have nonempty Requires?
     especially if [dir] is in the [senv.required] *)
  assert (is_initial senv);
  assert (not (DirPath.is_empty dir));
  let mp = MPfile dir in
  let vmtab = Vmlibrary.set_path dir (Environ.vm_library senv.env) in
  let env = Environ.set_vm_library vmtab senv.env in
  mp,
  { env = env;
    modpath = mp;
    modvariant = LIBRARY;
    required = senv.required;

    modresolver = Mod_subst.empty_delta_resolver mp;
    paramresolver = ParamResolver.empty dir;
    revstruct = [];
    modlabels = Label.Set.empty;
    objlabels = Label.Set.empty;
    sections = None;
    future_cst = HandleMap.empty;
    univ = Univ.ContextSet.empty;
    qualities = Sorts.QVar.Set.empty;
    loads = [];
    local_retroknowledge = [];
    opaquetab = Opaqueproof.empty_opaquetab;
  }

let export ~output_native_objects senv dir =
  let () = check_current_library dir senv in
  let mp = senv.modpath in
  let str = NoFunctor (List.rev senv.revstruct) in
  let mb = Mod_declarations.make_module_body str senv.modresolver senv.local_retroknowledge in
  let ast, symbols =
    if output_native_objects then
      Nativelibrary.dump_library mp senv.env str
    else [], Nativevalues.empty_symbols
  in
  let permanent_flags = {
    rewrite_rules_allowed = Environ.rewrite_rules_allowed senv.env;
  } in
  let filter_dep (dp, { req_root; req_digest }) =
    if req_root then Some (dp, req_digest) else None
  in
  let comp_deps = List.map_filter filter_dep (DirPath.Map.bindings senv.required) in
  let lib = {
    comp_name = dir;
    comp_mod = mb;
    comp_univs = senv.univ;
    comp_qualities = senv.qualities;
    comp_deps = Array.of_list comp_deps;
    comp_flags = permanent_flags
  } in
  let vmlib = Vmlibrary.export @@ Environ.vm_library senv.env in
  mp, lib, vmlib, (ast, symbols)

let import lib vmtab vodigest senv =
  let senv = check_flags_for_library lib senv in
  let required = check_required senv.required lib.comp_deps in
  if DirPath.equal (ModPath.dp senv.modpath) lib.comp_name then
    CErrors.user_err
      Pp.(strbrk "Cannot load a library with the same name as the current one ("
          ++ DirPath.print lib.comp_name ++ str").");
  let mp = MPfile lib.comp_name in
  let mb = lib.comp_mod in
  let env = Environ.push_context_set ~strict:true lib.comp_univs senv.env in
  let env = Environ.link_vm_library vmtab env in
  let env = Environ.push_quality_set lib.comp_qualities env in
  let env =
    let linkinfo = Nativecode.link_info_of_dirpath lib.comp_name in
    Modops.add_linked_module mp mb linkinfo env
  in
  let sections =
    Option.map (Section.map_custom (fun custom ->
        {custom with rev_reimport = (lib,vmtab,vodigest) :: custom.rev_reimport}))
      senv.sections
  in
  let required =
    if DirPath.Map.mem lib.comp_name required then
      (* should probably be an error, we are requiring the same library twice *)
      required
    else DirPath.Map.add lib.comp_name { req_root = true; req_digest = vodigest } required
  in
  mp,
  { senv with
    env;
    (* Do NOT store the name quotient from the dependencies in the set of
       constraints that will be marshalled on disk. *)
    paramresolver = ParamResolver.add_delta_resolver mp (mod_delta mb) senv.paramresolver;
    required;
    loads = (mp,mb)::senv.loads;
    sections;
  }

(** {6 Interactive sections *)

let open_section senv =
  let custom = {
    rev_env = senv.env;
    rev_univ = senv.univ;
    rev_qualities = senv.qualities;
    rev_objlabels = senv.objlabels;
    rev_reimport = [];
    rev_revstruct = senv.revstruct;
    rev_paramresolver = senv.paramresolver;
  } in
  let sections = Section.open_section ~custom senv.sections in
  { senv with sections=Some sections }

let close_section senv =
  let open Section in
  let sections0 = get_section senv.sections in
  let env0 = senv.env in
  (* First phase: revert the declarations added in the section *)
  let sections, entries, cstrs, qs, revert = Section.close_section sections0 in
  (* Don't revert the delayed constraints (future_cst). If some delayed constraints
     were forced inside the section, they have been turned into global monomorphic
     that are going to be replayed. Those that are not forced are not readded
     by {!add_constant_aux}. *)
  let { rev_env = env; rev_univ = univ; rev_qualities = qualities; rev_objlabels = objlabels;
        rev_reimport; rev_revstruct = revstruct; rev_paramresolver = paramresolver } = revert in
  let env = if Environ.rewrite_rules_allowed env0 then Environ.allow_rewrite_rules env else env in
  let senv = { senv with env; revstruct; sections; univ; qualities; objlabels; paramresolver } in
  (* Second phase: replay Requires *)
  let senv = List.fold_left (fun senv (lib,vmtab,vodigest) -> snd (import lib vmtab vodigest senv))
      senv (List.rev rev_reimport)
  in
  (* Third phase: replay the discharged section contents *)
  let senv = push_context_set ~strict:true cstrs senv in
  let senv = push_quality_set qs senv in
  let fold entry senv =
    match entry with
  | SecDefinition kn ->
    let cb = Environ.lookup_constant kn env0 in
    let info = Section.segment_of_constant kn sections0 in
    let cb = Discharge.cook_constant senv.env info cb in
    let cb = compile_bytecode senv.env cb in
    (* Delayed constants are already in the global environment *)
    add_constant_aux senv (kn, cb)
  | SecInductive ind ->
    let mib = Environ.lookup_mind ind env0 in
    let info = Section.segment_of_inductive ind sections0 in
    let mib = Discharge.cook_inductive info mib in
    add_checked_mind ind mib senv
  in
  List.fold_right fold entries senv

let flatten_env senv =
  let label = function MPdot (_,l) -> l | _ -> assert false in
  let rec close senv =
    match senv.modvariant with
    | STRUCT _ -> close (snd (end_module (label senv.modpath) None senv))
    | SIG (params,env) -> close (snd (end_module (label senv.modpath) None {senv with modvariant = STRUCT (params,env)}))
    | LIBRARY | NONE -> senv in
  let senv = close senv in
  (senv.modpath, senv.revstruct)

(** {6 Safe typing } *)

type judgment = {
  jdg_env : safe_environment;
  jdg_val : constr;
  jdg_type : types;
}

let typing senv c =
  let j = Typeops.infer (env_of_senv senv) c in
  { jdg_env = senv;
    jdg_val = j.Environ.uj_val;
    jdg_type = j.Environ.uj_type;
  }

(** {6 Retroknowledge / native compiler } *)

let register_inline kn senv =
  let open Environ in
  if not (evaluable_constant kn senv.env) then
    CErrors.user_err Pp.(str "Register inline: an evaluable constant is expected");
  let env = senv.env in
  let cb = lookup_constant kn env in
  let cb = {cb with const_inline_code = true} in
  let env = add_constant kn cb env in { senv with env}

let check_register_ind (type t) ind (r : t CPrimitives.prim_ind) env =
  let (mb,ob as spec) = Inductive.lookup_mind_specif env ind in
  let ind = match mb.mind_universes with
    | Polymorphic _ -> CErrors.user_err Pp.(str "A universe monomorphic inductive type is expected.")
    | Monomorphic -> Constr.UnsafeMonomorphic.mkInd ind
  in
  let check_if b msg =
    if not b then
      CErrors.user_err msg in
  check_if (Int.equal (Array.length mb.mind_packets) 1) Pp.(str "A non mutual inductive is expected.");
  check_if (not @@ Inductive.is_private spec) Pp.(str "A non-private inductive type is expected");
  let check_nparams n =
    check_if (Int.equal mb.mind_nparams n) Pp.(str "An inductive type with " ++ int n ++ str " parameters is expected")
  in
  let check_nconstr n =
    check_if (Int.equal (Array.length ob.mind_consnames) n)
      Pp.(str "an inductive type with " ++ int n ++ str " constructors is expected")
  in
  let check_name pos s =
    check_if (Id.equal ob.mind_consnames.(pos) (Id.of_string s))
      Pp.(str"the " ++ int (pos + 1) ++ str
       "th constructor does not have the expected name: " ++ str s) in
  let check_type pos t =
    check_if (Constr.equal t ob.mind_user_lc.(pos))
      Pp.(str"the " ++ int (pos + 1) ++ str
       "th constructor does not have the expected type") in
  let check_type_cte pos = check_type pos ind in
  match r with
  | CPrimitives.PIT_bool ->
    check_nparams 0;
    check_nconstr 2;
    check_name 0 "true";
    check_type_cte 0;
    check_name 1 "false";
    check_type_cte 1
  | CPrimitives.PIT_carry ->
    check_nparams 1;
    check_nconstr 2;
    let test_type pos =
      let c = ob.mind_user_lc.(pos) in
      let s = Pp.(str"the " ++ int (pos + 1) ++ str
              "th constructor does not have the expected type") in
      check_if (Constr.isProd c) s;
      let (_,d,cd) = Constr.destProd c in
      check_if (Constr.is_Type d) s;
      check_if
        (Constr.equal
                (mkProd (Context.anonR,mkRel 1, mkApp (ind,[|mkRel 2|])))
                cd)
        s in
    check_name 0 "C0";
    test_type 0;
    check_name 1 "C1";
    test_type 1;
  | CPrimitives.PIT_pair ->
    check_nparams 2;
    check_nconstr 1;
    check_name 0 "pair";
    let c = ob.mind_user_lc.(0) in
    let s =  Pp.str "the constructor does not have the expected type" in
    begin match Term.decompose_prod c with
      | ([_,b;_,a;_,_B;_,_A], codom) ->
        check_if (is_Type _A) s;
        check_if (is_Type _B) s;
        check_if (Constr.equal a (mkRel 2)) s;
        check_if (Constr.equal b (mkRel 2)) s;
        check_if (Constr.equal codom (mkApp (ind,[|mkRel 4; mkRel 3|]))) s
      | _ -> check_if false s
    end
  | CPrimitives.PIT_cmp ->
    check_nparams 0;
    check_nconstr 3;
    check_name 0 "Eq";
    check_type_cte 0;
    check_name 1 "Lt";
    check_type_cte 1;
    check_name 2 "Gt";
    check_type_cte 2
  | CPrimitives.PIT_f_cmp ->
    check_nconstr 4;
    check_name 0 "FEq";
    check_type_cte 0;
    check_name 1 "FLt";
    check_type_cte 1;
    check_name 2 "FGt";
    check_type_cte 2;
    check_name 3 "FNotComparable";
    check_type_cte 3
  | CPrimitives.PIT_f_class ->
    check_nconstr 9;
    check_name 0 "PNormal";
    check_type_cte 0;
    check_name 1 "NNormal";
    check_type_cte 1;
    check_name 2 "PSubn";
    check_type_cte 2;
    check_name 3 "NSubn";
    check_type_cte 3;
    check_name 4 "PZero";
    check_type_cte 4;
    check_name 5 "NZero";
    check_type_cte 5;
    check_name 6 "PInf";
    check_type_cte 6;
    check_name 7 "NInf";
    check_type_cte 7;
    check_name 8 "NaN";
    check_type_cte 8

let register_inductive ind prim senv =
  check_register_ind ind prim senv.env;
  let action = Retroknowledge.Register_ind(prim,ind) in
  add_retroknowledge action senv

let add_constraints c =
  add_constraints
    (Univ.ContextSet.add_constraints c Univ.ContextSet.empty)


(* NB: The next old comment probably refers to [propagate_loads] above.
   When a Require is done inside a module, we'll redo this require
   at the upper level after the module is ended, and so on.
   This is probably not a big deal anyway, since these Require's
   inside modules should be pretty rare. Maybe someday we could
   brutally forbid this tricky "feature"... *)

(* we have an inefficiency: Since loaded files are added to the
environment every time a module is closed, their components are
calculated many times. This could be avoided in several ways:

1 - for each file create a dummy environment containing only this
file's components, merge this environment with the global
environment, and store for the future (instead of just its type)

2 - create "persistent modules" environment table in Environ add put
loaded by side-effect once and for all (like it is done in OCaml).
Would this be correct with respect to undo's and stuff ?
*)

let set_strategy k l e = { e with env =
   (Environ.set_oracle e.env
      (Conv_oracle.set_strategy (Environ.oracle e.env) k l)) }
