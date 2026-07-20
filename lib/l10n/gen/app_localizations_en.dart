// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Garbanzo AI';

  @override
  String get language => 'Language';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSpanish => 'Español';

  @override
  String get languageSystem => 'System default';

  @override
  String get accept => 'Accept';

  @override
  String get active => 'Active';

  @override
  String get add => 'Add';

  @override
  String get addAgentTitle => 'Add agent';

  @override
  String get agents => 'Agents';

  @override
  String get alwaysRespond => 'Always respond';

  @override
  String get apply => 'Apply';

  @override
  String attachedImageLabel(String name) {
    return 'Attached image: $name';
  }

  @override
  String get authErrorIncorrectEmailOrPassword => 'Incorrect email or password';

  @override
  String get autoJumpInWhenRelevantLlm => 'Auto — jump in when relevant (LLM)';

  @override
  String get autoLowercase => 'auto';

  @override
  String get autoModel => 'Auto';

  @override
  String get block => 'Block';

  @override
  String get blockLowercase => 'block';

  @override
  String get blockSender => 'Block sender';

  @override
  String get cancel => 'Cancel';

  @override
  String get change => 'Change';

  @override
  String get chatStyle => 'Chat style';

  @override
  String get checkNow => 'Check now';

  @override
  String get clear => 'Clear';

  @override
  String get close => 'Close';

  @override
  String get commitAndDeployToGithubPages =>
      'Commit and deploy to GitHub Pages.';

  @override
  String get composeAStyle => 'Compose a style';

  @override
  String get confirm => 'Confirm';

  @override
  String couldNotUpdate(String error) {
    return 'Could not update: $error';
  }

  @override
  String get create => 'Create';

  @override
  String get delete => 'Delete';

  @override
  String deleteAgentConfirmation(String name) {
    return 'Delete agent $name? This cannot be undone.';
  }

  @override
  String get deleteLowercase => 'delete';

  @override
  String deleteRoomConfirmation(String name) {
    return 'Delete \"$name\"? This cannot be undone.';
  }

  @override
  String deleteStyleTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String deleteTemplateTitle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get discard => 'Discard';

  @override
  String get downloadInstall => 'Download & install';

  @override
  String get edit => 'edit';

  @override
  String get editAgentTitle => 'Edit agent';

  @override
  String get editEllipsis => 'Edit…';

  @override
  String editTemplateTitle(String name) {
    return 'Edit \"$name\"';
  }

  @override
  String errorWithDetails(String error) {
    return 'Error: $error';
  }

  @override
  String get failedToAcceptRequest => 'Failed to accept request';

  @override
  String get failedToAcceptShare => 'Failed to accept share';

  @override
  String get failedToBlockUser => 'Failed to block user';

  @override
  String get failedToCreateMemory => 'Failed to create memory';

  @override
  String get failedToCreateScheduledAction =>
      'Failed to create scheduled action';

  @override
  String get failedToCreateTemplate => 'Failed to create template';

  @override
  String get failedToDeactivateMemory => 'Failed to deactivate memory';

  @override
  String get failedToDeclineRequest => 'Failed to decline request';

  @override
  String get failedToDeclineShare => 'Failed to decline share';

  @override
  String failedToDeleteAgent(String error) {
    return 'Failed to delete agent: $error';
  }

  @override
  String get failedToDeleteDocument => 'Failed to delete document';

  @override
  String failedToDeleteRoom(String error) {
    return 'Failed to delete room: $error';
  }

  @override
  String get failedToDeleteScheduledAction =>
      'Failed to delete scheduled action';

  @override
  String get failedToDeleteStyle => 'Failed to delete style';

  @override
  String get failedToDeleteTemplate => 'Failed to delete template';

  @override
  String failedToEditMessage(String error) {
    return 'Failed to edit message: $error';
  }

  @override
  String get failedToLoadDocuments => 'Failed to load documents';

  @override
  String get failedToLoadFriends => 'Failed to load friends';

  @override
  String get failedToLoadMemories => 'Failed to load memories';

  @override
  String get failedToLoadModels => 'Failed to load models';

  @override
  String get failedToLoadNotifications => 'Failed to load notifications';

  @override
  String get failedToLoadScheduledActions => 'Failed to load scheduled actions';

  @override
  String get failedToLoadStyles => 'Failed to load styles';

  @override
  String get failedToLoadSystemPrompts => 'Failed to load system prompts';

  @override
  String get failedToLoadTools => 'Failed to load tools';

  @override
  String get failedToLoadUsage => 'Failed to load usage';

  @override
  String get failedToRemoveFriend => 'Failed to remove friend';

  @override
  String failedToRemoveMember(String error) {
    return 'Failed to remove member: $error';
  }

  @override
  String get failedToRenderDiagram => 'Failed to render diagram';

  @override
  String get failedToSaveDefaultPrompt => 'Failed to save default prompt';

  @override
  String failedToSaveMemory(String error) {
    return 'Failed to save memory: $error';
  }

  @override
  String get failedToSaveStyle => 'Failed to save style';

  @override
  String get failedToSendFriendRequest => 'Failed to send friend request';

  @override
  String failedToSendMessage(String error) {
    return 'Failed to send message: $error';
  }

  @override
  String get failedToShare => 'Failed to share';

  @override
  String get failedToUnblockUser => 'Failed to unblock user';

  @override
  String get failedToUpdateMemory => 'Failed to update memory';

  @override
  String failedToUpdateMemorySetting(String error) {
    return 'Failed to update memory setting: $error';
  }

  @override
  String get failedToUpdateScheduledAction =>
      'Failed to update scheduled action';

  @override
  String get failedToUpdateStyle => 'Failed to update style';

  @override
  String get failedToUpdateTemplate => 'Failed to update template';

  @override
  String get failedToUploadDocument => 'Failed to upload document';

  @override
  String get feedbackToApply => 'Feedback to apply:';

  @override
  String filesTooLarge(String files) {
    return 'Files too large:\\n$files';
  }

  @override
  String get fromYourKnowledgeBase => 'From your knowledge base';

  @override
  String get headingSignIn => 'Sign in';

  @override
  String get hintApiKeyAbcNdebug1 => 'API_KEY=abc\\nDEBUG=1';

  @override
  String get hintAtLeast6Characters => 'At least 6 characters';

  @override
  String get hintBearer => 'Bearer …';

  @override
  String get hintBug => 'bug';

  @override
  String get hintDeepWorkQuickAnswers => 'Deep work, Quick answers…';

  @override
  String get hintEG09MonFri => 'e.g. \"0 9 * * mon-fri\"';

  @override
  String get hintEGFilesystem => 'e.g. filesystem';

  @override
  String get hintEGMadridSpain => 'e.g. Madrid, Spain';

  @override
  String get hintEGMakeItFriendlier => 'e.g. Make it friendlier';

  @override
  String get hintEGMorningStandup => 'e.g. \"Morning standup\"';

  @override
  String get hintEGProductBrainstorm => 'e.g. Product brainstorm';

  @override
  String get hintEnterMemoryContent => 'Enter memory content';

  @override
  String get hintFriendExampleCom => 'friend@example.com';

  @override
  String get hintJaneDoe => 'Jane Doe';

  @override
  String get hintMemoryContent => 'Memory content';

  @override
  String get hintMessageTheRoomUseAgentnameOr =>
      'Message the room… (use @AgentName or @all)';

  @override
  String get hintOneLineSummary => 'One-line summary';

  @override
  String get hintSearchConversations => 'Search conversations...';

  @override
  String get hintSearchTools => 'Search tools…';

  @override
  String get hintUsrBinPython3 => '/usr/bin/python3';

  @override
  String get hintWhatShouldTheAssistantDo => 'What should the assistant do?';

  @override
  String get hintYouAreAFriendlyProductStrategist =>
      'You are a friendly product strategist…';

  @override
  String get hintYouExampleCom => 'you@example.com';

  @override
  String get inactive => 'Inactive';

  @override
  String get invite => 'Invite';

  @override
  String itemAddedToYourNouns(String name, String noun) {
    return '\"$name\" added to your ${noun}s';
  }

  @override
  String get labelAgentName => 'Agent name';

  @override
  String get labelAll => 'All';

  @override
  String get labelAllLowercase => 'all';

  @override
  String get labelArgsOnePerLine => 'Args (one per line)';

  @override
  String get labelAuthHeader => 'Auth header';

  @override
  String get labelBug => 'Bug';

  @override
  String get labelChats => 'Chats';

  @override
  String get labelCity => 'City';

  @override
  String get labelCommitMessageOptional => 'Commit message (optional)';

  @override
  String get labelConfirmNewPassword => 'Confirm new password';

  @override
  String get labelCopyUrl => 'Copy URL';

  @override
  String get labelCreateARoom => 'Create a room';

  @override
  String get labelCreateWithAi => 'Create with AI';

  @override
  String get labelCronExpression => 'Cron expression';

  @override
  String get labelCurrentPassword => 'Current password';

  @override
  String get labelDark => 'Dark';

  @override
  String get labelDescription => 'Description';

  @override
  String get labelDescriptionOptional => 'Description (optional)';

  @override
  String get labelDisabled => 'Disabled';

  @override
  String get labelEmail => 'Email';

  @override
  String get labelEnvKeyValueOnePerLine => 'Env (KEY=VALUE, one per line)';

  @override
  String get labelFailedToCreateServer => 'Failed to create server';

  @override
  String get labelFailedToCreateUser => 'Failed to create user';

  @override
  String get labelFailedToDeleteServer => 'Failed to delete server';

  @override
  String get labelFailedToLoadServers => 'Failed to load servers';

  @override
  String get labelFailedToLoadUsers => 'Failed to load users';

  @override
  String get labelFailedToSyncModels => 'Failed to sync models';

  @override
  String get labelFailedToTestServer => 'Failed to test server';

  @override
  String get labelFailedToUpdateModel => 'Failed to update model';

  @override
  String get labelFailedToUpdateServer => 'Failed to update server';

  @override
  String get labelFailedToUpdateUser => 'Failed to update user';

  @override
  String get labelFeature => 'Feature';

  @override
  String get labelFullName => 'Full name';

  @override
  String get labelFullNameOptional => 'Full name (optional)';

  @override
  String get labelGenerate => 'Generate';

  @override
  String get labelHttp => 'HTTP';

  @override
  String get labelInviteMembers => 'Invite members';

  @override
  String get labelLight => 'Light';

  @override
  String get labelMarkAllRead => 'Mark all read';

  @override
  String get labelModel => 'Model';

  @override
  String get labelMonospace => 'monospace';

  @override
  String get labelName => 'Name';

  @override
  String get labelNew => 'New';

  @override
  String get labelNewChat => 'New Chat';

  @override
  String get labelNewPassword => 'New password';

  @override
  String get labelNewRoom => 'New Room';

  @override
  String get labelOneOff => 'One-off';

  @override
  String get labelPassword => 'Password';

  @override
  String get labelPrompt => 'Prompt';

  @override
  String get labelPromptContent => 'Prompt content';

  @override
  String get labelPromptTemplate => 'Prompt template';

  @override
  String get labelPublish => 'Publish';

  @override
  String get labelPublishing => 'Publishing…';

  @override
  String get labelRecurring => 'Recurring';

  @override
  String get labelRefine => 'Refine';

  @override
  String get labelRooms => 'Rooms';

  @override
  String get labelRunAt => 'Run at';

  @override
  String get labelSaveToLibrary => 'Save to library';

  @override
  String get labelSend => 'Send';

  @override
  String get labelShowSchema => 'Show schema';

  @override
  String get labelSse => 'SSE';

  @override
  String get labelStop => 'Stop';

  @override
  String get labelStyles => 'Styles';

  @override
  String get labelPredefinedStyles => 'Predefined';

  @override
  String get labelYourStyles => 'Your styles';

  @override
  String get labelNewPrompt => 'New prompt';

  @override
  String get messageNoTemplatesYet =>
      'No saved prompts yet. Tap \"New prompt\" to create one, or \"Create with AI\" to draft one.';

  @override
  String get labelSync => 'Sync';

  @override
  String get labelSystem => 'System';

  @override
  String get labelSystemPrompt => 'System prompt';

  @override
  String get labelSystemPromptOptional => 'System prompt (optional)';

  @override
  String get labelTemplate => 'Template';

  @override
  String get labelTitle => 'Title';

  @override
  String get labelTitleOptional => 'Title (optional)';

  @override
  String get labelUpload => 'Upload';

  @override
  String get labelUrl => 'URL';

  @override
  String get labelWhenToRespond => 'When to respond';

  @override
  String get last12Months => 'Last 12 months';

  @override
  String get last30Days => 'Last 30 days';

  @override
  String get last7Days => 'Last 7 days';

  @override
  String get last90Days => 'Last 90 days';

  @override
  String get later => 'Later';

  @override
  String latestReleaseVersion(String releaseVersion) {
    return 'Latest release: v$releaseVersion';
  }

  @override
  String get loadingModels => 'Loading models…';

  @override
  String get loadingPreferences => 'Loading preferences…';

  @override
  String get loadingTools => 'Loading tools…';

  @override
  String get members => 'Members';

  @override
  String memoriesInformedReply(String count) {
    return '$count saved memories about you informed this reply';
  }

  @override
  String get memory => 'Memory';

  @override
  String get messageChangesReverted => 'Changes reverted';

  @override
  String get messageConversationDeleted => 'Conversation deleted';

  @override
  String messageFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get messageFailedToRemoveProfilePicture =>
      'Failed to remove profile picture';

  @override
  String get messageFailedToUploadProfilePicture =>
      'Failed to upload profile picture';

  @override
  String get messagePasswordUpdated => 'Password updated';

  @override
  String get messageProfilePictureRemoved => 'Profile picture removed';

  @override
  String get messageProfilePictureUpdated => 'Profile picture updated';

  @override
  String get messageSchemaCopied => 'Schema copied';

  @override
  String get messageStartAConversationFirst => 'Start a conversation first';

  @override
  String get messageThanksYourReportWasSubmitted =>
      'Thanks! Your report was submitted.';

  @override
  String get messageThisRemovesTheSavedStyleNot =>
      'This removes the saved style, not any chats.';

  @override
  String modelIdIsNotInstalled(String modelId) {
    return '$modelId is not installed';
  }

  @override
  String get noAppToDisplay => 'No app to display';

  @override
  String get noDailyData => 'No daily data';

  @override
  String get noDocumentsYet => 'No documents yet';

  @override
  String get noModelsSyncedYet => 'No models synced yet';

  @override
  String get noTemplate => 'No template';

  @override
  String get none => '— None —';

  @override
  String get ok => 'OK';

  @override
  String get onMentionOnly => 'On @mention only';

  @override
  String get onlySwitchBetweenTheseNoneMeans =>
      'Only switch between these — none means any';

  @override
  String pushServiceForegroundMessage(String title) {
    return '[PushService] foreground message: $title';
  }

  @override
  String get releasePage => 'Release page';

  @override
  String get remove => 'Remove';

  @override
  String removeDocumentConfirmation(String filename) {
    return 'Remove \"$filename\" from your knowledge base?';
  }

  @override
  String get removeFriend => 'Remove friend';

  @override
  String get removeLowercase => 'remove';

  @override
  String removeMemberFromRoomMessage(String userId) {
    return 'Remove $userId from this room?';
  }

  @override
  String get retry => 'Retry';

  @override
  String get revert => 'Revert';

  @override
  String get roundRobinTakeTurns => 'Round-robin (take turns)';

  @override
  String get save => 'Save';

  @override
  String get saveAndRerun => 'Save & rerun';

  @override
  String savedToLibrary(String name) {
    return 'Saved \"$name\" to your library';
  }

  @override
  String get semanticLabelBlockMath => 'blockMath';

  @override
  String get semanticLabelInlineMath => 'inlineMath';

  @override
  String get semanticLabelMuted => 'Muted';

  @override
  String get semanticLabelTool => 'tool';

  @override
  String get settings => 'Settings';

  @override
  String shareItemTitle(String itemName) {
    return 'Share \"$itemName\"';
  }

  @override
  String get shareWithAFriend => 'Share with a friend…';

  @override
  String sharedItemFromSender(String senderEmail) {
    return 'from $senderEmail';
  }

  @override
  String sharedItemTitle(String name, String noun) {
    return '\"$name\" ($noun)';
  }

  @override
  String get startAConversationToSetA => 'Start a conversation to set a prompt';

  @override
  String get submit => 'Submit';

  @override
  String get tabMcpServers => 'MCP Servers';

  @override
  String get tabModels => 'Models';

  @override
  String get tabReports => 'Reports';

  @override
  String get tabUsers => 'Users';

  @override
  String get templates => 'Templates';

  @override
  String testingServer(String name) {
    return 'Testing $name…';
  }

  @override
  String get thinking => 'Thinking';

  @override
  String get titleAccountAndSystemNotifications =>
      'Account and system notifications';

  @override
  String get titleAdmin => 'Admin';

  @override
  String get titleAdminPrivileges => 'Admin privileges';

  @override
  String get titleAllTools => 'All tools';

  @override
  String get titleAppSettings => 'App settings';

  @override
  String get titleAppearance => 'Appearance';

  @override
  String get titleAutoPlayResponses => 'Auto-play responses';

  @override
  String get titleAutoSendAfterTranscription => 'Auto-send after transcription';

  @override
  String get titleAutomaticLanguageSwitching => 'Automatic language switching';

  @override
  String get titleAutomaticallySendWhenVoiceInputFinishes =>
      'Automatically send when voice input finishes';

  @override
  String get titleBlockUser => 'Block User';

  @override
  String get titleBrowseAvailableMcpTools => 'Browse available MCP tools';

  @override
  String get titleChangePassword => 'Change password';

  @override
  String get titleChartsByModelConversationDay =>
      'Charts by model, conversation, day';

  @override
  String get titleChat => 'Chat';

  @override
  String get titleChatResponses => 'Chat responses';

  @override
  String get titleChoosePhoto => 'Choose photo';

  @override
  String get titleConversationSystemPrompt => 'Conversation system prompt';

  @override
  String get titleCreateMemory => 'Create Memory';

  @override
  String get titleCreateUser => 'Create user';

  @override
  String get titleCurrentVersion => 'Current version';

  @override
  String get titleDefaultModel => 'Default model';

  @override
  String get titleDeleteAgent => 'Delete agent?';

  @override
  String get titleDeleteConversation => 'Delete Conversation?';

  @override
  String get titleDeleteDocument => 'Delete document';

  @override
  String get titleDeleteMcpServer => 'Delete MCP server?';

  @override
  String get titleDeleteMemory => 'Delete Memory';

  @override
  String get titleDeleteRoom => 'Delete room?';

  @override
  String get titleDeleteScheduledAction => 'Delete scheduled action';

  @override
  String get titleDisplayTokenCountsAndResponseTime =>
      'Display token counts and response time';

  @override
  String get titleEditMcpServer => 'Edit MCP server';

  @override
  String get titleEditMemory => 'Edit Memory';

  @override
  String get titleEditMessage => 'Edit message';

  @override
  String get titleEditProfile => 'Edit profile';

  @override
  String get titleEditStyle => 'Edit style';

  @override
  String get titleEnabled => 'Enabled';

  @override
  String get titleFriendRequestsAndAccepts => 'Friend requests and accepts';

  @override
  String get titleFriendUpdates => 'Friend updates';

  @override
  String get titleFriends => 'Friends';

  @override
  String get titleGlobalDefault => 'Global default';

  @override
  String get titleGlobalDefaultSystemPrompt => 'Global default system prompt';

  @override
  String get titleKnowledgeBase => 'Knowledge base';

  @override
  String get titleKnowledgeBasePage => 'Knowledge Base';

  @override
  String get titleLlmModel => 'LLM Model';

  @override
  String get titleMemories => 'Memories';

  @override
  String get titleMemoryKnowledgeBase => 'Memory & knowledge base';

  @override
  String get titleModel => 'Model';

  @override
  String get titleModerator => 'Moderator';

  @override
  String get titleMyLanguages => 'My languages';

  @override
  String get titleNewMcpServer => 'New MCP server';

  @override
  String get titleNewRoom => 'New room';

  @override
  String get titleNotifications => 'Notifications';

  @override
  String get titleOpenFullSettings => 'Open full settings';

  @override
  String get titleOverridesYourGlobalDefaultForThis =>
      'Overrides your global default for this conversation only.';

  @override
  String get titlePages => 'Pages';

  @override
  String get titlePersonalContext => 'Personal context';

  @override
  String get titleProfileAppearanceModelsAndMore =>
      'Profile, appearance, models, and more';

  @override
  String get titlePublishChanges => 'Publish changes';

  @override
  String get titleReadAloudNewAssistantMessages =>
      'Read aloud new assistant messages';

  @override
  String get titleRememberThis => 'Remember This';

  @override
  String get titleReminders => 'Reminders';

  @override
  String get titleRemindersAndRecurringPrompts =>
      'Reminders and recurring prompts';

  @override
  String get titleRemoveFriend => 'Remove Friend';

  @override
  String get titleRemoveMember => 'Remove member?';

  @override
  String get titleReplyInTheLanguageYouSpeak =>
      'Reply in the language you speak (Talk Mode)';

  @override
  String get titleReportABugOrIdea => 'Report a bug or idea';

  @override
  String get titleReportABugOrRequestA => 'Report a bug or request a feature';

  @override
  String get titleRequestPending => 'request pending';

  @override
  String get titleRevertAllChanges => 'Revert all changes?';

  @override
  String get titleSavePromptToLibrary => 'Save prompt to library';

  @override
  String get titleSaveStyle => 'Save style';

  @override
  String get titleSavedMemories => 'Saved memories';

  @override
  String get titleScheduledActions => 'Scheduled actions';

  @override
  String get titleScheduledRemindersAndCheckIns =>
      'Scheduled reminders and check-ins';

  @override
  String get titleSendFeedbackStraightToTheAdmins =>
      'Send feedback straight to the admins';

  @override
  String get titleSendRequestsAndManageYourFriends =>
      'Send requests and manage your friends';

  @override
  String get titleSetYourLocation => 'Set your location';

  @override
  String get titleShareCoarseLocation => 'Share my location';

  @override
  String get titleShowMessageMetadata => 'Show message metadata';

  @override
  String get titleShowSystemPromptInThread => 'Show system prompt in thread';

  @override
  String get titleSignOut => 'Sign out';

  @override
  String get titleSkillsLibrary => 'Skills library';

  @override
  String get titleSpeed => 'Speed';

  @override
  String get titleStartAConversationToPickTools =>
      'Start a conversation to pick tools';

  @override
  String get titleStartAConversationToToggleInjection =>
      'Start a conversation to toggle injection';

  @override
  String get titleSystemAlerts => 'System alerts';

  @override
  String get titleSystemPrompt => 'System Prompt';

  @override
  String get titleTakePhoto => 'Take photo';

  @override
  String get titleTalkOverTheAiToInterrupt =>
      'Talk over the AI to interrupt (Talk Mode)';

  @override
  String get titleTapToUpdateOrCorrect => 'Tap to update or correct';

  @override
  String get titleThisConversation => 'This conversation';

  @override
  String get titleTokenUsage => 'Token usage';

  @override
  String get titleTools => 'Tools';

  @override
  String get titleUpdateNameAndEmail => 'Update name and email';

  @override
  String get titleUploadDocumentsForRetrievalAcrossChats =>
      'Upload documents for retrieval across chats';

  @override
  String get titleUseForNewChats => 'Use for new chats';

  @override
  String get titleUseKnowledgeBase => 'Use knowledge base';

  @override
  String get titleUseMemory => 'Use memory';

  @override
  String get titleUsersModelsMcpServersReports =>
      'Users, models, MCP servers, reports';

  @override
  String get titleVoice => 'Voice';

  @override
  String get titleVoiceInterruption => 'Voice interruption';

  @override
  String get titleWhatTheAssistantHasLearnedAbout =>
      'What the assistant has learned about you';

  @override
  String get titleYou => 'You';

  @override
  String get transport => 'Transport';

  @override
  String get tryAgain => 'Try again';

  @override
  String ttsSpeedValue(String speed) {
    return '${speed}x';
  }

  @override
  String get unblock => 'Unblock';

  @override
  String get unexpectedError => 'Unexpected error';

  @override
  String get update => 'Update';

  @override
  String updateToVersion(String releaseVersion) {
    return 'Update to v$releaseVersion';
  }

  @override
  String get usedForNewChats => 'Used for new chats';

  @override
  String userCreatedMessage(String email) {
    return 'User $email created';
  }

  @override
  String get validationErrorRequired => 'Required';

  @override
  String get wantsToBeYourFriend => 'wants to be your friend';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get validatorEnterPassword => 'Enter your password';

  @override
  String validatorPasswordMinLength(String length) {
    return 'Password must be at least $length characters';
  }

  @override
  String get validatorEnterEmail => 'Enter your email';

  @override
  String get validatorEnterValidEmail => 'Enter a valid email';

  @override
  String get validatorEnterAnEmail => 'Enter an email';

  @override
  String get validatorNameRequired => 'Name is required';

  @override
  String get validatorUrlRequired => 'URL is required for HTTP/SSE transports';

  @override
  String get validatorCommandRequired =>
      'Command is required for stdio transport';

  @override
  String get tooltipRefresh => 'Refresh';

  @override
  String get tooltipMore => 'More';

  @override
  String get tooltipSetStatus => 'Set status';

  @override
  String get tooltipStyleOptions => 'Style options';

  @override
  String get tooltipTestConnection => 'Test connection';

  @override
  String get tooltipEdit => 'Edit';

  @override
  String get tooltipDeleteLongPress => 'Delete (long-press)';

  @override
  String get tooltipStopEditing => 'Stop editing';

  @override
  String get tooltipClosePanel => 'Close panel';

  @override
  String get tooltipNew => 'New';

  @override
  String get tooltipCloseSettings => 'Close settings';

  @override
  String get tooltipFriendActions => 'Friend actions';

  @override
  String get tooltipCancelRequest => 'Cancel request';

  @override
  String get tooltipAcceptShare => 'Accept share';

  @override
  String get tooltipDeclineShare => 'Decline share';

  @override
  String get tooltipAccept => 'Accept';

  @override
  String get tooltipDecline => 'Decline';

  @override
  String get labelOff => 'Off';

  @override
  String get labelLow => 'Low';

  @override
  String get labelMedium => 'Medium';

  @override
  String get labelHigh => 'High';

  @override
  String get labelThinkingAuto => 'auto';

  @override
  String get monogramPlaceholder => '?';

  @override
  String get labelNewBadge => 'NEW';

  @override
  String get messageNoReportsYet => 'No reports yet';

  @override
  String messageNoReportsWithStatus(String status) {
    return 'No $status reports';
  }

  @override
  String get messageNoMcpServersConfigured => 'No MCP servers configured';

  @override
  String get messageUsePlusButtonToAddOne => 'Use the + button to add one.';

  @override
  String get messageTapSyncToDiscoverModels =>
      'Tap the sync button to discover models from the provider.';

  @override
  String get messageUnmute => 'Unmute';

  @override
  String get messageMute => 'Mute';

  @override
  String get messageEndCall => 'End call';

  @override
  String get messageTapToStart => 'Tap to start';

  @override
  String get messageListening => 'Listening…';

  @override
  String get messageTranscribing => 'Transcribing…';

  @override
  String get messageThinking => 'Thinking…';

  @override
  String get messageSpeakingTapToInterrupt => 'Speaking… tap to interrupt';

  @override
  String get messageSpeakingTalkOrTapToInterrupt =>
      'Speaking… talk or tap to interrupt';

  @override
  String get messageTapCircleToRetry => 'Tap the circle to retry';

  @override
  String get messageAuto => 'Auto';

  @override
  String get messageReplyLanguageAuto => 'Reply language: Auto';

  @override
  String messageReplyLanguageNamed(String language) {
    return 'Reply language: $language';
  }

  @override
  String labelCouldNotUpdateWithError(String error) {
    return 'Could not update: $error';
  }

  @override
  String messageTestingServer(String name) {
    return 'Testing $name…';
  }

  @override
  String messageTestOkToolsAvailable(int count) {
    return 'OK: $count tools available';
  }

  @override
  String messageTestFailed(String error) {
    return 'Failed: $error';
  }

  @override
  String get messageUnknownError => 'unknown error';

  @override
  String get messageSyncingModels => 'Syncing models from provider…';

  @override
  String messageModelsSyncedCount(int count) {
    return '$count models synced';
  }

  @override
  String messageUserCreated(String email) {
    return 'User $email created';
  }

  @override
  String get labelOpen => 'Open';

  @override
  String get labelInProgress => 'In progress';

  @override
  String get labelClosed => 'Closed';

  @override
  String get statusOpen => 'open';

  @override
  String get statusInProgress => 'in_progress';

  @override
  String get statusClosed => 'closed';

  @override
  String get messageOpenReports => 'No open reports';

  @override
  String get messageInProgressReports => 'No in progress reports';

  @override
  String get messageClosedReports => 'No closed reports';

  @override
  String get labelVision => 'Vision';

  @override
  String get labelTools => 'Tools';

  @override
  String get labelThinking => 'Thinking';

  @override
  String get tooltipVisionUnknown => 'Vision unknown for this model';

  @override
  String get tooltipToolsUnknown => 'Tools unknown for this model';

  @override
  String get tooltipThinkingUnknown => 'Thinking unknown for this model';

  @override
  String get labelLowSensitivity => 'Low sensitivity';

  @override
  String get labelHighSensitivity => 'High sensitivity';

  @override
  String get labelBargeInOff => 'Off';

  @override
  String get labelByModel => 'By model';

  @override
  String get labelByDay => 'By day';

  @override
  String get labelByConversation => 'By conversation';

  @override
  String get labelTokens => 'Tokens';

  @override
  String get labelMessages => 'Messages';

  @override
  String get messageNoDataForPeriod => 'No data for this period';

  @override
  String get titleUsageByModel => 'By model';

  @override
  String get titleUsageByDay => 'By day';

  @override
  String get titleUsageByConversation => 'By conversation';

  @override
  String get labelEnabled => 'Enabled';

  @override
  String get labelStdio => 'stdio';

  @override
  String get labelCommand => 'Command';

  @override
  String get messageAdminPanelSubtitle => 'Users, models, MCP servers, reports';

  @override
  String get messageAllowAdminPrivileges =>
      'Allow this user to manage users and MCP servers';

  @override
  String get messageDisabledServersIgnored =>
      'Disabled servers are ignored by the agent';

  @override
  String get titleProfile => 'Profile';

  @override
  String get titleModels => 'Models';

  @override
  String get titleMemory => 'Memory';

  @override
  String get titleSoftwareUpdate => 'Software update';

  @override
  String messageServerFallback(String model) {
    return 'Server fallback (usually $model)';
  }

  @override
  String get messageNotSetUsingDefaults => 'Not set — using built-in defaults';

  @override
  String get messageSavedMemoriesHint =>
      'Memories are managed from the chat screen via the memory page. Open the chat to review, edit, or delete them.';

  @override
  String get messageNoSavedStylesHint =>
      'No saved styles yet. Compose a model, thinking level, and prompt in Customize, then save the combination to switch in one tap.';

  @override
  String get labelSaveChanges => 'Save changes';

  @override
  String messageStyleModelNotInstalled(String modelId) {
    return '$modelId is not installed';
  }

  @override
  String get messageNotSupportedByThisModel => 'Not supported by this model';

  @override
  String get messageNoModelsAvailable => 'No models available.';

  @override
  String get messageCustomPromptReplacesTemplate =>
      'This conversation has a custom prompt. Picking a template replaces it.';

  @override
  String messageEditingStyle(String name) {
    return 'Editing \"$name\"';
  }

  @override
  String get messageStopUsingForNewChats => 'Stop using for new chats';

  @override
  String get labelCustomize => 'Customize';

  @override
  String get messageGenerateHint => 'Describe what you want the prompt to do:';

  @override
  String get messageRefineDraft => 'Refine draft';

  @override
  String get hintSarcasticCodingMentor =>
      'e.g. A sarcastic coding mentor that keeps answers short';

  @override
  String get messageGenerating => 'Generating…';

  @override
  String get messageGenerationFailed => 'Generation failed';

  @override
  String get messageCouldNotLoadModels => 'Could not load models';

  @override
  String get messageEveryoneAndAllAgents => 'Everyone and all agents';

  @override
  String get messageAgent => 'Agent';

  @override
  String get messageBranch => 'Branch';

  @override
  String get messageCopyMessageToClipboard => 'Copy message to clipboard';

  @override
  String get messageRegenerate => 'Regenerate';

  @override
  String get messageDeleteThisResponse =>
      'Delete this response and generate a new one';

  @override
  String get messageSpeak => 'Speak';

  @override
  String get messageCopied => 'Copied!';

  @override
  String get messageCouldNotReachServer =>
      'Could not reach the server — check your connection and try again.';

  @override
  String messageContextWindow(String used, String total) {
    return 'Context window: $used of $total tokens used';
  }

  @override
  String get messageAbove80PercentSummarized =>
      'Above 80%, older messages are summarized to free up space.';

  @override
  String messageCouldNotSubmit(String error) {
    return 'Could not submit: $error';
  }

  @override
  String get messageEmailUpdatedSignInAgain =>
      'Email updated. Please sign in again with the new address.';

  @override
  String get messageChangingEmailSignsYouOut => 'Changing email signs you out';

  @override
  String get messageNoFriendsYet =>
      'No friends yet. Send a request by email above.';

  @override
  String get titleIncomingRequests => 'Incoming requests';

  @override
  String get titleSharedWithYou => 'Shared with you';

  @override
  String get titleSentRequests => 'Sent requests';

  @override
  String get titleYourFriends => 'Your friends';

  @override
  String get titleBlocked => 'Blocked';

  @override
  String get messageAddAFriend => 'Add a friend';

  @override
  String messageBlockEmailConfirmation(String email) {
    return 'Block $email? Any friendship or pending request between you is removed, and neither of you can send new requests or add the other to rooms. You can unblock them later.';
  }

  @override
  String messageRemoveFriendConfirmation(String name) {
    return 'Remove $name from your friends? You can send a new request later.';
  }

  @override
  String messageYouAreNowFriendsWith(String email) {
    return 'You are now friends with $email';
  }

  @override
  String messageFriendRequestSentTo(String email) {
    return 'Friend request sent to $email';
  }

  @override
  String get labelStyleNoun => 'style';

  @override
  String get labelPromptTemplateNoun => 'prompt template';

  @override
  String messageItemAddedToYourNouns(String name, String noun) {
    return '\"$name\" added to your ${noun}s';
  }

  @override
  String get titleConfirmAction => 'Confirm action?';

  @override
  String get labelConversation => 'Conversation';

  @override
  String get labelAlways => 'Always';

  @override
  String get messageBackToChat => 'Back to chat';

  @override
  String get titleSearchResults => 'Search results';

  @override
  String messageNoResultsFor(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String get messageSearchHint => 'Enter a search query';

  @override
  String get messageEveryToolEnabled => 'Every available tool is enabled';

  @override
  String get titleEnabledTools => 'Enabled tools';

  @override
  String get titleAvailableTools => 'Available tools';

  @override
  String get messageCouldNotReachServerPleaseTryAgain =>
      'Could not reach the server. Please try again.';

  @override
  String get labelConnection => 'Connection';

  @override
  String get messageCityCountry => 'City, Country';

  @override
  String messageCityLevelOnly(String location) {
    return 'City-level only, shared as $location';
  }

  @override
  String get labelLocation => 'Location';

  @override
  String get messageNoDocumentsHint =>
      'Upload documents for retrieval across chats.';

  @override
  String messageCouldNotLoadConversation(String error) {
    return 'Could not load conversation: $error';
  }

  @override
  String messageCouldNotLoadConversations(String error) {
    return 'Could not load conversations: $error';
  }

  @override
  String messageCouldNotLoadOlderMessages(String error) {
    return 'Could not load older messages: $error';
  }

  @override
  String messageCouldNotCreateConversation(String error) {
    return 'Could not create conversation: $error';
  }

  @override
  String messageCouldNotDeleteConversation(String error) {
    return 'Could not delete conversation: $error';
  }

  @override
  String messageCouldNotRegenerate(String error) {
    return 'Could not regenerate: $error';
  }

  @override
  String messageCouldNotBranch(String error) {
    return 'Could not branch conversation: $error';
  }

  @override
  String messageCouldNotPinConversation(String error) {
    return 'Could not pin conversation: $error';
  }

  @override
  String messageCouldNotReloadConversation(String error) {
    return 'Could not reload conversation: $error';
  }

  @override
  String get messageNoConversationsYet => 'No conversations yet.';

  @override
  String get messageNoRoomsYet => 'No rooms yet.';

  @override
  String get messageStartAConversation => 'Start a conversation';

  @override
  String get messageExplainQuantumComputing =>
      'Explain quantum computing in simple terms';

  @override
  String get messageAttachOrDragFiles =>
      'Attach or drag in PDFs, spreadsheets, code, and pictures.';

  @override
  String get messageAttachPhotosOrFiles => 'Attach photos or files';

  @override
  String messageDuplicateFile(String name) {
    return 'Duplicate file: $name';
  }

  @override
  String get messageNewerVersionAvailable => 'A newer version is available';

  @override
  String get messageCheckingForUpdates => 'Checking for updates…';

  @override
  String get messageDownloadingUpdate => 'Downloading update…';

  @override
  String get messageDownloadedArchiveEmpty => 'Downloaded archive is empty';

  @override
  String get messageUpdateFailed => 'Update failed';

  @override
  String get messageInstallFailed => 'Install failed';

  @override
  String get labelError => 'Error';

  @override
  String get labelDismiss => 'Dismiss';

  @override
  String get messageDismissed => 'Dismissed';

  @override
  String get tooltipCopy => 'Copy';

  @override
  String get tooltipBranch => 'Branch';

  @override
  String get tooltipRegenerate => 'Regenerate';

  @override
  String get tooltipCopyMessage => 'Copy message to clipboard';

  @override
  String get messageDeleteResponseRegenerate =>
      'Delete this response and generate a new one';

  @override
  String get messageRegenerateTitle => 'Regenerate';

  @override
  String get tooltipSpeak => 'Speak';

  @override
  String get messageDragToPan => 'Drag to pan • Double tap to reset';

  @override
  String get messageDropFilesToAttach => 'Drop files to attach';

  @override
  String get labelCamera => 'Camera';

  @override
  String get labelGallery => 'Gallery';

  @override
  String get labelFile => 'File';

  @override
  String get messageDeleteConversationConfirmation =>
      'Delete this conversation?';

  @override
  String get messageConversationStyleUpdated => 'Conversation style updated';

  @override
  String get messageChangeConversationStyle => 'Change conversation style?';

  @override
  String messageCalling(String name) {
    return 'Calling $name…';
  }

  @override
  String get messageConnectionLost => 'Connection lost.';

  @override
  String get messageDeactivate => 'Deactivate';

  @override
  String get messageCreateMemory => 'Create memory';

  @override
  String get titleCreateMemoryAction => 'Create Memory';

  @override
  String get titleEditMemoryAction => 'Edit Memory';

  @override
  String get titleDeleteMemoryAction => 'Delete Memory';

  @override
  String messageDeleteMemoryConfirmation(String content) {
    return 'Are you sure you want to delete this memory?\n\n\"$content\"';
  }

  @override
  String get messageCreateNewMemory => 'Create new memory';

  @override
  String get messageNoMemoriesYet => 'No memories yet.';

  @override
  String get titleRoomMembers => 'Members';

  @override
  String get titleRoomAgents => 'Agents';

  @override
  String get messageCreateRoom =>
      'Create rooms where several AI agents (and people) chat together.';

  @override
  String get messageCreateARoomQuestion => 'Create a room?';

  @override
  String get messageAgentName => 'Agent';

  @override
  String get messageRoomOwner => 'Owner';

  @override
  String get messageEveryone => 'Everyone';

  @override
  String get messageMentionAll => '@all';

  @override
  String get messageUnnamed => '(unnamed)';

  @override
  String get messageNoRoomMessagesYet => 'No messages yet.';

  @override
  String get messageRoomMuted => 'Muted';

  @override
  String get tooltipRoomInfo => 'Room info';

  @override
  String get tooltipLeaveRoom => 'Leave room';

  @override
  String get tooltipRoomMenu => 'Room menu';

  @override
  String get messageDeleteRoom => 'Delete room';

  @override
  String get messageLeaveRoom => 'Leave room';

  @override
  String get messageInviteSent => 'Invite sent';

  @override
  String get messageNoModels => 'No models';

  @override
  String get messageNoTools => 'No tools';

  @override
  String tooltipSharePromptWithFriend(String name) {
    return 'Share \"$name\" with a friend';
  }

  @override
  String tooltipEditTemplate(String name) {
    return 'Edit \"$name\"';
  }

  @override
  String tooltipDeleteTemplate(String name) {
    return 'Delete \"$name\"';
  }

  @override
  String get messageEditSystemPrompt => 'Edit system prompt';

  @override
  String get messageEditMemory => 'Edit memory';

  @override
  String get messageEditScheduledAction => 'Edit scheduled action';

  @override
  String get messageEditThisMessage =>
      'Edit this message and rerun the conversation from here';

  @override
  String get messageEmailRequired => 'Email is required';

  @override
  String get messageFullNameRequired => 'Full name is required';

  @override
  String get messageCurrentPasswordRequired => 'Current password is required';

  @override
  String get messageNewPasswordRequired => 'New password is required';

  @override
  String get messagePasswordsDoNotMatch => 'Passwords do not match';

  @override
  String get messageProfileUpdated => 'Profile updated';

  @override
  String get messageFailedToUpdateProfile => 'Failed to update profile';

  @override
  String get messageFailedToChangePassword => 'Failed to change password';

  @override
  String get messageFailedToUpdateLocation => 'Failed to update location';

  @override
  String get labelMonthNames =>
      'Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec';

  @override
  String messageMonthDayYearTime(
    String month,
    String day,
    String year,
    String hour,
    String minute,
    String amPm,
  ) {
    return '$month $day, $year • $hour:$minute $amPm';
  }

  @override
  String get labelOneWeek => '1 week';

  @override
  String get labelEightHours => '8 hours';

  @override
  String get labelForever => 'forever';

  @override
  String get labelUnmute => 'unmute';

  @override
  String get messageMute1Week => 'Muted for 1 week';

  @override
  String get messageMute8Hours => 'Muted for 8 hours';

  @override
  String get messageMutedForever => 'Muted forever';

  @override
  String get messageUnmuted => 'Unmuted';

  @override
  String titleMutedUntil(String time) {
    return 'Muted until $time';
  }

  @override
  String get labelSystemDefault => 'System default';

  @override
  String get messageActivate => 'Activate';

  @override
  String get tooltipEditMemory => 'Edit memory';

  @override
  String get tooltipDeleteMemory => 'Delete memory';

  @override
  String get tooltipDeactivateMemory => 'Deactivate memory';

  @override
  String get tooltipActivateMemory => 'Activate memory';

  @override
  String get labelImage => 'Image';

  @override
  String get labelAudio => 'Audio';

  @override
  String get labelVideo => 'Video';

  @override
  String get labelDocument => 'Document';

  @override
  String get messageTool => 'tool';

  @override
  String get messageBlockMath => 'blockMath';

  @override
  String get messageInlineMath => 'inlineMath';

  @override
  String get messageDragToPanDoubleTapReset =>
      'Drag to pan • Double tap to reset';

  @override
  String get messageDropFilesHere => 'Drop files to attach';

  @override
  String get labelBytes => 'bytes';

  @override
  String get labelClose => 'Close';

  @override
  String messageFailedToRenderDiagramWithError(String error) {
    return 'Failed to render diagram: $error';
  }

  @override
  String messageCouldNotLoadDiagram(String error) {
    return 'Could not load diagram: $error';
  }

  @override
  String messageParseFailedForTool(String tool) {
    return 'Parse failed for $tool';
  }

  @override
  String get labelRetry => 'Retry';

  @override
  String get labelDone => 'Done';

  @override
  String get labelLoading => 'Loading…';

  @override
  String get labelDeviceBusy => 'Device or resource busy';

  @override
  String messageMicrophoneUnavailable(String error) {
    return 'Microphone unavailable: $error';
  }

  @override
  String messageCouldNotTranscribe(String error) {
    return 'Could not transcribe: $error';
  }

  @override
  String get messageDidntCatchThat => 'Didn’t catch that — try again';

  @override
  String get messageCouldNotResolveLocation =>
      'Could not resolve your location';

  @override
  String get messageFailedToResolveLocation =>
      'Failed to resolve your location';

  @override
  String get labelOr => 'or';

  @override
  String get labelOnline => 'online';

  @override
  String get messageCallingX => 'Calling X…';

  @override
  String get messageRevertAllChangesWarning =>
      'Discard every uncommitted change in your workspace. This cannot be undone.';

  @override
  String get labelRemember => 'Remember';

  @override
  String get messageRememberDescription =>
      'Save this content as a memory for future reference:';

  @override
  String get messageMemorySaved => 'Memory saved successfully';

  @override
  String messageFailedToSaveMemory(String error) {
    return 'Failed to save memory: $error';
  }

  @override
  String messageRecording(String duration) {
    return 'Recording $duration';
  }

  @override
  String messageFailedToDeleteRoom(String error) {
    return 'Failed to delete room: $error';
  }

  @override
  String get labelUndo => 'Undo';

  @override
  String messageModelNotInstalled(String modelId) {
    return '$modelId is not installed';
  }

  @override
  String get messageNoSavedStylesYet =>
      'No saved styles yet. Compose a model, thinking level, and prompt in Customize, then save the combination to switch in one tap.';

  @override
  String messageEditing(String name) {
    return 'Editing \"$name\"';
  }

  @override
  String messageFilesTooLarge(String files) {
    return 'Files too large:\n$files';
  }

  @override
  String get titleTheme => 'Theme';

  @override
  String get titleDisplaySystemPrompt =>
      'Display the active system prompt above the conversation';

  @override
  String get messageNoMcpToolsAvailable =>
      'No MCP tools available. Configure a server from the Admin panel.';

  @override
  String messageNToolsEnabled(int selected, int total) {
    return '$selected of $total tools enabled';
  }

  @override
  String get messageNoModelSelected => 'No model selected';

  @override
  String messageUsingSource(String source) {
    return 'Using: $source';
  }

  @override
  String get messageAppliedToEveryNewConversation =>
      'Applied to every new conversation unless overridden per-chat.';

  @override
  String get messageNoToolsAvailableConfigureMcp =>
      'No tools available. Configure an MCP server first.';

  @override
  String messageNoToolsMatchQuery(String query) {
    return 'No tools match \"$query\".';
  }

  @override
  String messageToolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tools',
      one: '$count tool',
    );
    return '$_temp0';
  }

  @override
  String get messageNoScheduledActionsYet => 'No scheduled actions yet';

  @override
  String get messageUsePlusButton =>
      'Use the + button to set up a reminder or recurring check-in.';

  @override
  String messageCronExpression(String expr) {
    return 'Cron: $expr';
  }

  @override
  String messageRemoveScheduledAction(String title) {
    return 'Remove \"$title\"? This cannot be undone.';
  }

  @override
  String get titleNewScheduledAction => 'New scheduled action';

  @override
  String get titleEditScheduledAction => 'Edit scheduled action';

  @override
  String get hintMorningStandup => 'Morning standup';

  @override
  String get helperCronExpression => 'min hour day month weekday';

  @override
  String get hintPickDateTime => 'Pick a date and time';

  @override
  String messageCreatedAt(String date) {
    return 'Created $date';
  }

  @override
  String messageUpdateToVersion(String version) {
    return 'Update to v$version';
  }

  @override
  String messageUpdateRestartAfterInstall(String currentVersion) {
    return 'You have v$currentVersion. The app restarts after installing.';
  }

  @override
  String messageLatestRelease(String version) {
    return 'Latest release: v$version';
  }

  @override
  String messageUpdateAvailable(String version) {
    return 'Garbanzo AI v$version is available';
  }

  @override
  String messageAssistantKnowsLocation(String location) {
    return 'The assistant knows you are near $location';
  }

  @override
  String get titlePhotos => 'Photos';

  @override
  String get titleFiles => 'Files';

  @override
  String get titleFolder => 'Folder';

  @override
  String messageFolderScope(String name) {
    return 'Reading files in $name';
  }

  @override
  String get messageRemoveFolder => 'Remove folder';

  @override
  String get messageFolderAttachFailed => 'Couldn\'t attach that folder';

  @override
  String get titleDelegateWorkflow => 'Delegate this task?';

  @override
  String messageWorkflowScope(String name) {
    return 'Works on a copy of $name';
  }

  @override
  String get messageWorkflowScanning => 'Scanning folder…';

  @override
  String get messageWorkflowUploading => 'Uploading folder…';

  @override
  String get messageWorkflowRunning => 'Agent is working…';

  @override
  String get messageWorkflowKeepsRunning =>
      'Keeps running if you close the app — you\'ll be notified.';

  @override
  String get messageWorkflowDone => 'Workflow finished';

  @override
  String get messageWorkflowFailed => 'Workflow failed';

  @override
  String get messageWorkflowNeedsFolder =>
      'Attach a folder to this chat first.';

  @override
  String get actionReviewChanges => 'Review changes';

  @override
  String get titleWorkflowChanges => 'Review changes';

  @override
  String get messageWorkflowNoChanges =>
      'The workflow didn\'t change any files.';

  @override
  String messageWorkflowApplyWarning(String path) {
    return 'Selected files will be written into $path.';
  }

  @override
  String messageWorkflowFilesSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files were too large to send — the agent won\'t see them',
      one: '1 file was too large to send — the agent won\'t see it',
    );
    return '$_temp0';
  }

  @override
  String get messageWorkflowFolderTruncated =>
      'The folder is too big to send in full — only part of it was included.';

  @override
  String get messageWorkflowTooLarge => 'Too large to apply';

  @override
  String messageWorkflowApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files applied',
      one: '1 file applied',
    );
    return '$_temp0';
  }

  @override
  String get messageWorkflowConflicts =>
      'Skipped — these changed on disk while the workflow ran:';

  @override
  String get messageWorkflowFailedFiles => 'Could not write:';

  @override
  String get labelFileAdded => 'Added';

  @override
  String get labelFileModified => 'Modified';

  @override
  String get labelFileDeleted => 'Deleted';

  @override
  String get labelDismissed => 'Dismissed';

  @override
  String actionApplySelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Apply $count files',
      one: 'Apply 1 file',
    );
    return '$_temp0';
  }

  @override
  String get messageSttUnavailable =>
      'Speech-to-text is currently unavailable on the server.';

  @override
  String get messageTranscriptionFailed =>
      'Transcription failed — please try again.';

  @override
  String messageDeleteStyle(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get messageSaveChangesToStyle => 'Save changes';

  @override
  String messageModelNameFallback(String modelId, String modelName) {
    return '$modelId / $modelName';
  }

  @override
  String messageDeleteStyleConfirmation(String name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get messageMemoriesStoreFactsHint =>
      'Memories store important facts about you\nfor more personalized conversations';

  @override
  String get messageSourceConversation => 'Source: Conversation';

  @override
  String get messageTypeMessageToBegin =>
      'Type a message below to begin chatting';

  @override
  String get messageWriteAPythonFunction => 'Write a Python function';

  @override
  String get messageWriteAPythonFunctionPrompt =>
      'Write a Python function to calculate factorial';

  @override
  String get messageHelpMeDebugCode => 'Help me debug code';

  @override
  String get messageHelpMeDebugCodePrompt => 'I need help debugging some code';

  @override
  String get titleGettingStarted => 'Getting started';

  @override
  String get tipVoiceInputTitle => 'Voice input';

  @override
  String get tipVoiceInputBody =>
      'Tap the mic to dictate — your speech is transcribed locally.';

  @override
  String get tipFilesAndImagesTitle => 'Files & images';

  @override
  String get tipFilesAndImagesBody =>
      'Attach or drag in PDFs, spreadsheets, code, and pictures.';

  @override
  String get tipMemoryTitle => 'Memory';

  @override
  String get tipMemoryBody =>
      'The assistant learns facts about you over time — review them anytime under Settings → Memories.';

  @override
  String get tipKnowledgeBaseTitle => 'Knowledge base';

  @override
  String get tipKnowledgeBaseBody =>
      'Upload documents once, then ask questions about them in any chat.';

  @override
  String get tipRoomsTitle => 'Rooms';

  @override
  String get tipRoomsBody =>
      'Create rooms where several AI agents (and people) chat together.';

  @override
  String get tooltipTimeRange => 'Time range';

  @override
  String messageNoUsageInLastDays(int days) {
    return 'No usage in the last $days days';
  }

  @override
  String get messageStartAConversationTokensHint =>
      'Start a conversation to see your token consumption here.';

  @override
  String messageDailyTokensDays(int days) {
    return 'Daily tokens ($days days)';
  }

  @override
  String get titleByConversation => 'Top conversations';

  @override
  String get labelTotalTokens => 'Total tokens';

  @override
  String get labelGenerated => 'Generated';

  @override
  String get messageUntitled => 'Untitled';

  @override
  String messageModelBreakdown(String prompt, String generated, int count) {
    return '$prompt in · $generated out · $count msgs';
  }

  @override
  String messagePromptGeneratedInOut(String prompt, String generated) {
    return '$prompt in · $generated out';
  }

  @override
  String get tooltipOpenConversations => 'Open conversations';

  @override
  String get tooltipSearchConversations => 'Search conversations';

  @override
  String get labelMicroApp => 'Micro-app';

  @override
  String get tooltipReopenMicroAppPanel => 'Reopen the micro-app panel';

  @override
  String tooltipReopenApp(String name) {
    return 'Reopen $name';
  }

  @override
  String messageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '$count message',
    );
    return '$_temp0';
  }

  @override
  String get hintSystemPromptExample =>
      'e.g. You are a concise, no-nonsense assistant. Give short factual answers with examples.';

  @override
  String get messageCityLevelOnlyHint =>
      'Shares your neighbourhood-level area, so \"near me\" questions (like nearby restaurants) work. Your exact coordinates are never stored.';

  @override
  String get messageNotifyAssistantBackground =>
      'Notify when assistant replies while app is in background';

  @override
  String get messageUpdatesCheckedAtStart =>
      'Updates are checked when the app starts';

  @override
  String get messageUpToDate => 'You are up to date';

  @override
  String get messageInstallAppRestart => 'Installing — the app will restart';

  @override
  String get messageUpdateCheckFailed => 'Update check failed';

  @override
  String get messageNoBuildForPlatform => 'No build for this platform';

  @override
  String get tooltipRedetectLocation => 'Re-detect from device location';

  @override
  String get hintTypeAMessage => 'Type a message…';

  @override
  String get messageRoomEmptyHint =>
      'Type a message to get started. Use @AgentName to call an agent, or @all to mention everyone.';

  @override
  String get titleMyMcpServers => 'My MCP servers';

  @override
  String get messagePersonalMcpServersHint =>
      'Connect your own tool servers. Only you can see and use these — admins manage shared servers for everyone.';

  @override
  String get labelAddServer => 'Add server';
}
