(* Yoann Padioleau
 *
 * Copyright (C) 2019-2022 r2c
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * version 2.1 as published by the Free Software Foundation, with the
 * special exception on linking described in file license.txt.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
 * license.txt for more details.
 *)
open Common
module G = AST_generic
module MV = Metavariable

let logger = Logging.get_logger [ __MODULE__ ]

(*****************************************************************************)
(* Prelude *)
(*****************************************************************************)
(* Data structures to represent a Semgrep rule (=~ AST of a rule).
 *
 * See also Mini_rule.ml where formula and many other features disappear.
 *
 *)

(*****************************************************************************)
(* Position information *)
(*****************************************************************************)

(* This is similar to what we do in AST_generic to get precise
 * error location when a rule is malformed.
 *)
type tok = AST_generic.tok [@@deriving show, eq, hash]
type 'a wrap = 'a AST_generic.wrap [@@deriving show, eq, hash]

(* To help report pattern errors in simple mode in the playground *)
type 'a loc = {
  pattern : 'a;
  t : tok;
  path : string list; (* path to pattern in YAML rule *)
}
[@@deriving show, eq]

(*****************************************************************************)
(* Taint-specific types *)
(*****************************************************************************)

let default_source_label = "__SOURCE__"
let default_source_requires tok = G.L (G.Bool (true, tok)) |> G.e

let default_sink_requires tok =
  G.N (G.Id ((default_source_label, tok), G.empty_id_info ())) |> G.e

type taint_source = {
  source_formula : formula;
  label : string;
      (** The label to attach to the data.
  Alt: We could have an optional label instead, allow taint that is not labeled,
       and allow sinks that work for any kind of taint? *)
  source_requires : AST_generic.expr;
      (** A Boolean expression over taint labels, using Python syntax.
       The operators allowed are 'not', 'or', and 'and'. The expression is
       evaluated using the `Eval_generic` machinery.

       The expression that is being checked as a source must satisfy this in order
       to the label to be produced. Note that with 'requires' a taint source behaves
       a bit like a propagator. *)
}

and taint_sanitizer = {
  not_conflicting : bool;
      (** If [not_conflicting] is enabled, the sanitizer cannot conflict with
    a sink or a source (i.e., match the exact same range) otherwise
    it is filtered out. This allows to e.g. declare `$F(...)` as a sanitizer,
    to assume that any other function will handle tainted data safely.
    Without this, `$F(...)` would automatically sanitize any other function
    call acting as a sink or a source.

    THINK: In retrospective, I'm not sure this was a good idea. We should add
    an option to disable the assumption that function calls always propagate
    taint, and deprecate not-conflicting sanitizers. *)
  sanitizer_formula : formula;
}
(** Note that, with taint labels, we can attach a label "SANITIZED" to the data
 to flag that it has been sanitized... so do we still need sanitizers? I am not
 sure to be honest, I think we will have to gain some experience in using labels
 first. Sanitizers do allow you to completely remove taint from data, although I
 think that can be simulated with labels too. We could translate (internally)
 `pattern-sanitizers` as `pattern-sources` with a `"__SANITIZED__"` label, and
 then rewrite the `requires` of all sinks as `(...) not __SANITIZED__`. But
 not-conflicting sanitizers cannot be simulated that way. That said, I think we
 should replace not-conflicting sanitizers with some `options:`, because they are
 a bit confusing to use sometimes. *)

and taint_propagator = {
  propagate_formula : formula;
  from : MV.mvar wrap;
  to_ : MV.mvar wrap;
}
(** e.g. if we want to specify that adding tainted data to a `HashMap` makes the
 * `HashMap` tainted too, then "formula" could be `(HashMap $H).add($X)`,
 * with "from" being `$X` and "to" being `$H`. So if `$X` is tainted then `$H`
 * will also be marked as tainted. *)

and taint_sink = {
  sink_formula : formula;
  sink_requires : AST_generic.expr;
      (** A Boolean expression over taint labels. See also 'taint_source'.
     The sink will only trigger a finding if the data that reaches it
     has a set of labels attached that satisfies the 'requires'.  *)
}

and taint_spec = {
  sources : tok * taint_source list;
  propagators : taint_propagator list;
  sanitizers : taint_sanitizer list;
  sinks : tok * taint_sink list;
}

(* Method to combine extracted ranges within a file:
    - either treat them as separate files; or
    - concatentate them together
*)
and extract_reduction = Separate | Concat

and extract_spec = {
  formula : formula;
  reduce : extract_reduction;
  dst_lang : Xlang.t;
  extract : string;
}

(*****************************************************************************)
(* Formula (patterns boolean composition) *)
(*****************************************************************************)

(* Classic boolean-logic/set operators with text range set semantic.
 * The main complication is the handling of metavariables and especially
 * negation in the presence of metavariables.
 *
 * less? enforce invariant that Not can only appear in And?
 *)
and formula =
  (* pattern: and pattern-inside: are actually slightly different so
   * we need to keep the information around.
   * (see tests/OTHER/rules/inside.yaml)
   * The same is true for pattern-not and pattern-not-inside
   * (see tests/OTHER/rules/negation_exact.yaml)
   *)
  | P of Xpattern.t (* a leaf pattern *)
  | Inside of tok * formula
  | Taint of tok * taint_spec
  | And of conjunction
  | Or of tok * formula list
  (* There are currently restrictions on where a Not can appear in a formula.
   * It must be inside an And to be intersected with "positive" formula.
   * TODO? Could this change if we were moving to a different range semantic?
   *)
  | Not of tok * formula

(* The conjuncts must contain at least
 * one positive "term" (unless it's inside a CondNestedFormula, in which
 * case there is not such a restriction).
 * See also split_and().
 *)
and conjunction = {
  conj_tok : tok;
  (* pattern-inside:'s and pattern:'s *)
  conjuncts : formula list;
  (* metavariable-xyz:'s *)
  conditions : (tok * metavar_cond) list;
  (* focus-metavariable:'s *)
  focus : (tok * MV.mvar) list;
}

(* todo: try to remove this at some point, but difficult. See
 * https://github.com/returntocorp/semgrep/issues/1218
 *)
and metavar_cond =
  | CondEval of AST_generic.expr (* see Eval_generic.ml *)
  (* todo: at some point we should remove CondRegexp and have just
   * CondEval, but for now there are some
   * differences between using the matched text region of a metavariable
   * (which we use for MetavarRegexp) and using its actual value
   * (which we use for MetavarComparison), which translate to different
   * calls in Eval_generic.ml
   * update: this is also useful to keep separate from CondEval for
   * the "regexpizer" optimizer (see Analyze_rule.ml).
   *)
  | CondRegexp of MV.mvar * Xpattern.regexp * bool (* constant-propagation *)
  | CondAnalysis of MV.mvar * metavar_analysis_kind
  | CondNestedFormula of MV.mvar * Xlang.t option * formula

and metavar_analysis_kind = CondEntropy | CondReDoS [@@deriving show, eq]

(* extra conditions, usually on metavariable content *)
type extra =
  | MetavarRegexp of MV.mvar * Xpattern.regexp * bool
  | MetavarPattern of MV.mvar * Xlang.t option * formula
  | MetavarComparison of metavariable_comparison
  | MetavarAnalysis of MV.mvar * metavar_analysis_kind
(* old: | PatWherePython of string, but it was too dangerous.
 * MetavarComparison is not as powerful, but safer.
 *)

(* See also engine/Eval_generic.ml *)
and metavariable_comparison = {
  metavariable : MV.mvar option;
  comparison : AST_generic.expr;
  (* I don't think those are really needed; they can be inferred
   * from the values *)
  strip : bool option;
  base : int option;
}

(*****************************************************************************)
(* The rule *)
(*****************************************************************************)

(* TODO? just reuse Error_code.severity *)
type severity = Error | Warning | Info | Inventory | Experiment
[@@deriving show]

type 'mode rule_info = {
  (* MANDATORY fields *)
  id : rule_id wrap;
  mode : 'mode;
  message : string; (* Currently a dummy value for extract mode rules *)
  severity : severity; (* Currently a dummy value for extract mode rules *)
  languages : Xlang.t;
  (* OPTIONAL fields *)
  options : Config_semgrep.t option;
  (* deprecated? todo: parse them *)
  equivalences : string list option;
  fix : string option;
  fix_regexp : (Xpattern.regexp * int option * string) option;
  paths : paths option;
  (* ex: [("owasp", "A1: Injection")] but can be anything *)
  metadata : JSON.t option;
}

and rule_id = string

and paths = {
  (* not regexp but globs *)
  include_ : string list;
  exclude : string list;
}
[@@deriving show]

type search_mode = [ `Search of formula ] [@@deriving show]
type extract_mode = [ `Extract of extract_spec ] [@@deriving show]
type mode = [ search_mode | extract_mode ] [@@deriving show]
type search_rule = search_mode rule_info [@@deriving show]
type extract_rule = extract_mode rule_info [@@deriving show]
type rule = mode rule_info [@@deriving show]

(* alias *)
type t = rule [@@deriving show]
type rules = rule list [@@deriving show]

(*****************************************************************************)
(* Helpers *)
(*****************************************************************************)

let partition_rules (rules : rules) : search_rule list * extract_rule list =
  rules
  |> Common.partition_either (fun r ->
         match r.mode with
         | `Search _ as s -> Left { r with mode = s }
         | `Extract _ as e -> Right { r with mode = e })

(*****************************************************************************)
(* Error Management *)
(*****************************************************************************)

(* This is used to let the user know which rule the engine was using when
 * a Timeout or OutOfMemory exn occured.
 *)
let (last_matched_rule : rule_id option ref) = ref None

(* Those are recoverable errors; We can just skip the rules containing
 * those errors.
 * less: use a record
 * alt: put in Output_from_core.atd?
 *)
type invalid_rule_error = invalid_rule_error_kind * rule_id * Parse_info.t

and invalid_rule_error_kind =
  | InvalidLanguage of string (* the language string *)
  (* TODO: the Parse_info.t for InvalidPattern is not precise for now;
   * it corresponds to the start of the pattern *)
  | InvalidPattern of
      string (* pattern *)
      * Xlang.t
      * string (* exn *)
      * string list (* yaml path *)
  | InvalidRegexp of string (* PCRE error message *)
  | DeprecatedFeature of string (* e.g., pattern-where-python: *)
  | MissingPositiveTermInAnd
  | InvalidOther of string
[@@deriving show]

let string_of_invalid_rule_error_kind = function
  | InvalidLanguage language -> spf "invalid language %s" language
  | InvalidRegexp message -> spf "invalid regex %s" message
  (* coupling: this is actually intercepted in
   * Semgrep_error_code.exn_to_error to generate a PatternParseError instead
   * of a RuleParseError *)
  | InvalidPattern (pattern, xlang, message, _yaml_path) ->
      spf
        "Invalid pattern for %s: %s\n\
         ----- pattern -----\n\
         %s\n\
         ----- end pattern -----\n"
        (Xlang.to_string xlang) message pattern
  | MissingPositiveTermInAnd ->
      "you need at least one positive term (not just negations or conditions)"
  | DeprecatedFeature s -> spf "deprecated feature: %s" s
  | InvalidOther s -> s

(* General errors

   TODO: define one exception for all this because pattern-matching
   on exceptions has no exhaustiveness checking.
*)
exception InvalidRule of invalid_rule_error
exception InvalidYaml of string * Parse_info.t
exception DuplicateYamlKey of string * Parse_info.t
exception UnparsableYamlException of string
exception ExceededMemoryLimit of string

let string_of_invalid_rule_error ((kind, rule_id, pos) : invalid_rule_error) =
  spf "invalid rule %s, %s: %s" rule_id
    (Parse_info.string_of_info pos)
    (string_of_invalid_rule_error_kind kind)

(*
   Exception printers for Printexc.to_string.
*)
let opt_string_of_exn (exn : exn) =
  match exn with
  | InvalidRule x -> Some (string_of_invalid_rule_error x)
  | InvalidYaml (msg, pos) ->
      Some (spf "invalid YAML, %s: %s" (Parse_info.string_of_info pos) msg)
  | DuplicateYamlKey (key, pos) ->
      Some
        (spf "invalid YAML, %s: duplicate key %S"
           (Parse_info.string_of_info pos)
           key)
  | UnparsableYamlException s ->
      (* TODO: what's the string s? *)
      Some (spf "unparsable YAML: %s" s)
  | ExceededMemoryLimit s ->
      (* TODO: what's the string s? *)
      Some (spf "exceeded memory limit: %s" s)
  | _ -> None

(* to be called by the application's main() *)
let register_exception_printer () = Printexc.register_printer opt_string_of_exn

(*****************************************************************************)
(* Visitor/extractor *)
(*****************************************************************************)
(* currently used in Check_rule.ml metachecker *)
let rec visit_new_formula f formula =
  match formula with
  | P p -> f p
  | Inside (_, formula) -> visit_new_formula f formula
  | Taint (_, { sources; propagators; sanitizers; sinks }) ->
      let apply g l =
        Common.map (g (visit_new_formula f)) l |> ignore;
        ()
      in
      apply visit_source (sources |> snd);
      apply visit_propagate propagators;
      apply visit_sink (sinks |> snd);
      apply visit_sanitizer sanitizers;
      ()
  | Not (_, x) -> visit_new_formula f x
  | Or (_, xs)
  | And { conjuncts = xs; _ } ->
      xs |> List.iter (visit_new_formula f)

and visit_source f { source_formula; _ } = f source_formula
and visit_sink f { sink_formula; _ } = f sink_formula
and visit_propagate f { propagate_formula; _ } = f propagate_formula
and visit_sanitizer f { sanitizer_formula; _ } = f sanitizer_formula

(* used by the metachecker for precise error location *)
let tok_of_formula = function
  | And { conj_tok = t; _ }
  | Or (t, _)
  | Not (t, _) ->
      t
  | P p -> snd p.pstr
  | Inside (t, _) -> t
  | Taint (t, _) -> t

let kind_of_formula = function
  | P _ -> "pattern"
  | Or _
  | And _
  | Inside _
  | Taint _
  | Not _ ->
      "formula"

(*****************************************************************************)
(* Converters *)
(*****************************************************************************)

(* Substitutes `$MVAR` with `int($MVAR)` in cond. *)
(* This now changes all such metavariables. We expect in most cases there should
   just be one, anyways.
*)
let rewrite_metavar_comparison_strip cond =
  let visitor =
    Map_AST.mk_visitor
      {
        Map_AST.default_visitor with
        Map_AST.kexpr =
          (fun (k, _) e ->
            (* apply on children *)
            let e = k e in
            match e.G.e with
            | G.N (G.Id ((s, tok), _idinfo)) when Metavariable.is_metavar_name s
              ->
                let py_int = G.Id (("int", tok), G.empty_id_info ()) in
                G.Call (G.N py_int |> G.e, G.fake_bracket [ G.Arg e ]) |> G.e
            | _ -> e);
      }
  in
  visitor.Map_AST.vexpr cond

(* return list of "positive" x list of Not *)
let split_and : formula list -> formula list * (tok * formula) list =
 fun xs ->
  xs
  |> Common.partition_either (fun e ->
         match e with
         (* positives *)
         | P _
         | And _
         | Or _
         | Inside _
         | Taint _ ->
             Left e
         (* negatives *)
         | Not (tok, f) -> Right (tok, f))
