# Project exhibit plan

Spec: ../specs/2026-09-06-project-exhibit-design.md

Use writing-plans and subagent-driven-development for bounded data/verification assets. Root owns all website UI per Sites ownership guidance. Existing local static app and user-selected localhost endpoint remain the target; no site reinitializer or new hosting registration.

1. Data asset task: read real course/project documentation, build exact source bundle and truthful chapter metadata with 8 ids. Own tools/build-exhibit-data.mjs, docs/lab/data/project.json, tests/exhibit/data.test.js. Tests enforce extraction/hashes/line ranges/lab ids/evidence counts. No UI edits.
2. RTL trace asset task: new external observer testbench and runner for exact board SoC; use existing board ROM or rebuild from original assembly. Own tests/tb_exhibit_soc.sv, scripts/export_exhibit_trace.py, docs/lab/data/board-trace.json. No RTL edits; assert 12 Fibonacci stores, final89/display/LED. Record real XSim provenance. No UI edits.
3. Root UI: preserve old page as playground, replace home with readable chapter navigation, real single-cycle replay, corresponding source viewer, and all lab interaction demos. Native modules/CSS. Update original tests to explicit playground route and add exhibit browser tests. Retain localhost endpoint.
4. Review/integration: independent review data/RTL assets, root validates all interactions and visuals plus prior engines, fix concrete failures; integrate to original and publication repositories, refresh local preview. No initialization feature.
