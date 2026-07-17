import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/admin/providers/admin_provider.dart';
import 'package:garbanzo_ai/features/admin/widgets/mcp_servers_tab.dart';
import 'package:garbanzo_ai/features/admin/widgets/models_tab.dart';
import 'package:garbanzo_ai/features/admin/widgets/reports_tab.dart';
import 'package:garbanzo_ai/features/admin/widgets/users_tab.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Admin portal with tabs for user management, model visibility, and MCP
/// server configuration.
///
/// Requires the current user to be an admin — if not, the endpoints will
/// return 403 and the underlying tabs will render an error state.
class AdminPage extends StatelessWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminProvider(),
      child: const _AdminPageContent(),
    );
  }
}

class _AdminPageContent extends StatelessWidget {
  const _AdminPageContent();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.titleAdmin),
          bottom: TabBar(
            isScrollable: true,
            tabs: [
              Tab(
                icon: Icon(Icons.people_outline),
                text: AppLocalizations.of(context)!.tabUsers,
              ),
              Tab(
                icon: Icon(Icons.memory),
                text: AppLocalizations.of(context)!.titleModels,
              ),
              Tab(
                icon: Icon(Icons.extension_outlined),
                text: AppLocalizations.of(context)!.tabMcpServers,
              ),
              Tab(
                icon: Icon(Icons.feedback_outlined),
                text: AppLocalizations.of(context)!.tabReports,
              ),
            ],
          ),
        ),
        body: const TabBarView(
          children: [UsersTab(), ModelsTab(), MCPServersTab(), ReportsTab()],
        ),
      ),
    );
  }
}
