# REQ Requirements

> Single-doc requirements register (project-reqs skill).
> Lifecycle: intent → in-progress → done   (off-ramps: blocked, scrapped)
> Protection: every Hard Requirement is protected until explicitly scrapped.
> JIRA: a ticket is a Unit of Intent until its sprint is active, then it promotes.
> Generated from requirements/<slug>.md by rapid (.rapid/lib/reqs.sh); never edit it by hand:
> pre-commit regenerates it, and rapid land refuses a register that differs from its tree.

## Hard Requirements
<!-- Committed + protected. A regression against any row here is a release-blocker. -->

| ID | Requirement | Pri | Status | Tests | Source | Trace |
|----|-------------|-----|--------|-------|--------|-------|
| REQ-R-forge-261114002533 | The canary keeps the rulesets and the rapid-check workflow of run 261114002533 on the forge. | P2 | ✅ done | ✅ `forge-261114002533.txt` | internal | `chore/forge-261114002533` |
| REQ-R-forge-261114002804 | The canary keeps the rulesets and the rapid-check workflow of run 261114002804 on the forge. | P2 | ✅ done | ✅ `forge-261114002804.txt` | internal | `chore/forge-261114002804` |
| REQ-R-forge-261114002945 | The canary keeps the rulesets and the rapid-check workflow of run 261114002945 on the forge. | P2 | ✅ done | ✅ `forge-261114002945.txt` | internal | `chore/forge-261114002945` |
| REQ-R-widget-261114002804 | A widget branch of run 261114002804 runs the forge jobs green. | P1 | ✅ done | ✅ `widget-261114002804.txt` | internal | `feature/widget-261114002804` |
| REQ-R-widget-261114002945 | A widget branch of run 261114002945 runs the forge jobs green. | P1 | ✅ done | ✅ `widget-261114002945.txt` | internal | `feature/widget-261114002945` |

## Units of Intent
<!-- NOT binding, NOT protected. Promotes to a Hard Requirement through a branch whose file says Promotes: <slug>. -->

| ID | Intent | Pri | Source | Sprint | Notes |
|----|--------|-----|--------|--------|-------|

## Scrapped
<!-- Graveyard. Kept for traceability. Never deleted. -->

| ID | Requirement | Scrapped | Why |
|----|-------------|----------|-----|
