"""Export successful fresh aggregate results plus separate real-board evidence."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import shutil
from datetime import datetime, timezone

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--simulation-root', type=Path, default=ROOT)
args = parser.parse_args()
simulation = args.simulation_root.resolve()
summary_path = simulation/'build/run-all/summary.json'
summary = json.loads(summary_path.read_text(encoding='utf-8'))
required = {'single_cycle', 'cp0', 'peripherals', 'cache', 'pipeline', 'mars',
            'soc', 'cpu_cache', 'upstream_sc', 'teach_soc', 'course_basics'}
if summary['overall_status'] != 'PASS' or {r['name'] for r in summary['tests']} != required:
    raise RuntimeError('Export requires a complete eleven-runner PASS; no skips or stale individual logs')
if not summary.get('source_commit') or summary.get('source_dirty') is not False:
    raise RuntimeError('Export requires run-time commit provenance from a clean checkout')
results = {'simulation_commit': summary['source_commit'],
    'generated_at_utc': summary['generated_at'], 'overall_status': 'PASS', 'tests': []}
for row in summary['tests']:
    if row['status'] != 'PASS':
        raise RuntimeError(f"Failed runner: {row['name']}")
    log = simulation/'build/run-all'/f"{row['name']}.log"
    markers = [line for line in log.read_text(encoding='utf-8', errors='replace').splitlines()
               if re.match(r'^(?:PASS[ :]|TB_\w+_PASS|CACHE_TESTS_PASS|JOINT |CHECKPOINT )', line)]
    if not markers:
        raise RuntimeError(f"Missing successful test markers: {row['name']}")
    results['tests'].append({k: row[k] for k in ['name', 'status', 'duration_seconds', 'returncode']}
        | {'markers': list(dict.fromkeys(markers)), 'log_sha256': hashlib.sha256(log.read_bytes()).hexdigest()})

payloads = {}
for name, source in {'board': ROOT/'build/hardware/board_test.json',
                     'recording': ROOT/'build/hardware/recording_result.json',
                     'course_basics': simulation/'build/course_basics/normal/result.json'}.items():
    payload = json.loads(source.read_text(encoding='utf-8'))
    if name != 'course_basics' and payload.get('pass') is not True:
        raise RuntimeError(f'No successful {name} evidence')
    payloads[name] = payload

out = ROOT/'evidence'
out.mkdir(exist_ok=True)
for name, payload in payloads.items():
    (out/(name+'.json')).write_text(json.dumps(payload, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
for name in ['timing.rpt', 'utilization.rpt', 'drc.rpt', 'build_result.txt']:
    source = ROOT/'build/board'/name
    lines = [line for line in source.read_text(errors='replace').splitlines()
             if not re.match(r'\| Host\s*:', line)]
    (out/('board-'+name)).write_text('\n'.join(lines)+'\n', encoding='utf-8')
for source, destination in [(simulation/'build/pipeline/pipeline_stages.csv', 'pipeline-stages.csv'),
                            (ROOT/'build/hardware/live_session.jsonl', 'live-telemetry.jsonl')]:
    shutil.copyfile(source, out/destination)
results['exported_at_utc'] = datetime.now(timezone.utc).isoformat()
(out/'results.json').write_text(json.dumps(results, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')
print('PASS EVIDENCE_EXPORT runners=11 physical_board=1 live_recording=1')
