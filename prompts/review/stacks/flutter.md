## Flutter and Dart

Detected from a `pubspec.yaml` file.

**Leave the tooling its job.** `dart format` settles formatting and `flutter analyze` (configured by `analysis_options.yaml`) reports a great deal mechanically. Do not repeat those, and do not suggest an `// ignore:` comment to get past a rule.

**`BuildContext` across an async gap is the defect to look for first.** After an `await`, the widget may be gone, and using the captured `context` then throws or silently targets a dead tree. Check for a `mounted` guard after every await before `Navigator`, `ScaffoldMessenger`, `Theme.of`, or `showDialog` is used, and capture what you need from the context _before_ awaiting where possible. The analyser flags many of these as `use_build_context_synchronously`; if that lint is disabled in `analysis_options.yaml`, that is itself worth mentioning.

**Disposal.** Anything with a lifecycle created in a `State` must be released in `dispose`: `AnimationController`, `TextEditingController`, `ScrollController`, `FocusNode`, `StreamSubscription`, `Timer`, and `ValueNotifier` listeners. A `setState` called after disposal throws, so an async callback that completes late needs a `mounted` check. Check that a subscription created in `initState` is cancelled and that a listener added with `addListener` has a matching `removeListener`.

**Rebuild cost.** `build` runs often, so it must stay cheap.

- No I/O, no network call, no future creation, and no expensive computation inside `build`. A `Future` constructed in `build` and handed to a `FutureBuilder` re-fires on every rebuild, which is a common and expensive bug: create it in `initState` or cache it.
- `const` constructors on static subtrees let Flutter skip rebuilding them. Missing `const` on a widget that never changes is worth a nit at most, but a large subtree rebuilt because state was lifted too high is a real finding.
- Check `setState` is scoped as narrowly as it can be, rather than rebuilding a whole page for one label.
- Watch for an unbounded `ListView` with a `children` list built from a large collection where `ListView.builder` would build lazily.

**State management.** Identify which approach the project already uses (Provider, Riverpod, Bloc, or plain `setState`) and hold the change to it. Mixing two in one feature is worth flagging on its own. Check state is not being read in a way that rebuilds more than necessary, and that business logic is not accumulating inside a widget.

**Null safety and errors.** Flag `!` on anything not provably non-null, and `late` fields whose initialisation path is not obviously guaranteed. An empty `catch {}` or a `catch (e)` that only prints swallows the failure; check the user is told something and the error is reported. Confirm a failed network call produces a visible state rather than an indefinite spinner.

**Platform and integration.** Method-channel calls need error handling for `PlatformException` and for the platform simply not implementing the method. Check permission requests handle refusal, including permanent refusal, rather than assuming a grant. Anything platform-specific should be behind a check rather than assumed.

**User-facing detail.** Hardcoded user-visible strings in a project that has localisation set up should go through it. Check images and assets declared in `pubspec.yaml` actually exist and are sized sensibly, that text scales with the user's font-size setting rather than being fixed, and that tappable targets and contrast are reasonable. A fixed-height container holding text will overflow when the system font is enlarged.

**`pubspec.yaml`.** Dependency constraints should be caret-bounded rather than `any`, and a `git` or `path` dependency is worth questioning since it makes builds irreproducible. Check `pubspec.lock` is updated in the same change, that the Dart and Flutter SDK constraints have not been quietly widened, and that a package added as a runtime dependency is not really a development tool belonging in `dev_dependencies`.
