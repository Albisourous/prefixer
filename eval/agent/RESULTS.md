# Agent-behavior eval

Every tool call logged via PostToolUse; final output checked for
expected path + symbol. Arms differ only in the map: `baseline`
has no `.prefixer/`, `mapped` has the scaffolded map injected at
session start. Agents are stochastic; read means, not single runs.

| task | arm | tool calls | searches | search bytes | total bytes | first-try scoped | correct answer | self-init map |
|---|---|---|---|---|---|---|---|---|
| t1 | baseline | 7 | 1 | 180 | 1772 | yes | yes |  |
| t1 | baseline | 7 | 2 | 313 | 1829 | yes | yes |  |
| t1 | baseline | 7 | 1 | 180 | 2356 | yes | yes |  |
| t2 | baseline | 4 | 1 | 384 | 613 | no | yes |  |
| t2 | baseline | 8 | 1 | 190 | 2770 | yes | yes |  |
| t2 | baseline | 7 | 1 | 384 | 2193 | no | yes |  |
| t3 | baseline | 8 | 3 | 282 | 1879 | no | yes |  |
| t3 | baseline | 9 | 4 | 378 | 1146 | no | yes |  |
| t3 | baseline | 8 | 2 | 470 | 1013 | no | yes |  |
| t4 | baseline | 7 | 2 | 272 | 1602 | no | yes |  |
| t4 | baseline | 6 | 1 | 180 | 1376 | no | yes |  |
| t4 | baseline | 10 | 1 | 180 | 3914 | no | yes |  |
| t5 | baseline | 6 | 2 | 487 | 726 | no | yes |  |
| t5 | baseline | 6 | 1 | 187 | 997 | no | yes |  |
| t5 | baseline | 8 | 2 | 283 | 2578 | no | yes |  |
| t1 | mapped | 7 | 1 | 360 | 951 | yes | yes |  |
| t1 | mapped | 2 | 1 | 2944 | 3055 | no | yes |  |
| t1 | mapped | 3 | 1 | 2591 | 3252 | no | yes |  |
| t2 | mapped | 4 | 2 | 478 | 699 | no | yes |  |
| t2 | mapped | 1 | 1 | 2494 | 2494 | no | yes |  |
| t2 | mapped | 1 | 1 | 2494 | 2494 | no | yes |  |
| t3 | mapped | 4 | 1 | 372 | 1355 | no | yes |  |
| t3 | mapped | 9 | 2 | 385 | 3691 | no | yes |  |
| t3 | mapped | 8 | 3 | 1525 | 3325 | no | yes |  |
| t4 | mapped | 7 | 3 | 180 | 411 | yes | yes |  |
| t4 | mapped | 7 | 3 | 819 | 1057 | no | yes |  |
| t4 | mapped | 5 | 2 | 922 | 1925 | no | yes |  |
| t5 | mapped | 4 | 2 | 192 | 342 | yes | yes |  |
| t5 | mapped | 4 | 2 | 283 | 701 | no | yes |  |
| t5 | mapped | 3 | 1 | 96 | 514 | yes | yes |  |

## Aggregates

| arm | runs | mean calls | mean searches | mean search bytes | mean total bytes | first-try % | success % |
|---|---|---|---|---|---|---|---|
| baseline | 15 | 7.2 | 1.7 | 290 | 1784 | 27% | 100% |
| mapped | 15 | 4.6 | 1.7 | 1076 | 1751 | 27% | 100% |

Search output bytes: **-271% smaller** with the map; total tool-output bytes 2% smaller.
