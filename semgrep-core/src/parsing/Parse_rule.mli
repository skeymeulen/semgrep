(*s: semgrep/parsing/Parse_rule.mli *)

exception InvalidLanguage of Rule.rule_id * string * Parse_info.t

exception InvalidPatternException of string * string * string * string

exception InvalidRegexp of Rule.rule_id * string * Parse_info.t

exception InvalidRule of Rule.rule_id * string * Parse_info.t

exception InvalidYaml of string * Parse_info.t

(* may raise all the exns above *)
val parse : Common.filename -> Rule.rules

(* used also by Convert_rule.ml *)
val parse_metavar_cond :
  string Rule.wrap (* enclosing location *) ->
  string (* condition to parse *) ->
  AST_generic.expr

(* internals used by other parsers (e.g., Parse_mini_rule.ml) *)

val parse_severity : id:string Rule.wrap -> string Rule.wrap -> Rule.severity

val parse_pattern : id:string -> lang:Lang.t -> string -> Pattern.t

(*e: semgrep/parsing/Parse_rule.mli *)
