(* SuperMemo 17 *)

datatype MemoryUnitStatus =
    Stability      of int (* how long a memory can last if undisturbed and if not retrieved *)
  | Retrievability of int (* the probability of retrieving a memory at any given time since the last review *)
  | ItemDifficulty of int (* maximum possible stability increase mapped from 0..1, 0 is easiest, 1 is hardest item *)
  ;

datatype MemoryUnit =
  Status of MemoryUnitStatus

val StartupInterval = days 3.96

(* matrix between 1 and 0 *)
fun postLapseStabilities lapse retrievability =

fun isLapse grade = grade < 0.5

datatype MemoryUnitPhase = Learn | Review

fun interval Learn  1 = StartupInterval
  | interval Review 1 =  postLapseStabilities 


hill-

