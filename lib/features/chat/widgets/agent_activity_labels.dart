import 'package:garbanzo_ai/features/chat/models/agent_activity.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

String agentActivityStepLabel(
  AgentActivityStep step,
  AppLocalizations l10n, {
  required bool active,
}) {
  return switch (step.kind) {
    AgentActivityKind.prepareApp =>
      active
          ? l10n.agentActivityPreparingApp(
              step.target ?? l10n.agentActivityMicroApp,
            )
          : l10n.agentActivityPreparedApp(
              step.target ?? l10n.agentActivityMicroApp,
            ),
    AgentActivityKind.research => l10n.agentActivityResearching,
    AgentActivityKind.gatherData => l10n.agentActivityGatheringData,
    AgentActivityKind.exploreFiles => l10n.agentActivityExploringFiles,
    AgentActivityKind.reviewFile => l10n.agentActivityReviewingFile(
      step.target ?? l10n.agentActivityAppFiles,
    ),
    AgentActivityKind.updateFile => l10n.agentActivityUpdatingFile(
      step.target ?? l10n.agentActivityAppFiles,
    ),
    AgentActivityKind.checkApp => l10n.agentActivityCheckingApp,
    AgentActivityKind.runStep => l10n.agentActivityRunningStep,
    AgentActivityKind.useTool => l10n.agentActivityUsingTool(
      humanize(step.toolName),
    ),
  };
}

String agentActivityTitle(
  AgentActivityGroup activity,
  AppLocalizations l10n, {
  required bool live,
}) {
  if (activity.isMicroApp) {
    final name = activity.appName ?? l10n.agentActivityMicroApp;
    if (live) return l10n.agentActivityBuildingApp(name);
    if (activity.microAppFailed) return l10n.agentActivityAppFailed(name);
    return activity.isEditing
        ? l10n.agentActivityUpdatedApp(name)
        : l10n.agentActivityOpenedApp(name);
  }

  if (live) return l10n.agentActivityWorking;
  return l10n.agentActivityCompletedSteps(activity.steps.length);
}
