import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// Application name shown in the window/tab title.
  ///
  /// In en, this message translates to:
  /// **'Garbanzo AI'**
  String get appTitle;

  /// Label for the language settings section.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// Language name for English.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Language name for Spanish.
  ///
  /// In en, this message translates to:
  /// **'Español'**
  String get languageSpanish;

  /// Use the system language setting.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get languageSystem;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:713 (Text)
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get accept;

  /// features/memory/widgets/memory_item_tile.dart:71 (Active)
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get active;

  /// features/rooms/widgets/add_agent_dialog.dart:264 (Text)
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get add;

  /// features/rooms/widgets/room_chat_view.dart:678 (Text); features/rooms/widgets/add_agent_dialog.dart:177 (Text)
  ///
  /// In en, this message translates to:
  /// **'Add agent'**
  String get addAgentTitle;

  /// features/rooms/widgets/room_chat_view.dart:645 (Text)
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get agents;

  /// features/rooms/widgets/add_agent_dialog.dart:217 (Text)
  ///
  /// In en, this message translates to:
  /// **'Always respond'**
  String get alwaysRespond;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:613 (Text)
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get apply;

  /// features/chat/widgets/message/attachment_display.dart:118 (Attached)
  ///
  /// In en, this message translates to:
  /// **'Attached image: {name}'**
  String attachedImageLabel(String name);

  /// pages/login_page.dart:61 (Incorrect)
  ///
  /// In en, this message translates to:
  /// **'Incorrect email or password'**
  String get authErrorIncorrectEmailOrPassword;

  /// features/rooms/widgets/add_agent_dialog.dart:225 (Text)
  ///
  /// In en, this message translates to:
  /// **'Auto — jump in when relevant (LLM)'**
  String get autoJumpInWhenRelevantLlm;

  /// features/chat/talk/talk_mode_page.dart:251 (Text)
  ///
  /// In en, this message translates to:
  /// **'auto'**
  String get autoLowercase;

  /// features/settings/pages/settings_page.dart:306 (Text); features/settings/pages/settings_page.dart:310 (Text); features/chat/talk/talk_mode_page.dart:251 (Text); and 1 more
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get autoModel;

  /// features/friends/pages/friends_page.dart:81 (Text); features/friends/pages/friends_page.dart:355 (Text)
  ///
  /// In en, this message translates to:
  /// **'Block'**
  String get block;

  /// features/friends/pages/friends_page.dart:314 (Text); features/friends/pages/friends_page.dart:355 (Text)
  ///
  /// In en, this message translates to:
  /// **'block'**
  String get blockLowercase;

  /// features/friends/pages/friends_page.dart:314 (Text)
  ///
  /// In en, this message translates to:
  /// **'Block sender'**
  String get blockSender;

  /// features/reports/widgets/submit_report_dialog.dart:158 (Text); features/memory/pages/memory_page.dart:50 (Text); features/memory/pages/memory_page.dart:85 (Text); and 31 more
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// features/settings/widgets/change_password_dialog.dart:144 (Text)
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// features/chat/widgets/style_picker.dart:169 (Chat); features/chat/widgets/style_picker.dart:687 (Text)
  ///
  /// In en, this message translates to:
  /// **'Chat style'**
  String get chatStyle;

  /// features/settings/widgets/update_section.dart:69 (Text)
  ///
  /// In en, this message translates to:
  /// **'Check now'**
  String get checkNow;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:600 (Text)
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// features/settings/widgets/update_dialog.dart:95 (Text)
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// features/microapps/widgets/micro_app_panel.dart:163 (Text)
  ///
  /// In en, this message translates to:
  /// **'Commit and deploy to GitHub Pages.'**
  String get commitAndDeployToGithubPages;

  /// features/chat/widgets/style_picker.dart:772 (Text)
  ///
  /// In en, this message translates to:
  /// **'Compose a style'**
  String get composeAStyle;

  /// features/chat/widgets/action_proposal_card.dart:241 (Text)
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// features/admin/widgets/reports_tab.dart:86 (Text)
  ///
  /// In en, this message translates to:
  /// **'Could not update: {error}'**
  String couldNotUpdate(String error);

  /// features/memory/pages/memory_page.dart:59 (Text); features/scheduled_actions/pages/scheduled_actions_page.dart:498 (Text); features/rooms/widgets/create_room_dialog.dart:95 (Text); and 2 more
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get create;

  /// features/memory/pages/memory_page.dart:123 (Text); features/scheduled_actions/pages/scheduled_actions_page.dart:284 (Text); features/chat/widgets/system_prompt_editor_dialog.dart:133 (Text); and 7 more
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// features/rooms/widgets/room_chat_view.dart:762 (Text)
  ///
  /// In en, this message translates to:
  /// **'Delete agent {name}? This cannot be undone.'**
  String deleteAgentConfirmation(String name);

  /// features/chat/widgets/style_picker.dart:1081 (Text)
  ///
  /// In en, this message translates to:
  /// **'delete'**
  String get deleteLowercase;

  /// features/rooms/widgets/rooms_list_view.dart:98 (Text)
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"? This cannot be undone.'**
  String deleteRoomConfirmation(String name);

  /// features/chat/widgets/style_picker.dart:534 (Text)
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteStyleTitle(String name);

  /// features/chat/widgets/system_prompt_editor_dialog.dart:125 (Text)
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String deleteTemplateTitle(String name);

  /// features/chat/widgets/system_prompt_editor_dialog.dart:718 (Text)
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discard;

  /// features/settings/widgets/update_section.dart:78 (Text)
  ///
  /// In en, this message translates to:
  /// **'Download & install'**
  String get downloadInstall;

  /// features/chat/widgets/style_picker.dart:1076 (Text)
  ///
  /// In en, this message translates to:
  /// **'edit'**
  String get edit;

  /// features/rooms/widgets/add_agent_dialog.dart:177 (Text)
  ///
  /// In en, this message translates to:
  /// **'Edit agent'**
  String get editAgentTitle;

  /// features/chat/widgets/style_picker.dart:1076 (Text)
  ///
  /// In en, this message translates to:
  /// **'Edit…'**
  String get editEllipsis;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:159 (Text)
  ///
  /// In en, this message translates to:
  /// **'Edit \"{name}\"'**
  String editTemplateTitle(String name);

  /// features/rooms/widgets/rooms_list_view.dart:52 (Text)
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String errorWithDetails(String error);

  /// features/friends/providers/friends_provider.dart:54 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to accept request'**
  String get failedToAcceptRequest;

  /// features/friends/providers/friends_provider.dart:121 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to accept share'**
  String get failedToAcceptShare;

  /// features/friends/providers/friends_provider.dart:85 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to block user'**
  String get failedToBlockUser;

  /// features/memory/providers/memory_provider.dart:50 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to create memory'**
  String get failedToCreateMemory;

  /// features/scheduled_actions/providers/scheduled_actions_provider.dart:34 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to create scheduled action'**
  String get failedToCreateScheduledAction;

  /// features/chat/providers/system_prompt_provider.dart:44 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to create template'**
  String get failedToCreateTemplate;

  /// features/memory/providers/memory_provider.dart:90 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to deactivate memory'**
  String get failedToDeactivateMemory;

  /// features/friends/providers/friends_provider.dart:63 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to decline request'**
  String get failedToDeclineRequest;

  /// features/friends/providers/friends_provider.dart:130 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to decline share'**
  String get failedToDeclineShare;

  /// features/rooms/widgets/room_chat_view.dart:785 (Text)
  ///
  /// In en, this message translates to:
  /// **'Failed to delete agent: {error}'**
  String failedToDeleteAgent(String error);

  /// features/knowledge_base/providers/knowledge_base_provider.dart:41 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to delete document'**
  String get failedToDeleteDocument;

  /// features/chat/widgets/chat_page.dart:376 (Text)
  ///
  /// In en, this message translates to:
  /// **'Failed to delete room: {error}'**
  String failedToDeleteRoom(String error);

  /// features/scheduled_actions/providers/scheduled_actions_provider.dart:85 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to delete scheduled action'**
  String get failedToDeleteScheduledAction;

  /// features/chat/providers/style_provider.dart:188 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to delete style'**
  String get failedToDeleteStyle;

  /// features/chat/providers/system_prompt_provider.dart:76 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to delete template'**
  String get failedToDeleteTemplate;

  /// features/chat/providers/chat_provider.dart:520 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to edit message: {error}'**
  String failedToEditMessage(String error);

  /// features/knowledge_base/providers/knowledge_base_provider.dart:19 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to load documents'**
  String get failedToLoadDocuments;

  /// features/friends/providers/friends_provider.dart:36 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to load friends'**
  String get failedToLoadFriends;

  /// features/memory/providers/memory_provider.dart:36 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to load memories'**
  String get failedToLoadMemories;

  /// features/chat/providers/model_provider.dart:27 (Failed); features/admin/providers/admin_provider.dart:267 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to load models'**
  String get failedToLoadModels;

  /// features/notifications/providers/notification_provider.dart:46 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to load notifications'**
  String get failedToLoadNotifications;

  /// features/scheduled_actions/providers/scheduled_actions_provider.dart:21 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to load scheduled actions'**
  String get failedToLoadScheduledActions;

  /// features/chat/providers/style_provider.dart:71 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to load styles'**
  String get failedToLoadStyles;

  /// features/chat/providers/system_prompt_provider.dart:29 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to load system prompts'**
  String get failedToLoadSystemPrompts;

  /// features/tools/providers/tool_provider.dart:25 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to load tools'**
  String get failedToLoadTools;

  /// features/usage/providers/usage_provider.dart:18 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to load usage'**
  String get failedToLoadUsage;

  /// features/friends/providers/friends_provider.dart:74 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to remove friend'**
  String get failedToRemoveFriend;

  /// features/rooms/widgets/room_chat_view.dart:748 (Text)
  ///
  /// In en, this message translates to:
  /// **'Failed to remove member: {error}'**
  String failedToRemoveMember(String error);

  /// features/chat/widgets/mermaid_diagram.dart:187 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to render diagram'**
  String get failedToRenderDiagram;

  /// features/chat/providers/system_prompt_provider.dart:85 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to save default prompt'**
  String get failedToSaveDefaultPrompt;

  /// features/chat/widgets/remember_this_button.dart:126 (Text)
  ///
  /// In en, this message translates to:
  /// **'Failed to save memory: {error}'**
  String failedToSaveMemory(String error);

  /// features/chat/providers/style_provider.dart:128 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to save style'**
  String get failedToSaveStyle;

  /// features/friends/providers/friends_provider.dart:46 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to send friend request'**
  String get failedToSendFriendRequest;

  /// features/chat/providers/chat_provider.dart:454 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to send message: {error}'**
  String failedToSendMessage(String error);

  /// features/friends/providers/friends_provider.dart:108 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to share'**
  String get failedToShare;

  /// features/friends/providers/friends_provider.dart:94 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to unblock user'**
  String get failedToUnblockUser;

  /// features/memory/providers/memory_provider.dart:69 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to update memory'**
  String get failedToUpdateMemory;

  /// features/chat/widgets/memory_toggle_widget.dart:33 (Text)
  ///
  /// In en, this message translates to:
  /// **'Failed to update memory setting: {error}'**
  String failedToUpdateMemorySetting(String error);

  /// features/scheduled_actions/providers/scheduled_actions_provider.dart:60 (Failed); features/scheduled_actions/providers/scheduled_actions_provider.dart:78 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to update scheduled action'**
  String get failedToUpdateScheduledAction;

  /// features/chat/providers/style_provider.dart:160 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to update style'**
  String get failedToUpdateStyle;

  /// features/chat/providers/system_prompt_provider.dart:61 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to update template'**
  String get failedToUpdateTemplate;

  /// features/knowledge_base/providers/knowledge_base_provider.dart:29 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to upload document'**
  String get failedToUploadDocument;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:688 (Text)
  ///
  /// In en, this message translates to:
  /// **'Feedback to apply:'**
  String get feedbackToApply;

  /// features/chat/widgets/chat_page.dart:473 (Text); features/chat/widgets/input/attach_menu_button.dart:74 (Text)
  ///
  /// In en, this message translates to:
  /// **'Files too large:\\n{files}'**
  String filesTooLarge(String files);

  /// features/chat/widgets/chat_message_widget.dart:235 (From)
  ///
  /// In en, this message translates to:
  /// **'From your knowledge base'**
  String get fromYourKnowledgeBase;

  /// pages/login_page.dart:79 (Sign)
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get headingSignIn;

  /// features/admin/widgets/mcp_server_dialog.dart:262 (Text)
  ///
  /// In en, this message translates to:
  /// **'API_KEY=abc\\nDEBUG=1'**
  String get hintApiKeyAbcNdebug1;

  /// features/admin/widgets/create_user_dialog.dart:116 (Text)
  ///
  /// In en, this message translates to:
  /// **'At least 6 characters'**
  String get hintAtLeast6Characters;

  /// features/admin/widgets/mcp_server_dialog.dart:272 (Text)
  ///
  /// In en, this message translates to:
  /// **'Bearer …'**
  String get hintBearer;

  /// features/reports/widgets/submit_report_dialog.dart:140 (Text)
  ///
  /// In en, this message translates to:
  /// **'bug'**
  String get hintBug;

  /// features/chat/widgets/style_picker.dart:1548 (Text)
  ///
  /// In en, this message translates to:
  /// **'Deep work, Quick answers…'**
  String get hintDeepWorkQuickAnswers;

  /// features/scheduled_actions/pages/scheduled_actions_page.dart:462 (Text)
  ///
  /// In en, this message translates to:
  /// **'e.g. \"0 9 * * mon-fri\"'**
  String get hintEG09MonFri;

  /// features/admin/widgets/mcp_server_dialog.dart:173 (Text)
  ///
  /// In en, this message translates to:
  /// **'e.g. filesystem'**
  String get hintEGFilesystem;

  /// features/settings/widgets/location_section.dart:159 (Text)
  ///
  /// In en, this message translates to:
  /// **'e.g. Madrid, Spain'**
  String get hintEGMadridSpain;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:695 (Text)
  ///
  /// In en, this message translates to:
  /// **'e.g. Make it friendlier'**
  String get hintEGMakeItFriendlier;

  /// features/scheduled_actions/pages/scheduled_actions_page.dart:427 (Text)
  ///
  /// In en, this message translates to:
  /// **'e.g. \"Morning standup\"'**
  String get hintEGMorningStandup;

  /// features/rooms/widgets/create_room_dialog.dart:36 (Text)
  ///
  /// In en, this message translates to:
  /// **'e.g. Product brainstorm'**
  String get hintEGProductBrainstorm;

  /// features/memory/pages/memory_page.dart:41 (Text); features/memory/pages/memory_page.dart:76 (Text)
  ///
  /// In en, this message translates to:
  /// **'Enter memory content'**
  String get hintEnterMemoryContent;

  /// features/friends/pages/friends_page.dart:251 (Text)
  ///
  /// In en, this message translates to:
  /// **'friend@example.com'**
  String get hintFriendExampleCom;

  /// features/admin/widgets/create_user_dialog.dart:85 (Text)
  ///
  /// In en, this message translates to:
  /// **'Jane Doe'**
  String get hintJaneDoe;

  /// features/chat/widgets/remember_this_button.dart:78 (Text)
  ///
  /// In en, this message translates to:
  /// **'Memory content'**
  String get hintMemoryContent;

  /// features/rooms/widgets/room_chat_view.dart:230 (Text)
  ///
  /// In en, this message translates to:
  /// **'Message the room… (use @AgentName or @all)'**
  String get hintMessageTheRoomUseAgentnameOr;

  /// features/reports/widgets/submit_report_dialog.dart:125 (Text)
  ///
  /// In en, this message translates to:
  /// **'One-line summary'**
  String get hintOneLineSummary;

  /// features/chat/widgets/search_widget.dart:46 (Text)
  ///
  /// In en, this message translates to:
  /// **'Search conversations...'**
  String get hintSearchConversations;

  /// features/tools/pages/skills_library_page.dart:117 (Text)
  ///
  /// In en, this message translates to:
  /// **'Search tools…'**
  String get hintSearchTools;

  /// features/admin/widgets/mcp_server_dialog.dart:238 (Text)
  ///
  /// In en, this message translates to:
  /// **'/usr/bin/python3'**
  String get hintUsrBinPython3;

  /// features/scheduled_actions/pages/scheduled_actions_page.dart:435 (Text)
  ///
  /// In en, this message translates to:
  /// **'What should the assistant do?'**
  String get hintWhatShouldTheAssistantDo;

  /// features/rooms/widgets/add_agent_dialog.dart:202 (Text)
  ///
  /// In en, this message translates to:
  /// **'You are a friendly product strategist…'**
  String get hintYouAreAFriendlyProductStrategist;

  /// features/admin/widgets/create_user_dialog.dart:98 (Text); pages/login_page.dart:119 (Text)
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get hintYouExampleCom;

  /// features/memory/widgets/memory_item_tile.dart:71 (Active)
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// features/rooms/widgets/room_chat_view.dart:839 (Text)
  ///
  /// In en, this message translates to:
  /// **'Invite'**
  String get invite;

  /// features/friends/pages/friends_page.dart:382 (Text)
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" added to your {noun}s'**
  String itemAddedToYourNouns(String name, String noun);

  /// features/rooms/widgets/add_agent_dialog.dart:186 (Text)
  ///
  /// In en, this message translates to:
  /// **'Agent name'**
  String get labelAgentName;

  /// features/admin/widgets/reports_tab.dart:153 (Text)
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get labelAll;

  /// features/admin/widgets/reports_tab.dart:153 (Text)
  ///
  /// In en, this message translates to:
  /// **'all'**
  String get labelAllLowercase;

  /// features/admin/widgets/mcp_server_dialog.dart:252 (Text)
  ///
  /// In en, this message translates to:
  /// **'Args (one per line)'**
  String get labelArgsOnePerLine;

  /// features/admin/widgets/mcp_server_dialog.dart:271 (Text)
  ///
  /// In en, this message translates to:
  /// **'Auth header'**
  String get labelAuthHeader;

  /// features/reports/widgets/submit_report_dialog.dart:104 (Text)
  ///
  /// In en, this message translates to:
  /// **'Bug'**
  String get labelBug;

  /// features/chat/widgets/mobile_drawer.dart:160 (Text); features/chat/widgets/chat_sidebar.dart:149 (Text)
  ///
  /// In en, this message translates to:
  /// **'Chats'**
  String get labelChats;

  /// features/settings/widgets/location_section.dart:158 (Text)
  ///
  /// In en, this message translates to:
  /// **'City'**
  String get labelCity;

  /// features/microapps/widgets/micro_app_panel.dart:168 (Text)
  ///
  /// In en, this message translates to:
  /// **'Commit message (optional)'**
  String get labelCommitMessageOptional;

  /// features/settings/widgets/change_password_dialog.dart:113 (Text)
  ///
  /// In en, this message translates to:
  /// **'Confirm new password'**
  String get labelConfirmNewPassword;

  /// features/microapps/widgets/micro_app_view_native.dart:86 (Text)
  ///
  /// In en, this message translates to:
  /// **'Copy URL'**
  String get labelCopyUrl;

  /// features/rooms/widgets/rooms_list_view.dart:365 (Text)
  ///
  /// In en, this message translates to:
  /// **'Create a room'**
  String get labelCreateARoom;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:525 (Text)
  ///
  /// In en, this message translates to:
  /// **'Create with AI'**
  String get labelCreateWithAi;

  /// features/scheduled_actions/pages/scheduled_actions_page.dart:461 (Text)
  ///
  /// In en, this message translates to:
  /// **'Cron expression'**
  String get labelCronExpression;

  /// features/settings/widgets/change_password_dialog.dart:71 (Text)
  ///
  /// In en, this message translates to:
  /// **'Current password'**
  String get labelCurrentPassword;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:51 (Text); features/settings/pages/settings_page.dart:200 (Text)
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get labelDark;

  /// features/reports/widgets/submit_report_dialog.dart:139 (Text); features/admin/widgets/mcp_server_dialog.dart:185 (Text)
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get labelDescription;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:177 (Text); features/chat/widgets/system_prompt_editor_dialog.dart:337 (Text); features/rooms/widgets/create_room_dialog.dart:44 (Text)
  ///
  /// In en, this message translates to:
  /// **'Description (optional)'**
  String get labelDescriptionOptional;

  /// features/admin/widgets/users_tab.dart:129 (Text)
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get labelDisabled;

  /// features/settings/widgets/edit_profile_dialog.dart:106 (Text); features/admin/widgets/create_user_dialog.dart:97 (Text); pages/login_page.dart:118 (Text)
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get labelEmail;

  /// features/admin/widgets/mcp_server_dialog.dart:261 (Text)
  ///
  /// In en, this message translates to:
  /// **'Env (KEY=VALUE, one per line)'**
  String get labelEnvKeyValueOnePerLine;

  /// features/admin/providers/admin_provider.dart:177 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to create server'**
  String get labelFailedToCreateServer;

  /// features/admin/providers/admin_provider.dart:93 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to create user'**
  String get labelFailedToCreateUser;

  /// features/admin/providers/admin_provider.dart:238 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to delete server'**
  String get labelFailedToDeleteServer;

  /// features/admin/providers/admin_provider.dart:141 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to load servers'**
  String get labelFailedToLoadServers;

  /// features/admin/providers/admin_provider.dart:67 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to load users'**
  String get labelFailedToLoadUsers;

  /// features/admin/providers/admin_provider.dart:284 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to sync models'**
  String get labelFailedToSyncModels;

  /// features/admin/providers/admin_provider.dart:249 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to test server'**
  String get labelFailedToTestServer;

  /// features/admin/providers/admin_provider.dart:314 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to update model'**
  String get labelFailedToUpdateModel;

  /// features/admin/providers/admin_provider.dart:223 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to update server'**
  String get labelFailedToUpdateServer;

  /// features/admin/providers/admin_provider.dart:124 (Failed)
  ///
  /// In en, this message translates to:
  /// **'Failed to update user'**
  String get labelFailedToUpdateUser;

  /// features/reports/widgets/submit_report_dialog.dart:109 (Text)
  ///
  /// In en, this message translates to:
  /// **'Feature'**
  String get labelFeature;

  /// features/settings/widgets/edit_profile_dialog.dart:97 (Text)
  ///
  /// In en, this message translates to:
  /// **'Full name'**
  String get labelFullName;

  /// features/admin/widgets/create_user_dialog.dart:84 (Text)
  ///
  /// In en, this message translates to:
  /// **'Full name (optional)'**
  String get labelFullNameOptional;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:707 (Text)
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get labelGenerate;

  /// features/admin/widgets/mcp_server_dialog.dart:198 (Text)
  ///
  /// In en, this message translates to:
  /// **'HTTP'**
  String get labelHttp;

  /// features/rooms/widgets/room_chat_view.dart:642 (Text); features/rooms/widgets/room_chat_view.dart:803 (Text)
  ///
  /// In en, this message translates to:
  /// **'Invite members'**
  String get labelInviteMembers;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:46 (Text); features/settings/pages/settings_page.dart:195 (Text)
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get labelLight;

  /// features/notifications/pages/notifications_page.dart:39 (Text)
  ///
  /// In en, this message translates to:
  /// **'Mark all read'**
  String get labelMarkAllRead;

  /// features/rooms/widgets/add_agent_dialog.dart:274 (Text); features/rooms/widgets/add_agent_dialog.dart:295 (Text); features/rooms/widgets/add_agent_dialog.dart:318 (Text)
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get labelModel;

  /// features/tools/pages/skills_library_page.dart:259 (Text)
  ///
  /// In en, this message translates to:
  /// **'monospace'**
  String get labelMonospace;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:168 (Text); features/chat/widgets/system_prompt_editor_dialog.dart:328 (Text); features/chat/widgets/style_picker.dart:1547 (Text); and 2 more
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get labelName;

  /// features/scheduled_actions/pages/scheduled_actions_page.dart:42 (Text)
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get labelNew;

  /// features/chat/widgets/mobile_drawer.dart:197 (Text); features/chat/widgets/conversation_list_widget.dart:68 (Text)
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get labelNewChat;

  /// features/settings/widgets/change_password_dialog.dart:90 (Text)
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get labelNewPassword;

  /// features/chat/widgets/mobile_drawer.dart:294 (Text); features/chat/widgets/chat_sidebar.dart:204 (Text)
  ///
  /// In en, this message translates to:
  /// **'New Room'**
  String get labelNewRoom;

  /// features/scheduled_actions/pages/scheduled_actions_page.dart:449 (Text)
  ///
  /// In en, this message translates to:
  /// **'One-off'**
  String get labelOneOff;

  /// features/admin/widgets/create_user_dialog.dart:115 (Text)
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get labelPassword;

  /// features/scheduled_actions/pages/scheduled_actions_page.dart:434 (Text); features/chat/widgets/style_picker.dart:1426 (Text)
  ///
  /// In en, this message translates to:
  /// **'Prompt'**
  String get labelPrompt;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:186 (Text)
  ///
  /// In en, this message translates to:
  /// **'Prompt content'**
  String get labelPromptContent;

  /// features/rooms/widgets/add_agent_dialog.dart:392 (Text)
  ///
  /// In en, this message translates to:
  /// **'Prompt template'**
  String get labelPromptTemplate;

  /// features/microapps/widgets/micro_app_panel.dart:148 (Text); features/microapps/widgets/micro_app_panel.dart:180 (Text)
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get labelPublish;

  /// features/microapps/widgets/micro_app_panel.dart:148 (Text)
  ///
  /// In en, this message translates to:
  /// **'Publishing…'**
  String get labelPublishing;

  /// features/scheduled_actions/pages/scheduled_actions_page.dart:444 (Text)
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get labelRecurring;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:707 (Text)
  ///
  /// In en, this message translates to:
  /// **'Refine'**
  String get labelRefine;

  /// features/chat/widgets/mobile_drawer.dart:165 (Text); features/chat/widgets/chat_sidebar.dart:154 (Text)
  ///
  /// In en, this message translates to:
  /// **'Rooms'**
  String get labelRooms;

  /// features/scheduled_actions/pages/scheduled_actions_page.dart:471 (Text)
  ///
  /// In en, this message translates to:
  /// **'Run at'**
  String get labelRunAt;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:560 (Text)
  ///
  /// In en, this message translates to:
  /// **'Save to library'**
  String get labelSaveToLibrary;

  /// features/friends/pages/friends_page.dart:269 (Text)
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get labelSend;

  /// features/tools/pages/skills_library_page.dart:265 (Text)
  ///
  /// In en, this message translates to:
  /// **'Show schema'**
  String get labelShowSchema;

  /// features/admin/widgets/mcp_server_dialog.dart:202 (Text)
  ///
  /// In en, this message translates to:
  /// **'SSE'**
  String get labelSse;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:533 (Text)
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get labelStop;

  /// features/chat/widgets/style_picker.dart:707 (Text)
  ///
  /// In en, this message translates to:
  /// **'Styles'**
  String get labelStyles;

  /// Header above the built-in/predefined styles section in the style picker.
  ///
  /// In en, this message translates to:
  /// **'Predefined'**
  String get labelPredefinedStyles;

  /// Header above the user-saved styles section in the style picker.
  ///
  /// In en, this message translates to:
  /// **'Your styles'**
  String get labelYourStyles;

  /// features/chat/widgets/style_picker.dart Prompts segment: create a new template.
  ///
  /// In en, this message translates to:
  /// **'New prompt'**
  String get labelNewPrompt;

  /// features/chat/widgets/style_picker.dart Prompts segment empty state.
  ///
  /// In en, this message translates to:
  /// **'No saved prompts yet. Tap \"New prompt\" to create one, or \"Create with AI\" to draft one.'**
  String get messageNoTemplatesYet;

  /// features/admin/widgets/models_tab.dart:165 (Text)
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get labelSync;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:56 (Text); features/settings/pages/settings_page.dart:205 (Text)
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get labelSystem;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:505 (Text)
  ///
  /// In en, this message translates to:
  /// **'System prompt'**
  String get labelSystemPrompt;

  /// features/rooms/widgets/add_agent_dialog.dart:201 (Text)
  ///
  /// In en, this message translates to:
  /// **'System prompt (optional)'**
  String get labelSystemPromptOptional;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:428 (Text)
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get labelTemplate;

  /// features/reports/widgets/submit_report_dialog.dart:124 (Text)
  ///
  /// In en, this message translates to:
  /// **'Title'**
  String get labelTitle;

  /// features/scheduled_actions/pages/scheduled_actions_page.dart:426 (Text)
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get labelTitleOptional;

  /// features/knowledge_base/pages/knowledge_base_page.dart:179 (Text)
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get labelUpload;

  /// features/admin/widgets/mcp_server_dialog.dart:222 (Text)
  ///
  /// In en, this message translates to:
  /// **'URL'**
  String get labelUrl;

  /// features/rooms/widgets/add_agent_dialog.dart:209 (Text)
  ///
  /// In en, this message translates to:
  /// **'When to respond'**
  String get labelWhenToRespond;

  /// features/usage/pages/usage_page.dart:41 (Text)
  ///
  /// In en, this message translates to:
  /// **'Last 12 months'**
  String get last12Months;

  /// features/usage/pages/usage_page.dart:39 (Text)
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get last30Days;

  /// features/usage/pages/usage_page.dart:38 (Text)
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get last7Days;

  /// features/usage/pages/usage_page.dart:40 (Text)
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get last90Days;

  /// features/settings/widgets/update_banner.dart:51 (Text)
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get later;

  /// features/settings/widgets/update_section.dart:48 (Text)
  ///
  /// In en, this message translates to:
  /// **'Latest release: v{releaseVersion}'**
  String latestReleaseVersion(String releaseVersion);

  /// features/rooms/widgets/add_agent_dialog.dart:285 (Text)
  ///
  /// In en, this message translates to:
  /// **'Loading models…'**
  String get loadingModels;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:342 (Text)
  ///
  /// In en, this message translates to:
  /// **'Loading preferences…'**
  String get loadingPreferences;

  /// features/settings/widgets/drawer_sections/tools_picker.dart:86 (Text); features/rooms/widgets/add_agent_dialog.dart:447 (Text)
  ///
  /// In en, this message translates to:
  /// **'Loading tools…'**
  String get loadingTools;

  /// features/rooms/widgets/room_chat_view.dart:616 (Text)
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get members;

  /// features/chat/widgets/chat_message_widget.dart:359 (line)
  ///
  /// In en, this message translates to:
  /// **'{count} saved memories about you informed this reply'**
  String memoriesInformedReply(String count);

  /// features/chat/widgets/memory_toggle_widget.dart:63 (Text)
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get memory;

  /// features/microapps/widgets/micro_app_panel.dart:231 (Text)
  ///
  /// In en, this message translates to:
  /// **'Changes reverted'**
  String get messageChangesReverted;

  /// features/chat/widgets/chat_page.dart:422 (Text)
  ///
  /// In en, this message translates to:
  /// **'Conversation deleted'**
  String get messageConversationDeleted;

  /// features/rooms/widgets/room_chat_view.dart:835 (Text); features/rooms/widgets/create_room_dialog.dart:91 (Text); features/rooms/widgets/add_agent_dialog.dart:167 (Text)
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String messageFailed(String error);

  /// features/settings/widgets/profile_section.dart:249 (Text)
  ///
  /// In en, this message translates to:
  /// **'Failed to remove profile picture'**
  String get messageFailedToRemoveProfilePicture;

  /// features/settings/widgets/profile_section.dart:230 (Text)
  ///
  /// In en, this message translates to:
  /// **'Failed to upload profile picture'**
  String get messageFailedToUploadProfilePicture;

  /// features/settings/widgets/change_password_dialog.dart:54 (Text)
  ///
  /// In en, this message translates to:
  /// **'Password updated'**
  String get messagePasswordUpdated;

  /// features/settings/widgets/profile_section.dart:243 (Text)
  ///
  /// In en, this message translates to:
  /// **'Profile picture removed'**
  String get messageProfilePictureRemoved;

  /// features/settings/widgets/profile_section.dart:224 (Text)
  ///
  /// In en, this message translates to:
  /// **'Profile picture updated'**
  String get messageProfilePictureUpdated;

  /// features/tools/pages/skills_library_page.dart:226 (Text)
  ///
  /// In en, this message translates to:
  /// **'Schema copied'**
  String get messageSchemaCopied;

  /// features/chat/widgets/chat_page.dart:447 (Text)
  ///
  /// In en, this message translates to:
  /// **'Start a conversation first'**
  String get messageStartAConversationFirst;

  /// features/reports/widgets/submit_report_dialog.dart:75 (Text)
  ///
  /// In en, this message translates to:
  /// **'Thanks! Your report was submitted.'**
  String get messageThanksYourReportWasSubmitted;

  /// features/chat/widgets/style_picker.dart:535 (Text)
  ///
  /// In en, this message translates to:
  /// **'This removes the saved style, not any chats.'**
  String get messageThisRemovesTheSavedStyleNot;

  /// features/chat/widgets/style_picker.dart:427 (Text); features/chat/widgets/style_picker.dart:1040 (line)
  ///
  /// In en, this message translates to:
  /// **'{modelId} is not installed'**
  String modelIdIsNotInstalled(String modelId);

  /// features/microapps/widgets/micro_app_panel.dart:43 (Text)
  ///
  /// In en, this message translates to:
  /// **'No app to display'**
  String get noAppToDisplay;

  /// features/usage/pages/usage_page.dart:255 (Text)
  ///
  /// In en, this message translates to:
  /// **'No daily data'**
  String get noDailyData;

  /// features/knowledge_base/pages/knowledge_base_page.dart:199 (Text)
  ///
  /// In en, this message translates to:
  /// **'No documents yet'**
  String get noDocumentsYet;

  /// features/admin/widgets/models_tab.dart:77 (Text)
  ///
  /// In en, this message translates to:
  /// **'No models synced yet'**
  String get noModelsSyncedYet;

  /// features/chat/widgets/style_picker.dart:1448 (Text)
  ///
  /// In en, this message translates to:
  /// **'No template'**
  String get noTemplate;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:435 (Text); features/rooms/widgets/add_agent_dialog.dart:396 (Text)
  ///
  /// In en, this message translates to:
  /// **'— None —'**
  String get none;

  /// features/microapps/widgets/micro_app_panel.dart:260 (Text)
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get ok;

  /// features/rooms/widgets/add_agent_dialog.dart:213 (Text)
  ///
  /// In en, this message translates to:
  /// **'On @mention only'**
  String get onMentionOnly;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:271 (Text)
  ///
  /// In en, this message translates to:
  /// **'Only switch between these — none means any'**
  String get onlySwitchBetweenTheseNoneMeans;

  /// features/notifications/services/push_service.dart:50 (PushService)
  ///
  /// In en, this message translates to:
  /// **'[PushService] foreground message: {title}'**
  String pushServiceForegroundMessage(String title);

  /// features/settings/widgets/update_dialog.dart:91 (Text)
  ///
  /// In en, this message translates to:
  /// **'Release page'**
  String get releasePage;

  /// features/rooms/widgets/room_chat_view.dart:736 (Text); features/friends/pages/friends_page.dart:108 (Text)
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// features/knowledge_base/pages/knowledge_base_page.dart:121 (Text)
  ///
  /// In en, this message translates to:
  /// **'Remove \"{filename}\" from your knowledge base?'**
  String removeDocumentConfirmation(String filename);

  /// features/friends/pages/friends_page.dart:354 (Text)
  ///
  /// In en, this message translates to:
  /// **'Remove friend'**
  String get removeFriend;

  /// features/friends/pages/friends_page.dart:354 (Text)
  ///
  /// In en, this message translates to:
  /// **'remove'**
  String get removeLowercase;

  /// features/rooms/widgets/room_chat_view.dart:725 (Text)
  ///
  /// In en, this message translates to:
  /// **'Remove {userId} from this room?'**
  String removeMemberFromRoomMessage(String userId);

  /// features/tools/pages/skills_library_page.dart:73 (Text); features/usage/pages/usage_page.dart:73 (Text); features/rooms/widgets/add_agent_dialog.dart:309 (Text); and 4 more
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// features/microapps/widgets/micro_app_panel.dart:220 (Text)
  ///
  /// In en, this message translates to:
  /// **'Revert'**
  String get revert;

  /// features/rooms/widgets/add_agent_dialog.dart:221 (Text)
  ///
  /// In en, this message translates to:
  /// **'Round-robin (take turns)'**
  String get roundRobinTakeTurns;

  /// features/memory/pages/memory_page.dart:97 (Text); features/scheduled_actions/pages/scheduled_actions_page.dart:498 (Text); features/settings/widgets/edit_profile_dialog.dart:143 (Text); and 7 more
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// features/chat/widgets/message/edit_button.dart:46 (Text)
  ///
  /// In en, this message translates to:
  /// **'Save & rerun'**
  String get saveAndRerun;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:370 (Text)
  ///
  /// In en, this message translates to:
  /// **'Saved \"{name}\" to your library'**
  String savedToLibrary(String name);

  /// features/chat/widgets/markdown_widget.dart:691 (Text)
  ///
  /// In en, this message translates to:
  /// **'blockMath'**
  String get semanticLabelBlockMath;

  /// features/chat/widgets/markdown_widget.dart:669 (Text)
  ///
  /// In en, this message translates to:
  /// **'inlineMath'**
  String get semanticLabelInlineMath;

  /// features/chat/widgets/mobile_drawer.dart:230 (Muted); features/chat/widgets/conversation_list_widget.dart:297 (Muted); features/rooms/widgets/rooms_list_view.dart:204 (Muted)
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get semanticLabelMuted;

  /// features/chat/widgets/tool_bubble_widget.dart:96 (line)
  ///
  /// In en, this message translates to:
  /// **'tool'**
  String get semanticLabelTool;

  /// features/settings/widgets/settings_drawer.dart:43 (Text); features/settings/pages/settings_page.dart:92 (AppBar)
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// features/friends/widgets/share_with_friend_dialog.dart:25 (Text)
  ///
  /// In en, this message translates to:
  /// **'Share \"{itemName}\"'**
  String shareItemTitle(String itemName);

  /// features/chat/widgets/style_picker.dart:1079 (Text)
  ///
  /// In en, this message translates to:
  /// **'Share with a friend…'**
  String get shareWithAFriend;

  /// features/friends/pages/friends_page.dart:370 (Text)
  ///
  /// In en, this message translates to:
  /// **'from {senderEmail}'**
  String sharedItemFromSender(String senderEmail);

  /// features/friends/pages/friends_page.dart:369 (Text)
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" ({noun})'**
  String sharedItemTitle(String name, String noun);

  /// features/settings/widgets/drawer_sections/conversation_section.dart:158 (Text)
  ///
  /// In en, this message translates to:
  /// **'Start a conversation to set a prompt'**
  String get startAConversationToSetA;

  /// features/reports/widgets/submit_report_dialog.dart:169 (Text)
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// features/admin/pages/admin_page.dart:42 (Tab)
  ///
  /// In en, this message translates to:
  /// **'MCP Servers'**
  String get tabMcpServers;

  /// features/admin/pages/admin_page.dart:41 (Tab)
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get tabModels;

  /// features/admin/pages/admin_page.dart:43 (Tab)
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get tabReports;

  /// features/admin/pages/admin_page.dart:40 (Tab)
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get tabUsers;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:406 (Text)
  ///
  /// In en, this message translates to:
  /// **'Templates'**
  String get templates;

  /// features/admin/widgets/mcp_servers_tab.dart:101 (Text)
  ///
  /// In en, this message translates to:
  /// **'Testing {name}…'**
  String testingServer(String name);

  /// features/chat/widgets/style_picker.dart:1340 (Text); features/rooms/widgets/add_agent_dialog.dart:364 (Text)
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get thinking;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:367 (Text); features/settings/pages/settings_page.dart:479 (Text)
  ///
  /// In en, this message translates to:
  /// **'Account and system notifications'**
  String get titleAccountAndSystemNotifications;

  /// features/settings/widgets/profile_section.dart:78 (Text); features/settings/widgets/drawer_sections/pages_section.dart:80 (Text); features/admin/widgets/users_tab.dart:119 (Text); and 1 more
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get titleAdmin;

  /// features/admin/widgets/create_user_dialog.dart:144 (Text)
  ///
  /// In en, this message translates to:
  /// **'Admin privileges'**
  String get titleAdminPrivileges;

  /// features/settings/widgets/drawer_sections/tools_picker.dart:119 (Text); features/rooms/widgets/add_agent_dialog.dart:461 (Text)
  ///
  /// In en, this message translates to:
  /// **'All tools'**
  String get titleAllTools;

  /// features/settings/widgets/settings_drawer.dart:82 (GroupHeader)
  ///
  /// In en, this message translates to:
  /// **'App settings'**
  String get titleAppSettings;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:39 (SectionHeader)
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get titleAppearance;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:214 (Text); features/settings/pages/settings_page.dart:403 (Text)
  ///
  /// In en, this message translates to:
  /// **'Auto-play responses'**
  String get titleAutoPlayResponses;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:221 (Text); features/settings/pages/settings_page.dart:410 (Text)
  ///
  /// In en, this message translates to:
  /// **'Auto-send after transcription'**
  String get titleAutoSendAfterTranscription;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:257 (Text)
  ///
  /// In en, this message translates to:
  /// **'Automatic language switching'**
  String get titleAutomaticLanguageSwitching;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:222 (Text)
  ///
  /// In en, this message translates to:
  /// **'Automatically send when voice input finishes'**
  String get titleAutomaticallySendWhenVoiceInputFinishes;

  /// features/friends/pages/friends_page.dart:64 (Text)
  ///
  /// In en, this message translates to:
  /// **'Block User'**
  String get titleBlockUser;

  /// features/settings/widgets/drawer_sections/pages_section.dart:41 (Text)
  ///
  /// In en, this message translates to:
  /// **'Browse available MCP tools'**
  String get titleBrowseAvailableMcpTools;

  /// features/settings/widgets/change_password_dialog.dart:60 (Text); features/settings/widgets/profile_section.dart:101 (Text)
  ///
  /// In en, this message translates to:
  /// **'Change password'**
  String get titleChangePassword;

  /// features/settings/widgets/drawer_sections/pages_section.dart:62 (Text); features/settings/pages/settings_page.dart:344 (Text)
  ///
  /// In en, this message translates to:
  /// **'Charts by model, conversation, day'**
  String get titleChartsByModelConversationDay;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:80 (SectionHeader)
  ///
  /// In en, this message translates to:
  /// **'Chat'**
  String get titleChat;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:348 (Text); features/settings/pages/settings_page.dart:460 (Text)
  ///
  /// In en, this message translates to:
  /// **'Chat responses'**
  String get titleChatResponses;

  /// features/settings/widgets/profile_section.dart:133 (Text)
  ///
  /// In en, this message translates to:
  /// **'Choose photo'**
  String get titleChoosePhoto;

  /// features/settings/widgets/drawer_sections/conversation_section.dart:117 (Conversation); features/chat/widgets/system_prompt_banner.dart:51 (Conversation)
  ///
  /// In en, this message translates to:
  /// **'Conversation system prompt'**
  String get titleConversationSystemPrompt;

  /// features/memory/pages/memory_page.dart:37 (Text)
  ///
  /// In en, this message translates to:
  /// **'Create Memory'**
  String get titleCreateMemory;

  /// features/admin/widgets/create_user_dialog.dart:69 (Text)
  ///
  /// In en, this message translates to:
  /// **'Create user'**
  String get titleCreateUser;

  /// features/settings/widgets/update_section.dart:24 (Text)
  ///
  /// In en, this message translates to:
  /// **'Current version'**
  String get titleCurrentVersion;

  /// features/settings/pages/settings_page.dart:288 (Text)
  ///
  /// In en, this message translates to:
  /// **'Default model'**
  String get titleDefaultModel;

  /// features/rooms/widgets/room_chat_view.dart:761 (Text)
  ///
  /// In en, this message translates to:
  /// **'Delete agent?'**
  String get titleDeleteAgent;

  /// features/chat/widgets/conversation_list_widget.dart:157 (Text)
  ///
  /// In en, this message translates to:
  /// **'Delete Conversation?'**
  String get titleDeleteConversation;

  /// features/knowledge_base/pages/knowledge_base_page.dart:120 (Text)
  ///
  /// In en, this message translates to:
  /// **'Delete document'**
  String get titleDeleteDocument;

  /// features/admin/widgets/mcp_servers_tab.dart:72 (Text)
  ///
  /// In en, this message translates to:
  /// **'Delete MCP server?'**
  String get titleDeleteMcpServer;

  /// features/memory/pages/memory_page.dart:108 (Text)
  ///
  /// In en, this message translates to:
  /// **'Delete Memory'**
  String get titleDeleteMemory;

  /// features/rooms/widgets/rooms_list_view.dart:97 (Text)
  ///
  /// In en, this message translates to:
  /// **'Delete room?'**
  String get titleDeleteRoom;

  /// features/scheduled_actions/pages/scheduled_actions_page.dart:272 (Text)
  ///
  /// In en, this message translates to:
  /// **'Delete scheduled action'**
  String get titleDeleteScheduledAction;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:83 (Text); features/settings/pages/settings_page.dart:237 (Text)
  ///
  /// In en, this message translates to:
  /// **'Display token counts and response time'**
  String get titleDisplayTokenCountsAndResponseTime;

  /// features/admin/widgets/mcp_server_dialog.dart:159 (Text)
  ///
  /// In en, this message translates to:
  /// **'Edit MCP server'**
  String get titleEditMcpServer;

  /// features/memory/pages/memory_page.dart:72 (Text)
  ///
  /// In en, this message translates to:
  /// **'Edit Memory'**
  String get titleEditMemory;

  /// features/chat/widgets/message/edit_button.dart:28 (Text)
  ///
  /// In en, this message translates to:
  /// **'Edit message'**
  String get titleEditMessage;

  /// features/settings/widgets/profile_section.dart:88 (Text); features/settings/widgets/edit_profile_dialog.dart:87 (Text)
  ///
  /// In en, this message translates to:
  /// **'Edit profile'**
  String get titleEditProfile;

  /// Dialog title for editing a saved style.
  ///
  /// In en, this message translates to:
  /// **'Edit style'**
  String get titleEditStyle;

  /// features/admin/widgets/mcp_server_dialog.dart:279 (Text)
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get titleEnabled;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:375 (Text); features/settings/pages/settings_page.dart:487 (Text)
  ///
  /// In en, this message translates to:
  /// **'Friend requests and accepts'**
  String get titleFriendRequestsAndAccepts;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:374 (Text); features/settings/pages/settings_page.dart:486 (Text)
  ///
  /// In en, this message translates to:
  /// **'Friend updates'**
  String get titleFriendUpdates;

  /// features/settings/widgets/drawer_sections/pages_section.dart:47 (Text); features/friends/pages/friends_page.dart:126 (Text)
  ///
  /// In en, this message translates to:
  /// **'Friends'**
  String get titleFriends;

  /// features/settings/widgets/drawer_sections/conversation_section.dart:175 (Text)
  ///
  /// In en, this message translates to:
  /// **'Global default'**
  String get titleGlobalDefault;

  /// features/settings/widgets/drawer_sections/conversation_section.dart:132 (Global); features/settings/pages/settings_page.dart:272 (Global); features/settings/pages/settings_page.dart:330 (Text)
  ///
  /// In en, this message translates to:
  /// **'Global default system prompt'**
  String get titleGlobalDefaultSystemPrompt;

  /// features/settings/widgets/drawer_sections/pages_section.dart:33 (Text)
  ///
  /// In en, this message translates to:
  /// **'Knowledge base'**
  String get titleKnowledgeBase;

  /// features/knowledge_base/pages/knowledge_base_page.dart:145 (Text)
  ///
  /// In en, this message translates to:
  /// **'Knowledge Base'**
  String get titleKnowledgeBasePage;

  /// features/settings/widgets/drawer_sections/conversation_section.dart:57 (Text)
  ///
  /// In en, this message translates to:
  /// **'LLM Model'**
  String get titleLlmModel;

  /// features/memory/pages/memory_page.dart:135 (Text); features/settings/widgets/drawer_sections/pages_section.dart:26 (Text)
  ///
  /// In en, this message translates to:
  /// **'Memories'**
  String get titleMemories;

  /// features/settings/widgets/drawer_sections/conversation_section.dart:239 (Text)
  ///
  /// In en, this message translates to:
  /// **'Memory & knowledge base'**
  String get titleMemoryKnowledgeBase;

  /// features/settings/widgets/drawer_sections/conversation_section.dart:55 (SectionHeader)
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get titleModel;

  /// features/rooms/widgets/add_agent_dialog.dart:235 (Text)
  ///
  /// In en, this message translates to:
  /// **'Moderator'**
  String get titleModerator;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:267 (Text)
  ///
  /// In en, this message translates to:
  /// **'My languages'**
  String get titleMyLanguages;

  /// features/admin/widgets/mcp_server_dialog.dart:159 (Text)
  ///
  /// In en, this message translates to:
  /// **'New MCP server'**
  String get titleNewMcpServer;

  /// features/rooms/widgets/create_room_dialog.dart:26 (Text)
  ///
  /// In en, this message translates to:
  /// **'New room'**
  String get titleNewRoom;

  /// features/settings/widgets/settings_drawer.dart:173 (Text); features/settings/widgets/drawer_sections/app_settings_section.dart:329 (Notifications); features/notifications/pages/notifications_page.dart:31 (Text)
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get titleNotifications;

  /// features/settings/widgets/settings_drawer.dart:61 (Text)
  ///
  /// In en, this message translates to:
  /// **'Open full settings'**
  String get titleOpenFullSettings;

  /// features/settings/widgets/drawer_sections/conversation_section.dart:118 (Overrides); features/chat/widgets/system_prompt_banner.dart:52 (Overrides)
  ///
  /// In en, this message translates to:
  /// **'Overrides your global default for this conversation only.'**
  String get titleOverridesYourGlobalDefaultForThis;

  /// features/settings/widgets/settings_drawer.dart:76 (GroupHeader)
  ///
  /// In en, this message translates to:
  /// **'Pages'**
  String get titlePages;

  /// features/settings/widgets/drawer_sections/conversation_section.dart:213 (SectionHeader)
  ///
  /// In en, this message translates to:
  /// **'Personal context'**
  String get titlePersonalContext;

  /// features/settings/widgets/settings_drawer.dart:62 (Text)
  ///
  /// In en, this message translates to:
  /// **'Profile, appearance, models, and more'**
  String get titleProfileAppearanceModelsAndMore;

  /// features/microapps/widgets/micro_app_panel.dart:159 (Text)
  ///
  /// In en, this message translates to:
  /// **'Publish changes'**
  String get titlePublishChanges;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:215 (Text); features/settings/pages/settings_page.dart:404 (Text)
  ///
  /// In en, this message translates to:
  /// **'Read aloud new assistant messages'**
  String get titleReadAloudNewAssistantMessages;

  /// features/chat/widgets/remember_this_button.dart:65 (Text)
  ///
  /// In en, this message translates to:
  /// **'Remember This'**
  String get titleRememberThis;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:358 (Text); features/settings/pages/settings_page.dart:470 (Text)
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get titleReminders;

  /// features/settings/widgets/drawer_sections/pages_section.dart:55 (Text)
  ///
  /// In en, this message translates to:
  /// **'Reminders and recurring prompts'**
  String get titleRemindersAndRecurringPrompts;

  /// features/friends/pages/friends_page.dart:92 (Text)
  ///
  /// In en, this message translates to:
  /// **'Remove Friend'**
  String get titleRemoveFriend;

  /// features/rooms/widgets/room_chat_view.dart:724 (Text)
  ///
  /// In en, this message translates to:
  /// **'Remove member?'**
  String get titleRemoveMember;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:258 (Text)
  ///
  /// In en, this message translates to:
  /// **'Reply in the language you speak (Talk Mode)'**
  String get titleReplyInTheLanguageYouSpeak;

  /// features/settings/widgets/drawer_sections/pages_section.dart:69 (Text)
  ///
  /// In en, this message translates to:
  /// **'Report a bug or idea'**
  String get titleReportABugOrIdea;

  /// features/reports/widgets/submit_report_dialog.dart:93 (Text)
  ///
  /// In en, this message translates to:
  /// **'Report a bug or request a feature'**
  String get titleReportABugOrRequestA;

  /// features/friends/pages/friends_page.dart:328 (Text)
  ///
  /// In en, this message translates to:
  /// **'request pending'**
  String get titleRequestPending;

  /// features/microapps/widgets/micro_app_panel.dart:209 (Text)
  ///
  /// In en, this message translates to:
  /// **'Revert all changes?'**
  String get titleRevertAllChanges;

  /// features/chat/widgets/system_prompt_editor_dialog.dart:321 (Text)
  ///
  /// In en, this message translates to:
  /// **'Save prompt to library'**
  String get titleSavePromptToLibrary;

  /// features/chat/widgets/style_picker.dart:1535 (Text)
  ///
  /// In en, this message translates to:
  /// **'Save style'**
  String get titleSaveStyle;

  /// features/settings/pages/settings_page.dart:428 (Text)
  ///
  /// In en, this message translates to:
  /// **'Saved memories'**
  String get titleSavedMemories;

  /// features/scheduled_actions/pages/scheduled_actions_page.dart:30 (Text); features/settings/widgets/drawer_sections/pages_section.dart:54 (Text)
  ///
  /// In en, this message translates to:
  /// **'Scheduled actions'**
  String get titleScheduledActions;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:359 (Text); features/settings/pages/settings_page.dart:471 (Text)
  ///
  /// In en, this message translates to:
  /// **'Scheduled reminders and check-ins'**
  String get titleScheduledRemindersAndCheckIns;

  /// features/settings/widgets/drawer_sections/pages_section.dart:70 (Text)
  ///
  /// In en, this message translates to:
  /// **'Send feedback straight to the admins'**
  String get titleSendFeedbackStraightToTheAdmins;

  /// features/settings/widgets/drawer_sections/pages_section.dart:48 (Text)
  ///
  /// In en, this message translates to:
  /// **'Send requests and manage your friends'**
  String get titleSendRequestsAndManageYourFriends;

  /// features/settings/widgets/location_section.dart:152 (Text)
  ///
  /// In en, this message translates to:
  /// **'Set your location'**
  String get titleSetYourLocation;

  /// features/settings/widgets/location_section.dart:50 (Text)
  ///
  /// In en, this message translates to:
  /// **'Share my location'**
  String get titleShareCoarseLocation;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:82 (Text); features/settings/pages/settings_page.dart:236 (Text)
  ///
  /// In en, this message translates to:
  /// **'Show message metadata'**
  String get titleShowMessageMetadata;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:89 (Text); features/settings/pages/settings_page.dart:243 (Text)
  ///
  /// In en, this message translates to:
  /// **'Show system prompt in thread'**
  String get titleShowSystemPromptInThread;

  /// features/settings/widgets/profile_section.dart:112 (Text)
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get titleSignOut;

  /// features/tools/pages/skills_library_page.dart:109 (Text); features/settings/widgets/drawer_sections/pages_section.dart:40 (Text)
  ///
  /// In en, this message translates to:
  /// **'Skills library'**
  String get titleSkillsLibrary;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:197 (Text); features/settings/pages/settings_page.dart:390 (Text)
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get titleSpeed;

  /// features/settings/widgets/drawer_sections/tools_picker.dart:30 (Text)
  ///
  /// In en, this message translates to:
  /// **'Start a conversation to pick tools'**
  String get titleStartAConversationToPickTools;

  /// features/settings/widgets/drawer_sections/conversation_section.dart:240 (Text)
  ///
  /// In en, this message translates to:
  /// **'Start a conversation to toggle injection'**
  String get titleStartAConversationToToggleInjection;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:366 (Text); features/settings/pages/settings_page.dart:478 (Text)
  ///
  /// In en, this message translates to:
  /// **'System alerts'**
  String get titleSystemAlerts;

  /// features/settings/widgets/drawer_sections/conversation_section.dart:151 (System)
  ///
  /// In en, this message translates to:
  /// **'System Prompt'**
  String get titleSystemPrompt;

  /// features/settings/widgets/profile_section.dart:142 (Text)
  ///
  /// In en, this message translates to:
  /// **'Take photo'**
  String get titleTakePhoto;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:231 (Text)
  ///
  /// In en, this message translates to:
  /// **'Talk over the AI to interrupt (Talk Mode)'**
  String get titleTalkOverTheAiToInterrupt;

  /// features/settings/widgets/location_section.dart:66 (Text)
  ///
  /// In en, this message translates to:
  /// **'Tap to update or correct'**
  String get titleTapToUpdateOrCorrect;

  /// features/settings/widgets/settings_drawer.dart:79 (GroupHeader); features/settings/widgets/drawer_sections/conversation_section.dart:156 (Text)
  ///
  /// In en, this message translates to:
  /// **'This conversation'**
  String get titleThisConversation;

  /// features/settings/widgets/drawer_sections/pages_section.dart:61 (Text); features/settings/pages/settings_page.dart:343 (Text); features/usage/pages/usage_page.dart:30 (Text)
  ///
  /// In en, this message translates to:
  /// **'Token usage'**
  String get titleTokenUsage;

  /// features/settings/widgets/drawer_sections/tools_picker.dart:27 (SectionHeader); features/settings/widgets/drawer_sections/tools_picker.dart:29 (Text); features/settings/widgets/drawer_sections/tools_picker.dart:74 (SectionHeader); and 1 more
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get titleTools;

  /// features/settings/widgets/profile_section.dart:89 (Text)
  ///
  /// In en, this message translates to:
  /// **'Update name and email'**
  String get titleUpdateNameAndEmail;

  /// features/settings/widgets/drawer_sections/pages_section.dart:34 (Text)
  ///
  /// In en, this message translates to:
  /// **'Upload documents for retrieval across chats'**
  String get titleUploadDocumentsForRetrievalAcrossChats;

  /// features/chat/widgets/style_picker.dart:1557 (Text)
  ///
  /// In en, this message translates to:
  /// **'Use for new chats'**
  String get titleUseForNewChats;

  /// features/settings/widgets/drawer_sections/conversation_section.dart:227 (Text)
  ///
  /// In en, this message translates to:
  /// **'Use knowledge base'**
  String get titleUseKnowledgeBase;

  /// features/settings/widgets/drawer_sections/conversation_section.dart:216 (Text)
  ///
  /// In en, this message translates to:
  /// **'Use memory'**
  String get titleUseMemory;

  /// features/settings/widgets/drawer_sections/pages_section.dart:81 (Text)
  ///
  /// In en, this message translates to:
  /// **'Users, models, MCP servers, reports'**
  String get titleUsersModelsMcpServersReports;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:162 (SectionHeader); features/settings/widgets/drawer_sections/app_settings_section.dart:165 (Text); features/settings/pages/settings_page.dart:360 (Text)
  ///
  /// In en, this message translates to:
  /// **'Voice'**
  String get titleVoice;

  /// features/settings/widgets/drawer_sections/app_settings_section.dart:230 (Text)
  ///
  /// In en, this message translates to:
  /// **'Voice interruption'**
  String get titleVoiceInterruption;

  /// features/settings/widgets/drawer_sections/pages_section.dart:27 (Text)
  ///
  /// In en, this message translates to:
  /// **'What the assistant has learned about you'**
  String get titleWhatTheAssistantHasLearnedAbout;

  /// features/rooms/widgets/room_message_bubble.dart:348 (You); features/admin/widgets/users_tab.dart:139 (Text)
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get titleYou;

  /// features/admin/widgets/mcp_server_dialog.dart:191 (Text)
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get transport;

  /// features/rooms/widgets/room_chat_view.dart:460 (Text)
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// features/settings/pages/settings_page.dart:399 (Text)
  ///
  /// In en, this message translates to:
  /// **'{speed}x'**
  String ttsSpeedValue(String speed);

  /// features/friends/pages/friends_page.dart:409 (Text)
  ///
  /// In en, this message translates to:
  /// **'Unblock'**
  String get unblock;

  /// features/chat/widgets/mermaid_diagram.dart:193 (Unexpected)
  ///
  /// In en, this message translates to:
  /// **'Unexpected error'**
  String get unexpectedError;

  /// features/settings/widgets/update_banner.dart:64 (Text)
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get update;

  /// features/settings/widgets/update_dialog.dart:33 (Text)
  ///
  /// In en, this message translates to:
  /// **'Update to v{releaseVersion}'**
  String updateToVersion(String releaseVersion);

  /// features/chat/widgets/style_picker.dart:1016 (Used)
  ///
  /// In en, this message translates to:
  /// **'Used for new chats'**
  String get usedForNewChats;

  /// features/admin/widgets/users_tab.dart:45 (Text)
  ///
  /// In en, this message translates to:
  /// **'User {email} created'**
  String userCreatedMessage(String email);

  /// features/settings/widgets/change_password_dialog.dart:83 (Required)
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get validationErrorRequired;

  /// features/friends/pages/friends_page.dart:296 (Text)
  ///
  /// In en, this message translates to:
  /// **'wants to be your friend'**
  String get wantsToBeYourFriend;

  /// Tooltip for password visibility toggle (show).
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// Tooltip for password visibility toggle (hide).
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// Validator message when password field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your password'**
  String get validatorEnterPassword;

  /// Validator message when password is too short.
  ///
  /// In en, this message translates to:
  /// **'Password must be at least {length} characters'**
  String validatorPasswordMinLength(String length);

  /// Validator message when email field is empty.
  ///
  /// In en, this message translates to:
  /// **'Enter your email'**
  String get validatorEnterEmail;

  /// Validator message when email is invalid.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email'**
  String get validatorEnterValidEmail;

  /// Validator message for create-user email field.
  ///
  /// In en, this message translates to:
  /// **'Enter an email'**
  String get validatorEnterAnEmail;

  /// Validator message when MCP server name is empty.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get validatorNameRequired;

  /// Validator message when URL is empty for HTTP/SSE.
  ///
  /// In en, this message translates to:
  /// **'URL is required for HTTP/SSE transports'**
  String get validatorUrlRequired;

  /// Validator message when command is empty for stdio.
  ///
  /// In en, this message translates to:
  /// **'Command is required for stdio transport'**
  String get validatorCommandRequired;

  /// Tooltip for refresh icon button.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get tooltipRefresh;

  /// Generic more-options tooltip.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get tooltipMore;

  /// Tooltip for report status menu.
  ///
  /// In en, this message translates to:
  /// **'Set status'**
  String get tooltipSetStatus;

  /// Tooltip for style card popup menu.
  ///
  /// In en, this message translates to:
  /// **'Style options'**
  String get tooltipStyleOptions;

  /// Tooltip for MCP server test button.
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get tooltipTestConnection;

  /// Tooltip for edit button.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get tooltipEdit;

  /// Tooltip for delete button requiring long press.
  ///
  /// In en, this message translates to:
  /// **'Delete (long-press)'**
  String get tooltipDeleteLongPress;

  /// Tooltip for cancel style edit button.
  ///
  /// In en, this message translates to:
  /// **'Stop editing'**
  String get tooltipStopEditing;

  /// Tooltip for style picker close button.
  ///
  /// In en, this message translates to:
  /// **'Close panel'**
  String get tooltipClosePanel;

  /// Tooltip for new scheduled action FAB.
  ///
  /// In en, this message translates to:
  /// **'New'**
  String get tooltipNew;

  /// Tooltip for settings close button.
  ///
  /// In en, this message translates to:
  /// **'Close settings'**
  String get tooltipCloseSettings;

  /// Tooltip for friend tile popup menu.
  ///
  /// In en, this message translates to:
  /// **'Friend actions'**
  String get tooltipFriendActions;

  /// Tooltip for outgoing request cancel button.
  ///
  /// In en, this message translates to:
  /// **'Cancel request'**
  String get tooltipCancelRequest;

  /// Tooltip for accept share button.
  ///
  /// In en, this message translates to:
  /// **'Accept share'**
  String get tooltipAcceptShare;

  /// Tooltip for decline share button.
  ///
  /// In en, this message translates to:
  /// **'Decline share'**
  String get tooltipDeclineShare;

  /// Tooltip for accept friend request button.
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get tooltipAccept;

  /// Tooltip for decline friend request button.
  ///
  /// In en, this message translates to:
  /// **'Decline'**
  String get tooltipDecline;

  /// Label for thinking level Off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get labelOff;

  /// Label for thinking level Low.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get labelLow;

  /// Label for thinking level Medium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get labelMedium;

  /// Label for thinking level High.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get labelHigh;

  /// Lowercase label for thinking level Auto.
  ///
  /// In en, this message translates to:
  /// **'auto'**
  String get labelThinkingAuto;

  /// Placeholder for empty-name monogram.
  ///
  /// In en, this message translates to:
  /// **'?'**
  String get monogramPlaceholder;

  /// New model badge in admin models tab.
  ///
  /// In en, this message translates to:
  /// **'NEW'**
  String get labelNewBadge;

  /// Empty state for admin reports tab without filter.
  ///
  /// In en, this message translates to:
  /// **'No reports yet'**
  String get messageNoReportsYet;

  /// Empty state for admin reports tab with status filter.
  ///
  /// In en, this message translates to:
  /// **'No {status} reports'**
  String messageNoReportsWithStatus(String status);

  /// Empty state for MCP servers tab.
  ///
  /// In en, this message translates to:
  /// **'No MCP servers configured'**
  String get messageNoMcpServersConfigured;

  /// Hint for adding MCP server.
  ///
  /// In en, this message translates to:
  /// **'Use the + button to add one.'**
  String get messageUsePlusButtonToAddOne;

  /// Hint for syncing models in admin.
  ///
  /// In en, this message translates to:
  /// **'Tap the sync button to discover models from the provider.'**
  String get messageTapSyncToDiscoverModels;

  /// Tooltip for unmute in Talk Mode.
  ///
  /// In en, this message translates to:
  /// **'Unmute'**
  String get messageUnmute;

  /// Tooltip for mute in Talk Mode.
  ///
  /// In en, this message translates to:
  /// **'Mute'**
  String get messageMute;

  /// Tooltip for hang-up in Talk Mode.
  ///
  /// In en, this message translates to:
  /// **'End call'**
  String get messageEndCall;

  /// Talk Mode idle status hint.
  ///
  /// In en, this message translates to:
  /// **'Tap to start'**
  String get messageTapToStart;

  /// Talk Mode listening status.
  ///
  /// In en, this message translates to:
  /// **'Listening…'**
  String get messageListening;

  /// Talk Mode transcribing status.
  ///
  /// In en, this message translates to:
  /// **'Transcribing…'**
  String get messageTranscribing;

  /// Talk Mode thinking status.
  ///
  /// In en, this message translates to:
  /// **'Thinking…'**
  String get messageThinking;

  /// Talk Mode speaking without barge-in.
  ///
  /// In en, this message translates to:
  /// **'Speaking… tap to interrupt'**
  String get messageSpeakingTapToInterrupt;

  /// Talk Mode speaking with barge-in.
  ///
  /// In en, this message translates to:
  /// **'Speaking… talk or tap to interrupt'**
  String get messageSpeakingTalkOrTapToInterrupt;

  /// Talk Mode retry hint.
  ///
  /// In en, this message translates to:
  /// **'Tap the circle to retry'**
  String get messageTapCircleToRetry;

  /// Talk Mode language menu Auto item.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get messageAuto;

  /// Talk Mode language tooltip when auto.
  ///
  /// In en, this message translates to:
  /// **'Reply language: Auto'**
  String get messageReplyLanguageAuto;

  /// Talk Mode language tooltip when pinned.
  ///
  /// In en, this message translates to:
  /// **'Reply language: {language}'**
  String messageReplyLanguageNamed(String language);

  /// Report status update failure snackbar.
  ///
  /// In en, this message translates to:
  /// **'Could not update: {error}'**
  String labelCouldNotUpdateWithError(String error);

  /// MCP server test snackbar.
  ///
  /// In en, this message translates to:
  /// **'Testing {name}…'**
  String messageTestingServer(String name);

  /// MCP server test success snackbar.
  ///
  /// In en, this message translates to:
  /// **'OK: {count} tools available'**
  String messageTestOkToolsAvailable(int count);

  /// MCP server test failure snackbar.
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String messageTestFailed(String error);

  /// Fallback when test result error is missing.
  ///
  /// In en, this message translates to:
  /// **'unknown error'**
  String get messageUnknownError;

  /// Snackbar while models are syncing.
  ///
  /// In en, this message translates to:
  /// **'Syncing models from provider…'**
  String get messageSyncingModels;

  /// Snackbar after model sync completes.
  ///
  /// In en, this message translates to:
  /// **'{count} models synced'**
  String messageModelsSyncedCount(int count);

  /// Snackbar after admin creates user.
  ///
  /// In en, this message translates to:
  /// **'User {email} created'**
  String messageUserCreated(String email);

  /// Report status label open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get labelOpen;

  /// Report status label in_progress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get labelInProgress;

  /// Report status label closed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get labelClosed;

  /// Report status filter value open (lowercase).
  ///
  /// In en, this message translates to:
  /// **'open'**
  String get statusOpen;

  /// Report status filter value in_progress (lowercase).
  ///
  /// In en, this message translates to:
  /// **'in_progress'**
  String get statusInProgress;

  /// Report status filter value closed (lowercase).
  ///
  /// In en, this message translates to:
  /// **'closed'**
  String get statusClosed;

  /// Empty state for open reports filter.
  ///
  /// In en, this message translates to:
  /// **'No open reports'**
  String get messageOpenReports;

  /// Empty state for in_progress reports filter.
  ///
  /// In en, this message translates to:
  /// **'No in progress reports'**
  String get messageInProgressReports;

  /// Empty state for closed reports filter.
  ///
  /// In en, this message translates to:
  /// **'No closed reports'**
  String get messageClosedReports;

  /// Capability badge label.
  ///
  /// In en, this message translates to:
  /// **'Vision'**
  String get labelVision;

  /// Capability badge label.
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get labelTools;

  /// Capability badge label.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get labelThinking;

  /// Tooltip for unknown vision capability.
  ///
  /// In en, this message translates to:
  /// **'Vision unknown for this model'**
  String get tooltipVisionUnknown;

  /// Tooltip for unknown tools capability.
  ///
  /// In en, this message translates to:
  /// **'Tools unknown for this model'**
  String get tooltipToolsUnknown;

  /// Tooltip for unknown thinking capability.
  ///
  /// In en, this message translates to:
  /// **'Thinking unknown for this model'**
  String get tooltipThinkingUnknown;

  /// Barge-in sensitivity level.
  ///
  /// In en, this message translates to:
  /// **'Low sensitivity'**
  String get labelLowSensitivity;

  /// Barge-in sensitivity level.
  ///
  /// In en, this message translates to:
  /// **'High sensitivity'**
  String get labelHighSensitivity;

  /// Barge-in sensitivity Off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get labelBargeInOff;

  /// Usage page dropdown by model.
  ///
  /// In en, this message translates to:
  /// **'By model'**
  String get labelByModel;

  /// Usage page dropdown by day.
  ///
  /// In en, this message translates to:
  /// **'By day'**
  String get labelByDay;

  /// Usage page dropdown by conversation.
  ///
  /// In en, this message translates to:
  /// **'By conversation'**
  String get labelByConversation;

  /// Usage page tokens label.
  ///
  /// In en, this message translates to:
  /// **'Tokens'**
  String get labelTokens;

  /// Usage page messages label.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get labelMessages;

  /// Usage page empty chart message.
  ///
  /// In en, this message translates to:
  /// **'No data for this period'**
  String get messageNoDataForPeriod;

  /// Usage page section by model.
  ///
  /// In en, this message translates to:
  /// **'By model'**
  String get titleUsageByModel;

  /// Usage page section by day.
  ///
  /// In en, this message translates to:
  /// **'By day'**
  String get titleUsageByDay;

  /// Usage page section by conversation.
  ///
  /// In en, this message translates to:
  /// **'By conversation'**
  String get titleUsageByConversation;

  /// Generic enabled label.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get labelEnabled;

  /// MCP transport stdio.
  ///
  /// In en, this message translates to:
  /// **'stdio'**
  String get labelStdio;

  /// MCP server command label.
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get labelCommand;

  /// Subtitle for admin page in settings drawer.
  ///
  /// In en, this message translates to:
  /// **'Users, models, MCP servers, reports'**
  String get messageAdminPanelSubtitle;

  /// Create user admin privileges subtitle.
  ///
  /// In en, this message translates to:
  /// **'Allow this user to manage users and MCP servers'**
  String get messageAllowAdminPrivileges;

  /// MCP server enabled switch subtitle.
  ///
  /// In en, this message translates to:
  /// **'Disabled servers are ignored by the agent'**
  String get messageDisabledServersIgnored;

  /// Settings page section label.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get titleProfile;

  /// Settings page section label.
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get titleModels;

  /// Settings page section label.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get titleMemory;

  /// Settings page section label.
  ///
  /// In en, this message translates to:
  /// **'Software update'**
  String get titleSoftwareUpdate;

  /// Subtitle when no default model is selected.
  ///
  /// In en, this message translates to:
  /// **'Server fallback (usually {model})'**
  String messageServerFallback(String model);

  /// Global default prompt subtitle when empty.
  ///
  /// In en, this message translates to:
  /// **'Not set — using built-in defaults'**
  String get messageNotSetUsingDefaults;

  /// Hint text in memory settings section.
  ///
  /// In en, this message translates to:
  /// **'Memories are managed from the chat screen via the memory page. Open the chat to review, edit, or delete them.'**
  String get messageSavedMemoriesHint;

  /// Empty state hint in style picker.
  ///
  /// In en, this message translates to:
  /// **'No saved styles yet. Compose a model, thinking level, and prompt in Customize, then save the combination to switch in one tap.'**
  String get messageNoSavedStylesHint;

  /// Button label when editing a style.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get labelSaveChanges;

  /// Snackbar when applying a style with missing model.
  ///
  /// In en, this message translates to:
  /// **'{modelId} is not installed'**
  String messageStyleModelNotInstalled(String modelId);

  /// Thinking control unsupported hint.
  ///
  /// In en, this message translates to:
  /// **'Not supported by this model'**
  String get messageNotSupportedByThisModel;

  /// Empty state when no models at all.
  ///
  /// In en, this message translates to:
  /// **'No models available.'**
  String get messageNoModelsAvailable;

  /// Hint under template picker when conversation has custom prompt.
  ///
  /// In en, this message translates to:
  /// **'This conversation has a custom prompt. Picking a template replaces it.'**
  String get messageCustomPromptReplacesTemplate;

  /// Header while editing a saved style.
  ///
  /// In en, this message translates to:
  /// **'Editing \"{name}\"'**
  String messageEditingStyle(String name);

  /// Popup item to unset default style.
  ///
  /// In en, this message translates to:
  /// **'Stop using for new chats'**
  String get messageStopUsingForNewChats;

  /// Style picker segmented button label.
  ///
  /// In en, this message translates to:
  /// **'Customize'**
  String get labelCustomize;

  /// Label above AI prompt generator intent field.
  ///
  /// In en, this message translates to:
  /// **'Describe what you want the prompt to do:'**
  String get messageGenerateHint;

  /// Title of AI refine panel.
  ///
  /// In en, this message translates to:
  /// **'Refine draft'**
  String get messageRefineDraft;

  /// Hint for AI prompt generator intent field.
  ///
  /// In en, this message translates to:
  /// **'e.g. A sarcastic coding mentor that keeps answers short'**
  String get hintSarcasticCodingMentor;

  /// Label shown while AI generates a prompt.
  ///
  /// In en, this message translates to:
  /// **'Generating…'**
  String get messageGenerating;

  /// Fallback AI generation error label.
  ///
  /// In en, this message translates to:
  /// **'Generation failed'**
  String get messageGenerationFailed;

  /// Placeholder when model list cannot load.
  ///
  /// In en, this message translates to:
  /// **'Could not load models'**
  String get messageCouldNotLoadModels;

  /// Mention autocomplete @all header.
  ///
  /// In en, this message translates to:
  /// **'Everyone and all agents'**
  String get messageEveryoneAndAllAgents;

  /// Mention autocomplete agent header.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get messageAgent;

  /// Message action branch tooltip.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get messageBranch;

  /// Copy button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy message to clipboard'**
  String get messageCopyMessageToClipboard;

  /// Regenerate button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get messageRegenerate;

  /// Regenerate dialog content.
  ///
  /// In en, this message translates to:
  /// **'Delete this response and generate a new one'**
  String get messageDeleteThisResponse;

  /// Speak button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get messageSpeak;

  /// Copy feedback tooltip.
  ///
  /// In en, this message translates to:
  /// **'Copied!'**
  String get messageCopied;

  /// Generic network/connection error message.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server — check your connection and try again.'**
  String get messageCouldNotReachServer;

  /// Context window indicator text.
  ///
  /// In en, this message translates to:
  /// **'Context window: {used} of {total} tokens used'**
  String messageContextWindow(String used, String total);

  /// Context window explanation.
  ///
  /// In en, this message translates to:
  /// **'Above 80%, older messages are summarized to free up space.'**
  String get messageAbove80PercentSummarized;

  /// Generic submit error with detail.
  ///
  /// In en, this message translates to:
  /// **'Could not submit: {error}'**
  String messageCouldNotSubmit(String error);

  /// Snackbar after email change.
  ///
  /// In en, this message translates to:
  /// **'Email updated. Please sign in again with the new address.'**
  String get messageEmailUpdatedSignInAgain;

  /// Edit profile email warning.
  ///
  /// In en, this message translates to:
  /// **'Changing email signs you out'**
  String get messageChangingEmailSignsYouOut;

  /// Empty friends list hint.
  ///
  /// In en, this message translates to:
  /// **'No friends yet. Send a request by email above.'**
  String get messageNoFriendsYet;

  /// Friends page section header.
  ///
  /// In en, this message translates to:
  /// **'Incoming requests'**
  String get titleIncomingRequests;

  /// Friends page section header.
  ///
  /// In en, this message translates to:
  /// **'Shared with you'**
  String get titleSharedWithYou;

  /// Friends page section header.
  ///
  /// In en, this message translates to:
  /// **'Sent requests'**
  String get titleSentRequests;

  /// Friends page section header.
  ///
  /// In en, this message translates to:
  /// **'Your friends'**
  String get titleYourFriends;

  /// Friends page section header.
  ///
  /// In en, this message translates to:
  /// **'Blocked'**
  String get titleBlocked;

  /// Card title in friends page.
  ///
  /// In en, this message translates to:
  /// **'Add a friend'**
  String get messageAddAFriend;

  /// Block user confirmation dialog content.
  ///
  /// In en, this message translates to:
  /// **'Block {email}? Any friendship or pending request between you is removed, and neither of you can send new requests or add the other to rooms. You can unblock them later.'**
  String messageBlockEmailConfirmation(String email);

  /// Remove friend confirmation dialog content.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from your friends? You can send a new request later.'**
  String messageRemoveFriendConfirmation(String name);

  /// Snackbar after auto-accepted friend request.
  ///
  /// In en, this message translates to:
  /// **'You are now friends with {email}'**
  String messageYouAreNowFriendsWith(String email);

  /// Snackbar after sending friend request.
  ///
  /// In en, this message translates to:
  /// **'Friend request sent to {email}'**
  String messageFriendRequestSentTo(String email);

  /// Noun for shared style item.
  ///
  /// In en, this message translates to:
  /// **'style'**
  String get labelStyleNoun;

  /// Noun for shared prompt template item.
  ///
  /// In en, this message translates to:
  /// **'prompt template'**
  String get labelPromptTemplateNoun;

  /// Snackbar after accepting shared item.
  ///
  /// In en, this message translates to:
  /// **'\"{name}\" added to your {noun}s'**
  String messageItemAddedToYourNouns(String name, String noun);

  /// Generic confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Confirm action?'**
  String get titleConfirmAction;

  /// Generic conversation label.
  ///
  /// In en, this message translates to:
  /// **'Conversation'**
  String get labelConversation;

  /// Talk mode language always label.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get labelAlways;

  /// App bar back label in some contexts.
  ///
  /// In en, this message translates to:
  /// **'Back to chat'**
  String get messageBackToChat;

  /// Search results header.
  ///
  /// In en, this message translates to:
  /// **'Search results'**
  String get titleSearchResults;

  /// Empty search results message.
  ///
  /// In en, this message translates to:
  /// **'No results for \"{query}\"'**
  String messageNoResultsFor(String query);

  /// Hint in search field.
  ///
  /// In en, this message translates to:
  /// **'Enter a search query'**
  String get messageSearchHint;

  /// Tools picker hint.
  ///
  /// In en, this message translates to:
  /// **'Every available tool is enabled'**
  String get messageEveryToolEnabled;

  /// Tools picker enabled section header.
  ///
  /// In en, this message translates to:
  /// **'Enabled tools'**
  String get titleEnabledTools;

  /// Tools picker available section header.
  ///
  /// In en, this message translates to:
  /// **'Available tools'**
  String get titleAvailableTools;

  /// Generic retry error message.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the server. Please try again.'**
  String get messageCouldNotReachServerPleaseTryAgain;

  /// Generic connection label.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get labelConnection;

  /// Location helper text.
  ///
  /// In en, this message translates to:
  /// **'City, Country'**
  String get messageCityCountry;

  /// Subtitle when coarse location sharing is on.
  ///
  /// In en, this message translates to:
  /// **'City-level only, shared as {location}'**
  String messageCityLevelOnly(String location);

  /// Location section label.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get labelLocation;

  /// Knowledge base empty state hint.
  ///
  /// In en, this message translates to:
  /// **'Upload documents for retrieval across chats.'**
  String get messageNoDocumentsHint;

  /// Error loading current conversation.
  ///
  /// In en, this message translates to:
  /// **'Could not load conversation: {error}'**
  String messageCouldNotLoadConversation(String error);

  /// Error loading conversation list.
  ///
  /// In en, this message translates to:
  /// **'Could not load conversations: {error}'**
  String messageCouldNotLoadConversations(String error);

  /// Error loading older messages.
  ///
  /// In en, this message translates to:
  /// **'Could not load older messages: {error}'**
  String messageCouldNotLoadOlderMessages(String error);

  /// Error creating conversation.
  ///
  /// In en, this message translates to:
  /// **'Could not create conversation: {error}'**
  String messageCouldNotCreateConversation(String error);

  /// Error deleting conversation.
  ///
  /// In en, this message translates to:
  /// **'Could not delete conversation: {error}'**
  String messageCouldNotDeleteConversation(String error);

  /// Error regenerating assistant response.
  ///
  /// In en, this message translates to:
  /// **'Could not regenerate: {error}'**
  String messageCouldNotRegenerate(String error);

  /// Error branching conversation.
  ///
  /// In en, this message translates to:
  /// **'Could not branch conversation: {error}'**
  String messageCouldNotBranch(String error);

  /// Error pinning conversation.
  ///
  /// In en, this message translates to:
  /// **'Could not pin conversation: {error}'**
  String messageCouldNotPinConversation(String error);

  /// Error reloading conversation.
  ///
  /// In en, this message translates to:
  /// **'Could not reload conversation: {error}'**
  String messageCouldNotReloadConversation(String error);

  /// Empty conversation list.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet.'**
  String get messageNoConversationsYet;

  /// Empty rooms list.
  ///
  /// In en, this message translates to:
  /// **'No rooms yet.'**
  String get messageNoRoomsYet;

  /// Hint to start chatting.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation'**
  String get messageStartAConversation;

  /// Chat input placeholder example.
  ///
  /// In en, this message translates to:
  /// **'Explain quantum computing in simple terms'**
  String get messageExplainQuantumComputing;

  /// Attachment drag target hint.
  ///
  /// In en, this message translates to:
  /// **'Attach or drag in PDFs, spreadsheets, code, and pictures.'**
  String get messageAttachOrDragFiles;

  /// Attachment menu camera/gallery option.
  ///
  /// In en, this message translates to:
  /// **'Attach photos or files'**
  String get messageAttachPhotosOrFiles;

  /// Duplicate attachment error.
  ///
  /// In en, this message translates to:
  /// **'Duplicate file: {name}'**
  String messageDuplicateFile(String name);

  /// Update banner message.
  ///
  /// In en, this message translates to:
  /// **'A newer version is available'**
  String get messageNewerVersionAvailable;

  /// Update status checking label.
  ///
  /// In en, this message translates to:
  /// **'Checking for updates…'**
  String get messageCheckingForUpdates;

  /// Update status downloading label.
  ///
  /// In en, this message translates to:
  /// **'Downloading update…'**
  String get messageDownloadingUpdate;

  /// Update error empty archive.
  ///
  /// In en, this message translates to:
  /// **'Downloaded archive is empty'**
  String get messageDownloadedArchiveEmpty;

  /// Update status error label.
  ///
  /// In en, this message translates to:
  /// **'Update failed'**
  String get messageUpdateFailed;

  /// Update install failure label.
  ///
  /// In en, this message translates to:
  /// **'Install failed'**
  String get messageInstallFailed;

  /// Generic error label.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get labelError;

  /// Dismiss button label.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get labelDismiss;

  /// Snackbar after dismissing update.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get messageDismissed;

  /// Generic copy tooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get tooltipCopy;

  /// Message branch tooltip.
  ///
  /// In en, this message translates to:
  /// **'Branch'**
  String get tooltipBranch;

  /// Message regenerate tooltip.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get tooltipRegenerate;

  /// Copy message tooltip.
  ///
  /// In en, this message translates to:
  /// **'Copy message to clipboard'**
  String get tooltipCopyMessage;

  /// Regenerate confirmation dialog content.
  ///
  /// In en, this message translates to:
  /// **'Delete this response and generate a new one'**
  String get messageDeleteResponseRegenerate;

  /// Regenerate confirmation dialog title.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get messageRegenerateTitle;

  /// Speak button tooltip.
  ///
  /// In en, this message translates to:
  /// **'Speak'**
  String get tooltipSpeak;

  /// Image viewer hint.
  ///
  /// In en, this message translates to:
  /// **'Drag to pan • Double tap to reset'**
  String get messageDragToPan;

  /// Drag-and-drop attachment hint.
  ///
  /// In en, this message translates to:
  /// **'Drop files to attach'**
  String get messageDropFilesToAttach;

  /// Camera option label.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get labelCamera;

  /// Gallery option label.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get labelGallery;

  /// File option label.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get labelFile;

  /// Delete conversation dialog content.
  ///
  /// In en, this message translates to:
  /// **'Delete this conversation?'**
  String get messageDeleteConversationConfirmation;

  /// Snackbar after applying style.
  ///
  /// In en, this message translates to:
  /// **'Conversation style updated'**
  String get messageConversationStyleUpdated;

  /// Style change confirmation title.
  ///
  /// In en, this message translates to:
  /// **'Change conversation style?'**
  String get messageChangeConversationStyle;

  /// Talk mode status when calling.
  ///
  /// In en, this message translates to:
  /// **'Calling {name}…'**
  String messageCalling(String name);

  /// Room connection lost indicator.
  ///
  /// In en, this message translates to:
  /// **'Connection lost.'**
  String get messageConnectionLost;

  /// Memory deactivate action.
  ///
  /// In en, this message translates to:
  /// **'Deactivate'**
  String get messageDeactivate;

  /// Memory FAB tooltip.
  ///
  /// In en, this message translates to:
  /// **'Create memory'**
  String get messageCreateMemory;

  /// Memory page app bar title.
  ///
  /// In en, this message translates to:
  /// **'Create Memory'**
  String get titleCreateMemoryAction;

  /// Memory page edit title.
  ///
  /// In en, this message translates to:
  /// **'Edit Memory'**
  String get titleEditMemoryAction;

  /// Memory page delete title.
  ///
  /// In en, this message translates to:
  /// **'Delete Memory'**
  String get titleDeleteMemoryAction;

  /// Confirmation dialog before deleting memory.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this memory?\n\n\"{content}\"'**
  String messageDeleteMemoryConfirmation(String content);

  /// Memory page empty action.
  ///
  /// In en, this message translates to:
  /// **'Create new memory'**
  String get messageCreateNewMemory;

  /// Memory list empty state.
  ///
  /// In en, this message translates to:
  /// **'No memories yet.'**
  String get messageNoMemoriesYet;

  /// Room members section header.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get titleRoomMembers;

  /// Room agents section header.
  ///
  /// In en, this message translates to:
  /// **'Agents'**
  String get titleRoomAgents;

  /// Create room dialog subtitle.
  ///
  /// In en, this message translates to:
  /// **'Create rooms where several AI agents (and people) chat together.'**
  String get messageCreateRoom;

  /// Create room dialog title.
  ///
  /// In en, this message translates to:
  /// **'Create a room?'**
  String get messageCreateARoomQuestion;

  /// Generic agent label.
  ///
  /// In en, this message translates to:
  /// **'Agent'**
  String get messageAgentName;

  /// Room owner badge.
  ///
  /// In en, this message translates to:
  /// **'Owner'**
  String get messageRoomOwner;

  /// Generic everyone label.
  ///
  /// In en, this message translates to:
  /// **'Everyone'**
  String get messageEveryone;

  /// Mention all literal.
  ///
  /// In en, this message translates to:
  /// **'@all'**
  String get messageMentionAll;

  /// Fallback for unnamed item.
  ///
  /// In en, this message translates to:
  /// **'(unnamed)'**
  String get messageUnnamed;

  /// Empty room chat state.
  ///
  /// In en, this message translates to:
  /// **'No messages yet.'**
  String get messageNoRoomMessagesYet;

  /// Room/conversation muted tooltip.
  ///
  /// In en, this message translates to:
  /// **'Muted'**
  String get messageRoomMuted;

  /// Room app bar info tooltip.
  ///
  /// In en, this message translates to:
  /// **'Room info'**
  String get tooltipRoomInfo;

  /// Leave room tooltip.
  ///
  /// In en, this message translates to:
  /// **'Leave room'**
  String get tooltipLeaveRoom;

  /// Room app bar menu tooltip.
  ///
  /// In en, this message translates to:
  /// **'Room menu'**
  String get tooltipRoomMenu;

  /// Room delete menu item.
  ///
  /// In en, this message translates to:
  /// **'Delete room'**
  String get messageDeleteRoom;

  /// Room leave menu item.
  ///
  /// In en, this message translates to:
  /// **'Leave room'**
  String get messageLeaveRoom;

  /// Snackbar after inviting member.
  ///
  /// In en, this message translates to:
  /// **'Invite sent'**
  String get messageInviteSent;

  /// Add agent dialog when no models.
  ///
  /// In en, this message translates to:
  /// **'No models'**
  String get messageNoModels;

  /// Add agent dialog when no tools.
  ///
  /// In en, this message translates to:
  /// **'No tools'**
  String get messageNoTools;

  /// Share prompt template tooltip.
  ///
  /// In en, this message translates to:
  /// **'Share \"{name}\" with a friend'**
  String tooltipSharePromptWithFriend(String name);

  /// Edit template tooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit \"{name}\"'**
  String tooltipEditTemplate(String name);

  /// Delete template tooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"'**
  String tooltipDeleteTemplate(String name);

  /// Default system prompt editor dialog title.
  ///
  /// In en, this message translates to:
  /// **'Edit system prompt'**
  String get messageEditSystemPrompt;

  /// Memory edit FAB tooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit memory'**
  String get messageEditMemory;

  /// Scheduled action edit title.
  ///
  /// In en, this message translates to:
  /// **'Edit scheduled action'**
  String get messageEditScheduledAction;

  /// Edit message tooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit this message and rerun the conversation from here'**
  String get messageEditThisMessage;

  /// Edit profile email validator.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get messageEmailRequired;

  /// Edit profile full name validator.
  ///
  /// In en, this message translates to:
  /// **'Full name is required'**
  String get messageFullNameRequired;

  /// Change password current validator.
  ///
  /// In en, this message translates to:
  /// **'Current password is required'**
  String get messageCurrentPasswordRequired;

  /// Change password new validator.
  ///
  /// In en, this message translates to:
  /// **'New password is required'**
  String get messageNewPasswordRequired;

  /// Change password confirm validator.
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get messagePasswordsDoNotMatch;

  /// Snackbar after profile update.
  ///
  /// In en, this message translates to:
  /// **'Profile updated'**
  String get messageProfileUpdated;

  /// Fallback edit profile error.
  ///
  /// In en, this message translates to:
  /// **'Failed to update profile'**
  String get messageFailedToUpdateProfile;

  /// Fallback change password error.
  ///
  /// In en, this message translates to:
  /// **'Failed to change password'**
  String get messageFailedToChangePassword;

  /// Fallback location update error.
  ///
  /// In en, this message translates to:
  /// **'Failed to update location'**
  String get messageFailedToUpdateLocation;

  /// Comma-separated abbreviated month names.
  ///
  /// In en, this message translates to:
  /// **'Jan,Feb,Mar,Apr,May,Jun,Jul,Aug,Sep,Oct,Nov,Dec'**
  String get labelMonthNames;

  /// Formatted timestamp string.
  ///
  /// In en, this message translates to:
  /// **'{month} {day}, {year} • {hour}:{minute} {amPm}'**
  String messageMonthDayYearTime(
    String month,
    String day,
    String year,
    String hour,
    String minute,
    String amPm,
  );

  /// Mute duration 1 week.
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get labelOneWeek;

  /// Mute duration 8 hours.
  ///
  /// In en, this message translates to:
  /// **'8 hours'**
  String get labelEightHours;

  /// Mute duration forever.
  ///
  /// In en, this message translates to:
  /// **'forever'**
  String get labelForever;

  /// Mute action unmute.
  ///
  /// In en, this message translates to:
  /// **'unmute'**
  String get labelUnmute;

  /// Snackbar mute 1 week.
  ///
  /// In en, this message translates to:
  /// **'Muted for 1 week'**
  String get messageMute1Week;

  /// Snackbar mute 8 hours.
  ///
  /// In en, this message translates to:
  /// **'Muted for 8 hours'**
  String get messageMute8Hours;

  /// Snackbar mute forever.
  ///
  /// In en, this message translates to:
  /// **'Muted forever'**
  String get messageMutedForever;

  /// Snackbar unmute.
  ///
  /// In en, this message translates to:
  /// **'Unmuted'**
  String get messageUnmuted;

  /// Muted until timestamp tooltip.
  ///
  /// In en, this message translates to:
  /// **'Muted until {time}'**
  String titleMutedUntil(String time);

  /// Generic system default label.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get labelSystemDefault;

  /// Memory activate action.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get messageActivate;

  /// Memory item edit tooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit memory'**
  String get tooltipEditMemory;

  /// Memory item delete tooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete memory'**
  String get tooltipDeleteMemory;

  /// Memory item deactivate tooltip.
  ///
  /// In en, this message translates to:
  /// **'Deactivate memory'**
  String get tooltipDeactivateMemory;

  /// Memory item activate tooltip.
  ///
  /// In en, this message translates to:
  /// **'Activate memory'**
  String get tooltipActivateMemory;

  /// Generic image label.
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get labelImage;

  /// Generic audio label.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get labelAudio;

  /// Generic video label.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get labelVideo;

  /// Generic document label.
  ///
  /// In en, this message translates to:
  /// **'Document'**
  String get labelDocument;

  /// Generic tool label.
  ///
  /// In en, this message translates to:
  /// **'tool'**
  String get messageTool;

  /// Semantic label for block math.
  ///
  /// In en, this message translates to:
  /// **'blockMath'**
  String get messageBlockMath;

  /// Semantic label for inline math.
  ///
  /// In en, this message translates to:
  /// **'inlineMath'**
  String get messageInlineMath;

  /// Image viewer hint.
  ///
  /// In en, this message translates to:
  /// **'Drag to pan • Double tap to reset'**
  String get messageDragToPanDoubleTapReset;

  /// Drag and drop attachment hint.
  ///
  /// In en, this message translates to:
  /// **'Drop files to attach'**
  String get messageDropFilesHere;

  /// Generic bytes label.
  ///
  /// In en, this message translates to:
  /// **'bytes'**
  String get labelBytes;

  /// Generic close label.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get labelClose;

  /// Mermaid diagram error with detail.
  ///
  /// In en, this message translates to:
  /// **'Failed to render diagram: {error}'**
  String messageFailedToRenderDiagramWithError(String error);

  /// Mermaid diagram load error.
  ///
  /// In en, this message translates to:
  /// **'Could not load diagram: {error}'**
  String messageCouldNotLoadDiagram(String error);

  /// Tool argument parse error.
  ///
  /// In en, this message translates to:
  /// **'Parse failed for {tool}'**
  String messageParseFailedForTool(String tool);

  /// Generic retry label.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get labelRetry;

  /// Generic done label.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get labelDone;

  /// Generic loading label.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get labelLoading;

  /// Talk mode mic busy error.
  ///
  /// In en, this message translates to:
  /// **'Device or resource busy'**
  String get labelDeviceBusy;

  /// Talk mode mic unavailable.
  ///
  /// In en, this message translates to:
  /// **'Microphone unavailable: {error}'**
  String messageMicrophoneUnavailable(String error);

  /// Talk mode transcription error.
  ///
  /// In en, this message translates to:
  /// **'Could not transcribe: {error}'**
  String messageCouldNotTranscribe(String error);

  /// Talk mode empty transcript.
  ///
  /// In en, this message translates to:
  /// **'Didn’t catch that — try again'**
  String get messageDidntCatchThat;

  /// Geolocation resolve error.
  ///
  /// In en, this message translates to:
  /// **'Could not resolve your location'**
  String get messageCouldNotResolveLocation;

  /// Fallback geolocation error.
  ///
  /// In en, this message translates to:
  /// **'Failed to resolve your location'**
  String get messageFailedToResolveLocation;

  /// Generic or.
  ///
  /// In en, this message translates to:
  /// **'or'**
  String get labelOr;

  /// Online status suffix.
  ///
  /// In en, this message translates to:
  /// **'online'**
  String get labelOnline;

  /// Talk mode calling placeholder.
  ///
  /// In en, this message translates to:
  /// **'Calling X…'**
  String get messageCallingX;

  /// Warning shown before discarding all uncommitted microapp changes.
  ///
  /// In en, this message translates to:
  /// **'Discard every uncommitted change in your workspace. This cannot be undone.'**
  String get messageRevertAllChangesWarning;

  /// Label on the remember-this button.
  ///
  /// In en, this message translates to:
  /// **'Remember'**
  String get labelRemember;

  /// Explanation in remember dialog.
  ///
  /// In en, this message translates to:
  /// **'Save this content as a memory for future reference:'**
  String get messageRememberDescription;

  /// Success snackbar after saving memory.
  ///
  /// In en, this message translates to:
  /// **'Memory saved successfully'**
  String get messageMemorySaved;

  /// Error snackbar after saving memory.
  ///
  /// In en, this message translates to:
  /// **'Failed to save memory: {error}'**
  String messageFailedToSaveMemory(String error);

  /// Voice recording duration label.
  ///
  /// In en, this message translates to:
  /// **'Recording {duration}'**
  String messageRecording(String duration);

  /// Error snackbar after deleting room.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete room: {error}'**
  String messageFailedToDeleteRoom(String error);

  /// Undo action label on snackbar.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get labelUndo;

  /// Info when a saved style references an uninstalled model.
  ///
  /// In en, this message translates to:
  /// **'{modelId} is not installed'**
  String messageModelNotInstalled(String modelId);

  /// Empty state in saved styles list.
  ///
  /// In en, this message translates to:
  /// **'No saved styles yet. Compose a model, thinking level, and prompt in Customize, then save the combination to switch in one tap.'**
  String get messageNoSavedStylesYet;

  /// Header while editing a saved style.
  ///
  /// In en, this message translates to:
  /// **'Editing \"{name}\"'**
  String messageEditing(String name);

  /// Error snackbar listing rejected oversized files.
  ///
  /// In en, this message translates to:
  /// **'Files too large:\n{files}'**
  String messageFilesTooLarge(String files);

  /// Theme section title.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get titleTheme;

  /// Subtitle for show-system-prompt toggle.
  ///
  /// In en, this message translates to:
  /// **'Display the active system prompt above the conversation'**
  String get titleDisplaySystemPrompt;

  /// Empty state in tools picker when no MCP server.
  ///
  /// In en, this message translates to:
  /// **'No MCP tools available. Configure a server from the Admin panel.'**
  String get messageNoMcpToolsAvailable;

  /// Tools picker summary per server.
  ///
  /// In en, this message translates to:
  /// **'{selected} of {total} tools enabled'**
  String messageNToolsEnabled(int selected, int total);

  /// Subtitle when no model is selected.
  ///
  /// In en, this message translates to:
  /// **'No model selected'**
  String get messageNoModelSelected;

  /// System prompt source label.
  ///
  /// In en, this message translates to:
  /// **'Using: {source}'**
  String messageUsingSource(String source);

  /// Description for global default system prompt.
  ///
  /// In en, this message translates to:
  /// **'Applied to every new conversation unless overridden per-chat.'**
  String get messageAppliedToEveryNewConversation;

  /// Empty state when no tools at all.
  ///
  /// In en, this message translates to:
  /// **'No tools available. Configure an MCP server first.'**
  String get messageNoToolsAvailableConfigureMcp;

  /// Empty state when search has no results.
  ///
  /// In en, this message translates to:
  /// **'No tools match \"{query}\".'**
  String messageNoToolsMatchQuery(String query);

  /// Header suffix showing number of tools.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} tool} other{{count} tools}}'**
  String messageToolCount(int count);

  /// Empty state for scheduled actions list.
  ///
  /// In en, this message translates to:
  /// **'No scheduled actions yet'**
  String get messageNoScheduledActionsYet;

  /// Empty state hint for scheduled actions.
  ///
  /// In en, this message translates to:
  /// **'Use the + button to set up a reminder or recurring check-in.'**
  String get messageUsePlusButton;

  /// Scheduled action subtitle showing cron expression.
  ///
  /// In en, this message translates to:
  /// **'Cron: {expr}'**
  String messageCronExpression(String expr);

  /// Confirmation dialog before deleting scheduled action.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{title}\"? This cannot be undone.'**
  String messageRemoveScheduledAction(String title);

  /// Dialog title for creating scheduled action.
  ///
  /// In en, this message translates to:
  /// **'New scheduled action'**
  String get titleNewScheduledAction;

  /// Dialog title for editing scheduled action.
  ///
  /// In en, this message translates to:
  /// **'Edit scheduled action'**
  String get titleEditScheduledAction;

  /// Example scheduled action title.
  ///
  /// In en, this message translates to:
  /// **'Morning standup'**
  String get hintMorningStandup;

  /// Helper text under cron expression field.
  ///
  /// In en, this message translates to:
  /// **'min hour day month weekday'**
  String get helperCronExpression;

  /// Hint when no run-at datetime selected.
  ///
  /// In en, this message translates to:
  /// **'Pick a date and time'**
  String get hintPickDateTime;

  /// Memory creation timestamp label.
  ///
  /// In en, this message translates to:
  /// **'Created {date}'**
  String messageCreatedAt(String date);

  /// Update dialog title.
  ///
  /// In en, this message translates to:
  /// **'Update to v{version}'**
  String messageUpdateToVersion(String version);

  /// Update dialog content.
  ///
  /// In en, this message translates to:
  /// **'You have v{currentVersion}. The app restarts after installing.'**
  String messageUpdateRestartAfterInstall(String currentVersion);

  /// Update section subtitle.
  ///
  /// In en, this message translates to:
  /// **'Latest release: v{version}'**
  String messageLatestRelease(String version);

  /// Update banner text.
  ///
  /// In en, this message translates to:
  /// **'Garbanzo AI v{version} is available'**
  String messageUpdateAvailable(String version);

  /// Subtitle when precise location sharing is on.
  ///
  /// In en, this message translates to:
  /// **'The assistant knows you are near {location}'**
  String messageAssistantKnowsLocation(String location);

  /// Attach menu option for images.
  ///
  /// In en, this message translates to:
  /// **'Photos'**
  String get titlePhotos;

  /// Attach menu option for files.
  ///
  /// In en, this message translates to:
  /// **'Files'**
  String get titleFiles;

  /// Attach menu option (desktop) for including a folder in the chat.
  ///
  /// In en, this message translates to:
  /// **'Folder'**
  String get titleFolder;

  /// Chip shown in the composer indicating the agent can read files in the attached folder.
  ///
  /// In en, this message translates to:
  /// **'Reading files in {name}'**
  String messageFolderScope(String name);

  /// Tooltip for removing the attached folder from a conversation.
  ///
  /// In en, this message translates to:
  /// **'Remove folder'**
  String get messageRemoveFolder;

  /// Error snackbar shown when attaching a folder fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t attach that folder'**
  String get messageFolderAttachFailed;

  /// Header of the confirm card for a delegated opencode workflow.
  ///
  /// In en, this message translates to:
  /// **'Delegate this task?'**
  String get titleDelegateWorkflow;

  /// Scope line on the delegate-workflow card naming the attached folder.
  ///
  /// In en, this message translates to:
  /// **'Works on a copy of {name}'**
  String messageWorkflowScope(String name);

  /// Status while the client walks the attached folder before uploading.
  ///
  /// In en, this message translates to:
  /// **'Scanning folder…'**
  String get messageWorkflowScanning;

  /// Status while the folder snapshot uploads; a percentage is appended.
  ///
  /// In en, this message translates to:
  /// **'Uploading folder…'**
  String get messageWorkflowUploading;

  /// Status while the delegated workflow runs on the server.
  ///
  /// In en, this message translates to:
  /// **'Agent is working…'**
  String get messageWorkflowRunning;

  /// Reassurance that a delegated workflow survives disconnecting.
  ///
  /// In en, this message translates to:
  /// **'Keeps running if you close the app — you\'ll be notified.'**
  String get messageWorkflowKeepsRunning;

  /// Status when a delegated workflow completed successfully.
  ///
  /// In en, this message translates to:
  /// **'Workflow finished'**
  String get messageWorkflowDone;

  /// Status when a delegated workflow ended in an error.
  ///
  /// In en, this message translates to:
  /// **'Workflow failed'**
  String get messageWorkflowFailed;

  /// Snackbar when confirming a workflow with no folder attached.
  ///
  /// In en, this message translates to:
  /// **'Attach a folder to this chat first.'**
  String get messageWorkflowNeedsFolder;

  /// Button opening the finished workflow's diff.
  ///
  /// In en, this message translates to:
  /// **'Review changes'**
  String get actionReviewChanges;

  /// Title of the dialog listing a finished workflow's file changes.
  ///
  /// In en, this message translates to:
  /// **'Review changes'**
  String get titleWorkflowChanges;

  /// Shown when a finished workflow produced an empty diff.
  ///
  /// In en, this message translates to:
  /// **'The workflow didn\'t change any files.'**
  String get messageWorkflowNoChanges;

  /// Warning above the change list naming the local folder that will be modified.
  ///
  /// In en, this message translates to:
  /// **'Selected files will be written into {path}.'**
  String messageWorkflowApplyWarning(String path);

  /// Subtitle for a change the server couldn't send back in full.
  ///
  /// In en, this message translates to:
  /// **'Too large to apply'**
  String get messageWorkflowTooLarge;

  /// Result summary after writing a workflow's changes locally.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file applied} other{{count} files applied}}'**
  String messageWorkflowApplied(int count);

  /// Heading for files left untouched because the local copy changed.
  ///
  /// In en, this message translates to:
  /// **'Skipped — these changed on disk while the workflow ran:'**
  String get messageWorkflowConflicts;

  /// Heading for files that failed to write during apply.
  ///
  /// In en, this message translates to:
  /// **'Could not write:'**
  String get messageWorkflowFailedFiles;

  /// Change type label for a newly created file.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get labelFileAdded;

  /// Change type label for an edited file.
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get labelFileModified;

  /// Change type label for a removed file.
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get labelFileDeleted;

  /// Status shown on a proposal card the user declined.
  ///
  /// In en, this message translates to:
  /// **'Dismissed'**
  String get labelDismissed;

  /// Confirm button in the workflow changes dialog.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Apply 1 file} other{Apply {count} files}}'**
  String actionApplySelected(int count);

  /// Error when STT service is unavailable.
  ///
  /// In en, this message translates to:
  /// **'Speech-to-text is currently unavailable on the server.'**
  String get messageSttUnavailable;

  /// Generic transcription failure message.
  ///
  /// In en, this message translates to:
  /// **'Transcription failed — please try again.'**
  String get messageTranscriptionFailed;

  /// Confirmation before deleting a saved style.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String messageDeleteStyle(String name);

  /// Button label when editing a style.
  ///
  /// In en, this message translates to:
  /// **'Save changes'**
  String get messageSaveChangesToStyle;

  /// Style card model display fallback.
  ///
  /// In en, this message translates to:
  /// **'{modelId} / {modelName}'**
  String messageModelNameFallback(String modelId, String modelName);

  /// Confirmation before deleting a saved style.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String messageDeleteStyleConfirmation(String name);

  /// Empty-state helper in memory list widget.
  ///
  /// In en, this message translates to:
  /// **'Memories store important facts about you\nfor more personalized conversations'**
  String get messageMemoriesStoreFactsHint;

  /// Caption shown on memory tile when it came from a chat.
  ///
  /// In en, this message translates to:
  /// **'Source: Conversation'**
  String get messageSourceConversation;

  /// Subtitle shown in empty chat state.
  ///
  /// In en, this message translates to:
  /// **'Type a message below to begin chatting'**
  String get messageTypeMessageToBegin;

  /// Suggestion chip label in empty chat state.
  ///
  /// In en, this message translates to:
  /// **'Write a Python function'**
  String get messageWriteAPythonFunction;

  /// Prompt sent when the user taps the Python suggestion chip.
  ///
  /// In en, this message translates to:
  /// **'Write a Python function to calculate factorial'**
  String get messageWriteAPythonFunctionPrompt;

  /// Suggestion chip label in empty chat state.
  ///
  /// In en, this message translates to:
  /// **'Help me debug code'**
  String get messageHelpMeDebugCode;

  /// Prompt sent when the user taps the debug suggestion chip.
  ///
  /// In en, this message translates to:
  /// **'I need help debugging some code'**
  String get messageHelpMeDebugCodePrompt;

  /// Onboarding card header in empty chat state.
  ///
  /// In en, this message translates to:
  /// **'Getting started'**
  String get titleGettingStarted;

  /// Onboarding tip title.
  ///
  /// In en, this message translates to:
  /// **'Voice input'**
  String get tipVoiceInputTitle;

  /// Onboarding tip body.
  ///
  /// In en, this message translates to:
  /// **'Tap the mic to dictate — your speech is transcribed locally.'**
  String get tipVoiceInputBody;

  /// Onboarding tip title.
  ///
  /// In en, this message translates to:
  /// **'Files & images'**
  String get tipFilesAndImagesTitle;

  /// Onboarding tip body.
  ///
  /// In en, this message translates to:
  /// **'Attach or drag in PDFs, spreadsheets, code, and pictures.'**
  String get tipFilesAndImagesBody;

  /// Onboarding tip title.
  ///
  /// In en, this message translates to:
  /// **'Memory'**
  String get tipMemoryTitle;

  /// Onboarding tip body.
  ///
  /// In en, this message translates to:
  /// **'The assistant learns facts about you over time — review them anytime under Settings → Memories.'**
  String get tipMemoryBody;

  /// Onboarding tip title.
  ///
  /// In en, this message translates to:
  /// **'Knowledge base'**
  String get tipKnowledgeBaseTitle;

  /// Onboarding tip body.
  ///
  /// In en, this message translates to:
  /// **'Upload documents once, then ask questions about them in any chat.'**
  String get tipKnowledgeBaseBody;

  /// Onboarding tip title.
  ///
  /// In en, this message translates to:
  /// **'Rooms'**
  String get tipRoomsTitle;

  /// Onboarding tip body.
  ///
  /// In en, this message translates to:
  /// **'Create rooms where several AI agents (and people) chat together.'**
  String get tipRoomsBody;

  /// Tooltip for usage page time-range popup menu.
  ///
  /// In en, this message translates to:
  /// **'Time range'**
  String get tooltipTimeRange;

  /// Empty-state title when there is no usage data.
  ///
  /// In en, this message translates to:
  /// **'No usage in the last {days} days'**
  String messageNoUsageInLastDays(int days);

  /// Empty-state helper in usage page.
  ///
  /// In en, this message translates to:
  /// **'Start a conversation to see your token consumption here.'**
  String get messageStartAConversationTokensHint;

  /// Usage page daily chart section title.
  ///
  /// In en, this message translates to:
  /// **'Daily tokens ({days} days)'**
  String messageDailyTokensDays(int days);

  /// Usage page conversations section title.
  ///
  /// In en, this message translates to:
  /// **'Top conversations'**
  String get titleByConversation;

  /// Usage page stat card label.
  ///
  /// In en, this message translates to:
  /// **'Total tokens'**
  String get labelTotalTokens;

  /// Usage page stat card label for generated tokens.
  ///
  /// In en, this message translates to:
  /// **'Generated'**
  String get labelGenerated;

  /// Fallback title for an unnamed conversation.
  ///
  /// In en, this message translates to:
  /// **'Untitled'**
  String get messageUntitled;

  /// By-model breakdown subtitle in usage page.
  ///
  /// In en, this message translates to:
  /// **'{prompt} in · {generated} out · {count} msgs'**
  String messageModelBreakdown(String prompt, String generated, int count);

  /// By-conversation breakdown subtitle in usage page.
  ///
  /// In en, this message translates to:
  /// **'{prompt} in · {generated} out'**
  String messagePromptGeneratedInOut(String prompt, String generated);

  /// Tooltip for chat app bar menu button.
  ///
  /// In en, this message translates to:
  /// **'Open conversations'**
  String get tooltipOpenConversations;

  /// Tooltip for chat app bar search button.
  ///
  /// In en, this message translates to:
  /// **'Search conversations'**
  String get tooltipSearchConversations;

  /// Fallback label for a micro-app panel.
  ///
  /// In en, this message translates to:
  /// **'Micro-app'**
  String get labelMicroApp;

  /// Tooltip for reopening a closed micro-app panel.
  ///
  /// In en, this message translates to:
  /// **'Reopen the micro-app panel'**
  String get tooltipReopenMicroAppPanel;

  /// Tooltip for reopening a closed micro-app on narrow screens.
  ///
  /// In en, this message translates to:
  /// **'Reopen {name}'**
  String tooltipReopenApp(String name);

  /// Conversation message count shown in sidebar/drawer.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{{count} message} other{{count} messages}}'**
  String messageCount(int count);

  /// Placeholder hint for the system prompt text field.
  ///
  /// In en, this message translates to:
  /// **'e.g. You are a concise, no-nonsense assistant. Give short factual answers with examples.'**
  String get hintSystemPromptExample;

  /// Subtitle shown when coarse location sharing is off.
  ///
  /// In en, this message translates to:
  /// **'Shares your neighbourhood-level area, so \"near me\" questions (like nearby restaurants) work. Your exact coordinates are never stored.'**
  String get messageCityLevelOnlyHint;

  /// Subtitle for the chat-responses notification toggle.
  ///
  /// In en, this message translates to:
  /// **'Notify when assistant replies while app is in background'**
  String get messageNotifyAssistantBackground;

  /// Idle status label in the update section.
  ///
  /// In en, this message translates to:
  /// **'Updates are checked when the app starts'**
  String get messageUpdatesCheckedAtStart;

  /// Status label when no update is available.
  ///
  /// In en, this message translates to:
  /// **'You are up to date'**
  String get messageUpToDate;

  /// Status label while an update is being installed.
  ///
  /// In en, this message translates to:
  /// **'Installing — the app will restart'**
  String get messageInstallAppRestart;

  /// Status label when an update check errored.
  ///
  /// In en, this message translates to:
  /// **'Update check failed'**
  String get messageUpdateCheckFailed;

  /// Install button label when no downloadable asset exists.
  ///
  /// In en, this message translates to:
  /// **'No build for this platform'**
  String get messageNoBuildForPlatform;

  /// Tooltip for the re-detect location button.
  ///
  /// In en, this message translates to:
  /// **'Re-detect from device location'**
  String get tooltipRedetectLocation;

  /// Placeholder hint in the message input field.
  ///
  /// In en, this message translates to:
  /// **'Type a message…'**
  String get hintTypeAMessage;

  /// Empty-state hint in a room chat view.
  ///
  /// In en, this message translates to:
  /// **'Type a message to get started. Use @AgentName to call an agent, or @all to mention everyone.'**
  String get messageRoomEmptyHint;

  /// Settings section title for the user's own MCP tool servers.
  ///
  /// In en, this message translates to:
  /// **'My MCP servers'**
  String get titleMyMcpServers;

  /// Explanatory hint below the personal MCP servers list in settings.
  ///
  /// In en, this message translates to:
  /// **'Connect your own tool servers. Only you can see and use these — admins manage shared servers for everyone.'**
  String get messagePersonalMcpServersHint;

  /// Button label to add a new personal MCP server.
  ///
  /// In en, this message translates to:
  /// **'Add server'**
  String get labelAddServer;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
