# Lightweight Cipher Linear Diffusion XOR Circuits (13 Tracks)

Pure Lean 4.36.0 (zero Mathlib) certified straight-line XOR circuit minimization for thirteen standardized
lightweight cipher linear diffusion layers (Pyjamask-128 forward `M0..M3`, key `M_K`, and kernel-proved
inverses `InvM0..InvM3`, PHOTON-256 8×8 GF(2^4) MDS, Clyde-128/Spook 64-bit L-box, and Ascon NIST SP 800-232
`Σ0` and `Σ2`), pinned verbatim to [`rweather/lightweight-crypto@fa4ec9a021`](https://github.com/rweather/lightweight-crypto/tree/fa4ec9a021b9233263de77e7dd971de8c9761495) (MIT).

## Tracks

| Task ID | Diffusion Layer | Seed XORs | Literature Frontier | Target File |
| :--- | :--- | ---: | ---: | :--- |
| `pyjamask_m0_xor` | Pyjamask-128 M0 (0xa3861085) (32×32) | `320` | `~100-130` | `LwcLinearXor/PyjamaskM0Circuit.lean` |
| `pyjamask_m1_xor` | Pyjamask-128 M1 (0x63417021) (32×32) | `320` | `~100-130` | `LwcLinearXor/PyjamaskM1Circuit.lean` |
| `pyjamask_m2_xor` | Pyjamask-128 M2 (0x692cf280) (32×32) | `384` | `~110-140` | `LwcLinearXor/PyjamaskM2Circuit.lean` |
| `pyjamask_m3_xor` | Pyjamask-128 M3 (0x48a54813) (32×32) | `320` | `~100-130` | `LwcLinearXor/PyjamaskM3Circuit.lean` |
| `pyjamask_mk_xor` | Pyjamask-128 Key M_K (0xb881b9ca) (32×32) | `448` | `~110-145` | `LwcLinearXor/PyjamaskMKCircuit.lean` |
| `pyjamask_inv_m0_xor` | Pyjamask-128 InvM0 (0x2037a121) (32×32) | `320` | `~100-130` | `LwcLinearXor/PyjamaskInvM0Circuit.lean` |
| `pyjamask_inv_m1_xor` | Pyjamask-128 InvM1 (0x108ff2a0) (32×32) | `384` | `~110-140` | `LwcLinearXor/PyjamaskInvM1Circuit.lean` |
| `pyjamask_inv_m2_xor` | Pyjamask-128 InvM2 (0x9054d8c0) (32×32) | `320` | `~100-130` | `LwcLinearXor/PyjamaskInvM2Circuit.lean` |
| `pyjamask_inv_m3_xor` | Pyjamask-128 InvM3 (0x3354b117) (32×32) | `448` | `~110-145` | `LwcLinearXor/PyjamaskInvM3Circuit.lean` |
| `photon256_mds_xor` | PHOTON-256 8×8 GF(2^4) MDS (32×32) | `475` | `~120-160` | `LwcLinearXor/Photon256MdsCircuit.lean` |
| `clyde128_lbox_xor` | Clyde-128 / Spook 64-bit L-box (64×64) | `384` | `<340` | `LwcLinearXor/Clyde128LboxCircuit.lean` |
| `ascon_sigma0_xor` | Ascon Σ0 (rot 19, 28) (64×64) | `128` | `<128` | `LwcLinearXor/AsconSigma0Circuit.lean` |
| `ascon_sigma2_xor` | Ascon Σ2 (rot 1, 6) (64×64) | `128` | `<128` | `LwcLinearXor/AsconSigma2Circuit.lean` |
