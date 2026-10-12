# User guide

[简体中文](USER_GUIDE.zh-CN.md) · [Home](../README.md)

For the V0.4 open-source alpha. Start with **Offline rules → Open → Copy**, then evaluate experimental preparation separately.

## Install and prerequisites

Use macOS 14+ and at least one supported client that you have installed and signed into yourself. This project does not bundle model access, log you in or increase subscription limits.

Find the alpha DMG in Releases, or build locally with Apple developer tools. The binary is ad hoc signed and not Apple-notarized; macOS may block it. Do not disable security protections. Use local source builds or wait for a signed distribution if the downloaded binary is blocked.

When upgrading, preserve important unsent text, quit the old picker, replace the app and relaunch. Replacing files alone does not update a running process. The window should show V0.4.

## First setup

Open Settings → Apps and check the detected clients. Enable the apps you intend to use. In Models, check only configured models you have verified in your account's real menus. The public directory cannot prove account access. New discoveries are not editable routing entries until the Markdown policy is updated.

Offline mode works without JEV. A JEV key is not a ChatGPT/Claude credential: never paste vendor login tokens into that field.

## Describe a useful task

Include a goal, materials, output and important constraints. Examples:

- `Reconcile figures across three PDFs and identify contradictions without inventing missing values.`
- `Define software architecture and module boundaries for a small inventory app. Do not implement yet.`
- `Polish the layout of an existing client report while preserving the conclusions.`
- `Translate this paragraph into concise Chinese while keeping the product names.`

Rich-text paste, bold, italic, lists and viewport wrapping are supported. Markdown is accepted literally, not rendered. Classification and handoff use text, not rich formatting or pasted images; add source attachments in the original client yourself.

## Read the recommendations

The bundled policy usually displays four ranked cards: two international choices followed by two China-model choices. Priority is a trial task policy, not a success probability or a proven universal quality ranking.

Each card names the model, effort, app/context and API reference price. Click a card and adjust its workspace and reasoning effort using the horizontal controls. The workspace labels reflect the target product; verify that the actual app supports them. China clients' App setting means the picker preserves their existing effort configuration rather than inventing High/Max support.

Expand Why this model to inspect the rule reason and matched terms. If the task has multiple goals or no clear match, choose the main category. Offline matching is deliberately limited; it does not understand every semantic expression or complex negation.

## Manual handoff: the recommended alpha path

1. Open the selected app.
2. Use Copy task to replace the clipboard with the task text.
3. Create an empty task in the original app, set the suggested model/effort/context manually, paste the text and attach any files.
4. Review and send it yourself. Continue chatting there.

This needs no Accessibility permission and does not proxy model requests through the picker.

## Experimental automatic preparation

Prepare requires user-granted macOS Accessibility access. The adapter attempts a new task, selects menus, reads back context/model/effort, checks an empty composer and verifies the full pasted text. Only successful readback should display Ready. No auto-send action exists.

An existing draft, changed focus, ambiguous menu, failed readback or timeout stops preparation. Opening the target app is not proof of a successful handoff. Inspect the destination and fall back to Open + Copy when needed. End-to-end acceptance across the four clients is pending.

Claude uses an amber access/account notice on both open and preparation paths. The button acknowledges it once and begins the action. It does not diagnose a safe network or guarantee account safety; the service's rules still apply.

## Optional JEV classification

Save your personal JEV key in Settings → JEV connection. It is stored in macOS Keychain. Test connection checks authentication, not real task accuracy. Try a non-sensitive task and assess the result before relying on it.

AI recommendation sends the current task and classification conditions to JEV and may incur API charges. Local policy selects the routes. Target execution remains in the original clients. Network/allowance/response failures trigger explicit local fallback for that task; they do not silently change your saved mode.

No live JEV account acceptance is claimed in this release. Use offline mode for text you should not transmit to the classifier. Once you send it in the target app, that app's data policies apply.

## Update models, prices and FX

Update models and Update prices & FX refresh supported providers' public text models and normalized API references from Models.dev, plus Frankfurter daily USD/CNY FX. They are unauthenticated GET requests without task text or keys. Neither JEV nor Accessibility is required.

Valid streams update the local cache; failed streams retain their corresponding old data. Inline status distinguishes success, partial success and failure. Undo restores the previous complete cached version. Model discovery is separate from routing: verify the real menu, access, workspace and effort, then edit the Markdown policy.

## Price table

Prices are per million input/output tokens, output-price descending and input as tie-breaker. Unknown rows appear last. Chinese puts CNY first; English puts USD first, with the other currency beside it. Entries carry source and check/update dates; catalog-fetch and FX-observation dates are separate.

These are approximate API references, not your subscription bill, remaining calls or cost per completed task. Converted USD/CNY equivalents are not verified country-specific offers. Cache, context tiers, peak/off-peak periods, Fast/Batch and tool fees can differ.

Edit the APIPrices.json template if you need your own references. Import validates and applies directly with Undo; Restore bundled prices restores an old baseline rather than claiming online verification. Price does not reorder the task policy.

## Markdown policy

Import or drag in a file based on Resources/DefaultRules.md or DefaultRules.en.md. Preview validated rule changes, apply, export or roll back. Keep stable task IDs and increment the policy version.

V2 specifies bilingual any/all/exclusion terms, default context/complexity, matching priority and effort escalation/reduction. The model table defines the app, exact display name, supported contexts and effort options; task routes define primary/backup choices. Arbitrary articles are not importable policies. V1 remains readable but requires manual category selection.

Verify actual menus before adding a new model; a public API record is not proof that all desktop modes support it.

## Shortcuts, windows and preferences

The default is Control + Option + Space. Click the shortcut button and record a main key plus one/two modifiers, including Command, Control or Option. Esc cancels. Conflicts retain the old combination; Reset restores the default.

The main window is intended to minimize and reopen from Dock, menu bar or hotkey; closing it keeps the process alive. Settings should open ahead of it. V0.4 window behavior needs live acceptance. Check the version and restart older processes before reporting a regression.

Language/theme changes preserve the current attributed task and selection. System appearance is available in Settings. The input box is not a cross-process task store: preserve important text before quitting.

## Troubleshooting and feedback

- Missing/unavailable model: verify the account menu, uncheck it, select a fallback or update the policy.
- New directory, unchanged cards: expected; discovery does not rewrite routing.
- Failed preparation: check Accessibility, login, project/context and an empty task; use manual handoff.
- Poor offline match: state the main goal, choose a category or improve the matching terms.
- JEV failure with visible recommendations: read the source badge; it may be an offline fallback.
- Missing prices/failed refresh: old values remain, unknown prices are labeled; retry or import your reference table.
- Blocked alpha binary: build locally or wait for signed distribution, without disabling system security.

Report OS/chip, picker version, target-client version, an anonymized task and expected/observed behavior. State the recommendation and handoff modes. Do not post keys, transcripts, customer files or account screenshots. Follow SECURITY.md for sensitive reports.
