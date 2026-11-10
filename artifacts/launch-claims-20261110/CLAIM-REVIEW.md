# Cairn public-claim review

Reviewed 10 November 2026 against master `7129dff82375694c4248ee6cd187c183314357c3`, containing merged PRs [#27](https://github.com/EmotiveImpact/Cairn/pull/27) and [#28](https://github.com/EmotiveImpact/Cairn/pull/28).

## Scope and preservation

Text and accessible descriptions only in the approved homepage. All scene elements, hierarchy, classes, IDs, media, inline styles, numeric animation data and links remain in place. The four pinned motion/style files and the original October main-markup hash remain unchanged. The preservation test reverses only the enumerated text edits and checks the entire original homepage hash as well. Supporting changes update their generators and committed output. Archived design studies are outside the active export and remain untouched.

The screenshot artwork is deliberately retained. Its historic sample figures remain visibly labelled as development data and are not represented as measured results.

## Evidence and consequential claims

[Native CI run 42720760461](https://github.com/EmotiveImpact/Cairn/actions/runs/42720760461) completed successfully on head `8193b1cbb4ce367a94e871bed04ee95fef1ca75e`. Job steps were independently read: packaging failure checks, debug build, safety, workspace, licence, evidence, reliability, lifecycle/crash, CLI refusal and universal release build/reliability all succeeded. The licence suite uses test doubles; the CI package is ad-hoc signed. This does not establish live licensing, real Keychain or distribution acceptance.

The earlier safety artifact files record pending native checks at the time they were written. PR #27 and its exact-head run supersede that pending-CI status, but do not close their physical-Mac or live-service gates.

### sample

The 38.6 GB and capacity figures are authored examples, not a measured benchmark. Preserve the animation values and historic app captures but label every scene, visible total and accessible description. The chat shows three rows totalling 33.5 GB, so its 38.6 GB total must identify the omitted 5.1 GB npm example.

- [website/v2/story.html](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/website/v2/story.html)
- [website/v2/story.js](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/website/v2/story.js)
- [artifacts/site-completion-20261109/SCROLL-VERIFICATION.md](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/artifacts/site-completion-20261109/SCROLL-VERIFICATION.md)

### protection

Protection uses known paths, names, source identity and policy. It is not a proof that every source file, export, conversation or cloud folder is protected everywhere. Replace absolute assurances with the actual boundary and review requirement.

- [Cairn/Core/SafePaths.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/SafePaths.swift)
- [Cairn/Safety/Cleaner.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Safety/Cleaner.swift)
- [Cairn/Safety/Regenerability.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Safety/Regenerability.swift)
- [Cairn/Diagnostics/SafetyCheck.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Diagnostics/SafetyCheck.swift)

### agent

Connections are optional. AgentCleaningMode defaults to off, but ask and allow are both implemented; allow does not require a fresh human prompt for each eligible cleanup. Scheduled rules also act after prior scoped consent. Connected clients may process paths through their own provider.

- [Cairn/Core/AgentCleanup.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/AgentCleanup.swift)
- [Cairn/App/MCPServer.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/App/MCPServer.swift)
- [Cairn/Core/AgentConnections.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/AgentConnections.swift)
- [Cairn/App/RuleRunner.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/App/RuleRunner.swift)
- [website/v2/site/content.cjs](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/website/v2/site/content.cjs)

### accounting

Candidate size is not reclaimed capacity. Trash and retained-source export have zero immediate reclaim; tool estimates differ from later capacity readings. The cartoon capacity increase remains illustrative.

- [Cairn/Core/CleanupAccounting.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/CleanupAccounting.swift)
- [Cairn/Core/ReclaimStats.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/ReclaimStats.swift)
- [Cairn/Core/ScanStore.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/ScanStore.swift)
- [Cairn/Diagnostics/ReliabilityCheck.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Diagnostics/ReliabilityCheck.swift)

### coverage

Scans have permission, time and coverage limits; package sizes may be partial or estimated. A disk map is not a complete attribution of every byte.

- [Cairn/Core/DiskMap.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/DiskMap.swift)
- [Cairn/Core/LocationMeasurement.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/LocationMeasurement.swift)
- [Cairn/Scanners/GitMaintenanceScanner.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Scanners/GitMaintenanceScanner.swift)
- [docs/STORAGE-CONTROL-CAPABILITIES.md](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/docs/STORAGE-CONTROL-CAPABILITIES.md)

### recovery

Put Back depends on a matching recorded Trash item. Direct deletion, tool actions, emptied Trash and changed items do not offer universal reversal.

- [Cairn/Core/RecoveryHistory.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/RecoveryHistory.swift)
- [Cairn/Core/ActionJournal.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/ActionJournal.swift)
- [Cairn/Safety/Cleaner.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Safety/Cleaner.swift)
- [Cairn/Diagnostics/ModelSafetyCheck.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Diagnostics/ModelSafetyCheck.swift)

### scope

Methods vary by category. Final Cut libraries are advice-only; virtual-machine disk files are not directly removed. In-use checks detect known processes and recent project output, not every possible user. Ruby gem findings are advice only and legacy execution is refused.

- [Cairn/Scanners/CreativeCachesScanner.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Scanners/CreativeCachesScanner.swift)
- [Cairn/Scanners/DockerScanner.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Scanners/DockerScanner.swift)
- [Cairn/Core/InUse.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/InUse.swift)
- [Cairn/Safety/Cleaner.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Safety/Cleaner.swift)
- [artifacts/gem-safety-20261109/VERIFICATION.md](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/artifacts/gem-safety-20261109/VERIFICATION.md)

### git

The scanner emits git gc --prune=now as an unselected review candidate. Do not advertise an unconditional preservation or undo guarantee for Git maintenance. Source-control path guards still apply; a scanner candidate is not certification of an executable adapter.

- [Cairn/Scanners/GitMaintenanceScanner.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Scanners/GitMaintenanceScanner.swift)
- [Cairn/Safety/Cleaner.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Safety/Cleaner.swift)
- [Cairn/Core/SafePaths.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/SafePaths.swift)

### snapshots

Local snapshot removal reduces the local rollback window. Per-snapshot savings are not measurable in this scanner, so it emits unknown sizes and unselected review candidates.

- [Cairn/Scanners/TimeMachineSnapshotsScanner.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Scanners/TimeMachineSnapshotsScanner.swift)

### model

PR #27 routes eligible local-model removal through identity checks, the shared journal, Trash and recorded Put Back. Ollama exposes a command to copy, not the same in-app removal path. No live model or Apple service acceptance is established.

- [Cairn/Core/LocalModels.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/LocalModels.swift)
- [Cairn/UI/AppleIntelligenceWorkspace.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/UI/AppleIntelligenceWorkspace.swift)
- [Cairn/Diagnostics/ModelSafetyCheck.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Diagnostics/ModelSafetyCheck.swift)
- [artifacts/model-safety-20261109/VERIFICATION.md](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/artifacts/model-safety-20261109/VERIFICATION.md)

### transfer

The supported export requires an eligible external, local, writable, identified, encrypted APFS drive. It retains the source and does not free internal capacity.

- [Cairn/Core/StorageTransfer.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/StorageTransfer.swift)
- [docs/STORAGE-CONTROL-CAPABILITIES.md](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/docs/STORAGE-CONTROL-CAPABILITIES.md)

### commercial

£35.99 and a one-time major-version licence are plans, not a live offer. No approved two-year macOS update commitment, future upgrade fee or unconditional perpetual compatibility is evidenced. Licensing uses activation and a 30-day offline allowance.

- [Cairn/Licensing/Licensing.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Licensing/Licensing.swift)
- [website/v2/site/content.cjs](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/website/v2/site/content.cjs)
- [artifacts/site-completion-20261109/SCROLL-VERIFICATION.md](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/artifacts/site-completion-20261109/SCROLL-VERIFICATION.md)

### release

macOS 14, arm64 and x86_64 are build targets. PR #27 CI passed, but CI packages are development artifacts, not notarised public releases. GitHub releases returned an empty list on 10 November. No checkout, public download, public deployment or supported-hardware acceptance was verified.

- [Package.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Package.swift)
- [.github/workflows/ci.yml](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/.github/workflows/ci.yml)
- [build_release.sh](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/build_release.sh)
- [website/v2/site/content.cjs](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/website/v2/site/content.cjs)

### pr27

Merged safeguards passed macOS CI at exact head 8193b1cbb4ce367a94e871bed04ee95fef1ca75e. Scheduled rules are sealed/scoped, revocable and Trash-only; eligible models use recorded recovery; Apple requests check cancellation; Ruby gem execution is refused. Admitted moves or macOS requests cannot be recalled. Failed protected-state writes require a retry, not a claim of durable cancellation. Live Keychain, hardware UI and live services remain unverified.

- [Cairn/Core/CleaningRules.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/CleaningRules.swift)
- [Cairn/Core/RuleConsentStore.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/RuleConsentStore.swift)
- [Cairn/Core/RuleStateWorker.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/RuleStateWorker.swift)
- [Cairn/App/RuleRunner.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/App/RuleRunner.swift)
- [Cairn/Core/AppleIntelligence.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Core/AppleIntelligence.swift)
- [Cairn/Diagnostics/CleaningRuleCheck.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Diagnostics/CleaningRuleCheck.swift)
- [Cairn/Diagnostics/ModelSafetyCheck.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Diagnostics/ModelSafetyCheck.swift)
- [Cairn/Diagnostics/LifecycleCheck.swift](https://github.com/EmotiveImpact/Cairn/blob/7129dff82375694c4248ee6cd187c183314357c3/Cairn/Diagnostics/LifecycleCheck.swift)

## Exact source wording changes

Every row is a literal replacement. Repeated occurrences are counted. HTML delimiters appear where needed to disambiguate the exact text. Generated pages inherit the source changes; the GitHub diff shows those outputs too.

| Source | Before | After | Evidence |
| --- | --- | --- | --- |
| `website/v2/story.html` | &lt;span&gt;Download app&lt;/span&gt; | &lt;span&gt;Download status&lt;/span&gt; | [release](#release) |
| `website/v2/story.html` ×2 | Download for Mac | Check availability | [release](#release) |
| `website/v2/story.html` | And works with your AI coding tools. Build files and caches go. Your code and AI conversations are never touched. | Review build files and caches, with optional AI-tool connections. Known working locations have protection checks. | [protection](#protection) |
| `website/v2/story.html` | found on a typical developer Mac | illustrative scan, not a benchmark | [sample](#sample) |
| `website/v2/story.html` | &lt;dt&gt;3 AI tools&lt;/dt&gt;&lt;dd&gt;Claude Code, Codex and Cursor&lt;/dd&gt; | &lt;dt&gt;AI tools&lt;/dt&gt;&lt;dd&gt;optional local connections&lt;/dd&gt; | [agent](#agent) |
| `website/v2/story.html` | &lt;dt&gt;0 files&lt;/dt&gt;&lt;dd&gt;of your code ever touched&lt;/dd&gt; | &lt;dt&gt;Review first&lt;/dt&gt;&lt;dd&gt;check each path and requirement&lt;/dd&gt; | [protection](#protection) |
| `website/v2/story.html` | Build files, caches and old installs pile up quietly while you work. Cairn shows you what each one is and clears only what your tools can make again. | Build files, caches and old installs pile up quietly. Cairn identifies candidates; you review their paths, requirements and removal methods. | [scope](#scope) |
| `website/v2/story.html` | Ask for it from Claude Code, Codex or Cursor. Your code and AI conversations are never touched. | Connect Claude Code, Codex or Cursor to inspect storage. Cleaning needs separate permission; the client may share results with its provider. | [agent](#agent) |
| `website/v2/story.html` | On a typical developer Mac | An illustrative scan | [sample](#sample) |
| `website/v2/story.html` | aria-label="38.6 gigabytes" | aria-label="Illustrative scan: 38.6 gigabytes, not a measured benchmark" | [sample](#sample) |
| `website/v2/story.html` | That’s what your tools left behind. &lt;span&gt;Build files and caches, made again when needed.&lt;/span&gt; | What a scan could find. &lt;span&gt;Example figures. Your results will vary.&lt;/span&gt; | [sample](#sample) |
| `website/v2/story.html` | aria-label="What makes up 38.6 GB" | aria-label="Illustrative breakdown of 38.6 GB" | [sample](#sample) |
| `website/v2/story.html` | See it at a glance | An illustrative disk | [sample](#sample) |
| `website/v2/story.html` | Your whole disk, in one picture. &lt;span&gt;The junk lights up. Your work stays put.&lt;/span&gt; | A view of your disk. &lt;span&gt;Inspect candidates and scan coverage.&lt;/span&gt; | [coverage](#coverage) |
| `website/v2/story.html` | &lt;em class="ready-a"&gt;ready to free&lt;/em&gt;&lt;em class="ready-b"&gt;cleaned up&lt;/em&gt; | &lt;em class="ready-a"&gt;example candidates&lt;/em&gt;&lt;em class="ready-b"&gt;example change&lt;/em&gt; | [accounting](#accounting) |
| `website/v2/story.html` | Macintosh HD, 494 GB: your projects 142 GB and AI conversations 3.1 GB are protected; Xcode build files 14.2 GB, Docker build cache 9.8 GB, node_modules 9.5 GB and npm 5.1 GB are ready to free; photos 61 GB, apps 48 GB and system 160 GB are left alone. After cleaning, free space grows from 42.6 GB to 81.2 GB. | Illustrative disk animation, not a scan or cleanup result. Example candidates total 38.6 GB; the animated free-space figure changes from 42.6 to 81.2 GB. Candidate sizes do not predict reclaimed space. Moving to Trash does not free space. | [accounting](#accounting) |
| `website/v2/story.html` | &lt;i&gt;&lt;/i&gt;Ready to free | &lt;i&gt;&lt;/i&gt;Candidates | [accounting](#accounting) |
| `website/v2/story.html` | &lt;i&gt;&lt;/i&gt;Protected, never touched | &lt;i&gt;&lt;/i&gt;Known protected paths | [protection](#protection) |
| `website/v2/story.html` | Scroll to clean it up | Scroll to see the example | [sample](#sample) |
| `website/v2/story.html` | &lt;b&gt;38.6 GB back.&lt;/b&gt; Your projects, photos and AI chats didn’t move. | &lt;b&gt;Illustrative change.&lt;/b&gt; Actual space varies. Trash alone frees none. | [accounting](#accounting) |
| `website/v2/story.html` | Works with your AI coding tools | Optional AI-tool connections | [agent](#agent) |
| `website/v2/story.html` | Ask Claude Code, Codex or Cursor what’s filling your Mac. Cairn answers with real sizes. | Connect Claude Code, Codex or Cursor to inspect storage. This conversation shows sample data. | [agent](#agent) |
| `website/v2/story.html` | &lt;b&gt;Real sizes, measured on your Mac.&lt;/b&gt; No guesses, no scary warnings. | &lt;b&gt;Sizes, with their limits.&lt;/b&gt; Estimates and partial scans are labelled. | [coverage](#coverage) |
| `website/v2/story.html` | &lt;b&gt;Nothing moves until you say so.&lt;/b&gt; Every clean is reviewed first. | &lt;b&gt;Cleaning is off by default.&lt;/b&gt; Choose review or permitted automation. | [agent](#agent) |
| `website/v2/story.html` | &lt;b&gt;Your code and conversations are never included.&lt;/b&gt; | &lt;b&gt;Known working locations have protection checks.&lt;/b&gt; | [protection](#protection) |
| `website/v2/story.html` | Claude Code chat: asked what is taking up space, Cairn lists Xcode build files 14.2 GB, Docker build cache 9.8 GB and node_modules 9.5 GB, 38.6 GB in total. | Illustrative AI-tool conversation with sample sizes, not a live result. The 38.6 GB total includes 5.1 GB of npm cache not shown in the three rows. | [sample](#sample) |
| `website/v2/story.html` | Cairn found build files and caches your tools can rebuild on their own: | Example candidates to review for rebuildability: | [scope](#scope) |
| `website/v2/story.html` | 38.6 GB&lt;span&gt;you can get back&lt;/span&gt; | 38.6 GB&lt;span&gt;example total, including npm cache&lt;/span&gt; | [sample](#sample) |
| `website/v2/story.html` | Then review it and free it, &lt;span&gt;in one calm place.&lt;/span&gt; | Then review what can go, &lt;span&gt;in one calm place.&lt;/span&gt; | [accounting](#accounting) |
| `website/v2/story.html` | Exact paths and sizes. Folders you work in stay protected. | Inspect paths, sizes and requirements before acting. | [protection](#protection) |
| `website/v2/story.html` | Every clean is recorded, with the way back for each one. | Inspect action records. Recovery depends on the method. | [recovery](#recovery) |
| `website/v2/story.html` | Real Cairn screens, example numbers | Development screens, sample data. Not measured results. | [sample](#sample) |
| `website/v2/story.html` | Render and preview files from Final Cut, Logic, Lightroom and more. | Review caches and previews. Final Cut library cleanup stays in Final Cut. | [scope](#scope) |
| `website/v2/story.html` | Caches from Slack, Discord and Notion. Each app makes them again the next time it opens. | Review recognised caches from Slack, Discord and Notion, with app-specific requirements. | [scope](#scope) |
| `website/v2/story.html` | Downloaded models, often gigabytes each. Your AI conversations are never touched. | Review downloaded models. Eligible items use Trash; Ollama removal stays in Ollama. | [model](#model) |
| `website/v2/story.html` | Plus big forgotten files, duplicates, leftovers from apps you have removed, and copies to an external drive with your originals kept. | Plus large-file, duplicate and app-leftover review, and copies to eligible encrypted APFS drives with originals kept. | [transfer](#transfer) |
| `website/v2/story.html` | Where Cairn cleans, &lt;span&gt;and where it never goes.&lt;/span&gt; | What can go, &lt;span&gt;and what needs care.&lt;/span&gt; | [scope](#scope) |
| `website/v2/story.html` | You see every item before anything goes, and nothing moves until you click Clean. | Review manual cleanups first. Scheduled rules and AI-tool cleaning need separate permission. | [agent](#agent) |
| `website/v2/story.html` | Cleared straight away | Review the removal method | [accounting](#accounting) |
| `website/v2/story.html` | Caches and build files your apps and tools make again when they need them, so the space is free at once. | Eligible caches may be deleted or sent to Trash. Tool results vary; only a fresh reading shows available space. | [accounting](#accounting) |
| `website/v2/story.html` | Build folders in your projects, such as node_modules, target, .venv and DerivedData | Recognised build folders, such as node_modules, target, .venv and DerivedData, subject to rebuildability checks | [scope](#scope) |
| `website/v2/story.html` | Docker, OrbStack and Colima space, cleared with Docker’s own commands | Docker cleanup commands; OrbStack and Colima disk guidance, not direct virtual-disk deletion | [scope](#scope) |
| `website/v2/story.html` | Spare Git storage in big repositories, tidied by Git itself. Your history stays. | Git maintenance candidates need separate review. Pruning can remove unreachable objects; it is not reversible. | [git](#git) |
| `website/v2/story.html` | Time Machine snapshots kept on this Mac, removed with macOS’s own tool. Your backup drive is not touched. | Local Time Machine snapshot removal uses macOS’s tool and reduces local recovery history. Savings are unknown. | [snapshots](#snapshots) |
| `website/v2/story.html` | Your own files, only when you pick them. Put them back from Cairn’s Activity page or the Trash. | Eligible selected files can go to Trash. Put Back needs a matching recorded item still there; Trash does not free space. | [recovery](#recovery) |
| `website/v2/story.html` | Downloaded AI models you no longer use | Eligible local AI models; Ollama offers a command to copy | [model](#model) |
| `website/v2/story.html` | Never touched | Known protected locations | [protection](#protection) |
| `website/v2/story.html` | Blocked inside Cairn itself, whatever a scan finds. | Known paths are checked, not every valuable file. Inspect unfamiliar locations and keep backups. | [protection](#protection) |
| `website/v2/story.html` | &lt;li&gt;Your source code and Git history&lt;/li&gt; | &lt;li&gt;Known source-control paths; review generated folders separately&lt;/li&gt; | [protection](#protection) |
| `website/v2/story.html` | &lt;li&gt;AI coding chats and history from Claude Code, Codex, Cursor and ChatGPT&lt;/li&gt; | &lt;li&gt;Known coding-session paths for Claude Code, Codex, Cursor and ChatGPT&lt;/li&gt; | [protection](#protection) |
| `website/v2/story.html` | &lt;li&gt;iCloud Drive, Dropbox and OneDrive folders&lt;/li&gt; | &lt;li&gt;Known iCloud and macOS CloudStorage locations&lt;/li&gt; | [protection](#protection) |
| `website/v2/story.html` | &lt;li&gt;Keychains, SSH keys, .env files and databases&lt;/li&gt; | &lt;li&gt;Known credential paths and recognised secret and database files&lt;/li&gt; | [protection](#protection) |
| `website/v2/story.html` | Folders in use, or built in the last 15 minutes, are skipped. Prefer everything to go to the Trash? Choose Move to Trash in Settings. | Detected in-use items and recent build output are skipped. Move to Trash applies to eligible files, not every tool action. Ruby gem cleanup is advice only. | [scope](#scope) |
| `website/v2/story.html` | Buy Cairn Pro · £35.99 | Planned Pro · £35.99 | [commercial](#commercial) |
| `website/v2/story.html` | Pay once and your licence never runs out. Cairn 1 gets free updates for every new macOS for at least two years after you buy. Cairn 2, when it comes, will be a small upgrade fee, and Cairn 1 keeps working if you skip it. | Planned: £35.99 once for this major version. Sales are not open. Final licence, support and update terms are pending; future macOS compatibility and upgrade pricing are not promised. | [commercial](#commercial) |
| `website/v2/story.html` | For macOS 14 Sonoma or later, on Apple silicon and Intel Macs. | Targets macOS 14+ on Apple silicon and Intel. Hardware acceptance and a notarised public release are still pending. | [release](#release) |
| `website/v2/story.html` | Everything it cleans | What it reviews | [scope](#scope) |
| `website/v2/story.html` | &lt;span&gt;Your code and AI conversations are never touched.&lt;/span&gt; | &lt;span&gt;Known working locations have protection checks.&lt;/span&gt; | [protection](#protection) |
| `website/v2/story.html` ×2 | Cairn home screen: 38.6 GB you can get back, free space over the last 30 days, what grew recently, the last clean and your AI coding tools | Sample Cairn home screen: illustrative 38.6 GB, storage history and AI tools; not measured results | [sample](#sample) |
| `website/v2/story.html` | Cairn Projects screen: 21.7 GB of build output across 8 projects, with 14.6 GB in projects left alone for 30 days or more | Sample Cairn Projects screen: illustrative build-output and idle-project figures | [sample](#sample) |
| `website/v2/story.html` ×2 | Cairn Activity screen: 31.1 GB freed this past month, with a receipt for every clean | Sample Cairn Activity screen: illustrative history and receipts; recovery varies by action | [sample](#sample) |
| `website/v2/story.html` | Cairn home screen with 38.6 GB you can get back and free space over 30 days | Sample Cairn home screen with illustrative candidate sizes and storage history | [sample](#sample) |
| `website/v2/story.html` | Cairn Clean screen: Xcode, Docker, project build files and npm ticked, 38.6 GB selected | Sample Cairn Clean screen: illustrative Xcode, Docker, project and npm candidates | [sample](#sample) |
| `website/v2/story.html` | Cairn review card: check once, then free 38.6 GB from Xcode, Docker, node_modules and npm | Sample Cairn review card: illustrative 38.6 GB selection, not guaranteed reclaimed space | [sample](#sample) |
| `website/v2/story.html` | Cairn Projects screen with 21.7 GB of build output across 8 coding projects | Sample Cairn Projects screen with illustrative build-output figures | [sample](#sample) |
| `website/v2/story.html` | Cairn Done screen: 38.6 GB freed, free space up from 42.6 GB to 81.2 GB | Sample Cairn result screen: illustrative capacity change, not a measured cleanup result | [sample](#sample) |
| `website/v2/story.html` | Screens from the Cairn app, with example numbers. | Development captures with sample data, not measured results. Recovery depends on the action. | [sample](#sample) |
| `website/v2/site/content.cjs` | Scheduled cleaning, local-model removal, Apple Intelligence controls and broad Ruby gem cleanup are still under safety review and are not presented here as release-ready. | Scheduled rules now require approved scopes and use Trash only. Eligible local models use recorded Trash recovery; Apple asset requests check cancellation. Ruby gem cleanup is advice only. These safeguards passed macOS CI; live Mac acceptance remains open. | [pr27](#pr27) |
| `website/v2/site/content.cjs` | Scheduled-rule consent, local-model removal, Apple Intelligence cancellation and broad Ruby gem cleanup require further safety work before release. | Scheduled consent and model recovery were hardened and passed macOS CI. Cancellation cannot recall an admitted move or macOS request. Failed protected-state saves need a retry before quitting; live Keychain acceptance remains open. Ruby gem cleanup is advice only. | [pr27](#pr27) |
| `website/v2/site/content.cjs` | The planned licence covers this major version. It is not a promise that all future major versions will be included. | The planned licence covers this major version. Final update and support terms remain pending; future macOS compatibility and major-version upgrade pricing are not promised. | [commercial](#commercial) |
| `website/v2/site/content.cjs` | &lt;span&gt;Safety review of experimental paths&lt;/span&gt;&lt;strong&gt;In progress&lt;/strong&gt; | &lt;span&gt;Consent &amp; recovery safeguards&lt;/span&gt;&lt;strong&gt;CI passed; Mac acceptance pending&lt;/strong&gt; | [pr27](#pr27) |
| `website/v2/site/content.cjs` | The normal workflow requires review. The source also includes opt-in scheduled rules and optional AI-tool cleaning permissions. Scheduled-rule consent is still under safety review; it is not a release-ready feature. Leave those options off when you only want to inspect storage. | Manual cleanup requires review. Opt-in scheduled rules use approved scopes and Trash only while Cairn is open. AI-tool cleaning is off by default; you can choose approval each time or permit eligible cleanup without a new prompt. macOS CI passed the consent safeguards; live acceptance remains open. Leave these options off for inspection only. | [pr27](#pr27) |
| `website/v2/site/content.cjs` | Experimental removal and automation paths still need safety work. | On 9 November, scheduled consent, cancellation and local-model recovery safeguards passed macOS CI and merged. Ruby gem cleanup is now advice only, with legacy commands refused. Physical Mac and live-service acceptance remain open. | [pr27](#pr27) |
| `website/v2/site/content.cjs` | reviewed on 9 November 2026 | reviewed on 10 November 2026 | [pr27](#pr27) |
| `website/v2/site/content.cjs` | licence records use the macOS Keychain. | licence records and protected scheduled-rule consent state use the macOS Keychain. | [pr27](#pr27) |
| `website/v2/site/content.cjs` | This review is hosted privately with ChatGPT Sites. Hosting data handling and the final public hosting arrangement still need to be reviewed before public release. | Public deployment has not been verified. Hosting data handling and the final public hosting arrangement still need to be reviewed before public release. | [release](#release) |
| `website/v2/docs/guide/reviewing.mdx` | Scheduled-rule consent remains under safety review and is not a release-ready feature. | Scheduled rules use approved scopes and Trash only while Cairn is open. AI-tool cleaning is off by default, with a choice of approval each time or permitted eligible cleanup without a new prompt. Consent safeguards passed macOS CI on 9 November; live Mac acceptance remains open. | [pr27](#pr27) |
| `website/v2/docs/reference/faq.mdx` | Scheduled-rule consent is still under safety review; it is not a release-ready feature. | Scheduled rules use approved scopes and Trash only while Cairn is open. AI-tool cleaning is off by default, with a choice of approval each time or permitted eligible cleanup without a new prompt. Consent safeguards passed macOS CI on 9 November; live Mac acceptance remains open. | [pr27](#pr27) |

## Validation

- Local website build and existing interaction, docs, storage and navigation checks passed: 18 pages, 568 local references.
- Source and static export pass the claim checks and original-design preservation checks.
- Four negative fixtures reject misleading visible copy, metadata, gallery descriptions and unavailable purchase calls to action.
- Rendered desktop/mobile validation is running in the isolated GitHub workflow; see VERIFICATION.md for final results and limitations.

No native app source, packaging script or native CI definition changed. No personal cleanup, release, merge, public deployment, checkout or publication is authorised by this PR.
