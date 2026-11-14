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
| REQ-R-forge-261114014554 | The canary keeps the rulesets and the rapid-check workflow of run 261114014554 on the forge. | P2 | ✅ done | ✅ `forge-261114014554.txt` | internal | `chore/forge-261114014554` |
| REQ-R-forge-261114020513 | The canary keeps the rulesets and the rapid-check workflow of run 261114020513 on the forge. | P2 | ✅ done | ✅ `forge-261114020513.txt` | internal | `chore/forge-261114020513` |
| REQ-R-forge-261114055524 | The canary keeps the rulesets and the rapid-check workflow of run 261114055524 on the forge. | P2 | ✅ done | ✅ `forge-261114055524.txt` | internal | `chore/forge-261114055524` |
| REQ-R-forge-261114065910 | The canary keeps the rulesets and the rapid-check workflow of run 261114065910 on the forge. | P2 | ✅ done | ✅ `forge-261114065910.txt` | internal | `chore/forge-261114065910` |
| REQ-R-gadget-261114002945 | A gadget branch of run 261114002945 lands through its pull request. | P1 | ✅ done | ✅ `gadget-261114002945.txt` | internal | `feature/gadget-261114002945` |
| REQ-R-gadget-261114014554 | A gadget branch of run 261114014554 lands through its pull request. | P1 | ✅ done | ✅ `gadget-261114014554.txt` | internal | `feature/gadget-261114014554` |
| REQ-R-gadget-261114020513 | A gadget branch of run 261114020513 lands through its pull request. | P1 | ✅ done | ✅ `gadget-261114020513.txt` | internal | `feature/gadget-261114020513` |
| REQ-R-gadget-261114055524 | A gadget branch of run 261114055524 lands through its pull request. | P1 | ✅ done | ✅ `gadget-261114055524.txt` | internal | `feature/gadget-261114055524` |
| REQ-R-gadget-261114065910 | A gadget branch of run 261114065910 lands through its pull request. | P1 | ✅ done | ✅ `gadget-261114065910.txt` | internal | `feature/gadget-261114065910` |
| REQ-R-plainv9-3-230313 | A probe branch of the canary shows a plain push of a branch. | P1 | ✅ done | ✅ `w3.txt` | internal | `feature/plainv9-3-230313` |
| REQ-R-review-261114002945 | Lands of run 261114002945 go through review on the forge. | P2 | ✅ done | ✅ `review-261114002945.txt` | internal | `chore/review-261114002945` |
| REQ-R-review-261114014554 | Lands of run 261114014554 go through review on the forge. | P2 | ✅ done | ✅ `review-261114014554.txt` | internal | `chore/review-261114014554` |
| REQ-R-review-261114020513 | Lands of run 261114020513 go through review on the forge. | P2 | ✅ done | ✅ `review-261114020513.txt` | internal | `chore/review-261114020513` |
| REQ-R-review-261114055524 | Lands of run 261114055524 go through review on the forge. | P2 | ✅ done | ✅ `review-261114055524.txt` | internal | `chore/review-261114055524` |
| REQ-R-review-261114065910 | Lands of run 261114065910 go through review on the forge. | P2 | ✅ done | ✅ `review-261114065910.txt` | internal | `chore/review-261114065910` |
| REQ-R-unreview-261114003642 | Lands of the canary go back to optional review. | P2 | ✅ done | ✅ `unreview-261114003642.txt` | internal | `chore/unreview-261114003642` |
| REQ-R-unreview-261114014554 | Run 261114014554 puts lands back to optional review. | P2 | ✅ done | ✅ `unreview-261114014554.txt` | internal | `chore/unreview-261114014554` |
| REQ-R-unreview-261114020513 | Run 261114020513 puts lands back to optional review. | P2 | ✅ done | ✅ `unreview-261114020513.txt` | internal | `chore/unreview-261114020513` |
| REQ-R-unreview-261114055524 | Run 261114055524 puts lands back to optional review. | P2 | ✅ done | ✅ `unreview-261114055524.txt` | internal | `chore/unreview-261114055524` |
| REQ-R-unreview-261114065910 | Run 261114065910 puts lands back to optional review. | P2 | ✅ done | ✅ `unreview-261114065910.txt` | internal | `chore/unreview-261114065910` |
| REQ-R-upgrade-261114014554 | The canary takes the framework under test for run 261114014554. | P2 | ✅ done | ✅ `.rapid/rapid` | internal | `chore/upgrade-261114014554` |
| REQ-R-upgrade-261114020513 | The canary takes the framework under test for run 261114020513. | P2 | ✅ done | ✅ `.rapid/rapid` | internal | `chore/upgrade-261114020513` |
| REQ-R-upgrade-261114055524 | The canary takes the framework under test for run 261114055524. | P2 | ✅ done | ✅ `.rapid/rapid` | internal | `chore/upgrade-261114055524` |
| REQ-R-upgrade-261114065910 | The canary takes the framework under test for run 261114065910. | P2 | ✅ done | ✅ `.rapid/rapid` | internal | `chore/upgrade-261114065910` |
| REQ-R-upgrade-policy-261114014554 | Run 261114014554 lets a framework upgrade land as one commit on the canary. | P2 | ✅ done | ✅ `upgrade-policy-261114014554.txt` | internal | `chore/upgrade-policy-261114014554` |
| REQ-R-widget-261114002804 | A widget branch of run 261114002804 runs the forge jobs green. | P1 | ✅ done | ✅ `widget-261114002804.txt` | internal | `feature/widget-261114002804` |
| REQ-R-widget-261114002945 | A widget branch of run 261114002945 runs the forge jobs green. | P1 | ✅ done | ✅ `widget-261114002945.txt` | internal | `feature/widget-261114002945` |
| REQ-R-widget-261114014554 | A widget branch of run 261114014554 runs the forge jobs green. | P1 | ✅ done | ✅ `widget-261114014554.txt` | internal | `feature/widget-261114014554` |
| REQ-R-widget-261114020513 | A widget branch of run 261114020513 runs the forge jobs green. | P1 | ✅ done | ✅ `widget-261114020513.txt` | internal | `feature/widget-261114020513` |
| REQ-R-widget-261114055524 | A widget branch of run 261114055524 runs the forge jobs green. | P1 | ✅ done | ✅ `widget-261114055524.txt` | internal | `feature/widget-261114055524` |
| REQ-R-widget-261114065910 | A widget branch of run 261114065910 runs the forge jobs green. | P1 | ✅ done | ✅ `widget-261114065910.txt` | internal | `feature/widget-261114065910` |

## Units of Intent
<!-- NOT binding, NOT protected. Promotes to a Hard Requirement through a branch whose file says Promotes: <slug>. -->

| ID | Intent | Pri | Source | Sprint | Notes |
|----|--------|-----|--------|--------|-------|

## Scrapped
<!-- Graveyard. Kept for traceability. Never deleted. -->

| ID | Requirement | Scrapped | Why |
|----|-------------|----------|-----|
