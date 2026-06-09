# protocol-
### iOS Shortcuts EMA Data Collection Pipeline 

---

## What this is

Automated EMA data collection via iOS Shortcuts, feeding into a CSV for downstream analysis.
Part of a 70-day N-of-1 behavioral self-experiment.

---

## Measurement

**Frequency:** 3× daily (morning / afternoon / evening)

**Each entry captures:**

| Variable | Prompt | Scale |
|---|---|---|
| `mood` | Current emotional valence | 0–100 |
| `agency` | Task progress feeling | 0–100 |
| `metacognition` | Awareness of current state | 0–100 |
| `melatonin_taken` | Melatonin taken? | 0 / 1 |
| `override_reason` | Deviation note | text |

---

## Output

Each Shortcut run appends one row to `data/Miura_Data.csv`:

```
timestamp, mood, agency, metacognition, melatonin_taken, override_reason
2026-03-07T10:00:00-05:00, 72, 65, 80, 1, N/A
```

---

## Files

```
protocol-/
├── data/
│   └── Miura_Data.csv       ← raw EMA output
├── src/
│   └── data_logger.py       ← validation & manual fallback entry
└── schedule.json            ← 70-day randomized melatonin protocol
```

---

## Validation

```bash
python src/data_logger.py validate
```

Checks for out-of-range values, missing entries, and duplicate timestamps.

---

*Full study design and analysis: [N-of-1-Melatonin-Study](https://github.com/haomeng797-ship-it/N-of-1-Melatonin-Study)*
