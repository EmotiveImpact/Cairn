# Ruby cleanup safety, 9 November 2026

## Implemented

Old Ruby gem versions remain visible as unselected advice, with an explicitly estimated size. Cairn no longer emits an executable `gem cleanup` item: that command discovers its own roots and versions, not the folders represented by the scan. The executor independently refuses legacy gem cleanup commands before resolving or starting the tool.

The scanner's measurement/result helper accepts explicit roots so fixtures never inspect a real Ruby installation. Safety checks cover multiple roots, changed installed versions, changed roots, cancelled inspection, non-executable advice, legacy command argument variants, executor rejection and unchanged fixture files. Executor regression uses a nonexistent absolute tool path, which ToolRunner independently refuses if the policy guard regresses.

## Verification

- `git diff --check`: passed.
- Source review confirms tool refusal happens before ToolRunner availability/start.
- This Linux workspace has no Swift/macOS compiler. Build and native disposable suites remain pending on the combined safety branch CI.
- No personal Ruby stores or files were modified, and no Ruby cleanup command was run.

## Boundary

This withdraws the unsafe adapter rather than claiming a certified, narrower RubyGems removal implementation. It does not fix the other scheduled-cleaning or model-removal review findings by itself and is not release certification.
