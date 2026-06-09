# iOS Shortcuts EMA Data Collection Pipeline

*The custom data-collection tool for a 70-day N-of-1 affect study, built in iOS Shortcuts.*

Ecological momentary assessment (EMA) is collected three times a day on an iPhone via
Shortcuts. Each entry is validated and appended to a timestamped CSV for downstream
analysis. This repository documents the collection tool only; the cleaned data,
analysis, and manuscript live in the companion repository
[N-of-1-Melatonin-Study](https://github.com/haomeng797-ship-it/N-of-1-Melatonin-Study).

## Measurement

Three prompts per day (morning, afternoon, evening). Each entry records:

| Variable | Prompt | Scale |
|---|---|---|
| `mood` | current emotional valence | 0–100 |
| `agency` | sense of task progress | 0–100 |
| `metacognition` | awareness of current state | 0–100 |
| `melatonin_taken` | melatonin taken last night? | 0 / 1 |
| `override_reason` | deviation note | free text |

## Output

Each Shortcut run appends one row to `data/Miura_Data.csv`:

```
timestamp, mood, agency, metacognition, melatonin_taken, override_reason
2026-03-07T10:00:00-05:00, 72, 65, 80, 1, N/A
```

## Repository layout

- `data/Miura_Data.csv`: raw EMA output appended by the Shortcut
- `src/data_logger.py`: Python validation and manual-fallback entry
- `schedule.json`: pre-registered 70-day randomized melatonin schedule

## Validation

Run from the repository root, after an entry or in batch:

```bash
python src/data_logger.py validate   # out-of-range values, missing entries, duplicate timestamps
```

## Companion repository

Full study design, cleaned data, analysis, and manuscript:
[N-of-1-Melatonin-Study](https://github.com/haomeng797-ship-it/N-of-1-Melatonin-Study).

## License

Released under CC-BY 4.0.
