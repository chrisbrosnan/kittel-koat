(*
  Main program for complexity analysis

  @author Stephan Falke

  Copyright 2010-2014 Stephan Falke

  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS,
  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
  See the License for the specific language governing permissions and
  limitations under the License.
*)

(* timeout stuff *)

let set_timer tsecs =
  ignore (Unix.setitimer Unix.ITIMER_REAL { Unix.it_interval = 0.0; Unix.it_value = tsecs })

exception Timeout

let handle_sigalrm signo =
  raise Timeout

let timed_run f arg1 arg2 arg3 tsecs defaultval =
  let oldsig = Sys.signal Sys.sigalrm (Sys.Signal_handle handle_sigalrm) in
    try
      set_timer tsecs;
      let res = f arg1 arg2 arg3 in
        set_timer 0.0;
        Sys.set_signal Sys.sigalrm oldsig;
        res
    with
      | Timeout ->
        (
          Sys.set_signal Sys.sigalrm oldsig;
          defaultval
        )

(* command line stuff *)

let combine = ref Simple.Ctrls
let filename = ref ""
let timeout = ref 0.0
let maxchaining = ref 15

let usage = "usage: " ^ Sys.argv.(0) ^ " <filename>"

let stringToCombine s printer =
  if s = "statements" then
    Simple.Stmts
  else if s = "controlpoints" then
    Simple.Ctrls
  else if s = "ifs-loops" then
    Simple.IfsLoops
  else if s = "loops" then
    Simple.Loops
  else
  (
    Printf.printf "%s\n" (Sys.argv.(0) ^ ": unknown combination method `" ^ s ^ "'.");
    printer ();
    exit 1
  )

IFDEF HAVE_Z3 THEN
let supportedSmtSolvers = ["yices";"yices2";"z3";"cvc4";"mathsat5";"z3-internal"]
ELSE
let supportedSmtSolvers = ["yices";"yices2";"z3";"cvc4";"mathsat5"]
END

let checkSmtSolver s printer =
  if Utils.contains supportedSmtSolvers s then
    s
  else
    (
      Printf.printf "%s\n" (Sys.argv.(0) ^ ": unknown SMT solver `" ^ s ^ "'.");
      printer ();
      exit 1
    )

let rec speclist =
  [
    ("-combine", Arg.String (fun s -> combine := stringToCombine s print_usage), "     - Set the combination method for Simple programs (statements/controlpoints/ifs-loops/loops)");
    ("--combine", Arg.String (fun s -> combine := stringToCombine s print_usage), "");
    ("-timeout", Arg.Set_float timeout, Printf.sprintf "     - Set the timeout (seconds, 0 = no timeout) [default %.2f]" !timeout);
    ("--timeout", Arg.Set_float timeout, "");
    ("-smt-solver", Arg.String (fun s -> Smt.setSolver (checkSmtSolver
s print_usage)), "  - Set the SMT solver (" ^ (String.concat "/" supportedSmtSolvers) ^ ")");
    ("--smt-solver", Arg.String (fun s -> Smt.setSolver (checkSmtSolver s print_usage)), "");
    ("-max-chaining", Arg.Set_int maxchaining, Printf.sprintf "- Set the maximum number of chaining processor applications [default %i]" !maxchaining);
    ("--max-chaining", Arg.Set_int maxchaining, "");
    ("-help", Arg.Unit (fun () -> print_usage (); exit 1), "        - Display this list of options");
    ("--help", Arg.Unit (fun () -> print_usage (); exit 1), "");
    ("-log", Arg.Int (fun i -> Log.logging_level := i), Printf.sprintf "         - Print live log (level 1) or debug (level 5) output during proof [default %i]" !Log.logging_level);
    ("--log", Arg.Int (fun i -> Log.logging_level := i), "");
    ("-version", Arg.Unit (fun () -> Printf.printf "KoAT\nCopyright 2010-2014 Stephan Falke\nVersion %s\n" Git_sha1.git_sha1; exit 1), "     - Display the version of this program");
    ("--version", Arg.Unit (fun () -> Printf.printf "KoAT\nCopyright 2010-2014 Stephan Falke\nVersion %s\n" Git_sha1.git_sha1; exit 1), "")
  ]
and print_usage () =
  Arg.usage speclist usage

(* main function *)

let main () =
  Arg.parse speclist (fun f -> filename := f) usage;
  if !filename = "" then
  (
    Printf.printf "%s\n" (Sys.argv.(0) ^ ": need a filename.");
    print_usage ();
    exit 1
  )
  else
    Log.init_timer ();
    let (startFun, cint) = Parser.parseCint !filename !combine in
      if Cint.isUnary cint then
        let tt = Cint.toTrs cint in
          Smt.smt_time := 0.0;
          let start = Unix.gettimeofday () in
            match if !timeout = 0.0 then (Cmeta.process tt !maxchaining startFun) else (timed_run Cmeta.process tt !maxchaining startFun !timeout None) with
              | None -> Printf.printf "MAYBE\n"
              | Some (c, proof) ->
                (
                  let stop = Unix.gettimeofday () in
                    Printf.printf "%s\n\n" (Complexity.toStringCompetitionStyle c);
                    Printf.printf "%s" (proof ());
                    Printf.printf "\n\n%s\n\n" ("Complexity upper bound " ^ (Complexity.toString c));
                    Printf.printf "Time: %.3f sec (SMT: %.3f sec)\n" (stop -. start) (!Smt.smt_time)
                )
      else
      (
        Smt.smt_time := 0.0;
        let start = Unix.gettimeofday () in
          match if !timeout = 0.0 then (Cintmeta.process cint !maxchaining startFun) else (timed_run Cintmeta.process cint !maxchaining startFun !timeout None) with
            | None -> Printf.printf "MAYBE\n"
            | Some (c, proof) ->
              (
                let stop = Unix.gettimeofday () in
                  Printf.printf "%s\n\n" (Complexity.toStringCompetitionStyle c);
                  Printf.printf "%s" (proof ());
                  Printf.printf "%s\n\n" ("Complexity upper bound " ^ (Complexity.toString c));
                  Printf.printf "Time: %.3f sec (SMT: %.3f sec)\n" (stop -. start) (!Smt.smt_time)
              )
      )

let _ = main ()
