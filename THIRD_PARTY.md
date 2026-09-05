# References and redistribution boundaries

The RTL in this repository is a new implementation. Existing student projects
were inspected and probed before implementation; they are not treated as a
correctness oracle. No old XPR/XDC project was imported into the board build.

| Reference | Inspected revision | Use |
|---|---|---|
| [I-Rinka/build-cpu-within-20days](https://github.com/I-Rinka/build-cpu-within-20days) | 51740630c0b492c2ff2f95c5190f5e052c5351db | Single-cycle/pipeline decomposition and defect probes; MIT |
| [zan-pu/pipelined-zanpu](https://github.com/zan-pu/pipelined-zanpu) | 8b838dd3a3799a90beeece818f185a4cb39684c1 | Pipeline source organization and defect probes; MIT |
| [zan-pu/documentation](https://github.com/zan-pu/documentation) | f6e3f4e517b2270f57636dd1d461562e39d29b88 | Report structure; no full text republished |
| [zan-pu/diagram](https://github.com/zan-pu/diagram) | 64532785a130ed32dcbe6e00b3a6254ea4cd3a37 | Datapath comparisons; our diagrams use our signals |
| [ZanPU documentation](https://zanpu.spencerwoo.com/3_pipelining/3-5_design) | accessed during source assessment | Historical design explanation; not 2026 grading criteria |
| [bit-mips/bitmips_experiments](https://github.com/bit-mips/bitmips_experiments) | eaf1ad0b2badf93c6abf1cdd1296849212c76365 | Course integration reference; local supplied lab5 image/trace tested separately |
| [bit-mips/bitmips_experiments_doc](https://github.com/bit-mips/bitmips_experiments_doc) | 3e87fe78509f50d7ead30807f6722201eea84701 | Experiment workflow reference |
| [Oldmemory1/BIT-Computer-Organization-and-Architecture](https://github.com/Oldmemory1/BIT-Computer-Organization-and-Architecture) | 23afed7a27c7a783fa2020b092898c257ebfe5e9 | Lab workflow only; its ISA encoding is not reused |

The optional [VGA reference](https://github.com/zan-pu/vga-driver) was not adopted;
the selected expansion peripheral is the EES-338 on-board buzzer.

Teacher PDFs, textbook scans, vendor PDFs, MARS JAR, Vivado executables, original
lab5 source/image/golden trace are not redistributed here. Tests locate the
user-provided originals via documented environment variables, copy only to
ignored build directories and record their hashes. Original locally supplied
course copies may differ from the repository revisions listed above.

Generated UART IP sources are copies of our own RTL. Vivado-generated IP metadata
and GUI Tcl identify their generating tool; packaged source is reproducible with
`scripts/package_uart_ip.tcl`. MIT licensing here does not relicense third-party
tool binaries or materials not distributed by this repository.
