#!/usr/bin/env python3
"""model-choices.py — Exercício 05: every choice, counted locally before paying for one.

A pre-flight MODEL, not the job. It generates the same raw as carregar-raw.sh
(gerador-eventos.py --dias 30 --taxa 12 --seed 42, then plantar-problemas.py
--atraso 3 --reentrega 5) into a temp dir and re-implements, in plain Python,
the four choices pipeline-corridas.py makes:

  arrival day  = the raw folder dt=  (chegada)
  event day    = data_corrida[:10]   (UTC, as the job's Spark session)
  daily load   = keep 0 <= arrival - event <= JANELA; count the rest as fora_da_janela
  backfill     = keep the listed event days, any arrival >= event day
  CHAVE        = keep the first arrival of each corrida_id
  MODO         = append adds every run's rows; sobrescrever replaces the event-day
                 partitions the run writes (dynamic partition overwrite)

It prints, per window 0..7 and key, what the dashboard question would answer
after one run and after a re-run, plus the backfill of D-3 for a window too
short to see it. The numbers in DECISOES.md that come from AWS are the job's
own report; this model only explains the alternatives that were not run.

    python3 -I verification/model-choices.py 2>&1 | tee docs/evidence/model-choices.txt

Python 3.10+, standard library only. Writes only to a temp dir it removes.
"""

from __future__ import annotations

import collections
import datetime as dt
import json
import subprocess
import sys
import tempfile
from pathlib import Path

LAB = Path(__file__).resolve().parent.parent
NIGHT = range(0, 6)  # faixa_hora BETWEEN 0 AND 5

# One raw line: (corrida_id, arrival day, event day, hour of day in UTC).
Row = tuple[str, str, str, int]
# The trusted table: event day (the dt= partition) -> rows in that folder.
Table = dict[str, list[Row]]


def load_raw(root: Path) -> list[Row]:
    """(corrida_id, arrival day, event day, hour) for every raw line."""
    rows: list[Row] = []
    for folder in sorted(root.glob("dt=*")):
        arrival = folder.name[3:]
        for f in sorted(folder.glob("*.json")):
            for line in f.read_text(encoding="utf-8").splitlines():
                r = json.loads(line)
                ts = r["data_corrida"]  # 2026-11-04T01:23:45Z, UTC
                rows.append((r["corrida_id"], arrival, ts[:10], int(ts[11:13])))
    return rows


def lag(arrival: str, event: str) -> int:
    return (dt.date.fromisoformat(arrival) - dt.date.fromisoformat(event)).days


def select(rows: list[Row], janela: int | None, days: set[str] | None,
           key: bool) -> tuple[list[Row], int, int]:
    """One job run: (rows written, fora_da_janela, duplicates removed)."""
    if days is None:  # daily load, DIAS=todos
        fora = sum(1 for r in rows if lag(r[1], r[2]) > janela)
        kept = [r for r in rows if 0 <= lag(r[1], r[2]) <= janela]
    else:  # backfill, DIAS=<event days>: the window does not apply
        fora = 0
        kept = [r for r in rows if r[2] in days and lag(r[1], r[2]) >= 0]
    before = len(kept)
    if key:
        first: dict[str, Row] = {}
        for r in sorted(kept, key=lambda r: r[1]):  # orderBy("chegada"): first arrival wins
            first.setdefault(r[0], r)
        kept = list(first.values())
    return kept, fora, before - len(kept)


def write(table: Table, written: list[Row], mode: str) -> None:
    by_day: Table = collections.defaultdict(list)
    for r in written:
        by_day[r[2]].append(r)
    for day, part in by_day.items():
        if mode == "append":
            table.setdefault(day, []).extend(part)
        else:  # sobrescrever = dynamic partition overwrite: only the days written
            table[day] = part


def ask(table: Table, desde: str) -> tuple[int, int, int]:
    """(7-day night count, rows, distinct corrida_id) — the verifier's questions."""
    allrows = [r for part in table.values() for r in part]
    night = sum(1 for r in allrows if r[2] >= desde and r[3] in NIGHT)
    return night, len(allrows), len({r[0] for r in allrows})


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="eda-a25-model-") as tmp:
        out = Path(tmp)
        subprocess.run([sys.executable, "-I", str(LAB / "app/gerador-eventos.py"), "--dias", "30",
                        "--taxa", "12", "--seed", "42", "--saida", str(out)],
                       check=True, stdout=subprocess.DEVNULL)
        planted = subprocess.run([sys.executable, "-I", str(LAB / "app/plantar-problemas.py"),
                                  "--saida", str(out), "--atraso", "3", "--reentrega", "5"],
                                 check=True, capture_output=True, text=True).stdout
        root = out / "raw" / "corridas"
        files = sorted(p.relative_to(root).as_posix() for p in root.glob("dt=*/*.json"))
        rows = load_raw(root)

    days = sorted({r[1] for r in rows})
    hoje = dt.date.fromisoformat(days[-1])
    d3, desde = str(hoje - dt.timedelta(days=3)), str(hoje - dt.timedelta(days=6))
    lags = collections.Counter(lag(r[1], r[2]) for r in rows)

    print(planted.strip())
    print(f"\nraw: {len(files)} files, {len(rows):,} lines, {len({r[0] for r in rows}):,} distinct corrida_id")
    print("lines per arrival lag (arrival day - event day): "
          + ", ".join(f"{k} d = {v:,}" for k, v in sorted(lags.items())))

    print("\nDAILY LOAD (DIAS=todos), run 1 and run 2 on the same raw. Verifier: night 11137, rows = distinct = 518400")
    print(f"{'modo':<13}{'chave':<12}{'janela':>6}{'fora':>8}{'dups':>8} | {'night 1':>8}{'rows 1':>9}{'dist 1':>9}"
          f" | {'night 2':>8}{'rows 2':>10}  passes 1/2/3")
    for mode in ("append", "sobrescrever"):
        for key in (False, True):
            for janela in range(0, 8):
                table: Table = {}
                written, fora, dups = select(rows, janela, None, key)
                write(table, written, mode)
                n1, r1, d1 = ask(table, desde)
                write(table, select(rows, janela, None, key)[0], mode)
                n2, r2, d2 = ask(table, desde)
                ok = ["PASS" if c else "fail" for c in
                      (n1 == 11137, (n1, r1) == (n2, r2), r2 == d2 == 518400)]
                print(f"{mode:<13}{'corrida_id' if key else 'nenhuma':<12}{janela:>6}{fora:>8,}{dups:>8,} |"
                      f" {n1:>8,}{r1:>9,}{d1:>9,} | {n2:>8,}{r2:>10,}  {'/'.join(ok)}")

    print(f"\nBACKFILL of D-3 = {d3} (DIAS={d3}) after a daily load whose window is too short (sobrescrever, corrida_id)")
    for janela in (2, 3):
        table = {}
        write(table, select(rows, janela, None, True)[0], "sobrescrever")
        before = ask(table, desde)
        written, _, dups = select(rows, None, {d3}, True)
        write(table, written, "sobrescrever")
        after = ask(table, desde)
        write(table, select(rows, None, {d3}, True)[0], "sobrescrever")  # the backfill, re-run
        again = ask(table, desde)
        print(f"  janela {janela}: before night {before[0]:,} rows {before[1]:,} -> backfill writes "
              f"{len({r[2] for r in written})} folder, {len(written):,} rows (dups {dups}) -> night {after[0]:,} "
              f"rows {after[1]:,} distinct {after[2]:,}; backfill re-run -> night {again[0]:,} rows {again[1]:,}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
