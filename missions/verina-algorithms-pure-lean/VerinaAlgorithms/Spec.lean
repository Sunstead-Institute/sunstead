import Std.Data.HashMap

set_option linter.unusedVariables false

/-!
Frozen verbatim upstream implementations, preconditions, postconditions, and target propositions
for `verina-algorithms-pure-lean` (`sunblaze-ucb/verina@66b3ce5014ed`, Apache-2.0, pure Lean 4 with zero Mathlib).
-/

namespace VerinaAdv1

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux
def filterlist (x : Int) (nums : List Int) : List Int :=
  let rec aux (lst : List Int) : List Int :=
    match lst with
    | []      => []
    | y :: ys => if y = x then y :: aux ys else aux ys
  aux nums
-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def FindSingleNumber_precond (nums : List Int) : Prop :=
  -- !benchmark @start precond
  let numsCount := nums.map (fun x => nums.count x)
  numsCount.all (fun count => count = 1 ∨ count = 2) ∧ numsCount.count 1 = 1
  -- !benchmark @end precond


-- !benchmark @start code_aux
-- !benchmark @end code_aux


def FindSingleNumber (nums : List Int) (h_precond : FindSingleNumber_precond (nums)) : Int :=
  -- !benchmark @start code
  let rec findUnique (remaining : List Int) : Int :=
    match remaining with
    | [] =>
      0
    | x :: xs =>
      let filtered : List Int :=
        filterlist x nums
      let count : Nat :=
        filtered.length
      if count = 1 then
        x
      else
        findUnique xs
  findUnique nums
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def FindSingleNumber_postcond (nums : List Int) (result: Int) (h_precond : FindSingleNumber_precond (nums)) : Prop :=
  -- !benchmark @start postcond
  (nums.length > 0)
  ∧
  ((filterlist result nums).length = 1)
  ∧
  (∀ (x : Int),
    x ∈ nums →
    (x = result) ∨ ((filterlist x nums).length = 2))
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (nums: List Int) (h_precond : FindSingleNumber_precond (nums)),
    FindSingleNumber_postcond (nums) (FindSingleNumber (nums) h_precond) h_precond

end VerinaAdv1

namespace VerinaAdv5

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux
def listToNat : List Nat → Nat
| []       => 0
| d :: ds  => d + 10 * listToNat ds
-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def addTwoNumbers_precond (l1 : List Nat) (l2 : List Nat) : Prop :=
  -- !benchmark @start precond
  l1.length > 0 ∧ l2.length > 0 ∧
  (∀ d ∈ l1, d < 10) ∧ (∀ d ∈ l2, d < 10) ∧
  (l1.getLast! ≠ 0 ∨ l1 = [0]) ∧
  (l2.getLast! ≠ 0 ∨ l2 = [0])
  -- !benchmark @end precond


-- !benchmark @start code_aux
-- !benchmark @end code_aux


def addTwoNumbers (l1 : List Nat) (l2 : List Nat) (h_precond : addTwoNumbers_precond (l1) (l2)) : List Nat :=
  -- !benchmark @start code
  let rec addAux (l1 l2 : List Nat) (carry : Nat) : List Nat :=
    match l1, l2 with
    | [], [] =>
      if carry = 0 then [] else [carry]
    | h1::t1, [] =>
      let sum := h1 + carry
      (sum % 10) :: addAux t1 [] (sum / 10)
    | [], h2::t2 =>
      let sum := h2 + carry
      (sum % 10) :: addAux [] t2 (sum / 10)
    | h1::t1, h2::t2 =>
      let sum := h1 + h2 + carry
      (sum % 10) :: addAux t1 t2 (sum / 10)
  addAux l1 l2 0
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def addTwoNumbers_postcond (l1 : List Nat) (l2 : List Nat) (result: List Nat) (h_precond : addTwoNumbers_precond (l1) (l2)) : Prop :=
  -- !benchmark @start postcond
  listToNat result = listToNat l1 + listToNat l2 ∧
  (∀ d ∈ result, d < 10) ∧
  -- No leading zeros unless the result is zero
  (result.getLast! ≠ 0 ∨ (l1 = [0] ∧ l2 = [0] ∧ result = [0]))
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (l1: List Nat) (l2: List Nat) (h_precond : addTwoNumbers_precond (l1) (l2)),
    addTwoNumbers_postcond (l1) (l2) (addTwoNumbers (l1) (l2) h_precond) h_precond

end VerinaAdv5

namespace VerinaAdv11

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible, simp]
def findMajorityElement_precond (lst : List Int) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux
def countOccurrences (n : Int) (lst : List Int) : Nat :=
  lst.foldl (fun acc x => if x = n then acc + 1 else acc) 0
-- !benchmark @end code_aux


def findMajorityElement (lst : List Int) (h_precond : findMajorityElement_precond (lst)) : Int :=
  -- !benchmark @start code
  let n := lst.length
  let majority := lst.find? (fun x => countOccurrences x lst > n / 2)
  match majority with
  | some x => x
  | none => -1
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible, simp]
def findMajorityElement_postcond (lst : List Int) (result: Int) (h_precond : findMajorityElement_precond (lst)) : Prop :=
  -- !benchmark @start postcond
  let count := fun x => (lst.filter (fun y => y = x)).length
  let n := lst.length
  let majority := count result > n / 2 ∧ lst.all (fun x => count x ≤ n / 2 ∨ x = result)
  (result = -1 → lst.all (count · ≤ n / 2) ∨ majority) ∧
  (result ≠ -1 → majority)
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (lst: List Int) (h_precond : findMajorityElement_precond (lst)),
    findMajorityElement_postcond (lst) (findMajorityElement (lst) h_precond) h_precond

end VerinaAdv11

namespace VerinaAdv12

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def firstDuplicate_precond (lst : List Int) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def firstDuplicate (lst : List Int) (h_precond : firstDuplicate_precond (lst)) : Option Int :=
  -- !benchmark @start code
  let rec helper (seen : List Int) (rem : List Int) : Option Int :=
    match rem with
    | [] => none
    | h :: t => if seen.contains h then some h else helper (h :: seen) t
  helper [] lst
  -- !benchmark @end code


-- !benchmark @start postcond_aux
def secondOccIdx (lst : List Int) (v : Int) : Nat :=
  let first := lst.idxOf v
  first + 1 + (lst.drop (first + 1)).idxOf v
-- !benchmark @end postcond_aux


@[reducible]
def firstDuplicate_postcond (lst : List Int) (result: Option Int) (h_precond : firstDuplicate_precond (lst)) : Prop :=
  -- !benchmark @start postcond
  match result with
  | none => List.Nodup lst
  | some x =>
      lst.count x > 1 ∧
      lst.all (fun y => (lst.count y = 1) ∨ (secondOccIdx lst x ≤ secondOccIdx lst y))
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (lst: List Int) (h_precond : firstDuplicate_precond (lst)),
    firstDuplicate_postcond (lst) (firstDuplicate (lst) h_precond) h_precond

end VerinaAdv12

namespace VerinaAdv14

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def ifPowerOfFour_precond (n : Nat) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def ifPowerOfFour (n : Nat) (h_precond : ifPowerOfFour_precond (n)) : Bool :=
  -- !benchmark @start code
  let rec helper (n : Nat) : Bool :=
    match n with
    | 0 =>
      false
    | Nat.succ m =>
      match m with
      | 0 =>
        true
      | Nat.succ l =>
        if (l+2)%4=0 then
          helper ((l+2)/4)
        else
          false
  helper n
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def ifPowerOfFour_postcond (n : Nat) (result: Bool) (h_precond : ifPowerOfFour_precond (n)) : Prop :=
  -- !benchmark @start postcond
  result ↔ (∃ m:Nat, n=4^m)
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (n: Nat) (h_precond : ifPowerOfFour_precond (n)),
    ifPowerOfFour_postcond (n) (ifPowerOfFour (n) h_precond) h_precond

end VerinaAdv14

namespace VerinaAdv15

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def increasingTriplet_precond (nums : List Int) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def increasingTriplet (nums : List Int) (h_precond : increasingTriplet_precond (nums)) : Bool :=
  -- !benchmark @start code
  if nums.length < 3 then
    false
  else
    let rec loop (xs : List Int) (first : Option Int) (second : Option Int) : Bool :=
    match xs with
    | [] => false
    | x :: rest =>
      match first with
      | none => loop rest (some x) none
      | some f =>
        if x ≤ f then loop rest (some x) second
        else match second with
        | none => loop rest first (some x)
        | some s =>
          if x ≤ s then loop rest first (some x)
          else true
  loop nums none none
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def increasingTriplet_postcond (nums : List Int) (result: Bool) (h_precond : increasingTriplet_precond (nums)) : Prop :=
  -- !benchmark @start postcond
  let nums' := nums.zipIdx
  (result →
    nums'.any (fun (x, i) =>
      nums'.any (fun (y, j) =>
        nums'.any (fun (z, k) =>
          i < j ∧ j < k ∧ x < y ∧ y < z
        )
      )
    ))
  ∧
  (¬ result → nums'.all (fun (x, i) =>
    nums'.all (fun (y, j) =>
      nums'.all (fun (z, k) =>
        i ≥ j ∨ j ≥ k ∨ x ≥ y ∨ y ≥ z
      )
    )
  ))
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (nums: List Int) (h_precond : increasingTriplet_precond (nums)),
    increasingTriplet_postcond (nums) (increasingTriplet (nums) h_precond) h_precond

end VerinaAdv15

namespace VerinaAdv16

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def insertionSort_precond (xs : List Int) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def insertionSort (xs : List Int) (h_precond : insertionSort_precond (xs)) : List Int :=
  -- !benchmark @start code
    let rec insert (x : Int) (ys : List Int) : List Int :=
      match ys with
      | []      => [x]
      | y :: ys' =>
        if x <= y then
          x :: y :: ys'
        else
          y :: insert x ys'

    let rec sort (arr : List Int) : List Int :=
      match arr with
      | []      => []
      | x :: xs => insert x (sort xs)

    sort xs
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def insertionSort_postcond (xs : List Int) (result: List Int) (h_precond : insertionSort_precond (xs)) : Prop :=
  -- !benchmark @start postcond
  List.Pairwise (· ≤ ·) result ∧ List.isPerm xs result
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (xs: List Int) (h_precond : insertionSort_precond (xs)),
    insertionSort_postcond (xs) (insertionSort (xs) h_precond) h_precond

end VerinaAdv16

namespace VerinaAdv19

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux
-- Check if a character is an uppercase alphabet letter
def isUpperAlpha (c : Char) : Bool :=
  'A' ≤ c ∧ c ≤ 'Z'

-- Check if a character is a lowercase alphabet letter
def isLowerAlpha (c : Char) : Bool :=
  'a' ≤ c ∧ c ≤ 'z'

-- Determine if a character is alphabetic
def isAlpha (c : Char) : Bool :=
  isUpperAlpha c ∨ isLowerAlpha c

-- Convert a single character to lowercase
def toLower (c : Char) : Char :=
  if isUpperAlpha c then Char.ofNat (c.toNat + 32) else c

-- Normalize a character: keep only lowercase letters
def normalizeChar (c : Char) : Option Char :=
  if isAlpha c then some (toLower c) else none

-- Normalize a string into a list of lowercase alphabetic characters
def normalizeString (s : String) : List Char :=
  s.toList.foldr (fun c acc =>
    match normalizeChar c with
    | some c' => c' :: acc
    | none    => acc
  ) []
-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def isCleanPalindrome_precond (s : String) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux
-- Reverse the list
def reverseList (xs : List Char) : List Char :=
  xs.reverse
-- !benchmark @end code_aux


def isCleanPalindrome (s : String) (h_precond : isCleanPalindrome_precond (s)) : Bool :=
  -- !benchmark @start code
  let norm := normalizeString s
  norm = reverseList norm
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def isCleanPalindrome_postcond (s : String) (result: Bool) (h_precond : isCleanPalindrome_precond (s)) : Prop :=
  -- !benchmark @start postcond
  let norm := normalizeString s
  (result = true → norm = norm.reverse) ∧
  (result = false → norm ≠ norm.reverse)
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (s: String) (h_precond : isCleanPalindrome_precond (s)),
    isCleanPalindrome_postcond (s) (isCleanPalindrome (s) h_precond) h_precond

end VerinaAdv19

namespace VerinaAdv20

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def isItEight_precond (n : Int) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def isItEight (n : Int) (h_precond : isItEight_precond (n)) : Bool :=
  -- !benchmark @start code
  let rec hasDigitEight (m : Nat) : Bool :=
    if m <= 0 then false
    else if m % 10 == 8 then true
    else hasDigitEight (m / 10)
    termination_by m

  let absN := Int.natAbs n
  n % 8 == 0 || hasDigitEight absN
  -- !benchmark @end code

-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def isItEight_postcond (n : Int) (result: Bool) (h_precond : isItEight_precond (n)) : Prop :=
  -- !benchmark @start postcond
  let absN := Int.natAbs n;
  (n % 8 == 0 ∨ ∃ i, absN / (10^i) % 10 == 8) ↔ result
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (n: Int) (h_precond : isItEight_precond (n)),
    isItEight_postcond (n) (isItEight (n) h_precond) h_precond

end VerinaAdv20

namespace VerinaAdv21

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible, simp]
def isPalindrome_precond (s : String) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def isPalindrome (s : String) (h_precond : isPalindrome_precond (s)) : Bool :=
  -- !benchmark @start code
  let length := s.length

if length <= 1 then
  true
else
  let arr := s.toList

  let rec checkIndices (left : Nat) (right : Nat) (chars : List Char) : Bool :=
    if left >= right then
      true
    else
      match chars[left]?, chars[right]? with
      | some cLeft, some cRight =>
        if cLeft == cRight then
          checkIndices (left + 1) (right - 1) chars
        else
          false
      | _, _ => false
  let approach1 := checkIndices 0 (length - 1) arr

  let rec reverseList (acc : List Char) (xs : List Char) : List Char :=
    match xs with
    | []      => acc
    | h :: t  => reverseList (h :: acc) t
  let reversed := reverseList [] arr
  let approach2 := (arr == reversed)

  approach1 && approach2
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible, simp]
def isPalindrome_postcond (s : String) (result: Bool) (h_precond : isPalindrome_precond (s)) : Prop :=
  -- !benchmark @start postcond
  (result → (s.toList == s.toList.reverse)) ∧
  (¬ result → (s.toList ≠ [] ∧ s.toList != s.toList.reverse))
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (s: String) (h_precond : isPalindrome_precond (s)),
    isPalindrome_postcond (s) (isPalindrome (s) h_precond) h_precond

end VerinaAdv21

namespace VerinaAdv23

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def isPowerOfTwo_precond (n : Int) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def isPowerOfTwo (n : Int) (h_precond : isPowerOfTwo_precond (n)) : Bool :=
  -- !benchmark @start code
  if n <= 0 then false
  else
    let rec aux (m : Int) (fuel : Nat) : Bool :=
      if fuel = 0 then false
      else if m = 1 then true
      else if m % 2 ≠ 0 then false
      else aux (m / 2) (fuel - 1)
    aux n n.natAbs
  -- !benchmark @end code


-- !benchmark @start postcond_aux
def pow (base : Int) (exp : Nat) : Int :=
  match exp with
  | 0 => 1
  | n+1 => base * pow base n
-- !benchmark @end postcond_aux


@[reducible]
def isPowerOfTwo_postcond (n : Int) (result: Bool) (h_precond : isPowerOfTwo_precond (n)) : Prop :=
  -- !benchmark @start postcond
  if result then ∃ (x : Nat), (pow 2 x = n) ∧ (n > 0)
  else ¬ (∃ (x : Nat), (pow 2 x = n) ∧ (n > 0))
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (n: Int) (h_precond : isPowerOfTwo_precond (n)),
    isPowerOfTwo_postcond (n) (isPowerOfTwo (n) h_precond) h_precond

end VerinaAdv23

namespace VerinaAdv24

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible, simp]
def lengthOfLIS_precond (nums : List Int) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def lengthOfLIS (nums : List Int) (h_precond : lengthOfLIS_precond (nums)) : Int :=
  -- !benchmark @start code
  let rec lisHelper (dp : List Int) (x : Int) : List Int :=
    let rec replace (l : List Int) (acc : List Int) : List Int :=
      match l with
      | [] => (acc.reverse ++ [x])
      | y :: ys => if x ≤ y then acc.reverse ++ (x :: ys) else replace ys (y :: acc)
    replace dp []

  let finalDP := nums.foldl lisHelper []
  finalDP.length
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible, simp]
def lengthOfLIS_postcond (nums : List Int) (result: Int) (h_precond : lengthOfLIS_precond (nums)) : Prop :=
  -- !benchmark @start postcond
  -- Helper function to check strictly increasing
  let rec isStrictlyIncreasing (l : List Int) : Bool :=
    match l with
    | [] | [_] => true
    | x :: y :: rest => x < y && isStrictlyIncreasing (y :: rest)

  -- Generate all subsequences
  let rec subsequences (xs : List Int) : List (List Int) :=
    match xs with
    | [] => [[]]
    | x :: xs' =>
      let rest := subsequences xs'
      rest ++ rest.map (fun r => x :: r)

  let allIncreasing := subsequences nums |>.filter (fun l => isStrictlyIncreasing l)

  allIncreasing.any (fun l => l.length = result) ∧
  allIncreasing.all (fun l => l.length ≤ result)
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (nums: List Int) (h_precond : lengthOfLIS_precond (nums)),
    lengthOfLIS_postcond (nums) (lengthOfLIS (nums) h_precond) h_precond

end VerinaAdv24

namespace VerinaAdv26

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux
def digitToLetters (c : Char) : List Char :=
  match c with
  | '2' => ['a', 'b', 'c']
  | '3' => ['d', 'e', 'f']
  | '4' => ['g', 'h', 'i']
  | '5' => ['j', 'k', 'l']
  | '6' => ['m', 'n', 'o']
  | '7' => ['p', 'q', 'r', 's']
  | '8' => ['t', 'u', 'v']
  | '9' => ['w', 'x', 'y', 'z']
  | _ => []
-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def letterCombinations_precond (digits : String) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux
-- !benchmark @end code_aux


def letterCombinations (digits : String) (h_precond : letterCombinations_precond (digits)) : List String :=
  -- !benchmark @start code
  let chars := digits.toList
  -- Return [] if any invalid digit exists
  if chars.any (fun c => digitToLetters c == []) then []
  else go chars
  where
    go : List Char → List String
    | [] => []
    | (d :: ds) =>
      let restCombinations := go ds
      let currentLetters := digitToLetters d
      match restCombinations with
      | [] => currentLetters.map (λ c => String.singleton c)
      | _ => currentLetters.flatMap (λ c => restCombinations.map (λ s => String.singleton c ++ s))
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def letterCombinations_postcond (digits : String) (result: List String) (h_precond : letterCombinations_precond (digits)) : Prop :=
  -- !benchmark @start postcond
  if digits.isEmpty then
    result = []
  else if digits.toList.any (λ c => ¬(c ∈ ['2','3','4','5','6','7','8','9'])) then
    result = []
  else
    let expected := digits.toList.map digitToLetters |>.foldl (λ acc ls => acc.flatMap (λ s => ls.map (λ c => s ++ String.singleton c)) ) [""]
    result.length = expected.length ∧ result.all (λ s => s ∈ expected) ∧ expected.all (λ s => s ∈ result)
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (digits: String) (h_precond : letterCombinations_precond (digits)),
    letterCombinations_postcond (digits) (letterCombinations (digits) h_precond) h_precond

end VerinaAdv26

namespace VerinaAdv35

-- !benchmark @start import type=solution
-- !benchmark @end import

-- !benchmark @start solution_aux
open Std
-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def majorityElement_precond (nums : List Int) : Prop :=
  -- !benchmark @start precond
  nums.length > 0 ∧ nums.any (fun x => nums.count x > nums.length / 2)
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def majorityElement (nums : List Int) (h_precond : majorityElement_precond (nums)) : Int :=
  -- !benchmark @start code
  Id.run do
    let mut counts : HashMap Int Nat := {}
    let n := nums.length
    for x in nums do
      let count := counts.getD x 0
      counts := counts.insert x (count + 1)
    match counts.toList.find? (fun (_, c) => c > n / 2) with
    | some (k, _) => k
    | none      => 0
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def majorityElement_postcond (nums : List Int) (result: Int) (h_precond : majorityElement_precond (nums)) : Prop :=
  -- !benchmark @start postcond
  let n := nums.length
  (nums.count result) > n / 2
  ∧ ∀ x ∈ nums, x ≠ result → nums.count x ≤ n / 2
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (nums: List Int) (h_precond : majorityElement_precond (nums)),
    majorityElement_postcond (nums) (majorityElement (nums) h_precond) h_precond

end VerinaAdv35

namespace VerinaAdv39

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible, simp]
def maxOfList_precond (lst : List Nat) : Prop :=
  -- !benchmark @start precond
  lst.length > 0
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def maxOfList (lst : List Nat) (h_precond : maxOfList_precond (lst)) : Nat :=
  -- !benchmark @start code
  let rec helper (lst : List Nat) : Nat :=
    match lst with
    | [] => 0  -- technically shouldn't happen if input is always non-empty
    | [x] => x
    | x :: xs =>
      let maxTail := helper xs
      if x > maxTail then x else maxTail

  helper lst
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible, simp]
def maxOfList_postcond (lst : List Nat) (result: Nat) (h_precond : maxOfList_precond (lst)) : Prop :=
  -- !benchmark @start postcond
  result ∈ lst ∧ ∀ x ∈ lst, x ≤ result
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (lst: List Nat) (h_precond : maxOfList_precond (lst)),
    maxOfList_postcond (lst) (maxOfList (lst) h_precond) h_precond

end VerinaAdv39

namespace VerinaAdv41

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def maxOfThree_precond (a : Int) (b : Int) (c : Int) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def maxOfThree (a : Int) (b : Int) (c : Int) (h_precond : maxOfThree_precond (a) (b) (c)) : Int :=
  -- !benchmark @start code
  if a >= b && a >= c then a
  else if b >= a && b >= c then b
  else c
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def maxOfThree_postcond (a : Int) (b : Int) (c : Int) (result: Int) (h_precond : maxOfThree_precond (a) (b) (c)) : Prop :=
  -- !benchmark @start postcond
  (result >= a ∧ result >= b ∧ result >= c) ∧ (result = a ∨ result = b ∨ result = c)
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (a: Int) (b: Int) (c: Int) (h_precond : maxOfThree_precond (a) (b) (c)),
    maxOfThree_postcond (a) (b) (c) (maxOfThree (a) (b) (c) h_precond) h_precond

end VerinaAdv41

namespace VerinaAdv45

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible, simp]
def maxSubarraySum_precond (xs : List Int) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def maxSubarraySum (xs : List Int) (h_precond : maxSubarraySum_precond (xs)) : Int :=
  -- !benchmark @start code
  let rec helper (lst : List Int) (curMax : Int) (globalMax : Int) : Int :=
    match lst with
    | [] => globalMax
    | x :: rest =>
      let newCurMax := max x (curMax + x)
      let newGlobal := max globalMax newCurMax
      helper rest newCurMax newGlobal
  match xs with
  | [] => 0
  | x :: rest => helper rest x x
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible, simp]
def maxSubarraySum_postcond (xs : List Int) (result: Int) (h_precond : maxSubarraySum_precond (xs)) : Prop :=
  -- !benchmark @start postcond
  -- Find all possible subarrays and their sums
  let subarray_sums := List.range (xs.length + 1) |>.flatMap (fun start =>
    List.range' 1 (xs.length - start) |>.map (fun len =>
      ((xs.drop start).take len).sum
    ))

  -- Check if there exists a subarray with sum equal to result
  let has_result_subarray := subarray_sums.any (fun sum => sum == result)


  -- Check if result is the maximum among all subarray sums
  let is_maximum := subarray_sums.all (· ≤ result)

  match xs with
  | [] => result == 0
  | _ => has_result_subarray ∧ is_maximum
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (xs: List Int) (h_precond : maxSubarraySum_precond (xs)),
    maxSubarraySum_postcond (xs) (maxSubarraySum (xs) h_precond) h_precond

end VerinaAdv45

namespace VerinaAdv47

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible, simp]
def mergeIntervals_precond (intervals : List (Prod Int Int)) : Prop :=
  -- !benchmark @start precond
  intervals.all (fun (s, e) => s ≤ e)
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def mergeIntervals (intervals : List (Prod Int Int)) (h_precond : mergeIntervals_precond (intervals)) : List (Prod Int Int) :=
  -- !benchmark @start code
  -- Insertion sort based on the start of intervals
  let rec insert (x : Prod Int Int) (sorted : List (Prod Int Int)) : List (Prod Int Int) :=
    match sorted with
    | [] => [x]
    | y :: ys => if x.fst ≤ y.fst then x :: sorted else y :: insert x ys

  let rec sort (xs : List (Prod Int Int)) : List (Prod Int Int) :=
    match xs with
    | [] => []
    | x :: xs' => insert x (sort xs')

  let sorted := sort intervals

  -- Merge sorted intervals
  let rec merge (xs : List (Prod Int Int)) (acc : List (Prod Int Int)) : List (Prod Int Int) :=
    match xs, acc with
    | [], _ => acc.reverse
    | (s, e) :: rest, [] => merge rest [(s, e)]
    | (s, e) :: rest, (ps, pe) :: accTail =>
      if s ≤ pe then
        merge rest ((ps, max pe e) :: accTail)
      else
        merge rest ((s, e) :: (ps, pe) :: accTail)

  merge sorted []
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible, simp]
def mergeIntervals_postcond (intervals : List (Prod Int Int)) (result: List (Prod Int Int)) (h_precond : mergeIntervals_precond (intervals)) : Prop :=
  -- !benchmark @start postcond
  -- Check that all original intervals are covered by some result interval
  let covered := intervals.all (fun (s, e) =>
    result.any (fun (rs, re) => rs ≤ s ∧ e ≤ re))

  -- Check that no intervals in the result overlap
  let rec noOverlap (l : List (Prod Int Int)) : Bool :=
    match l with
    | [] | [_] => true
    | (_, e1) :: (s2, e2) :: rest => e1 < s2 && noOverlap ((s2, e2) :: rest)

  let resultBounded := result.all (fun (rs, re) =>
    intervals.any (fun (s, _) => s = rs) ∧
    intervals.any (fun (_, e) => e = re))

  -- Check that no result interval spans a gap between non-overlapping inputs
  let noSpuriousMerge := result.all (fun (rs, re) =>
    (intervals.filter (fun (s, e) => rs ≤ s ∧ e ≤ re)).all (fun (s, _) =>
      s = rs ∨ intervals.any (fun (s2, e2) => rs ≤ s2 ∧ e2 ≤ re ∧ s2 < s ∧ e2 ≥ s)))

  covered ∧ noOverlap result ∧ resultBounded ∧ noSpuriousMerge
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (intervals: List (Prod Int Int)) (h_precond : mergeIntervals_precond (intervals)),
    mergeIntervals_postcond (intervals) (mergeIntervals (intervals) h_precond) h_precond

end VerinaAdv47

namespace VerinaAdv48

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible, simp]
def mergeSort_precond (list : List Int) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def mergeSort (list : List Int) (h_precond : mergeSort_precond (list)) : List Int :=
  -- !benchmark @start code
  -- Implementation using insertion sort instead of merge sort
  -- for simplicity and to avoid termination issues

  -- Helper to insert an element into a sorted list
  let rec insert (x : Int) (sorted : List Int) : List Int :=
    match sorted with
    | [] => [x]
    | y :: ys =>
        if x ≤ y then
          x :: sorted
        else
          y :: insert x ys
  termination_by sorted.length

  -- Main insertion sort function
  let rec sort (l : List Int) : List Int :=
    match l with
    | [] => []
    | x :: xs =>
        let sortedRest := sort xs
        insert x sortedRest
  termination_by l.length

  sort list
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible, simp]
def mergeSort_postcond (list : List Int) (result: List Int) (h_precond : mergeSort_precond (list)) : Prop :=
  -- !benchmark @start postcond
  List.Pairwise (· ≤ ·) result ∧ List.isPerm list result
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (list: List Int) (h_precond : mergeSort_precond (list)),
    mergeSort_postcond (list) (mergeSort (list) h_precond) h_precond

end VerinaAdv48

namespace VerinaAdv49

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def mergeSortedLists_precond (arr1 : List Int) (arr2 : List Int) : Prop :=
  -- !benchmark @start precond
  List.Pairwise (· ≤ ·) arr1 ∧ List.Pairwise (· ≤ ·) arr2
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def mergeSortedLists (arr1 : List Int) (arr2 : List Int) (h_precond : mergeSortedLists_precond (arr1) (arr2)) : List Int :=
  -- !benchmark @start code
  let rec merge (xs : List Int) (ys : List Int) : List Int :=
    match xs, ys with
    | [], _ => ys
    | _, [] => xs
    | x :: xt, y :: yt =>
      if x <= y then
        x :: merge xt (y :: yt)
      else
        y :: merge (x :: xt) yt

  merge arr1 arr2
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def mergeSortedLists_postcond (arr1 : List Int) (arr2 : List Int) (result: List Int) (h_precond : mergeSortedLists_precond (arr1) (arr2)) : Prop :=
  -- !benchmark @start postcond
  List.Pairwise (· ≤ ·) result ∧ List.isPerm (arr1 ++ arr2) result
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (arr1: List Int) (arr2: List Int) (h_precond : mergeSortedLists_precond (arr1) (arr2)),
    mergeSortedLists_postcond (arr1) (arr2) (mergeSortedLists (arr1) (arr2) h_precond) h_precond

end VerinaAdv49

namespace VerinaAdv53

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible, simp]
def minimumRightShifts_precond (nums : List Int) : Prop :=
  -- !benchmark @start precond
  List.Nodup nums
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def minimumRightShifts (nums : List Int) (h_precond : minimumRightShifts_precond (nums)) : Int :=
  -- !benchmark @start code
  let n := nums.length
  -- base cases: empty or single element list is already sorted
  if n <= 1 then 0 else

  -- local helper function to check if a list is sorted in ascending order
  let rec isSortedAux (l : List Int) : Bool :=
    match l with
    | [] => true       -- empty list is sorted
    | [_] => true      -- single element list is sorted
    | x :: y :: xs => if x <= y then isSortedAux (y :: xs) else false -- check pairwise

  -- check if the input list is already sorted
  if isSortedAux nums then 0 else

  -- local helper function to perform a single right shift
  -- assume the list `l` is non-empty based on the initial n > 1 check
  let rightShiftOnce (l : List Int) : List Int :=
     match l.reverse with
     | [] => [] -- should not happen for n > 1
     | last :: revInit => last :: revInit.reverse -- `last` is the original last element

  -- recursive function to check subsequent shifts
  -- `shifts_count` is the number of shifts already performed to get `current_list`
  -- we are checking if `current_list` is sorted
  let rec checkShifts (shifts_count : Nat) (current_list : List Int) : Int :=
    -- base case: stop recursion if we've checked n-1 shifts (count goes from 1 to n)
    -- the original list (0 shifts) has already been checked
    if shifts_count >= n then -1
    else
      -- check if the current state is sorted
      if isSortedAux current_list then
        (shifts_count : Int) -- found it after 'shifts_count' shifts
      else
        -- recursion: increment shift count, apply next shift
        checkShifts (shifts_count + 1) (rightShiftOnce current_list)
  -- specify the decreasing measure for the termination checker: n - shifts_count
  termination_by n - shifts_count

  -- start the checking process by performing the first shift and checking subsequent states
  -- the initial list (0 shifts) hass already been checked and is not sorted
  checkShifts 1 (rightShiftOnce nums) -- start checking from the state after 1 shift
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible, simp]
def minimumRightShifts_postcond (nums : List Int) (result: Int) (h_precond : minimumRightShifts_precond (nums)) : Prop :=
  -- !benchmark @start postcond
  let n := nums.length

  let isSorted (l : List Int) := List.Pairwise (· ≤ ·) l
  let rightShift (k : Nat) (l : List Int) := l.rotateRight k

  -- specification logic based on the result value
  if n <= 1 then result = 0 else -- specification for base cases

  -- case 1: a non-negative result means a solution was found
  (result ≥ 0 ∧
   -- result corresponds to a valid shift count result < n
   result < n ∧
   -- applying result shifts results in a sorted list
   isSorted (rightShift result.toNat nums) ∧
   -- result is the minimum such non-negative shift count
   (List.range result.toNat |>.all (fun j => ¬ isSorted (rightShift j nums)))
  ) ∨

  -- case 2: result is -1 means no solution exists within n shifts
  (result = -1 ∧
   -- for all possible shift counts k from 0 to n-1, the resulting list is not sorted
   (List.range n |>.all (fun k => ¬ isSorted (rightShift k nums)))
  )
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (nums: List Int) (h_precond : minimumRightShifts_precond (nums)),
    minimumRightShifts_postcond (nums) (minimumRightShifts (nums) h_precond) h_precond

end VerinaAdv53

namespace VerinaAdv54

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def missingNumber_precond (nums : List Nat) : Prop :=
  -- !benchmark @start precond
  nums.all (fun x => x ≤ nums.length) ∧ List.Nodup nums
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def missingNumber (nums : List Nat) (h_precond : missingNumber_precond (nums)) : Nat :=
  -- !benchmark @start code
  let n := nums.length
  let expectedSum := (n * (n + 1)) / 2
  let actualSum := nums.foldl (· + ·) 0
  expectedSum - actualSum
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def missingNumber_postcond (nums : List Nat) (result: Nat) (h_precond : missingNumber_precond (nums)) : Prop :=
  -- !benchmark @start postcond
  let n := nums.length
  (result ∈ List.range (n + 1)) ∧
  ¬(result ∈ nums) ∧
  ∀ x, (x ∈ List.range (n + 1)) → x ≠ result → x ∈ nums
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (nums: List Nat) (h_precond : missingNumber_precond (nums)),
    missingNumber_postcond (nums) (missingNumber (nums) h_precond) h_precond

end VerinaAdv54

namespace VerinaAdv55

-- !benchmark @start import type=solution
-- !benchmark @end import

-- !benchmark @start solution_aux
open Std
-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def mostFrequent_precond (xs : List Int) : Prop :=
  -- !benchmark @start precond
  xs ≠ []
  -- !benchmark @end precond


-- !benchmark @start code_aux
-- Build a frequency map from the list
def countMap (xs : List Int) : HashMap Int Nat :=
  let step := fun m x =>
    let current := m.getD x 0
    m.insert x (current + 1)
  let init := (HashMap.emptyWithCapacity : HashMap Int Nat)
  xs.foldl step init

-- Compute the maximum frequency in the map
def getMaxFrequency (m : HashMap Int Nat) : Nat :=
  let step := fun acc (_k, v) =>
    if v > acc then v else acc
  let init := 0
  m.toList.foldl step init

-- Extract all keys whose frequency == maxFreq
def getCandidates (m : HashMap Int Nat) (maxFreq : Nat) : List Int :=
  let isTarget := fun (_k, v) => v = maxFreq
  let extract := fun (k, _) => k
  m.toList.filter isTarget |>.map extract

-- Return the first candidate element from original list
def getFirstWithFreq (xs : List Int) (candidates : List Int) : Int :=
  match xs.find? (fun x => candidates.contains x) with
  | some x => x
  | none => 0
-- !benchmark @end code_aux


def mostFrequent (xs : List Int) (h_precond : mostFrequent_precond (xs)) : Int :=
  -- !benchmark @start code
  let freqMap := countMap xs
  let maxF := getMaxFrequency freqMap
  let candidates := getCandidates freqMap maxF
  getFirstWithFreq xs candidates
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def mostFrequent_postcond (xs : List Int) (result: Int) (h_precond : mostFrequent_precond (xs)) : Prop :=
  -- !benchmark @start postcond
  let count := fun x => xs.countP (fun y => y = x)
  result ∈ xs ∧
  xs.all (fun x => count x ≤ count result) ∧
  ((xs.filter (fun x => count x = count result)).head? = some result)
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (xs: List Int) (h_precond : mostFrequent_precond (xs)),
    mostFrequent_postcond (xs) (mostFrequent (xs) h_precond) h_precond

end VerinaAdv55

namespace VerinaAdv56

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def moveZeroes_precond (xs : List Int) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux
-- Count how many times a specific value appears in the list

-- !benchmark @end code_aux


def moveZeroes (xs : List Int) (h_precond : moveZeroes_precond (xs)) : List Int :=
  -- !benchmark @start code
  let nonzeros := xs.filter (fun x => x ≠ 0)
  let zeros := xs.filter (fun x => x = 0)
  nonzeros ++ zeros
  -- !benchmark @end code


-- !benchmark @start postcond_aux
def countVal (val : Int) : List Int → Nat
  | [] => 0
  | x :: xs =>
    let rest := countVal val xs
    if x = val then rest + 1 else rest

-- Check whether one list is a subsequence of another (preserving relative order)
def isSubsequence (xs ys : List Int) : Bool :=
  match xs, ys with
  | [], _ => true
  | _ :: _, [] => false
  | x :: xt, y :: yt =>
    if x = y then isSubsequence xt yt else isSubsequence xs yt
-- !benchmark @end postcond_aux


@[reducible]
def moveZeroes_postcond (xs : List Int) (result: List Int) (h_precond : moveZeroes_precond (xs)) : Prop :=
  -- !benchmark @start postcond
  -- 1. All non-zero elements must maintain their relative order
  isSubsequence (xs.filter (fun x => x ≠ 0)) result = true ∧

  -- 2. All zeroes must be located at the end of the output list
  (result.dropWhile (fun x => x ≠ 0)).all (fun x => x = 0) ∧

  -- 3. The output must contain the same number of elements,
  --    and the number of zeroes must remain unchanged
  countVal 0 xs = countVal 0 result ∧
  xs.length = result.length
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (xs: List Int) (h_precond : moveZeroes_precond (xs)),
    moveZeroes_postcond (xs) (moveZeroes (xs) h_precond) h_precond

end VerinaAdv56

namespace VerinaAdv60

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def partitionEvensOdds_precond (nums : List Nat) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def partitionEvensOdds (nums : List Nat) (h_precond : partitionEvensOdds_precond (nums)) : (List Nat × List Nat) :=
  -- !benchmark @start code
  let rec helper (nums : List Nat) : (List Nat × List Nat) :=
    match nums with
    | [] => ([], [])
    | x :: xs =>
      let (evens, odds) := helper xs
      if x % 2 == 0 then (x :: evens, odds)
      else (evens, x :: odds)
  helper nums
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def partitionEvensOdds_postcond (nums : List Nat) (result: (List Nat × List Nat)) (h_precond : partitionEvensOdds_precond (nums)): Prop :=
  -- !benchmark @start postcond
  let evens := result.fst
  let odds := result.snd
  -- All elements from nums are in evens ++ odds, no extras
  evens ++ odds = nums.filter (fun n => n % 2 == 0) ++ nums.filter (fun n => n % 2 == 1) ∧
  evens.all (fun n => n % 2 == 0) ∧
  odds.all (fun n => n % 2 == 1)
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (nums: List Nat) (h_precond : partitionEvensOdds_precond (nums)),
    partitionEvensOdds_postcond (nums) (partitionEvensOdds (nums) h_precond) h_precond

end VerinaAdv60

namespace VerinaAdv64

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def removeElement_precond (lst : List Nat) (target : Nat) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def removeElement (lst : List Nat) (target : Nat) (h_precond : removeElement_precond (lst) (target)) : List Nat :=
  -- !benchmark @start code
  let rec helper (lst : List Nat) (target : Nat) : List Nat :=
    match lst with
    | [] => []
    | x :: xs =>
      let rest := helper xs target
      if x = target then rest else x :: rest
  helper lst target
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def removeElement_postcond (lst : List Nat) (target : Nat) (result: List Nat) (h_precond : removeElement_precond (lst) (target)): Prop :=
  -- !benchmark @start postcond
  -- 1. All elements equal to target are removed from the result.
  -- 2. All other elements are preserved in order.
  -- 3. No new elements are added.

  -- Helper predicate: result contains exactly the elements of lst that are not equal to target, in order
  let lst' := lst.filter (fun x => x ≠ target)
  result.zipIdx.all (fun (x, i) =>
    match lst'[i]? with
    | some y => x = y
    | none => false) ∧ result.length = lst'.length
  -- !benchmark @end postcond


-- !benchmark @start proof_aux
-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (lst: List Nat) (target: Nat) (h_precond : removeElement_precond (lst) (target)),
    removeElement_postcond (lst) (target) (removeElement (lst) (target) h_precond) h_precond

end VerinaAdv64

namespace VerinaAdv65

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def reverseString_precond (s : String) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def reverseString (s : String) (h_precond : reverseString_precond (s)) : String :=
  -- !benchmark @start code
  let rec reverseAux (chars : List Char) (acc : List Char) : List Char :=
    match chars with
    | [] => acc
    | h::t => reverseAux t (h::acc)
  String.mk (reverseAux (s.toList) [])
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def reverseString_postcond (s : String) (result: String) (h_precond : reverseString_precond (s)) : Prop :=
  -- !benchmark @start postcond
  result.length = s.length ∧ result.toList = s.toList.reverse
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (s: String) (h_precond : reverseString_precond (s)),
    reverseString_postcond (s) (reverseString (s) h_precond) h_precond

end VerinaAdv65

namespace VerinaAdv66

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def reverseWords_precond (words_str : String) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def reverseWords (words_str : String) (h_precond : reverseWords_precond (words_str)) : String :=
  -- !benchmark @start code
  let rawWords : List String := words_str.splitOn " "
  let rec filterNonEmpty (words : List String) : List String :=
    match words with
    | [] => []
    | h :: t =>
      if h = "" then
        filterNonEmpty t
      else
        h :: filterNonEmpty t
  let filteredWords : List String := filterNonEmpty rawWords
  let revWords : List String := filteredWords.reverse
  let rec joinWithSpace (words : List String) : String :=
    match words with
    | [] => ""
    | [w] => w
    | h :: t =>
      -- Append the current word with a space and continue joining the rest.
      h ++ " " ++ joinWithSpace t
  let result : String := joinWithSpace revWords
  result
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def reverseWords_postcond (words_str : String) (result: String) (h_precond : reverseWords_precond (words_str)) : Prop :=
  -- !benchmark @start postcond
  ∃ words : List String,
    (words = (words_str.splitOn " ").filter (fun w => w ≠ "")) ∧
    result = String.intercalate " " (words.reverse)
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (words_str: String) (h_precond : reverseWords_precond (words_str)),
    reverseWords_postcond (words_str) (reverseWords (words_str) h_precond) h_precond

end VerinaAdv66

namespace VerinaAdv70

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def semiOrderedPermutation_precond (nums : List Int) : Prop :=
  -- !benchmark @start precond
  let n := nums.length
  n > 0 ∧
  -- Must be a permutation of [1..n]: all distinct, all in range
  List.Nodup nums ∧
  nums.all (fun x => 1 ≤ x ∧ x ≤ Int.ofNat n)
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def semiOrderedPermutation (nums : List Int) (h_precond : semiOrderedPermutation_precond (nums)) : Int :=
  -- !benchmark @start code
  let lengthList := nums.length
  let numOne : Int := 1
  let largestNum : Int := Int.ofNat lengthList

  let firstIndex := nums.idxOf numOne
  let lastIndex := nums.idxOf largestNum

  let startPosition := 0
  let endPosition := lengthList - 1

  let shouldMoveOne := firstIndex != startPosition
  let shouldMoveLast := lastIndex != endPosition

  let distanceOne := if shouldMoveOne then firstIndex else 0
  let distanceLast := if shouldMoveLast then endPosition - lastIndex else 0

  let totalMoves := distanceOne + distanceLast
  let needAdjustment := firstIndex > lastIndex
  let adjustedMoves := if needAdjustment then totalMoves - 1 else totalMoves

  adjustedMoves
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def semiOrderedPermutation_postcond (nums : List Int) (result: Int) (h_precond : semiOrderedPermutation_precond (nums)) : Prop :=
  -- !benchmark @start postcond
  let n := nums.length
  let pos1 := nums.idxOf 1
  let posn := nums.idxOf (Int.ofNat n)
  if pos1 > posn then
    pos1 + n = result + 2 + posn
  else
    pos1 + n = result + 1 + posn
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (nums: List Int) (h_precond : semiOrderedPermutation_precond (nums)),
    semiOrderedPermutation_postcond (nums) (semiOrderedPermutation (nums) h_precond) h_precond

end VerinaAdv70

namespace VerinaAdv72

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible, simp]
def singleDigitPrimeFactor_precond (n : Nat) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def singleDigitPrimeFactor (n : Nat) (h_precond : singleDigitPrimeFactor_precond (n)) : Nat :=
  -- !benchmark @start code
  if n == 0 then 0
  else if n % 2 == 0 then 2
  else if n % 3 == 0 then 3
  else if n % 5 == 0 then 5
  else if n % 7 == 0 then 7
  else 0
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible, simp]
def singleDigitPrimeFactor_postcond (n : Nat) (result: Nat) (h_precond : singleDigitPrimeFactor_precond (n)) : Prop :=
  -- !benchmark @start postcond
  result ∈ [0, 2, 3, 5, 7] ∧
  (result = 0 → (n = 0 ∨ [2, 3, 5, 7].all (n % · ≠ 0))) ∧
  (result ≠ 0 → n ≠ 0 ∧ n % result == 0 ∧ (List.range result).all (fun x => x ∈ [2, 3, 5, 7] → n % x ≠ 0))
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (n: Nat) (h_precond : singleDigitPrimeFactor_precond (n)),
    singleDigitPrimeFactor_postcond (n) (singleDigitPrimeFactor (n) h_precond) h_precond

end VerinaAdv72

namespace VerinaAdv73

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def smallestMissing_precond (l : List Nat) : Prop :=
  -- !benchmark @start precond
  List.Pairwise (· < ·) l
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def smallestMissing (l : List Nat) (h_precond : smallestMissing_precond (l)) : Nat :=
  -- !benchmark @start code
  let sortedList := l
  let rec search (lst : List Nat) (n : Nat) : Nat :=
    match lst with
    | [] => n
    | x :: xs =>
      let isEqual := x = n
      let isGreater := x > n
      let nextCand := n + 1
      if isEqual then
        search xs nextCand
      else if isGreater then
        n
      else
        search xs n
  let result := search sortedList 0
  result
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def smallestMissing_postcond (l : List Nat) (result: Nat) (h_precond : smallestMissing_precond (l)) : Prop :=
  -- !benchmark @start postcond
  result ∉ l ∧ ∀ candidate : Nat, candidate < result → candidate ∈ l
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (l: List Nat) (h_precond : smallestMissing_precond (l)),
    smallestMissing_postcond (l) (smallestMissing (l) h_precond) h_precond

end VerinaAdv73

namespace VerinaAdv76

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible]
def topKFrequent_precond (nums : List Int) (k : Nat) : Prop :=
  -- !benchmark @start precond
  k ≤ nums.eraseDups.length
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def topKFrequent (nums : List Int) (k : Nat) (h_precond : topKFrequent_precond (nums) (k)) : List Int :=
  -- !benchmark @start code
  -- Build frequency list maintaining first occurrence order (deterministic)
  let freqList : List (Int × Nat) :=
    nums.foldl (init := []) fun acc n =>
      match acc.find? (fun (key, _) => key == n) with
      | some _ => acc.map (fun (key, cnt) => if key == n then (key, cnt + 1) else (key, cnt))
      | none => acc ++ [(n, 1)]
  -- Sort by frequency (descending), stable sort preserves first-occurrence order for ties
  let sorted := freqList.foldl
    (fun acc pair =>
      let (x, cx) := pair
      let rec insertSorted (xs : List (Int × Nat)) : List (Int × Nat) :=
        match xs with
        | [] => [pair]
        | (y, cy) :: ys =>
          if cx > cy then
            pair :: (y, cy) :: ys
          else
            (y, cy) :: insertSorted ys
      insertSorted acc
    ) []

  sorted.take k |>.map (fun (n, _) => n)
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible]
def topKFrequent_postcond (nums : List Int) (k : Nat) (result: List Int) (h_precond : topKFrequent_precond (nums) (k)) : Prop :=
  -- !benchmark @start postcond
  -- Result contains exactly k elements
  result.length = k ∧

  -- All elements in result appear in the original list
  result.all (· ∈ nums) ∧

  -- All elements in result are distinct
  List.Pairwise (· ≠ ·) result ∧

  -- For any element in result and any element not in result, the frequency of the
  -- element in result is greater or equal (simplified: no tie-breaking constraint on ordering)
  (result.all (fun x =>
    nums.all (fun y =>
      y ∈ result ∨ nums.count x ≥ nums.count y
    ))) ∧

  -- Elements in result are ordered by non-increasing frequency
  List.Pairwise (fun (x, i) (y, j) =>
    i < j → nums.count x ≥ nums.count y
  ) result.zipIdx
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (nums: List Int) (k: Nat) (h_precond : topKFrequent_precond (nums) (k)),
    topKFrequent_postcond (nums) (k) (topKFrequent (nums) (k) h_precond) h_precond

end VerinaAdv76

namespace VerinaAdv81

-- !benchmark @start import type=solution

-- !benchmark @end import

-- !benchmark @start solution_aux

-- !benchmark @end solution_aux

-- !benchmark @start precond_aux

-- !benchmark @end precond_aux
@[reducible, simp]
def uniqueSorted_precond (arr : List Int) : Prop :=
  -- !benchmark @start precond
  True
  -- !benchmark @end precond


-- !benchmark @start code_aux

-- !benchmark @end code_aux


def uniqueSorted (arr : List Int) (h_precond : uniqueSorted_precond (arr)) : List Int :=
  -- !benchmark @start code
  let rec insert (x : Int) (sorted : List Int) : List Int :=
  match sorted with
  | [] =>
    [x]
  | head :: tail =>
    if x <= head then
      x :: head :: tail
    else
      head :: insert x tail

let rec insertionSort (xs : List Int) : List Int :=
  match xs with
  | [] =>
    []
  | h :: t =>
    let sortedTail := insertionSort t
    insert h sortedTail

let removeDups : List Int → List Int
| xs =>
  let rec aux (remaining : List Int) (seen : List Int) (acc : List Int) : List Int :=
    match remaining with
    | [] =>
      acc.reverse
    | h :: t =>
      if h ∈ seen then
        aux t seen acc
      else
        aux t (h :: seen) (h :: acc)
  aux xs [] []

insertionSort (removeDups arr)
  -- !benchmark @end code


-- !benchmark @start postcond_aux

-- !benchmark @end postcond_aux


@[reducible, simp]
def uniqueSorted_postcond (arr : List Int) (result: List Int) (h_precond : uniqueSorted_precond (arr)) : Prop :=
  -- !benchmark @start postcond
  List.isPerm arr.eraseDups result ∧ List.Pairwise (· ≤ ·) result
  -- !benchmark @end postcond


-- !benchmark @start proof_aux

-- !benchmark @end proof_aux

def SunsteadTarget : Prop :=
  ∀ (arr: List Int) (h_precond : uniqueSorted_precond (arr)),
    uniqueSorted_postcond (arr) (uniqueSorted (arr) h_precond) h_precond

end VerinaAdv81

