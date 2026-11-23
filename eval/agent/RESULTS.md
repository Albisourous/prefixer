# Agent-behavior eval

Every tool call logged (PostToolUse hook or the ACP
session/update stream, adapter-dependent); final output checked
for expected path + symbol. Arms differ only in the map:
`baseline` has no `.prefixer/`, `mapped` has the scaffolded map
injected at session start. Agents are stochastic; read means,
not single runs.

| task | arm | tool calls | searches | search bytes | total bytes | first-try scoped | correct answer | self-init map |
|---|---|---|---|---|---|---|---|---|
| t1 | baseline | 11 | 2 | 1788 | 23514 | no | yes |  |
| t1 | baseline | 7 | 2 | 313 | 1829 | yes | yes |  |
| t1 | baseline | 7 | 1 | 180 | 2356 | yes | yes |  |
| t2 | baseline | 6 | 1 | 2821 | 2910 | no | yes |  |
| t2 | baseline | 8 | 1 | 190 | 2770 | yes | yes |  |
| t2 | baseline | 7 | 1 | 384 | 2193 | no | yes |  |
| t3 | baseline | 10 | 1 | 372 | 1598 | no | yes |  |
| t3 | baseline | 9 | 4 | 378 | 1146 | no | yes |  |
| t3 | baseline | 8 | 2 | 470 | 1013 | no | yes |  |
| t4 | baseline | 7 | 1 | 443 | 1657 | no | yes |  |
| t4 | baseline | 6 | 1 | 180 | 1376 | no | yes |  |
| t4 | baseline | 10 | 1 | 180 | 3914 | no | yes |  |
| t5 | baseline | 7 | 2 | 441 | 876 | yes | yes |  |
| t5 | baseline | 6 | 1 | 187 | 997 | no | yes |  |
| t5 | baseline | 8 | 2 | 283 | 2578 | no | yes |  |
| t1 | mapped | 7 | 1 | 180 | 1107 | no | yes |  |
| t1 | mapped | 2 | 1 | 2944 | 3055 | no | yes |  |
| t1 | mapped | 3 | 1 | 2591 | 3252 | no | yes |  |
| t2 | mapped | 3 | 1 | 384 | 384 | no | yes |  |
| t2 | mapped | 1 | 1 | 2494 | 2494 | no | yes |  |
| t2 | mapped | 1 | 1 | 2494 | 2494 | no | yes |  |
| t3 | mapped | 3 | 1 | 92 | 92 | yes | yes |  |
| t3 | mapped | 9 | 2 | 385 | 3691 | no | yes |  |
| t3 | mapped | 8 | 3 | 1525 | 3325 | no | yes |  |
| t4 | mapped | 6 | 2 | 270 | 270 | no | yes |  |
| t4 | mapped | 7 | 3 | 819 | 1057 | no | yes |  |
| t4 | mapped | 5 | 2 | 922 | 1925 | no | yes |  |
| t5 | mapped | 6 | 1 | 187 | 890 | no | yes |  |
| t5 | mapped | 4 | 2 | 283 | 701 | no | yes |  |
| t5 | mapped | 3 | 1 | 96 | 514 | yes | yes |  |

## Aggregates

| arm | runs | mean calls | mean searches | mean search bytes | mean total bytes | first-try % | success % |
|---|---|---|---|---|---|---|---|
| baseline | 15 | 7.8 | 1.5 | 574 | 3382 | 27% | 100% |
| mapped | 15 | 4.5 | 1.5 | 1044 | 1683 | 13% | 100% |

Search output bytes: **82% larger** with the map; total tool-output bytes 50% smaller.
