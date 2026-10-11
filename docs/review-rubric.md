# Review rubric

Apply this to every PR: the author before opening it, the reviewer agent and
Belt's REVIEW station after. Every question is yes or no. A "no" blocks the
merge unless the PR body explains it. The rules behind each question are in
`docs/engineering.md`.

## 1. Coherence: does it fit the design?

- [ ] Each changed file stays in its layer (model, evaluation, commands,
      format and export), and no model file names a command or format type?
- [ ] Errors thrown are the layer's own error type, and no new error enum was
      added where a case on the existing one would do?
- [ ] Every document change goes through a `Command`?
- [ ] A new command is in its family's `all`, the family is in
      `CommandRegistry.builtInFamilies`, and the command is a step in
      `UndoPropertyTests`?
- [ ] Names match the ones already used for the same idea (ids, labels,
      file names, command ids like `family.verb`)?

## 2. Duplication: does it reuse what exists?

- [ ] `scripts/ci` printed no jscpd failure, and the threshold was not raised?
- [ ] No new copy of bezier evaluation, clamping, flattening, or id lookup;
      the existing helper is called instead?
- [ ] If the PR removed a clone, did it lower the jscpd threshold?
- [ ] No near-copy that jscpd misses (same logic, renamed variables) of a
      function in another file?

## 3. Correctness: can it break a document or crash?

- [ ] After every new or changed command, the document still passes
      `FlareFormat.validate`, and so does the undone document?
- [ ] `undo` restores the document exactly, including inside groups and
      coalesced runs?
- [ ] A new document rule is checked in `FlareFormat.validate`, not only in a
      command guard?
- [ ] Untrusted input (files, envelopes, params) throws a typed error, with no
      unchecked index and no Int overflow on file values?
- [ ] A new model field decodes from a file that lacks it?

## 4. Design debt: is the codebase simpler or no worse?

- [ ] The encoded form of a command holds only its params, not undo state?
- [ ] Exporters, hit testing and bounds handle the new model feature, or throw
      a typed error, instead of skipping it in silence?
- [ ] No wrapper with one caller, no unused parameter, no "for later" code?
- [ ] An API that was replaced is deleted, with every caller moved?

## 5. Test quality: would the tests catch a regression?

- [ ] Each test asserts a concrete result that would fail if the code returned
      a default value?
- [ ] The new behavior is tested across families too (mixed command sequences,
      undo, validate, encode and decode), not only in its own file?
- [ ] A bug fix comes with a test that failed before the fix?
- [ ] Randomness is seeded with `SplitMix64`, and new parsers have a fuzz
      test?
- [ ] `scripts/ci` printed `CI: PASS` on the rebased branch?
