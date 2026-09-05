# Two-way data cache

`rtl/cache/data_cache.v` implements the independent cache contract in
`docs/design.md`. It is a blocking, two-way, write-back, write-allocate cache
with parameterized power-of-two `SETS` and `WORDS_PER_LINE` values. The default
configuration is 16 sets and four 32-bit words per line (512 data bytes total).
Both parameters must be positive powers of two; 1 is legal for either
parameter. An illegal instance emits a `DATA_CACHE_PARAMETER_ERROR` diagnostic
and terminates at simulation time zero instead of silently mapping addresses
with invalid index masks.

## Transactions

The cache accepts one CPU request at a time. The requester asserts `cpu_valid`
and keeps the write flag, address, write data, and byte strobes unchanged until
the rising edge on which `cpu_ready` is high. `cpu_ready` is a one-cycle
completion indication. A read result is valid in `cpu_rdata` on that edge.

Line writeback and refill use word transactions on the backing-memory port.
For every word, `mem_valid`, direction, address, data, and strobes remain stable
until a rising edge with `mem_ready`. Writebacks use `mem_wstrb=4'b1111`;
refills use `mem_write=0` and consume `mem_rdata`. Only one backing-memory
transaction is outstanding.

Reset is synchronous and active high. It cancels any CPU or memory operation,
invalidates both ways, clears dirty/LRU metadata and counters, and suppresses
both ready/valid completion signals. Data RAM contents are deliberately not
reset, because invalid lines cannot be read and clearing the whole array would
create unnecessary reset logic.

## Replacement and writes

Each way stores the full address line number with its valid and dirty bits. A
per-set LRU bit identifies the victim after both ways become valid; an invalid
way is always chosen first. A dirty victim is written back one word at a time,
then the requested line is refilled one word at a time.

CPU stores merge only lanes selected by `cpu_wstrb`. This merge occurs on both
hits and write-allocate refills, and the line becomes dirty. Thus byte and other
partial stores retain the untouched bytes from the cached or refilled word.

`hit_count` and `miss_count` count CPU requests once when lookup classifies
them. `writeback_count` counts completed dirty line evictions, rather than the
individual word writes within an eviction. All counters wrap naturally at
32 bits.

## Verification

Run the unit verification from the repository root:

```powershell
python tests/run_cache.py
```

The runner invokes Vivado Simulator 2019.2 (`xvlog`, `xelab`, and `xsim`) with
`build/cache` as the working directory. It runs the default 16-set/four-word
configuration, a four-set/two-word variant, and a functional one-set/one-word
smoke configuration. It also verifies explicit rejection of zero and three for
each parameter, covering the non-positive and non-power-of-two cases.

The self-checking testbench uses an independent backing-memory array and
architectural reference array. Its deterministic memory model applies every
delay from zero through seven cycles and rejects unstable requests. Directed
tests cover both ways, LRU selection, clean and dirty replacement, exact line
transaction counts, all four individual byte strobes, partial-store
persistence after eviction, request holding, counter values, reset during a
stalled refill, and reset during a stalled dirty writeback. A deterministic
random workload then compares every read against the independent reference.

This verifies the standalone cache module only. CPU/cache/SoC integration and
the complete C10 capability evidence remain pending.
