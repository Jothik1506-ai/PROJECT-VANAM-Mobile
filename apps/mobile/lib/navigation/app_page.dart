/// Every screen the app reports about itself (feedback, crash reports,
/// activity), in one place. Each page has:
///
///  * a **unique, stable [id]** — never reuse or rename one, because reports
///    and logs are matched on it (labels may be reworded freely);
///  * a human-readable [label] — what members see and what feedback shows;
///  * [kind] and a short [description] metadata.
///
/// The main tabs also carry their [tabIndex], in bottom-bar order. Add new
/// screens here first; `app_page_test.dart` fails if an id or label repeats.
enum AppPage {
  // ---- Main tabs (bottom bar, in order) ----
  reels(
    id: 'tab.reels',
    label: 'Reels',
    kind: AppPageKind.tab,
    tabIndex: 0,
    description: 'Full-screen browse of family photo and video posts.',
  ),
  messages(
    id: 'tab.messages',
    label: 'Messages',
    kind: AppPageKind.tab,
    tabIndex: 1,
    description: 'Family group and direct chat list.',
  ),
  home(
    id: 'tab.home',
    label: 'Home',
    kind: AppPageKind.tab,
    tabIndex: 2,
    description: 'Family feed, Stories and web updates.',
  ),
  profile(
    id: 'tab.profile',
    label: 'Profile',
    kind: AppPageKind.tab,
    tabIndex: 3,
    description: 'Member profile, theme, privacy and sign out.',
  ),

  // ---- Screens opened from the tabs ----
  chat(
    id: 'screen.chat',
    label: 'Chat',
    kind: AppPageKind.screen,
    description: 'One conversation: family group or direct chat.',
  ),
  notifications(
    id: 'screen.notifications',
    label: 'Notifications',
    kind: AppPageKind.screen,
    description: 'In-app notifications list.',
  ),
  comments(
    id: 'screen.comments',
    label: 'Comments',
    kind: AppPageKind.screen,
    description: 'Comments on a Home post.',
  ),
  storyViewer(
    id: 'screen.story_viewer',
    label: 'Story viewer',
    kind: AppPageKind.screen,
    description: 'Full-screen 24-hour Story.',
  ),

  // ---- Signed-out flow ----
  login(
    id: 'flow.login',
    label: 'Login',
    kind: AppPageKind.flow,
    description: 'Username and password, invite code or QR sign-in.',
  ),
  auth(
    id: 'flow.auth',
    label: 'Auth',
    kind: AppPageKind.flow,
    description: 'Sign-in checks before the app shell opens.',
  );

  const AppPage({
    required this.id,
    required this.label,
    required this.kind,
    required this.description,
    this.tabIndex,
  });

  /// Unique and stable. Used for storage keys, reports and logs.
  final String id;
  final String label;
  final AppPageKind kind;
  final String description;

  /// Position in the bottom bar; null for pages that are not tabs.
  final int? tabIndex;

  /// The bottom-bar tabs, ordered by [tabIndex].
  static final List<AppPage> tabs = List.unmodifiable(
    (values.where((p) => p.tabIndex != null).toList()
      ..sort((a, b) => a.tabIndex!.compareTo(b.tabIndex!))),
  );

  /// Finds a page by its display label (feedback still passes labels).
  static AppPage? byLabel(String label) {
    for (final page in values) {
      if (page.label == label) return page;
    }
    return null;
  }

  static AppPage? byId(String id) {
    for (final page in values) {
      if (page.id == id) return page;
    }
    return null;
  }

  /// Duplicate ids or labels, empty if the registry is valid.
  static List<String> duplicates() {
    final seenIds = <String>{};
    final seenLabels = <String>{};
    final problems = <String>[];
    for (final page in values) {
      if (!seenIds.add(page.id)) problems.add('duplicate id ${page.id}');
      if (!seenLabels.add(page.label)) {
        problems.add('duplicate label ${page.label}');
      }
    }
    return problems;
  }
}

enum AppPageKind { tab, screen, flow }
