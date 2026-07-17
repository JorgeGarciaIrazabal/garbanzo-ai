import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/core/auth_state.dart';
import 'package:garbanzo_ai/features/admin/pages/admin_page.dart';
import 'package:garbanzo_ai/features/chat/widgets/chat_page.dart';
import 'package:garbanzo_ai/features/friends/pages/friends_page.dart';
import 'package:garbanzo_ai/features/knowledge_base/pages/knowledge_base_page.dart';
import 'package:garbanzo_ai/features/memory/pages/memory_page.dart';
import 'package:garbanzo_ai/features/notifications/pages/notifications_page.dart';
import 'package:garbanzo_ai/features/scheduled_actions/pages/scheduled_actions_page.dart';
import 'package:garbanzo_ai/features/settings/pages/settings_page.dart';
import 'package:garbanzo_ai/features/tools/pages/skills_library_page.dart';
import 'package:garbanzo_ai/features/usage/pages/usage_page.dart';
import 'package:garbanzo_ai/pages/login_page.dart';

/// Pure redirect rule so it can be unit-tested without a widget tree.
///
/// Returns the location to redirect to, or null to stay.
String? computeRedirect({
  required bool loggedIn,
  required String matchedLocation,
}) {
  final onLogin = matchedLocation == '/login';
  if (!loggedIn) return onLogin ? null : '/login';
  if (onLogin || matchedLocation == '/') return '/chat';
  return null;
}

/// Root navigator key. Lets chrome that lives *above* the Navigator (e.g.
/// the update banner wrapped around the router in `main.dart`) open dialogs
/// with a context that can actually find the Navigator.
final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Builds the app router. [auth] drives the login redirect guard;
/// `refreshListenable` re-evaluates redirects when auth state changes
/// (login, logout).
GoRouter buildRouter(AuthState auth) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/chat',
    refreshListenable: auth,
    redirect: (context, state) async {
      // One-shot token validation on cold start; cached afterwards.
      await auth.ensureReady();
      return computeRedirect(
        loggedIn: auth.loggedIn,
        matchedLocation: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/chat'),
      GoRoute(path: '/login', builder: (_, _) => const LoginPage()),
      GoRoute(path: '/chat', builder: (_, _) => const ChatPage()),
      GoRoute(
        path: '/chat/:conversationId',
        builder: (_, state) =>
            ChatPage(conversationId: state.pathParameters['conversationId']),
      ),
      // Rooms render inside the chat shell (sidebar stays put); the bare
      // /rooms list page is gone — the sidebar's Rooms tab replaced it.
      GoRoute(path: '/rooms', redirect: (_, _) => '/chat'),
      GoRoute(
        path: '/rooms/:roomId',
        builder: (_, state) =>
            ChatPage(roomId: state.pathParameters['roomId']!),
      ),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      GoRoute(path: '/memory', builder: (_, _) => const MemoryPage()),
      GoRoute(path: '/friends', builder: (_, _) => const FriendsPage()),
      GoRoute(path: '/kb', builder: (_, _) => const KnowledgeBasePage()),
      GoRoute(path: '/usage', builder: (_, _) => const UsagePage()),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsPage(),
      ),
      GoRoute(path: '/skills', builder: (_, _) => const SkillsLibraryPage()),
      GoRoute(
        path: '/scheduled-actions',
        builder: (_, _) => const ScheduledActionsPage(),
      ),
      GoRoute(
        path: '/admin',
        redirect: (context, state) async {
          // cachedUser is populated by the ensureReady()/login flows; the
          // fallback fetch covers a hot-reload edge where the cache is empty.
          final user =
              AuthService.instance.cachedUser ??
              await AuthService.instance.getCurrentUser();
          return (user?.isAdmin ?? false) ? null : '/chat';
        },
        builder: (_, _) => const AdminPage(),
      ),
    ],
  );
}
