# Run using bin/ci

CI.run do
  step "Setup", "bin/setup --skip-server"

  step "Style: Ruby", "bin/rubocop"
  step "Packages: packwerk", "bin/packwerk validate && bin/packwerk check"
  step "Ledgers: open items", "bin/check-open-items"
  step "Ledgers: commit references", "bin/check-commit-refs"
  step "GraphQL: schema compatibility", "bin/check-schema-compat"

  step "Tests: RSpec", "bin/rails db:test:prepare && COVERAGE=1 FULL_SUITE=1 bundle exec rspec --format progress --format json --out tmp/rspec.json"
  step "Tests: branch coverage", "bin/check-branch-coverage"
  step "Tests: layers", "bin/test-layers tmp/rspec.json"
  step "Schema: structure.sql round-trip", "bin/check-structure"
  step "Alerts: promtool", "bin/check-alerts"

  step "Security: Gem audit", "bin/bundler-audit"
  step "Security: Brakeman code analysis", "bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error"


  # Optional: set a green GitHub commit status to unblock PR merge.
  # Requires the `gh` CLI and `gh extension install basecamp/gh-signoff`.
  # if success?
  #   step "Signoff: All systems go. Ready for merge and deploy.", "gh signoff"
  # else
  #   failure "Signoff: CI failed. Do not merge or deploy.", "Fix the issues and try again."
  # end
end
