# Actions budget decision — 2026-10-01

Navid requested a temporary pause of nonessential automatic Actions, with tests kept in the repository for manual execution on owned machines. A renewed monthly allowance is not permission to restore automatic runs.

## Rules for agents

- Do not add or restore automatic CI triggers, scheduled runs, browser tests or Mac build matrices without Navid's explicit approval. This also applies to older PRs and template updates.
- Keep all tests and quality requirements. Record local commands, the checked commit and results in each PR. Missing CI is not a passing test; failing tests must still be fixed.
- Run GitHub checks deliberately for substantial changes: authentication/authorization, migrations, deployment, new modules or major behavior changes. “Major” describes impact, not a SemVer major-version change.
- Future automatic checks require an explicit agreed opt-in and relevant file filters; avoid duplicate runs and unnecessary matrices. No recurring E2E schedule by default.
- Reserve hosted capacity for releases, secrets rotation and urgent fixes. Measure usage before setting a numerical budget; do not enable paid overages without approval.
- Do not cancel production deploys or infrastructure applies. Production actions retain their own approval requirements.

## Verification and activation

Workflow YAML and trigger conditions are checked locally for this change. No full application suite or hosted build is needed for this trigger/documentation-only edit. Main branch metadata currently reports no enforced status checks; branch protection is unchanged. The new triggers take effect only after the PR is merged. Existing running jobs and workflows introduced by other open PRs are not disabled by this change.

## Implementation in this repository

Swift package tests and iPhone/iPad and Mac Catalyst builds run only through manual CI on the selected branch. Local Mac commands: `swift test` in `Packages/LifeOSKit`, then XcodeGen and the xcodebuild commands in `.github/workflows/ci.yml`. No self-hosted runners are configured.
