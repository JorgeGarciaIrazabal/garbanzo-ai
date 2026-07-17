import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/features/reports/widgets/submit_report_dialog.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Navigation list to every feature page. One place to find everything,
/// instead of page links scattered between toggle sections.
class PagesSection extends StatelessWidget {
  const PagesSection({super.key});

  void _open(BuildContext context, String path) {
    Navigator.of(context).pop(); // close the drawer first
    context.push(path);
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = AuthService.instance.cachedUser?.isAdmin ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          leading: const Icon(Icons.psychology_outlined),
          title: Text(AppLocalizations.of(context)!.titleMemories),
          subtitle: Text(
            AppLocalizations.of(context)!.titleWhatTheAssistantHasLearnedAbout,
          ),
          dense: true,
          onTap: () => _open(context, '/memory'),
        ),
        ListTile(
          leading: const Icon(Icons.menu_book_outlined),
          title: Text(AppLocalizations.of(context)!.titleKnowledgeBase),
          subtitle: Text(
            AppLocalizations.of(
              context,
            )!.titleUploadDocumentsForRetrievalAcrossChats,
          ),
          dense: true,
          onTap: () => _open(context, '/kb'),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: Text(AppLocalizations.of(context)!.titleSkillsLibrary),
          subtitle: Text(
            AppLocalizations.of(context)!.titleBrowseAvailableMcpTools,
          ),
          dense: true,
          onTap: () => _open(context, '/skills'),
        ),
        ListTile(
          leading: const Icon(Icons.people_outline),
          title: Text(AppLocalizations.of(context)!.titleFriends),
          subtitle: Text(
            AppLocalizations.of(context)!.titleSendRequestsAndManageYourFriends,
          ),
          dense: true,
          onTap: () => _open(context, '/friends'),
        ),
        ListTile(
          leading: const Icon(Icons.schedule),
          title: Text(AppLocalizations.of(context)!.titleScheduledActions),
          subtitle: Text(
            AppLocalizations.of(context)!.titleRemindersAndRecurringPrompts,
          ),
          dense: true,
          onTap: () => _open(context, '/scheduled-actions'),
        ),
        ListTile(
          leading: const Icon(Icons.bar_chart),
          title: Text(AppLocalizations.of(context)!.titleTokenUsage),
          subtitle: Text(
            AppLocalizations.of(context)!.titleChartsByModelConversationDay,
          ),
          dense: true,
          onTap: () => _open(context, '/usage'),
        ),
        ListTile(
          key: const ValueKey('report_issue_tile'),
          leading: const Icon(Icons.feedback_outlined),
          title: Text(AppLocalizations.of(context)!.titleReportABugOrIdea),
          subtitle: Text(
            AppLocalizations.of(context)!.titleSendFeedbackStraightToTheAdmins,
          ),
          dense: true,
          onTap: () {
            Navigator.of(context).pop(); // close the drawer first
            SubmitReportDialog.show(context);
          },
        ),
        if (isAdmin)
          ListTile(
            leading: const Icon(Icons.admin_panel_settings_outlined),
            title: Text(AppLocalizations.of(context)!.titleAdmin),
            subtitle: Text(
              AppLocalizations.of(context)!.messageAdminPanelSubtitle,
            ),
            dense: true,
            onTap: () => _open(context, '/admin'),
          ),
      ],
    );
  }
}
