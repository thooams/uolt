# Data Model: uolt-true

**Not applicable.** `uolt-true` processes no input, manages no state, and produces no output.
It has no entities, fields, relationships, or state transitions.

The only "state" is the process exit status, fixed at `0` (`EXIT_SUCCESS`). See
[contracts/cli.md](./contracts/cli.md) for the observable contract.
