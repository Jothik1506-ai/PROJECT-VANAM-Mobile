import 'package:flutter/foundation.dart';

import '../models/family_member.dart';

/// DEV/TESTING AID ONLY — not a real feature, not real auth.
///
/// There is one phone and one real Profile identity. This lets a single
/// tester simulate what a multi-person Family Group conversation looks like
/// — different senders, different bubble styles — before real family
/// members are on their own devices with a real backend.
///
/// `null` = sending as your real Profile identity (own bubble, right-aligned).
/// Non-null = "chatting as" one of the mock family members, for testing how
/// an incoming-style bubble with their name renders.
final testSenderOverride = ValueNotifier<String?>(null);

/// Names available in the identity switcher, sourced from the same mock
/// family list Home already shows — see ARCHITECTURE.md Section 9, this is
/// preview/testing data, not a real member directory.
List<String> get testIdentityChoices =>
    mockFamilyMembers.map((m) => m.name).toList();
