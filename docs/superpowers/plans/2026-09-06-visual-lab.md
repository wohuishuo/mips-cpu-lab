# Visual CPU lab implementation plan

Spec: ../specs/2026-09-06-visual-lab-design.md

Use subagent-driven-development. Isolated branch codex/visual-lab, sibling worktree. User authorized continuous execution. Root owns integration and commits; workers do not commit shared files or spawn workers.

## Global constraints

Frozen engine/editor contracts in spec. Scope confined to docs/lab, tests/visualizer, supporting launch/docs. No RTL/evidence edits. Browser CUSTOM extension clearly described. No CDN, eval, dependency on Vivado for UI.

## Task 1: CPU engine

Own docs/lab/engine/cpu.js and tests/visualizer/cpu.test.js. Read existing pipeline contract/reference. Write meaningful failing independent tests then implement assembler, cycle model, serialization. Test ordinary arithmetic, loads/stores, RAW/load-use, one delay slot, waits, halt, invalid input, custom callback and rewind. Run node --test tests/visualizer/cpu.test.js. Report actual supported ISA and contracts.

## Task 2: Circuit engine and editor

Own docs/lab/engine/circuit.js, docs/lab/circuit-editor.js, docs/lab/circuit-editor.css, tests/visualizer/circuit.test.js. Implement graph rules, truth tables, DFF, A/B/Y install and self-contained accessible SVG drag/connect editor with challenge feedback. Test NAND/XOR/full-adder, uint32, unknown, cycles, width, DFF, installed custom function. Run node --test tests/visualizer/circuit.test.js.

## Task 3: Root application

Own docs/lab/index.html, app.js, styles.css, package.json, launch script, docs. Create distinctive dark circuit-board workspace with program/data inputs, true cycle controls, state highlighting, five-stage SVG with ports, timeline and 1-bit full-adder drilldown. Connect editor install to CPU reset and custom callback. Default example computes and stores values using custom unit. Preserve user program editing. Error boundaries stop timers. Limit history and DOM records.

## Task 4: Review and verification

Fresh review checks task 1 and 2 contracts/quality after implementation. Root runs baseline Python tests, all Node tests, browser interaction checks and desktop/mobile visual inspection. Fix findings, then final broad reviewer, focused rerun. Deliver runnable app, screenshot, documented software dependencies and capability map. Publish only where existing public-repo authorization applies and tooling allows.
