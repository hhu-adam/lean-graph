/-
Copyright (c) 2023 Scott Morrison. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Scott Morrison
-/
import Lean.Data.SMap
import Lean

/-!
Note: [TODO] This file contains random stuff copied from mathlib


# Additional functions on `Lean.Name`.

We provide `Name.getModule`,
and `allNames` and `allNamesByModule`.
-/


/-!
# Extra functions on Lean.SMap
-/

set_option autoImplicit true

open Lean Meta Elab

/-- Monadic fold over a staged map.

Copied from `Mathlib.Lean.SMap`-/
def Lean.SMap.foldM__importGraph {m : Type w → Type w} [Monad m] [BEq α] [Hashable α]
    (f : σ → α → β → m σ) (init : σ) (map : Lean.SMap α β) : m σ := do
  map.map₂.foldlM f (← map.map₁.foldM f init)

/-- Lean 4 makes declarations which are technically not internal
(that is, head string does not start with `_`) but which sometimes should
be treated as such. For example, the `to_additive` attribute needs to
transform `proof_1` constants generated by `Lean.Meta.mkAuxDefinitionFor`.
This might be better fixed in core, but until then, this method can act
as a polyfill. This method only looks at the name to decide whether it is probably internal.
Note: this declaration also occurs as `shouldIgnore` in the Lean 4 file `test/lean/run/printDecls`.

Note: copied from `Mathlib.Lean.Expr.Basic`
-/
def Lean.Name.isInternal'__importGraph (declName : Name) : Bool :=
  declName.isInternal ||
  match declName with
  | .str _ s => "match_".isPrefixOf s || "proof_".isPrefixOf s
  | _        => true


/-! The remaining section is copied from `Mathlib.Lean.Name` -/
namespace ImportGraph
open ImportGraph

private def isBlackListed (declName : Name) : CoreM Bool := do
  if declName.toString.startsWith "Lean" then return true
  let env ← getEnv
  pure $ declName.isInternal'__importGraph
   || isAuxRecursor env declName
   || isNoConfusion env declName
  <||> isRec declName <||> isMatcher declName

/--
Retrieve all names in the environment satisfying a predicate.
-/
def allNames (p : Name → Bool) : CoreM (Array Name) := do
  (← getEnv).constants.foldM__importGraph (init := #[]) fun names n _ => do
    if p n && !(← isBlackListed n) then
      return names.push n
    else
      return names

/--
Retrieve all names in the environment satisfying a predicate,
gathered together into a `HashMap` according to the module they are defined in.
-/
def allNamesByModule (p : Name → Bool) : CoreM (HashMap Name (Array Name)) := do
  (← getEnv).constants.foldM__importGraph (init := HashMap.empty) fun names n _ => do
    if p n && !(← isBlackListed n) then
      let some m ← findModuleOf? n | return names
      -- TODO use `Std.HashMap.modify` when we bump Std4 (or `alter` if that is written).
      match names.find? m with
      | some others => return names.insert m (others.push n)
      | none => return names.insert m #[n]
    else
      return names

/-- Returns the very first part of a name: for `Graph.Lean.Data.Set.Basic` it returns `Graph.Lean`. -/
def getModule (name : Name) (s := "") : Name :=
  match name with
    | .anonymous => s
    | .num _ _ => panic s!"panic in `getModule`: did not expect numerical name: {name}."
    | .str pre s => getModule pre s
