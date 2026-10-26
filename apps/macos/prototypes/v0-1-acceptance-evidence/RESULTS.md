# Results

## Decision

The user approved the dark-mode acceptance-evidence prototype as the macOS
v0.1 release gate.

Release is ready only when all 29 required items pass. A failed or unchecked
item blocks release; there is no score, waiver-by-percentage, or retry-until-
green rule.

The required evidence is grouped as follows:

- 6 deterministic core tests for eligibility, no-read protection, workflow,
  cancellation, presentation state, and permission isolation;
- 6 API-adapter tests for the exact request, all three language verdicts,
  errors, deadline/no-retry behavior, URL policy, and ephemeral/log-free
  transport;
- 6 adapter integration checks using native and browser fixtures, Chrome's
  on-demand AX activation, focus races, real permission state, and URLSession;
- 8 repeatable manual checks covering TextEdit, Safari, Chrome, permission UI,
  menu/shortcut behavior, visible failures, a synthetic privacy canary, and
  macOS 14 plus the current development macOS;
- 3 release-boundary checks tying the client to the tested language API
  contract, naming only supported application surfaces, and producing a
  reproducible metadata-only report.

Detector accuracy remains validated in the separate language API repository.
The desktop release gate verifies the client contract and privacy behavior; it
does not claim support for Apple Mail, complex editors, or correction.
