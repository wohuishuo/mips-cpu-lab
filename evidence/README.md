# Evidence snapshot

`results.json` is exported from the eleven-runner aggregate executed in a clean
Git clone. Its `simulation_commit` is captured when the test run starts; later
documentation/media commits do not change which RTL revision was tested.
The tested commit is a local development-history identifier. Publication uses a
fresh source snapshot because the GitHub authorization could not upload commits
containing active workflow files. `tested-source.json` supplies content hashes
for the tested RTL, tests, software, constraints and build/regression entry points
so their identity can be verified without that private local history.
PASS markers and SHA-256 values refer to the actual per-runner logs. Full tool
logs can be regenerated with `scripts/run_all.py --with-course`.

`course_basics.json` records the six lab1/lab3 profiles and hashes of external
course files. `pipeline-stages.csv` contains real XSim stage snapshots.
`board.json`, `recording.json`, and `live-telemetry.jsonl` come from the physically
connected programmed FPGA, not a simulated UART.

The `board-*` reports describe the original programmed single-cycle image.
`clean-rebuild.json` describes a separate successful clone build, including its
own bitstream hash. Bitstream headers contain build metadata, so different hashes
do not by themselves imply different RTL. The programmed image is explicitly
identified in `board-build_result.txt` and `docs/hardware.md`.

There is no camera photograph or field recording of the buzzer in this evidence
set. GPIO values demonstrate driven electrical signals; physical appearance and
sound are separate observations. The teaching images are labeled accordingly.

To export a new complete snapshot after testing and recording:

```powershell
python scripts/export_evidence.py --simulation-root C:/work/mips-cpu-lab-clean
```

The exporter requires eleven PASS results with no skips and recorded clean-source
provenance. It never substitutes an old individual XSim log for a failed aggregate
run. Teacher source, ROM, golden trace, device serial identifiers and host names
are excluded from this public snapshot.
