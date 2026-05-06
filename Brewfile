# Tooling required to build a JuiceScreen release locally and on macos-15 CI.
# Used by .github/workflows/release.yml via `brew bundle --file=Brewfile`.
#
# Homebrew formula versions are not pinnable inline. The release workflow logs
# the resolved version of each tool so drift becomes visible in the workflow
# output. If a tool's major version bumps and breaks the release pipeline,
# pin via a tap/commit ref or downgrade locally before re-running.

brew "xcodegen"
brew "create-dmg"
brew "xcbeautify"
