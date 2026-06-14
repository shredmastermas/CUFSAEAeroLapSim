# Convergence study — runtime vs quality vs size

Corrected physics. Ranges CL [0.035, 0.075], CD [0.01, 0.03], CoP [0.45, 0.65]. Quality = agreement with the finest run on a 125-point shared probe set (mean/max |Δtotal|, Spearman of rankings). Lower |Δ| and Spearman→1 mean 'finer would not change the answer.'

## Part 1 — grid density (fidelity = High)

| level | cells | runtime s | s/cell | best total | best CoP | best L/D | mean|Δ| vs finest | max|Δ| | Spearman |
|---|---|---|---|---|---|---|---|---|---|
| L0 coarse | 125 | 72.4 | 0.5792 | 496.0 | 0.6 | 7.5 | 0.0 | 0.0 | 1.0 |
| L1 medium | 729 | 418.0 | 0.5734 | 496.0 | 0.6 | 7.5 | 0.0 | 0.0 | 1.0 |
| L2 fine | 4913 | 2808.0 | 0.5715 | 496.54 | 0.5875 | 7.5 | 0.0 | 0.0 | 1.0 |

## Part 2 — solver fidelity (grid fixed at L1 = 9x9x9)

| fidelity | cells | runtime s | s/cell | best total | mean|Δ| vs High | max|Δ| | Spearman |
|---|---|---|---|---|---|---|---|
| High | 729 | 418.0 | 0.5734 | 496.0 | 0.0 | 0.0 | 1.0 |
| Medium | 729 | 231.6 | 0.3177 | 496.42 | 1.764 | 8.613 | 0.99626 |
| Low | 729 | 172.3 | 0.2364 | 490.14 | 6.242 | 14.728 | 0.99402 |
