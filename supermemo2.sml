(*
  Algorithm SM-2
  Implemented by len@falken.directory
*)

fun min (a:real, b:real) = if a < b then a else b;

structure Repetition =
struct
  exception NotNat;
  datatype Type = Value of int;
  fun from (n:int) = if n < 0 then (raise NotNat) else (Value n);
end;

structure ResponseQuality =
struct
  val minimum = 0.0
  and maximum = 5.0
    ;
  exception ResponseQualityNotBetween0and5;
  datatype Type = Value of real;
  fun from (n:int)
    = if   n < (Real.floor minimum) orelse n > (Real.floor maximum)
      then raise ResponseQualityNotBetween0and5
      else Real.fromInt n
    ;
end;

structure EFactor =
struct
  val start   = 2.5;
  val minimum = 1.3;
  datatype Type = Value of real;
  fun next (Value current) (ResponseQuality.Value q)
    (* Original: = min(current+(0.1-(5.0-q)*(0.08+(5.0-q)*0.02)), minimum) *)
    = let val delta = ResponseQuality.maximum - q
      in  min(current+(0.1-delta*(0.08+delta*0.02)), minimum)
      end
    ;
end;

structure Item =
struct
  datatype Type = Value of string;
end;

structure MemoryUnit =
struct
  type Type = {
    repetition : Repetition.Type,
    ef         : EFactor.Type,
    item       : Item.Type
  };

  fun new (item:Item.Type) = {
    repetition = Repetition.Value 0,
    ef         = EFactor.Value    EFactor.start,
    item       = item
  };

  fun next { repetition = Repetition.Value r, ef = ef, item = item }
           (ResponseQuality.Value q)
    = {
        repetition = if   q < ((Real.fromInt o Real.round) (ResponseQuality.maximum / 2.0))
                     then Repetition.Value  0
                     else Repetition.Value (r+1),
        ef         = EFactor.next ef (ResponseQuality.Value q),
        item       = item
      }
    ;

  fun intervalAt (Repetition.Value 0) (              _ ) = 0.0
    | intervalAt (Repetition.Value 1) (              _ ) = 1.0
    | intervalAt (Repetition.Value 2) (              _ ) = 6.0
    | intervalAt (Repetition.Value n) (EFactor.Value ef)
      = (intervalAt (Repetition.Value (n-1)) (EFactor.Value ef)) * ef
    ;
end;


signature SuperMemo =
sig
  exception InvalidAddItemExists;

  type MemoryUnit;
  type Units = MemoryUnit list;

  val add    :Units -> MemoryUnit -> Units;
  val remove :Units -> MemoryUnit -> Units;
  val draw   :Units -> MemoryUnit;
  val answer :Units -> Item.Type -> MemoryUnit -> Units;
end;

structure SuperMemo2 :> SuperMemo =
struct
  exception InvalidAddItemExists;

  type MemoryUnit = MemoryUnit.Type;
  type Units = MemoryUnit list;

  fun add (units:Units) (Item.Value item)
    = if   (List.exists (fn { item = Item.Value e, ... } => e = item) units)
      then units
      else ((MemoryUnit.new (Item.Value item)) :: units)
    ;

  fun remove (units:Units) (Item.Value item)
    = List.filter (fn { item = Item.Value e, ... } => e <> item) units
    ;

  fun answer units (Item.Value item) drawnUnit =
  add (remove units drawnUnit) 
end;
