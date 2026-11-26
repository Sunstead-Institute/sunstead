def LwcSbox.keccakChiTotalScore : Nat := 20
def LwcSbox.keccakChiTotalGates : List (Nat × Nat × Nat) := [
  (2, 0, 1), (2, 1, 2), (2, 2, 3), (2, 0, 4),
  (2, 3, 4), (2, 1, 2), (0, 0, 2), (0, 11, 10),
  (2, 2, 3), (0, 1, 3), (0, 14, 13), (2, 3, 4),
  (0, 2, 4), (0, 17, 16), (2, 0, 4), (0, 0, 3),
  (0, 20, 19), (2, 0, 1), (0, 1, 22), (0, 23, 4)
]
def LwcSbox.keccakChiTotalOutputs : List Nat := [12, 15, 18, 21, 24]
