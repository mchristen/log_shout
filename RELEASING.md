# Releasing LogShout

## One-time account setup

1. Confirm the gem name `log_shout` is available or owned by your RubyGems account.
2. Enable MFA on that account. The gem declares `rubygems_mfa_required`.
3. On RubyGems, create a pending trusted publisher for a first release (or a
   trusted publisher on the existing gem):
   - Gem: `log_shout`
   - Repository owner: `mchristen`
   - Repository: `log_shout`
   - Workflow filename: `release.yml`
   - Environment: `release`
4. In the GitHub repository, create a `release` environment with required reviewer
   approval if available for the repository, and protect your release branches.

See the official [Trusted Publishing guide](https://guides.rubygems.org/trusted-publishing/).
No long-lived RubyGems API token is needed by the workflow.

## Each release

1. Set `LogShout::VERSION` in `lib/log_shout/version.rb`. Update the matching
   changelog entry with the release date and user-visible changes. Verify the
   maintainer email and public metadata before the first release.
2. If dependencies change, run `bundle _2.7.2_ lock`, regenerate `gemset.nix`
   with `bundix`, and commit both lock representations.
3. Run `bundle exec rake`, `bundle exec rake build`, and
   `ruby script/check_package.rb`. Inspect the packaged file list. The package
   check installs runtime dependencies from RubyGems into a temporary directory.
4. Commit all release changes and ensure CI passes on Ruby 4.0.0 and the latest
   4.0 patch release. Review the exact commit to publish.
5. Create and push the matching version tag, for example `v0.1.0`, pointing at
   that tested commit.
6. In GitHub Actions, manually run **Release** from the default branch, entering
   that existing tag. It verifies the tag matches the gemspec, reruns checks,
   and publishes through RubyGems Trusted Publishing. Approve the `release`
   environment deployment when configured.
7. Verify the published version and its metadata on RubyGems, then create release
   notes from the changelog. Published version numbers cannot be reused.

The repository includes preparation and verification code only; account setup,
pushing release tags, and publishing are deliberate maintainer actions.
