#!/usr/bin/env python3
"""Reproducible stock-heuristic floors for the crypto-linear-xor-opt tasks.

For tasks where no published 2-input XOR count could be sourced, Sunstead's
best_known is the best result of a stock heuristic anyone can run in a minute:
randomized Paar (cancellation-free greedy common-pair elimination, random
tie-breaking, fixed seed). A result a stock heuristic finds is not research, so it
should not pay like one.

Every circuit is checked against the target matrix before it is reported.

Usage: python3 scripts/best_known/linear_floor.py [--runs N] [--seed S]
"""
from __future__ import annotations

import argparse
import random

GF_POLY = 0x11B


def rot_rows(shifts: list[int], n: int = 32) -> list[int]:
    """Rows of x -> XOR_r rotl(x, r) on n-bit words (bit i of rotl(x, r) is bit i - r of x)."""
    return [sum(1 << ((i - r) % n) for r in shifts) for i in range(n)]


def _xtime(a: int) -> int:
    a <<= 1
    return a ^ GF_POLY if a & 0x100 else a


def _gmul(a: int, c: int) -> int:
    r = 0
    while c:
        if c & 1:
            r ^= a
        a = _xtime(a)
        c >>= 1
    return r


def mixcolumns_rows(column: list[int]) -> list[int]:
    """Bit rows of a circulant 4x4 GF(2^8) matrix acting on 4 bytes (LSB-first bits)."""
    rows = []
    for i in range(4):
        for bit in range(8):
            m = 0
            for j in range(4):
                c = column[(j - i) % 4]
                for k in range(8):
                    if (_gmul(1 << k, c) >> bit) & 1:
                        m |= 1 << (8 * j + k)
            rows.append(m)
    return rows


def rows_from_sets(sets: list[list[int]]) -> list[int]:
    return [sum(1 << j for j in s) for s in sets]


# Matrices as defined in missions/crypto-linear-xor-opt/CryptoLinearXor/Spec.lean.
MATRICES: dict[str, tuple[list[int], int]] = {
    "aes_mixcolumns_xor": (mixcolumns_rows([2, 3, 1, 1]), 32),
    "aes_invmixcolumns_xor": (mixcolumns_rows([0xE, 0xB, 0xD, 0x9]), 32),
    "sm4_linear_l_xor": (rot_rows([0, 2, 10, 18, 24]), 32),
    "sm4_key_lprime_xor": (rot_rows([0, 13, 23]), 32),
    "aria_diffusion_xor": (rows_from_sets([
        [3, 4, 6, 8, 9, 13, 14], [2, 5, 7, 8, 9, 12, 15], [1, 4, 6, 10, 11, 12, 15], [0, 5, 7, 10, 11, 13, 14],
        [0, 2, 5, 8, 11, 14, 15], [1, 3, 4, 9, 10, 14, 15], [0, 2, 7, 9, 10, 12, 13], [1, 3, 6, 8, 11, 12, 13],
        [0, 1, 4, 7, 10, 13, 15], [0, 1, 5, 6, 11, 12, 14], [2, 3, 5, 6, 8, 13, 15], [2, 3, 4, 7, 9, 12, 14],
        [1, 2, 6, 7, 9, 11, 12], [0, 3, 6, 7, 8, 10, 13], [0, 3, 4, 5, 9, 11, 14], [1, 2, 4, 5, 8, 10, 15],
    ]), 16),
    "camellia_p_xor": (rows_from_sets([
        [0, 2, 3, 5, 6, 7], [0, 1, 3, 4, 6, 7], [0, 1, 2, 4, 5, 7], [1, 2, 3, 4, 5, 6],
        [0, 1, 5, 6, 7], [1, 2, 4, 6, 7], [2, 3, 4, 5, 7], [0, 3, 4, 5, 6],
    ]), 8),
}


def paar(rows: list[int], n: int, rng: random.Random) -> tuple[list[tuple[int, int]], list[int]]:
    """Randomized Paar: repeatedly XOR the most frequent signal pair; returns (gates, outputs)."""
    rowsets = [{j for j in range(n) if (r >> j) & 1} for r in rows]
    gates: list[tuple[int, int]] = []
    nsig = n
    while True:
        count: dict[tuple[int, int], int] = {}
        for rs in rowsets:
            items = sorted(rs)
            for a in range(len(items)):
                for b in range(a + 1, len(items)):
                    pair = (items[a], items[b])
                    count[pair] = count.get(pair, 0) + 1
        if not count:
            break
        top = max(count.values())
        if top < 2:
            for rs in rowsets:
                items = sorted(rs)
                while len(items) > 1:
                    gates.append((items[0], items[1]))
                    items = [nsig] + items[2:]
                    nsig += 1
                rs.clear()
                rs.update(items)
            break
        pair = rng.choice(sorted(p for p, v in count.items() if v == top))
        gates.append(pair)
        for rs in rowsets:
            if pair[0] in rs and pair[1] in rs:
                rs.difference_update(pair)
                rs.add(nsig)
        nsig += 1
    return gates, [next(iter(rs)) for rs in rowsets]


def check(rows: list[int], n: int, gates: list[tuple[int, int]], outputs: list[int]) -> bool:
    sig = [1 << j for j in range(n)]
    for a, b in gates:
        sig.append(sig[a] ^ sig[b])
    return all(sig[o] == r for o, r in zip(outputs, rows))


def floor_for(task: str, runs: int, seed: int) -> int:
    rows, n = MATRICES[task]
    rng = random.Random(seed)
    best = None
    for _ in range(runs):
        gates, outputs = paar(rows, n, rng)
        if not check(rows, n, gates, outputs):
            raise AssertionError(f"{task}: heuristic produced a wrong circuit")
        if best is None or len(gates) < best:
            best = len(gates)
    assert best is not None
    return best


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--runs", type=int, default=200)
    ap.add_argument("--seed", type=int, default=1)
    args = ap.parse_args()
    for task in MATRICES:
        print(f"{task}\t{floor_for(task, args.runs, args.seed)}")


if __name__ == "__main__":
    main()
