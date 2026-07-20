// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'Garbanzo AI';

  @override
  String get language => 'Idioma';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageSpanish => 'Español';

  @override
  String get languageSystem => 'Predeterminado del sistema';

  @override
  String get accept => 'Aceptar';

  @override
  String get active => 'Activo';

  @override
  String get add => 'Añadir';

  @override
  String get addAgentTitle => 'Añadir agente';

  @override
  String get agents => 'Agentes';

  @override
  String get alwaysRespond => 'Responder siempre';

  @override
  String get apply => 'Aplicar';

  @override
  String attachedImageLabel(String name) {
    return 'Imagen adjunta: $name';
  }

  @override
  String get authErrorIncorrectEmailOrPassword =>
      'Correo o contraseña incorrectos';

  @override
  String get autoJumpInWhenRelevantLlm =>
      'Auto — intervenir cuando sea relevante (LLM)';

  @override
  String get autoLowercase => 'auto';

  @override
  String get autoModel => 'Auto';

  @override
  String get block => 'Bloquear';

  @override
  String get blockLowercase => 'bloquear';

  @override
  String get blockSender => 'Bloquear remitente';

  @override
  String get cancel => 'Cancelar';

  @override
  String get change => 'Cambiar';

  @override
  String get chatStyle => 'Estilo de chat';

  @override
  String get checkNow => 'Buscar ahora';

  @override
  String get clear => 'Limpiar';

  @override
  String get close => 'Cerrar';

  @override
  String get commitAndDeployToGithubPages =>
      'Hacer commit y desplegar en GitHub Pages.';

  @override
  String get composeAStyle => 'Componer un estilo';

  @override
  String get confirm => 'Confirmar';

  @override
  String couldNotUpdate(String error) {
    return 'No se ha podido actualizar: $error';
  }

  @override
  String get create => 'Crear';

  @override
  String get delete => 'Eliminar';

  @override
  String deleteAgentConfirmation(String name) {
    return '¿Eliminar el agente $name? Esta acción no se puede deshacer.';
  }

  @override
  String get deleteLowercase => 'eliminar';

  @override
  String deleteRoomConfirmation(String name) {
    return '¿Eliminar \"$name\"? Esta acción no se puede deshacer.';
  }

  @override
  String deleteStyleTitle(String name) {
    return '¿Eliminar \"$name\"?';
  }

  @override
  String deleteTemplateTitle(String name) {
    return '¿Eliminar \"$name\"?';
  }

  @override
  String get discard => 'Descartar';

  @override
  String get downloadInstall => 'Descargar e instalar';

  @override
  String get edit => 'editar';

  @override
  String get editAgentTitle => 'Editar agente';

  @override
  String get editEllipsis => 'Editar…';

  @override
  String editTemplateTitle(String name) {
    return 'Editar \"$name\"';
  }

  @override
  String errorWithDetails(String error) {
    return 'Error: $error';
  }

  @override
  String get failedToAcceptRequest => 'Error al aceptar la solicitud';

  @override
  String get failedToAcceptShare => 'Error al aceptar la compartición';

  @override
  String get failedToBlockUser => 'Error al bloquear al usuario';

  @override
  String get failedToCreateMemory => 'Error al crear el recuerdo';

  @override
  String get failedToCreateScheduledAction =>
      'Error al crear la acción programada';

  @override
  String get failedToCreateTemplate => 'Error al crear la plantilla';

  @override
  String get failedToDeactivateMemory => 'Error al desactivar el recuerdo';

  @override
  String get failedToDeclineRequest => 'Error al rechazar la solicitud';

  @override
  String get failedToDeclineShare => 'Error al rechazar la compartición';

  @override
  String failedToDeleteAgent(String error) {
    return 'Error al eliminar el agente: $error';
  }

  @override
  String get failedToDeleteDocument => 'Error al eliminar el documento';

  @override
  String failedToDeleteRoom(String error) {
    return 'Error al eliminar la sala: $error';
  }

  @override
  String get failedToDeleteScheduledAction =>
      'Error al eliminar la acción programada';

  @override
  String get failedToDeleteStyle => 'Error al eliminar el estilo';

  @override
  String get failedToDeleteTemplate => 'Error al eliminar la plantilla';

  @override
  String failedToEditMessage(String error) {
    return 'Error al editar el mensaje: $error';
  }

  @override
  String get failedToLoadDocuments => 'Error al cargar los documentos';

  @override
  String get failedToLoadFriends => 'Error al cargar los amigos';

  @override
  String get failedToLoadMemories => 'Error al cargar los recuerdos';

  @override
  String get failedToLoadModels => 'Error al cargar los modelos';

  @override
  String get failedToLoadNotifications => 'Error al cargar las notificaciones';

  @override
  String get failedToLoadScheduledActions =>
      'Error al cargar las acciones programadas';

  @override
  String get failedToLoadStyles => 'Error al cargar los estilos';

  @override
  String get failedToLoadSystemPrompts =>
      'Error al cargar las instrucciones del sistema';

  @override
  String get failedToLoadTools => 'Error al cargar las herramientas';

  @override
  String get failedToLoadUsage => 'Error al cargar el uso';

  @override
  String get failedToRemoveFriend => 'Error al eliminar al amigo';

  @override
  String failedToRemoveMember(String error) {
    return 'Error al eliminar el miembro: $error';
  }

  @override
  String get failedToRenderDiagram => 'Error al renderizar el diagrama';

  @override
  String get failedToSaveDefaultPrompt =>
      'Error al guardar la instrucción predeterminada';

  @override
  String failedToSaveMemory(String error) {
    return 'Error al guardar el recuerdo: $error';
  }

  @override
  String get failedToSaveStyle => 'Error al guardar el estilo';

  @override
  String get failedToSendFriendRequest =>
      'Error al enviar la solicitud de amistad';

  @override
  String failedToSendMessage(String error) {
    return 'Error al enviar el mensaje: $error';
  }

  @override
  String get failedToShare => 'Error al compartir';

  @override
  String get failedToUnblockUser => 'Error al desbloquear al usuario';

  @override
  String get failedToUpdateMemory => 'Error al actualizar el recuerdo';

  @override
  String failedToUpdateMemorySetting(String error) {
    return 'Error al actualizar el ajuste de recuerdos: $error';
  }

  @override
  String get failedToUpdateScheduledAction =>
      'Error al actualizar la acción programada';

  @override
  String get failedToUpdateStyle => 'Error al actualizar el estilo';

  @override
  String get failedToUpdateTemplate => 'Error al actualizar la plantilla';

  @override
  String get failedToUploadDocument => 'Error al subir el documento';

  @override
  String get feedbackToApply => 'Comentarios a aplicar:';

  @override
  String filesTooLarge(String files) {
    return 'Archivos demasiado grandes:\n$files';
  }

  @override
  String get fromYourKnowledgeBase => 'De tu base de conocimientos';

  @override
  String get headingSignIn => 'Iniciar sesión';

  @override
  String get hintApiKeyAbcNdebug1 => 'API_KEY=abc\\nDEBUG=1';

  @override
  String get hintAtLeast6Characters => 'Al menos 6 caracteres';

  @override
  String get hintBearer => 'Bearer …';

  @override
  String get hintBug => 'error';

  @override
  String get hintDeepWorkQuickAnswers =>
      'Trabajo profundo, respuestas rápidas…';

  @override
  String get hintEG09MonFri => 'p. ej. \"0 9 * * mon-fri\"';

  @override
  String get hintEGFilesystem => 'p. ej. filesystem';

  @override
  String get hintEGMadridSpain => 'p. ej. Madrid, España';

  @override
  String get hintEGMakeItFriendlier => 'p. ej. Hazlo más amable';

  @override
  String get hintEGMorningStandup => 'p. ej. \"Reunión diaria\"';

  @override
  String get hintEGProductBrainstorm => 'p. ej. Lluvia de ideas de producto';

  @override
  String get hintEnterMemoryContent => 'Introduce el contenido del recuerdo';

  @override
  String get hintFriendExampleCom => 'amigo@ejemplo.com';

  @override
  String get hintJaneDoe => 'Jane Doe';

  @override
  String get hintMemoryContent => 'Contenido del recuerdo';

  @override
  String get hintMessageTheRoomUseAgentnameOr =>
      'Mensaje para la sala… (usa @AgentName o @all)';

  @override
  String get hintOneLineSummary => 'Resumen en una línea';

  @override
  String get hintSearchConversations => 'Buscar conversaciones…';

  @override
  String get hintSearchTools => 'Buscar herramientas…';

  @override
  String get hintUsrBinPython3 => '/usr/bin/python3';

  @override
  String get hintWhatShouldTheAssistantDo => '¿Qué debe hacer el asistente?';

  @override
  String get hintYouAreAFriendlyProductStrategist =>
      'Eres un estratega de producto amigable…';

  @override
  String get hintYouExampleCom => 'tu@ejemplo.com';

  @override
  String get inactive => 'Inactivo';

  @override
  String get invite => 'Invitar';

  @override
  String itemAddedToYourNouns(String name, String noun) {
    return '\"$name\" se ha añadido a tus ${noun}s';
  }

  @override
  String get labelAgentName => 'Nombre del agente';

  @override
  String get labelAll => 'Todos';

  @override
  String get labelAllLowercase => 'todos';

  @override
  String get labelArgsOnePerLine => 'Args (uno por línea)';

  @override
  String get labelAuthHeader => 'Cabecera de autenticación';

  @override
  String get labelBug => 'Error';

  @override
  String get labelChats => 'Chats';

  @override
  String get labelCity => 'Ciudad';

  @override
  String get labelCommitMessageOptional => 'Mensaje de commit (opcional)';

  @override
  String get labelConfirmNewPassword => 'Confirmar nueva contraseña';

  @override
  String get labelCopyUrl => 'Copiar URL';

  @override
  String get labelCreateARoom => 'Crear una sala';

  @override
  String get labelCreateWithAi => 'Crear con IA';

  @override
  String get labelCronExpression => 'Expresión cron';

  @override
  String get labelCurrentPassword => 'Contraseña actual';

  @override
  String get labelDark => 'Oscuro';

  @override
  String get labelDescription => 'Descripción';

  @override
  String get labelDescriptionOptional => 'Descripción (opcional)';

  @override
  String get labelDisabled => 'Desactivado';

  @override
  String get labelEmail => 'Correo electrónico';

  @override
  String get labelEnvKeyValueOnePerLine => 'Env (KEY=VALUE, uno por línea)';

  @override
  String get labelFailedToCreateServer => 'Error al crear el servidor';

  @override
  String get labelFailedToCreateUser => 'Error al crear el usuario';

  @override
  String get labelFailedToDeleteServer => 'Error al eliminar el servidor';

  @override
  String get labelFailedToLoadServers => 'Error al cargar los servidores';

  @override
  String get labelFailedToLoadUsers => 'Error al cargar los usuarios';

  @override
  String get labelFailedToSyncModels => 'Error al sincronizar los modelos';

  @override
  String get labelFailedToTestServer => 'Error al probar el servidor';

  @override
  String get labelFailedToUpdateModel => 'Error al actualizar el modelo';

  @override
  String get labelFailedToUpdateServer => 'Error al actualizar el servidor';

  @override
  String get labelFailedToUpdateUser => 'Error al actualizar el usuario';

  @override
  String get labelFeature => 'Funcionalidad';

  @override
  String get labelFullName => 'Nombre completo';

  @override
  String get labelFullNameOptional => 'Nombre completo (opcional)';

  @override
  String get labelGenerate => 'Generar';

  @override
  String get labelHttp => 'HTTP';

  @override
  String get labelInviteMembers => 'Invitar miembros';

  @override
  String get labelLight => 'Claro';

  @override
  String get labelMarkAllRead => 'Marcar todas como leídas';

  @override
  String get labelModel => 'Modelo';

  @override
  String get labelMonospace => 'monoespaciado';

  @override
  String get labelName => 'Nombre';

  @override
  String get labelNew => 'Nueva';

  @override
  String get labelNewChat => 'Nuevo chat';

  @override
  String get labelNewPassword => 'Nueva contraseña';

  @override
  String get labelNewRoom => 'Nueva sala';

  @override
  String get labelOneOff => 'Puntual';

  @override
  String get labelPassword => 'Contraseña';

  @override
  String get labelPrompt => 'Instrucción';

  @override
  String get labelPromptContent => 'Contenido de la instrucción';

  @override
  String get labelPromptTemplate => 'Plantilla de instrucción';

  @override
  String get labelPublish => 'Publicar';

  @override
  String get labelPublishing => 'Publicando…';

  @override
  String get labelRecurring => 'Recurrente';

  @override
  String get labelRefine => 'Refinar';

  @override
  String get labelRooms => 'Salas';

  @override
  String get labelRunAt => 'Ejecutar a las';

  @override
  String get labelSaveToLibrary => 'Guardar en la biblioteca';

  @override
  String get labelSend => 'Enviar';

  @override
  String get labelShowSchema => 'Mostrar esquema';

  @override
  String get labelSse => 'SSE';

  @override
  String get labelStop => 'Detener';

  @override
  String get labelStyles => 'Estilos';

  @override
  String get labelPredefinedStyles => 'Predefinidos';

  @override
  String get labelYourStyles => 'Tus estilos';

  @override
  String get labelNewPrompt => 'Nueva instrucción';

  @override
  String get messageNoTemplatesYet =>
      'Aún no hay instrucciones guardadas. Toca \"Nueva instrucción\" para crear una, o \"Crear con IA\" para redactar una.';

  @override
  String get labelSync => 'Sincronizar';

  @override
  String get labelSystem => 'Sistema';

  @override
  String get labelSystemPrompt => 'Instrucción del sistema';

  @override
  String get labelSystemPromptOptional => 'Instrucción del sistema (opcional)';

  @override
  String get labelTemplate => 'Plantilla';

  @override
  String get labelTitle => 'Título';

  @override
  String get labelTitleOptional => 'Título (opcional)';

  @override
  String get labelUpload => 'Subir';

  @override
  String get labelUrl => 'URL';

  @override
  String get labelWhenToRespond => 'Cuándo responder';

  @override
  String get last12Months => 'Últimos 12 meses';

  @override
  String get last30Days => 'Últimos 30 días';

  @override
  String get last7Days => 'Últimos 7 días';

  @override
  String get last90Days => 'Últimos 90 días';

  @override
  String get later => 'Más tarde';

  @override
  String latestReleaseVersion(String releaseVersion) {
    return 'Última versión: v$releaseVersion';
  }

  @override
  String get loadingModels => 'Cargando modelos…';

  @override
  String get loadingPreferences => 'Cargando preferencias…';

  @override
  String get loadingTools => 'Cargando herramientas…';

  @override
  String get members => 'Miembros';

  @override
  String memoriesInformedReply(String count) {
    return '$count recuerdos guardados sobre ti han informado esta respuesta';
  }

  @override
  String get memory => 'Recuerdo';

  @override
  String get messageChangesReverted => 'Cambios revertidos';

  @override
  String get messageConversationDeleted => 'Conversación eliminada';

  @override
  String messageFailed(String error) {
    return 'Error: $error';
  }

  @override
  String get messageFailedToRemoveProfilePicture =>
      'Error al eliminar la foto de perfil';

  @override
  String get messageFailedToUploadProfilePicture =>
      'Error al subir la foto de perfil';

  @override
  String get messagePasswordUpdated => 'Contraseña actualizada';

  @override
  String get messageProfilePictureRemoved => 'Foto de perfil eliminada';

  @override
  String get messageProfilePictureUpdated => 'Foto de perfil actualizada';

  @override
  String get messageSchemaCopied => 'Esquema copiado';

  @override
  String get messageStartAConversationFirst =>
      'Empieza una conversación primero';

  @override
  String get messageThanksYourReportWasSubmitted =>
      '¡Gracias! Tu informe se ha enviado.';

  @override
  String get messageThisRemovesTheSavedStyleNot =>
      'Esto elimina el estilo guardado, no los chats.';

  @override
  String modelIdIsNotInstalled(String modelId) {
    return '$modelId no está instalado';
  }

  @override
  String get noAppToDisplay => 'No hay ninguna micro-app para mostrar';

  @override
  String get noDailyData => 'Sin datos diarios';

  @override
  String get noDocumentsYet => 'Aún no hay documentos';

  @override
  String get noModelsSyncedYet => 'Aún no se han sincronizado modelos';

  @override
  String get noTemplate => 'Sin plantilla';

  @override
  String get none => '— Ninguna —';

  @override
  String get ok => 'Aceptar';

  @override
  String get onMentionOnly => 'Solo al mencionar @';

  @override
  String get onlySwitchBetweenTheseNoneMeans =>
      'Cambia solo entre estos; si no hay ninguno, permite cualquiera';

  @override
  String pushServiceForegroundMessage(String title) {
    return '[PushService] mensaje en primer plano: $title';
  }

  @override
  String get releasePage => 'Página de la versión';

  @override
  String get remove => 'Eliminar';

  @override
  String removeDocumentConfirmation(String filename) {
    return '¿Eliminar \"$filename\" de tu base de conocimientos?';
  }

  @override
  String get removeFriend => 'Eliminar amigo';

  @override
  String get removeLowercase => 'eliminar';

  @override
  String removeMemberFromRoomMessage(String userId) {
    return '¿Eliminar a $userId de esta sala?';
  }

  @override
  String get retry => 'Reintentar';

  @override
  String get revert => 'Revertir';

  @override
  String get roundRobinTakeTurns => 'Round-robin (turnos)';

  @override
  String get save => 'Guardar';

  @override
  String get saveAndRerun => 'Guardar y volver a ejecutar';

  @override
  String savedToLibrary(String name) {
    return 'Se ha guardado \"$name\" en tu biblioteca';
  }

  @override
  String get semanticLabelBlockMath => 'matemáticas en bloque';

  @override
  String get semanticLabelInlineMath => 'matemáticas en línea';

  @override
  String get semanticLabelMuted => 'Silenciado';

  @override
  String get semanticLabelTool => 'herramienta';

  @override
  String get settings => 'Ajustes';

  @override
  String shareItemTitle(String itemName) {
    return 'Compartir \"$itemName\"';
  }

  @override
  String get shareWithAFriend => 'Compartir con un amigo…';

  @override
  String sharedItemFromSender(String senderEmail) {
    return 'de $senderEmail';
  }

  @override
  String sharedItemTitle(String name, String noun) {
    return '\"$name\" ($noun)';
  }

  @override
  String get startAConversationToSetA =>
      'Empieza una conversación para establecer una instrucción';

  @override
  String get submit => 'Enviar';

  @override
  String get tabMcpServers => 'Servidores MCP';

  @override
  String get tabModels => 'Modelos';

  @override
  String get tabReports => 'Informes';

  @override
  String get tabUsers => 'Usuarios';

  @override
  String get templates => 'Plantillas';

  @override
  String testingServer(String name) {
    return 'Probando $name…';
  }

  @override
  String get thinking => 'Pensando';

  @override
  String get titleAccountAndSystemNotifications =>
      'Notificaciones de cuenta y sistema';

  @override
  String get titleAdmin => 'Admin';

  @override
  String get titleAdminPrivileges => 'Privilegios de administrador';

  @override
  String get titleAllTools => 'Todas las herramientas';

  @override
  String get titleAppSettings => 'Ajustes de la app';

  @override
  String get titleAppearance => 'Apariencia';

  @override
  String get titleAutoPlayResponses => 'Reproducir respuestas automáticamente';

  @override
  String get titleAutoSendAfterTranscription =>
      'Enviar automáticamente tras transcribir';

  @override
  String get titleAutomaticLanguageSwitching => 'Cambio automático de idioma';

  @override
  String get titleAutomaticallySendWhenVoiceInputFinishes =>
      'Enviar automáticamente al terminar la entrada de voz';

  @override
  String get titleBlockUser => 'Bloquear usuario';

  @override
  String get titleBrowseAvailableMcpTools =>
      'Explorar herramientas MCP disponibles';

  @override
  String get titleChangePassword => 'Cambiar contraseña';

  @override
  String get titleChartsByModelConversationDay =>
      'Gráficos por modelo, conversación y día';

  @override
  String get titleChat => 'Chat';

  @override
  String get titleChatResponses => 'Respuestas del chat';

  @override
  String get titleChoosePhoto => 'Elegir foto';

  @override
  String get titleConversationSystemPrompt =>
      'Instrucción del sistema de la conversación';

  @override
  String get titleCreateMemory => 'Crear recuerdo';

  @override
  String get titleCreateUser => 'Crear usuario';

  @override
  String get titleCurrentVersion => 'Versión actual';

  @override
  String get titleDefaultModel => 'Modelo predeterminado';

  @override
  String get titleDeleteAgent => '¿Eliminar agente?';

  @override
  String get titleDeleteConversation => '¿Eliminar conversación?';

  @override
  String get titleDeleteDocument => 'Eliminar documento';

  @override
  String get titleDeleteMcpServer => '¿Eliminar servidor MCP?';

  @override
  String get titleDeleteMemory => 'Eliminar recuerdo';

  @override
  String get titleDeleteRoom => '¿Eliminar sala?';

  @override
  String get titleDeleteScheduledAction => 'Eliminar acción programada';

  @override
  String get titleDisplayTokenCountsAndResponseTime =>
      'Mostrar tokens y tiempo de respuesta';

  @override
  String get titleEditMcpServer => 'Editar servidor MCP';

  @override
  String get titleEditMemory => 'Editar recuerdo';

  @override
  String get titleEditMessage => 'Editar mensaje';

  @override
  String get titleEditProfile => 'Editar perfil';

  @override
  String get titleEditStyle => 'Editar estilo';

  @override
  String get titleEnabled => 'Activado';

  @override
  String get titleFriendRequestsAndAccepts =>
      'Solicitudes y aceptaciones de amistad';

  @override
  String get titleFriendUpdates => 'Actualizaciones de amigos';

  @override
  String get titleFriends => 'Amigos';

  @override
  String get titleGlobalDefault => 'Valor global predeterminado';

  @override
  String get titleGlobalDefaultSystemPrompt =>
      'Instrucción del sistema global predeterminada';

  @override
  String get titleKnowledgeBase => 'Base de conocimientos';

  @override
  String get titleKnowledgeBasePage => 'Base de Conocimientos';

  @override
  String get titleLlmModel => 'Modelo LLM';

  @override
  String get titleMemories => 'Recuerdos';

  @override
  String get titleMemoryKnowledgeBase => 'Recuerdos y base de conocimientos';

  @override
  String get titleModel => 'Modelo';

  @override
  String get titleModerator => 'Moderador';

  @override
  String get titleMyLanguages => 'Mis idiomas';

  @override
  String get titleNewMcpServer => 'Nuevo servidor MCP';

  @override
  String get titleNewRoom => 'Nueva sala';

  @override
  String get titleNotifications => 'Notificaciones';

  @override
  String get titleOpenFullSettings => 'Abrir ajustes completos';

  @override
  String get titleOverridesYourGlobalDefaultForThis =>
      'Sustituye tu valor global solo para esta conversación.';

  @override
  String get titlePages => 'Páginas';

  @override
  String get titlePersonalContext => 'Contexto personal';

  @override
  String get titleProfileAppearanceModelsAndMore =>
      'Perfil, apariencia, modelos y más';

  @override
  String get titlePublishChanges => 'Publicar cambios';

  @override
  String get titleReadAloudNewAssistantMessages =>
      'Leer en voz alta los mensajes del asistente';

  @override
  String get titleRememberThis => 'Recordar esto';

  @override
  String get titleReminders => 'Recordatorios';

  @override
  String get titleRemindersAndRecurringPrompts =>
      'Recordatorios e instrucciones recurrentes';

  @override
  String get titleRemoveFriend => 'Eliminar amigo';

  @override
  String get titleRemoveMember => '¿Eliminar miembro?';

  @override
  String get titleReplyInTheLanguageYouSpeak =>
      'Responde en el idioma en el que hablas (modo conversación)';

  @override
  String get titleReportABugOrIdea => 'Informar de un error o idea';

  @override
  String get titleReportABugOrRequestA =>
      'Informar de un error o sugerir una funcionalidad';

  @override
  String get titleRequestPending => 'solicitud pendiente';

  @override
  String get titleRevertAllChanges => '¿Revertir todos los cambios?';

  @override
  String get titleSavePromptToLibrary => 'Guardar instrucción en la biblioteca';

  @override
  String get titleSaveStyle => 'Guardar estilo';

  @override
  String get titleSavedMemories => 'Recuerdos guardados';

  @override
  String get titleScheduledActions => 'Acciones programadas';

  @override
  String get titleScheduledRemindersAndCheckIns =>
      'Recordatorios y check-ins programados';

  @override
  String get titleSendFeedbackStraightToTheAdmins =>
      'Enviar comentarios directamente a los administradores';

  @override
  String get titleSendRequestsAndManageYourFriends =>
      'Enviar solicitudes y gestionar tus amigos';

  @override
  String get titleSetYourLocation => 'Establecer tu ubicación';

  @override
  String get titleShareCoarseLocation => 'Compartir mi ubicación';

  @override
  String get titleShowMessageMetadata => 'Mostrar metadatos del mensaje';

  @override
  String get titleShowSystemPromptInThread =>
      'Mostrar instrucción del sistema en el hilo';

  @override
  String get titleSignOut => 'Cerrar sesión';

  @override
  String get titleSkillsLibrary => 'Biblioteca de habilidades';

  @override
  String get titleSpeed => 'Velocidad';

  @override
  String get titleStartAConversationToPickTools =>
      'Empieza una conversación para elegir herramientas';

  @override
  String get titleStartAConversationToToggleInjection =>
      'Empieza una conversación para activar o desactivar la inyección';

  @override
  String get titleSystemAlerts => 'Alertas del sistema';

  @override
  String get titleSystemPrompt => 'Instrucción del sistema';

  @override
  String get titleTakePhoto => 'Hacer foto';

  @override
  String get titleTalkOverTheAiToInterrupt =>
      'Habla por encima de la IA para interrumpir (modo conversación)';

  @override
  String get titleTapToUpdateOrCorrect => 'Toca para actualizar o corregir';

  @override
  String get titleThisConversation => 'Esta conversación';

  @override
  String get titleTokenUsage => 'Uso de tokens';

  @override
  String get titleTools => 'Herramientas';

  @override
  String get titleUpdateNameAndEmail => 'Actualizar nombre y correo';

  @override
  String get titleUploadDocumentsForRetrievalAcrossChats =>
      'Sube documentos para recuperarlos entre chats';

  @override
  String get titleUseForNewChats => 'Usar para chats nuevos';

  @override
  String get titleUseKnowledgeBase => 'Usar base de conocimientos';

  @override
  String get titleUseMemory => 'Usar recuerdos';

  @override
  String get titleUsersModelsMcpServersReports =>
      'Usuarios, modelos, servidores MCP e informes';

  @override
  String get titleVoice => 'Voz';

  @override
  String get titleVoiceInterruption => 'Interrupción por voz';

  @override
  String get titleWhatTheAssistantHasLearnedAbout =>
      'Lo que el asistente ha aprendido sobre ti';

  @override
  String get titleYou => 'Tú';

  @override
  String get transport => 'Transporte';

  @override
  String get tryAgain => 'Volver a intentar';

  @override
  String ttsSpeedValue(String speed) {
    return '${speed}x';
  }

  @override
  String get unblock => 'Desbloquear';

  @override
  String get unexpectedError => 'Error inesperado';

  @override
  String get update => 'Actualizar';

  @override
  String updateToVersion(String releaseVersion) {
    return 'Actualizar a v$releaseVersion';
  }

  @override
  String get usedForNewChats => 'Usado para chats nuevos';

  @override
  String userCreatedMessage(String email) {
    return 'Usuario $email creado';
  }

  @override
  String get validationErrorRequired => 'Obligatorio';

  @override
  String get wantsToBeYourFriend => 'quiere ser tu amigo';

  @override
  String get showPassword => 'Mostrar contraseña';

  @override
  String get hidePassword => 'Ocultar contraseña';

  @override
  String get validatorEnterPassword => 'Introduce tu contraseña';

  @override
  String validatorPasswordMinLength(String length) {
    return 'La contraseña debe tener al menos $length caracteres';
  }

  @override
  String get validatorEnterEmail => 'Introduce tu correo electrónico';

  @override
  String get validatorEnterValidEmail =>
      'Introduce un correo electrónico válido';

  @override
  String get validatorEnterAnEmail => 'Introduce un correo electrónico';

  @override
  String get validatorNameRequired => 'El nombre es obligatorio';

  @override
  String get validatorUrlRequired =>
      'Se requiere URL para los transportes HTTP/SSE';

  @override
  String get validatorCommandRequired =>
      'Se requiere comando para el transporte stdio';

  @override
  String get tooltipRefresh => 'Actualizar';

  @override
  String get tooltipMore => 'Más';

  @override
  String get tooltipSetStatus => 'Establecer estado';

  @override
  String get tooltipStyleOptions => 'Opciones de estilo';

  @override
  String get tooltipTestConnection => 'Probar conexión';

  @override
  String get tooltipEdit => 'Editar';

  @override
  String get tooltipDeleteLongPress => 'Eliminar (mantener pulsado)';

  @override
  String get tooltipStopEditing => 'Dejar de editar';

  @override
  String get tooltipClosePanel => 'Cerrar panel';

  @override
  String get tooltipNew => 'Nuevo';

  @override
  String get tooltipCloseSettings => 'Cerrar ajustes';

  @override
  String get tooltipFriendActions => 'Acciones de amigo';

  @override
  String get tooltipCancelRequest => 'Cancelar solicitud';

  @override
  String get tooltipAcceptShare => 'Aceptar compartición';

  @override
  String get tooltipDeclineShare => 'Rechazar compartición';

  @override
  String get tooltipAccept => 'Aceptar';

  @override
  String get tooltipDecline => 'Rechazar';

  @override
  String get labelOff => 'Apagado';

  @override
  String get labelLow => 'Bajo';

  @override
  String get labelMedium => 'Medio';

  @override
  String get labelHigh => 'Alto';

  @override
  String get labelThinkingAuto => 'auto';

  @override
  String get monogramPlaceholder => '?';

  @override
  String get labelNewBadge => 'NUEVO';

  @override
  String get messageNoReportsYet => 'Aún no hay informes';

  @override
  String messageNoReportsWithStatus(String status) {
    return 'No hay informes $status';
  }

  @override
  String get messageNoMcpServersConfigured =>
      'No hay servidores MCP configurados';

  @override
  String get messageUsePlusButtonToAddOne => 'Usa el botón + para añadir uno.';

  @override
  String get messageTapSyncToDiscoverModels =>
      'Toca el botón de sincronizar para descubrir modeles del proveedor.';

  @override
  String get messageUnmute => 'Activar micrófono';

  @override
  String get messageMute => 'Silenciar micrófono';

  @override
  String get messageEndCall => 'Finalizar llamada';

  @override
  String get messageTapToStart => 'Toca para empezar';

  @override
  String get messageListening => 'Escuchando…';

  @override
  String get messageTranscribing => 'Transcribiendo…';

  @override
  String get messageThinking => 'Pensando…';

  @override
  String get messageSpeakingTapToInterrupt => 'Hablando… toca para interrumpir';

  @override
  String get messageSpeakingTalkOrTapToInterrupt =>
      'Hablando… habla o toca para interrumpir';

  @override
  String get messageTapCircleToRetry => 'Toca el círculo para reintentar';

  @override
  String get messageAuto => 'Auto';

  @override
  String get messageReplyLanguageAuto => 'Idioma de respuesta: Auto';

  @override
  String messageReplyLanguageNamed(String language) {
    return 'Idioma de respuesta: $language';
  }

  @override
  String labelCouldNotUpdateWithError(String error) {
    return 'No se ha podido actualizar: $error';
  }

  @override
  String messageTestingServer(String name) {
    return 'Probando $name…';
  }

  @override
  String messageTestOkToolsAvailable(int count) {
    return 'OK: $count herramientas disponibles';
  }

  @override
  String messageTestFailed(String error) {
    return 'Error: $error';
  }

  @override
  String get messageUnknownError => 'error desconocido';

  @override
  String get messageSyncingModels => 'Sincronizando modelos del proveedor…';

  @override
  String messageModelsSyncedCount(int count) {
    return '$count modelos sincronizados';
  }

  @override
  String messageUserCreated(String email) {
    return 'Usuario $email creado';
  }

  @override
  String get labelOpen => 'Abierto';

  @override
  String get labelInProgress => 'En curso';

  @override
  String get labelClosed => 'Cerrado';

  @override
  String get statusOpen => 'abierto';

  @override
  String get statusInProgress => 'en_curso';

  @override
  String get statusClosed => 'cerrado';

  @override
  String get messageOpenReports => 'No hay informes abiertos';

  @override
  String get messageInProgressReports => 'No hay informes en curso';

  @override
  String get messageClosedReports => 'No hay informes cerrados';

  @override
  String get labelVision => 'Visión';

  @override
  String get labelTools => 'Herramientas';

  @override
  String get labelThinking => 'Razonamiento';

  @override
  String get tooltipVisionUnknown => 'Visión desconocida para este modelo';

  @override
  String get tooltipToolsUnknown =>
      'Herramientas desconocidas para este modelo';

  @override
  String get tooltipThinkingUnknown =>
      'Razonamiento desconocido para este modelo';

  @override
  String get labelLowSensitivity => 'Baja sensibilidad';

  @override
  String get labelHighSensitivity => 'Alta sensibilidad';

  @override
  String get labelBargeInOff => 'Apagado';

  @override
  String get labelByModel => 'Por modelo';

  @override
  String get labelByDay => 'Por día';

  @override
  String get labelByConversation => 'Por conversación';

  @override
  String get labelTokens => 'Tokens';

  @override
  String get labelMessages => 'Mensajes';

  @override
  String get messageNoDataForPeriod => 'No hay datos para este periodo';

  @override
  String get titleUsageByModel => 'Por modelo';

  @override
  String get titleUsageByDay => 'Por día';

  @override
  String get titleUsageByConversation => 'Por conversación';

  @override
  String get labelEnabled => 'Activado';

  @override
  String get labelStdio => 'stdio';

  @override
  String get labelCommand => 'Comando';

  @override
  String get messageAdminPanelSubtitle =>
      'Usuarios, modelos, servidores MCP, informes';

  @override
  String get messageAllowAdminPrivileges =>
      'Permitir a este usuario gestionar usuarios y servidores MCP';

  @override
  String get messageDisabledServersIgnored =>
      'Los servidores desactivados son ignorados por el agente';

  @override
  String get titleProfile => 'Perfil';

  @override
  String get titleModels => 'Modelos';

  @override
  String get titleMemory => 'Memoria';

  @override
  String get titleSoftwareUpdate => 'Actualización de software';

  @override
  String messageServerFallback(String model) {
    return 'Fallback del servidor (normalmente $model)';
  }

  @override
  String get messageNotSetUsingDefaults =>
      'No establecido — usando valores predeterminados integrados';

  @override
  String get messageSavedMemoriesHint =>
      'Los recuerdos se gestionan desde la pantalla de chat a través de la página de memoria. Abre el chat para revisarlos, editarlos o eliminarlos.';

  @override
  String get messageNoSavedStylesHint =>
      'Aún no hay estilos guardados. Compón un modelo, nivel de razonamiento e instrucción en Personalizar, luego guarda la combinación para cambiar en un toque.';

  @override
  String get labelSaveChanges => 'Guardar cambios';

  @override
  String messageStyleModelNotInstalled(String modelId) {
    return '$modelId no está instalado';
  }

  @override
  String get messageNotSupportedByThisModel => 'No compatible con este modelo';

  @override
  String get messageNoModelsAvailable => 'No hay modelos disponibles.';

  @override
  String get messageCustomPromptReplacesTemplate =>
      'Esta conversación tiene un prompt personalizado. Elegir una plantilla lo reemplaza.';

  @override
  String messageEditingStyle(String name) {
    return 'Editando \"$name\"';
  }

  @override
  String get messageStopUsingForNewChats => 'Dejar de usar para chats nuevos';

  @override
  String get labelCustomize => 'Personalizar';

  @override
  String get messageGenerateHint =>
      'Describe lo que quieres que haga la instrucción:';

  @override
  String get messageRefineDraft => 'Refinar borrador';

  @override
  String get hintSarcasticCodingMentor =>
      'p. ej. Un mentor de programación sarcástico que da respuestas cortas';

  @override
  String get messageGenerating => 'Generando…';

  @override
  String get messageGenerationFailed => 'Generación fallida';

  @override
  String get messageCouldNotLoadModels => 'No se han podido cargar los modelos';

  @override
  String get messageEveryoneAndAllAgents => 'Todos y todos los agentes';

  @override
  String get messageAgent => 'Agente';

  @override
  String get messageBranch => 'Rama';

  @override
  String get messageCopyMessageToClipboard => 'Copiar mensaje al portapapeles';

  @override
  String get messageRegenerate => 'Regenerar';

  @override
  String get messageDeleteThisResponse =>
      'Eliminar esta respuesta y generar una nueva';

  @override
  String get messageSpeak => 'Leer';

  @override
  String get messageCopied => '¡Copiado!';

  @override
  String get messageCouldNotReachServer =>
      'No se pudo contactar al servidor — revisa tu conexión e inténtalo de nuevo.';

  @override
  String messageContextWindow(String used, String total) {
    return 'Ventana de contexto: $used de $total tokens usados';
  }

  @override
  String get messageAbove80PercentSummarized =>
      'Por encima del 80%, los mensajes antiguos se resumen para liberar espacio.';

  @override
  String messageCouldNotSubmit(String error) {
    return 'No se ha podido enviar: $error';
  }

  @override
  String get messageEmailUpdatedSignInAgain =>
      'Correo electrónico actualizado. Vuelve a iniciar sesión con la nueva dirección.';

  @override
  String get messageChangingEmailSignsYouOut =>
      'Cambiar el correo electrónico cierra la sesión';

  @override
  String get messageNoFriendsYet =>
      'Aún no tienes amigos. Envía una solicitud por correo electrónico arriba.';

  @override
  String get titleIncomingRequests => 'Solicitudes entrantes';

  @override
  String get titleSharedWithYou => 'Compartido contigo';

  @override
  String get titleSentRequests => 'Solicitudes enviadas';

  @override
  String get titleYourFriends => 'Tus amigos';

  @override
  String get titleBlocked => 'Bloqueados';

  @override
  String get messageAddAFriend => 'Añadir un amigo';

  @override
  String messageBlockEmailConfirmation(String email) {
    return '¿Bloquear a $email? Se elimina cualquier amistad o solicitud pendiente entre vosotros, y ninguno de los dos puede enviar nuevas solicitudes o añadir al otro a salas. Puedes desbloquearlo más tarde.';
  }

  @override
  String messageRemoveFriendConfirmation(String name) {
    return '¿Eliminar a $name de tus amigos? Puedes enviar una nueva solicitud más tarde.';
  }

  @override
  String messageYouAreNowFriendsWith(String email) {
    return 'Ahora eres amigo de $email';
  }

  @override
  String messageFriendRequestSentTo(String email) {
    return 'Solicitud de amistad enviada a $email';
  }

  @override
  String get labelStyleNoun => 'estilo';

  @override
  String get labelPromptTemplateNoun => 'plantilla de instrucción';

  @override
  String messageItemAddedToYourNouns(String name, String noun) {
    return '\"$name\" se ha añadido a tus ${noun}s';
  }

  @override
  String get titleConfirmAction => '¿Confirmar acción?';

  @override
  String get labelConversation => 'Conversación';

  @override
  String get labelAlways => 'Siempre';

  @override
  String get messageBackToChat => 'Volver al chat';

  @override
  String get titleSearchResults => 'Resultados de búsqueda';

  @override
  String messageNoResultsFor(String query) {
    return 'No hay resultados para \"$query\"';
  }

  @override
  String get messageSearchHint => 'Introduce una consulta de búsqueda';

  @override
  String get messageEveryToolEnabled =>
      'Todas las herramientas disponibles están activadas';

  @override
  String get titleEnabledTools => 'Herramientas activadas';

  @override
  String get titleAvailableTools => 'Herramientas disponibles';

  @override
  String get messageCouldNotReachServerPleaseTryAgain =>
      'No se ha podido contactar con el servidor. Inténtalo de nuevo.';

  @override
  String get labelConnection => 'Conexión';

  @override
  String get messageCityCountry => 'Ciudad, País';

  @override
  String messageCityLevelOnly(String location) {
    return 'Solo a nivel de ciudad, compartido como $location';
  }

  @override
  String get labelLocation => 'Ubicación';

  @override
  String get messageNoDocumentsHint =>
      'Sube documentos para recuperarlos en todos los chats.';

  @override
  String messageCouldNotLoadConversation(String error) {
    return 'No se ha podido cargar la conversación: $error';
  }

  @override
  String messageCouldNotLoadConversations(String error) {
    return 'No se han podido cargar las conversaciones: $error';
  }

  @override
  String messageCouldNotLoadOlderMessages(String error) {
    return 'No se han podido cargar mensajes anteriores: $error';
  }

  @override
  String messageCouldNotCreateConversation(String error) {
    return 'No se ha podido crear la conversación: $error';
  }

  @override
  String messageCouldNotDeleteConversation(String error) {
    return 'No se ha podido eliminar la conversación: $error';
  }

  @override
  String messageCouldNotRegenerate(String error) {
    return 'No se ha podido regenerar: $error';
  }

  @override
  String messageCouldNotBranch(String error) {
    return 'No se ha podido ramificar la conversación: $error';
  }

  @override
  String messageCouldNotPinConversation(String error) {
    return 'No se ha podido fijar la conversación: $error';
  }

  @override
  String messageCouldNotReloadConversation(String error) {
    return 'No se ha podido recargar la conversación: $error';
  }

  @override
  String get messageNoConversationsYet => 'Aún no hay conversaciones.';

  @override
  String get messageNoRoomsYet => 'Aún no hay salas.';

  @override
  String get messageStartAConversation => 'Iniciar una conversación';

  @override
  String get messageExplainQuantumComputing =>
      'Explica la computación cuántica en términos sencillos';

  @override
  String get messageAttachOrDragFiles =>
      'Adjunta o arrastra PDFs, hojas de cálculo, código e imágenes.';

  @override
  String get messageAttachPhotosOrFiles => 'Adjuntar fotos o archivos';

  @override
  String messageDuplicateFile(String name) {
    return 'Archivo duplicado: $name';
  }

  @override
  String get messageNewerVersionAvailable =>
      'Hay una versión más reciente disponible';

  @override
  String get messageCheckingForUpdates => 'Buscando actualizaciones…';

  @override
  String get messageDownloadingUpdate => 'Descargando actualización…';

  @override
  String get messageDownloadedArchiveEmpty =>
      'El archivo descargado está vacío';

  @override
  String get messageUpdateFailed => 'Actualización fallida';

  @override
  String get messageInstallFailed => 'Instalación fallida';

  @override
  String get labelError => 'Error';

  @override
  String get labelDismiss => 'Descartar';

  @override
  String get messageDismissed => 'Descartado';

  @override
  String get tooltipCopy => 'Copiar';

  @override
  String get tooltipBranch => 'Rama';

  @override
  String get tooltipRegenerate => 'Regenerar';

  @override
  String get tooltipCopyMessage => 'Copiar mensaje al portapapeles';

  @override
  String get messageDeleteResponseRegenerate =>
      'Eliminar esta respuesta y generar una nueva';

  @override
  String get messageRegenerateTitle => 'Regenerar';

  @override
  String get tooltipSpeak => 'Leer';

  @override
  String get messageDragToPan =>
      'Arrastra para desplazar • Doble toque para restablecer';

  @override
  String get messageDropFilesToAttach => 'Suelta archivos para adjuntar';

  @override
  String get labelCamera => 'Cámara';

  @override
  String get labelGallery => 'Galería';

  @override
  String get labelFile => 'Archivo';

  @override
  String get messageDeleteConversationConfirmation =>
      '¿Eliminar esta conversación?';

  @override
  String get messageConversationStyleUpdated =>
      'Estilo de conversación actualizado';

  @override
  String get messageChangeConversationStyle =>
      '¿Cambiar el estilo de conversación?';

  @override
  String messageCalling(String name) {
    return 'Llamando a $name…';
  }

  @override
  String get messageConnectionLost => 'Conexión perdida.';

  @override
  String get messageDeactivate => 'Desactivar';

  @override
  String get messageCreateMemory => 'Crear recuerdo';

  @override
  String get titleCreateMemoryAction => 'Crear recuerdo';

  @override
  String get titleEditMemoryAction => 'Editar recuerdo';

  @override
  String get titleDeleteMemoryAction => 'Eliminar recuerdo';

  @override
  String messageDeleteMemoryConfirmation(String content) {
    return '¿Seguro que quieres eliminar este recuerdo?\n\n\"$content\"';
  }

  @override
  String get messageCreateNewMemory => 'Crear nuevo recuerdo';

  @override
  String get messageNoMemoriesYet => 'Aún no hay recuerdos.';

  @override
  String get titleRoomMembers => 'Miembros';

  @override
  String get titleRoomAgents => 'Agentes';

  @override
  String get messageCreateRoom =>
      'Crea salas donde varios agentes de IA (y personas) conversan juntos.';

  @override
  String get messageCreateARoomQuestion => '¿Crear una sala?';

  @override
  String get messageAgentName => 'Agente';

  @override
  String get messageRoomOwner => 'Propietario';

  @override
  String get messageEveryone => 'Todos';

  @override
  String get messageMentionAll => '@all';

  @override
  String get messageUnnamed => '(sin nombre)';

  @override
  String get messageNoRoomMessagesYet => 'Aún no hay mensajes.';

  @override
  String get messageRoomMuted => 'Silenciado';

  @override
  String get tooltipRoomInfo => 'Información de la sala';

  @override
  String get tooltipLeaveRoom => 'Salir de la sala';

  @override
  String get tooltipRoomMenu => 'Menú de la sala';

  @override
  String get messageDeleteRoom => 'Eliminar sala';

  @override
  String get messageLeaveRoom => 'Salir de la sala';

  @override
  String get messageInviteSent => 'Invitación enviada';

  @override
  String get messageNoModels => 'Sin modelos';

  @override
  String get messageNoTools => 'Sin herramientas';

  @override
  String tooltipSharePromptWithFriend(String name) {
    return 'Compartir \"$name\" con un amigo';
  }

  @override
  String tooltipEditTemplate(String name) {
    return 'Editar \"$name\"';
  }

  @override
  String tooltipDeleteTemplate(String name) {
    return 'Eliminar \"$name\"';
  }

  @override
  String get messageEditSystemPrompt => 'Editar instrucción del sistema';

  @override
  String get messageEditMemory => 'Editar recuerdo';

  @override
  String get messageEditScheduledAction => 'Editar acción programada';

  @override
  String get messageEditThisMessage =>
      'Editar este mensaje y reejecutar la conversación desde aquí';

  @override
  String get messageEmailRequired => 'El correo electrónico es obligatorio';

  @override
  String get messageFullNameRequired => 'El nombre completo es obligatorio';

  @override
  String get messageCurrentPasswordRequired =>
      'Se requiere la contraseña actual';

  @override
  String get messageNewPasswordRequired => 'Se requiere una nueva contraseña';

  @override
  String get messagePasswordsDoNotMatch => 'Las contraseñas no coinciden';

  @override
  String get messageProfileUpdated => 'Perfil actualizado';

  @override
  String get messageFailedToUpdateProfile => 'Error al actualizar el perfil';

  @override
  String get messageFailedToChangePassword => 'Error al cambiar la contraseña';

  @override
  String get messageFailedToUpdateLocation =>
      'Error al actualizar la ubicación';

  @override
  String get labelMonthNames =>
      'ene.,feb.,mar.,abr.,may.,jun.,jul.,ago.,sept.,oct.,nov.,dic.';

  @override
  String messageMonthDayYearTime(
    String month,
    String day,
    String year,
    String hour,
    String minute,
    String amPm,
  ) {
    return '$day de $month de $year • $hour:$minute $amPm';
  }

  @override
  String get labelOneWeek => '1 semana';

  @override
  String get labelEightHours => '8 horas';

  @override
  String get labelForever => 'para siempre';

  @override
  String get labelUnmute => 'desilenciar';

  @override
  String get messageMute1Week => 'Silenciado durante 1 semana';

  @override
  String get messageMute8Hours => 'Silenciado durante 8 horas';

  @override
  String get messageMutedForever => 'Silenciado para siempre';

  @override
  String get messageUnmuted => 'Desilenciado';

  @override
  String titleMutedUntil(String time) {
    return 'Silenciado hasta $time';
  }

  @override
  String get labelSystemDefault => 'Predeterminado del sistema';

  @override
  String get messageActivate => 'Activar';

  @override
  String get tooltipEditMemory => 'Editar recuerdo';

  @override
  String get tooltipDeleteMemory => 'Eliminar recuerdo';

  @override
  String get tooltipDeactivateMemory => 'Desactivar recuerdo';

  @override
  String get tooltipActivateMemory => 'Activar recuerdo';

  @override
  String get labelImage => 'Imagen';

  @override
  String get labelAudio => 'Audio';

  @override
  String get labelVideo => 'Vídeo';

  @override
  String get labelDocument => 'Documento';

  @override
  String get messageTool => 'herramienta';

  @override
  String get messageBlockMath => 'matemáticas en bloque';

  @override
  String get messageInlineMath => 'matemáticas en línea';

  @override
  String get messageDragToPanDoubleTapReset =>
      'Arrastra para desplazar • Doble toque para restablecer';

  @override
  String get messageDropFilesHere => 'Suelta archivos para adjuntar';

  @override
  String get labelBytes => 'bytes';

  @override
  String get labelClose => 'Cerrar';

  @override
  String messageFailedToRenderDiagramWithError(String error) {
    return 'Error al renderizar el diagrama: $error';
  }

  @override
  String messageCouldNotLoadDiagram(String error) {
    return 'No se ha podido cargar el diagrama: $error';
  }

  @override
  String messageParseFailedForTool(String tool) {
    return 'Error al analizar $tool';
  }

  @override
  String get labelRetry => 'Reintentar';

  @override
  String get labelDone => 'Hecho';

  @override
  String get labelLoading => 'Cargando…';

  @override
  String get labelDeviceBusy => 'Dispositivo o recurso ocupado';

  @override
  String messageMicrophoneUnavailable(String error) {
    return 'Micrófono no disponible: $error';
  }

  @override
  String messageCouldNotTranscribe(String error) {
    return 'No se ha podido transcribir: $error';
  }

  @override
  String get messageDidntCatchThat => 'No te he entendido — inténtalo de nuevo';

  @override
  String get messageCouldNotResolveLocation =>
      'No se ha podido determinar tu ubicación';

  @override
  String get messageFailedToResolveLocation =>
      'Error al determinar tu ubicación';

  @override
  String get labelOr => 'o';

  @override
  String get labelOnline => 'en línea';

  @override
  String get messageCallingX => 'Llamando a X…';

  @override
  String get messageRevertAllChangesWarning =>
      'Descarta todos los cambios no confirmados en tu espacio de trabajo. Esto no se puede deshacer.';

  @override
  String get labelRemember => 'Recordar';

  @override
  String get messageRememberDescription =>
      'Guarda este contenido como un recuerdo para futura referencia:';

  @override
  String get messageMemorySaved => 'Recuerdo guardado correctamente';

  @override
  String messageFailedToSaveMemory(String error) {
    return 'No se pudo guardar el recuerdo: $error';
  }

  @override
  String messageRecording(String duration) {
    return 'Grabando $duration';
  }

  @override
  String messageFailedToDeleteRoom(String error) {
    return 'No se pudo eliminar la sala: $error';
  }

  @override
  String get labelUndo => 'Deshacer';

  @override
  String messageModelNotInstalled(String modelId) {
    return '$modelId no está instalado';
  }

  @override
  String get messageNoSavedStylesYet =>
      'Aún no hay estilos guardados. Compón un modelo, nivel de razonamiento e instrucción en Personalizar, luego guarda la combinación para cambiar con un toque.';

  @override
  String messageEditing(String name) {
    return 'Editando \"$name\"';
  }

  @override
  String messageFilesTooLarge(String files) {
    return 'Archivos demasiado grandes:\n$files';
  }

  @override
  String get titleTheme => 'Tema';

  @override
  String get titleDisplaySystemPrompt =>
      'Muestra el prompt de sistema activo sobre la conversación';

  @override
  String get messageNoMcpToolsAvailable =>
      'No hay herramientas MCP disponibles. Configura un servidor desde el panel de Admin.';

  @override
  String messageNToolsEnabled(int selected, int total) {
    return '$selected de $total herramientas activas';
  }

  @override
  String get messageNoModelSelected => 'Ningún modelo seleccionado';

  @override
  String messageUsingSource(String source) {
    return 'Usando: $source';
  }

  @override
  String get messageAppliedToEveryNewConversation =>
      'Se aplica a cada conversación nueva a menos que se anule por chat.';

  @override
  String get messageNoToolsAvailableConfigureMcp =>
      'No hay herramientas disponibles. Configura primero un servidor MCP.';

  @override
  String messageNoToolsMatchQuery(String query) {
    return 'Ninguna herramienta coincide con \"$query\".';
  }

  @override
  String messageToolCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count herramientas',
      one: '$count herramienta',
    );
    return '$_temp0';
  }

  @override
  String get messageNoScheduledActionsYet => 'Aún no hay acciones programadas';

  @override
  String get messageUsePlusButton =>
      'Usa el botón + para crear un recordatorio o una verificación recurrente.';

  @override
  String messageCronExpression(String expr) {
    return 'Cron: $expr';
  }

  @override
  String messageRemoveScheduledAction(String title) {
    return '¿Eliminar \"$title\"? Esto no se puede deshacer.';
  }

  @override
  String get titleNewScheduledAction => 'Nueva acción programada';

  @override
  String get titleEditScheduledAction => 'Editar acción programada';

  @override
  String get hintMorningStandup => 'Reunión matutina';

  @override
  String get helperCronExpression => 'min hora día mes día_semana';

  @override
  String get hintPickDateTime => 'Elige fecha y hora';

  @override
  String messageCreatedAt(String date) {
    return 'Creado $date';
  }

  @override
  String messageUpdateToVersion(String version) {
    return 'Actualizar a v$version';
  }

  @override
  String messageUpdateRestartAfterInstall(String currentVersion) {
    return 'Tienes v$currentVersion. La aplicación se reinicia tras instalar.';
  }

  @override
  String messageLatestRelease(String version) {
    return 'Última versión: v$version';
  }

  @override
  String messageUpdateAvailable(String version) {
    return 'Garbanzo AI v$version está disponible';
  }

  @override
  String messageAssistantKnowsLocation(String location) {
    return 'El asistente sabe que estás cerca de $location';
  }

  @override
  String get titlePhotos => 'Fotos';

  @override
  String get titleFiles => 'Archivos';

  @override
  String get titleFolder => 'Carpeta';

  @override
  String messageFolderScope(String name) {
    return 'Leyendo archivos en $name';
  }

  @override
  String get messageRemoveFolder => 'Quitar carpeta';

  @override
  String get messageFolderAttachFailed => 'No se pudo adjuntar esa carpeta';

  @override
  String get titleDelegateWorkflow => '¿Delegar esta tarea?';

  @override
  String messageWorkflowScope(String name) {
    return 'Trabaja sobre una copia de $name';
  }

  @override
  String get messageWorkflowStarting => 'Iniciando…';

  @override
  String get messageWorkflowScanning => 'Explorando la carpeta…';

  @override
  String get messageWorkflowUploading => 'Subiendo la carpeta…';

  @override
  String messageWorkflowRunningIn(String name) {
    return 'El agente está trabajando en $name…';
  }

  @override
  String get messageWorkflowRunning => 'El agente está trabajando…';

  @override
  String get messageWorkflowKeepsRunning =>
      'Sigue en marcha aunque cierres la app: te avisaremos.';

  @override
  String get messageWorkflowDone => 'Tarea completada';

  @override
  String get messageWorkflowFailed => 'La tarea falló';

  @override
  String get messageWorkflowNeedsFolder =>
      'Primero adjunta una carpeta a este chat.';

  @override
  String get actionReviewChanges => 'Revisar cambios';

  @override
  String get titleWorkflowChanges => 'Revisar cambios';

  @override
  String get messageWorkflowNoChanges => 'La tarea no modificó ningún archivo.';

  @override
  String messageWorkflowApplyWarning(String path) {
    return 'Los archivos seleccionados se escribirán en $path.';
  }

  @override
  String messageWorkflowFilesSkipped(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count archivos eran demasiado grandes para enviarlos: el agente no los verá',
      one: '1 archivo era demasiado grande para enviarlo: el agente no lo verá',
    );
    return '$_temp0';
  }

  @override
  String get messageWorkflowFolderTruncated =>
      'La carpeta es demasiado grande para enviarla entera: solo se incluyó una parte.';

  @override
  String get messageWorkflowTooLarge => 'Demasiado grande para aplicar';

  @override
  String messageWorkflowApplied(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos aplicados',
      one: '1 archivo aplicado',
    );
    return '$_temp0';
  }

  @override
  String get messageWorkflowConflicts =>
      'Omitidos: cambiaron en el disco mientras la tarea se ejecutaba:';

  @override
  String get messageWorkflowFailedFiles => 'No se pudo escribir:';

  @override
  String get labelFileAdded => 'Añadido';

  @override
  String get labelFileModified => 'Modificado';

  @override
  String get labelFileDeleted => 'Eliminado';

  @override
  String get labelDismissed => 'Descartado';

  @override
  String actionApplySelected(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Aplicar $count archivos',
      one: 'Aplicar 1 archivo',
    );
    return '$_temp0';
  }

  @override
  String get messageWorkflowApplying => 'Aplicando cambios a tu carpeta…';

  @override
  String messageWorkflowAppliedShort(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count archivos aplicados a tu carpeta',
      one: '1 archivo aplicado a tu carpeta',
      zero: 'Ningún archivo cambiado',
    );
    return '$_temp0';
  }

  @override
  String get messageWorkflowConflictsLabel => 'Omitido (cambió en el disco):';

  @override
  String get messageWorkflowFailedFilesLabel => 'No se pudo escribir:';

  @override
  String get messageSttUnavailable =>
      'La conversación de voz a texto no está disponible en el servidor.';

  @override
  String get messageTranscriptionFailed =>
      'La transcripción falló — inténtalo de nuevo.';

  @override
  String messageDeleteStyle(String name) {
    return '¿Eliminar \"$name\"?';
  }

  @override
  String get messageSaveChangesToStyle => 'Guardar cambios';

  @override
  String messageModelNameFallback(String modelId, String modelName) {
    return '$modelId / $modelName';
  }

  @override
  String messageDeleteStyleConfirmation(String name) {
    return '¿Eliminar \"$name\"?';
  }

  @override
  String get messageMemoriesStoreFactsHint =>
      'Los recuerdos guardan datos importantes sobre ti\npara conversaciones más personalizadas';

  @override
  String get messageSourceConversation => 'Origen: Conversación';

  @override
  String get messageTypeMessageToBegin =>
      'Escribe un mensaje abajo para empezar a chatear';

  @override
  String get messageWriteAPythonFunction => 'Escribe una función en Python';

  @override
  String get messageWriteAPythonFunctionPrompt =>
      'Escribe una función en Python para calcular el factorial';

  @override
  String get messageHelpMeDebugCode => 'Ayúdame a depurar código';

  @override
  String get messageHelpMeDebugCodePrompt =>
      'Necesito ayuda para depurar código';

  @override
  String get titleGettingStarted => 'Primeros pasos';

  @override
  String get tipVoiceInputTitle => 'Entrada de voz';

  @override
  String get tipVoiceInputBody =>
      'Toca el micrófono para dictar — tu voz se transcribe localmente.';

  @override
  String get tipFilesAndImagesTitle => 'Archivos e imágenes';

  @override
  String get tipFilesAndImagesBody =>
      'Adjunta o arrastra PDFs, hojas de cálculo, código e imágenes.';

  @override
  String get tipMemoryTitle => 'Recuerdos';

  @override
  String get tipMemoryBody =>
      'El asistente aprende datos sobre ti con el tiempo — revísalos cuando quieras en Ajustes → Recuerdos.';

  @override
  String get tipKnowledgeBaseTitle => 'Base de conocimientos';

  @override
  String get tipKnowledgeBaseBody =>
      'Sube documentos una vez y haz preguntas sobre ellos en cualquier chat.';

  @override
  String get tipRoomsTitle => 'Salas';

  @override
  String get tipRoomsBody =>
      'Crea salas donde varios agentes de IA (y personas) conversan juntos.';

  @override
  String get tooltipTimeRange => 'Rango de tiempo';

  @override
  String messageNoUsageInLastDays(int days) {
    return 'Sin uso en los últimos $days días';
  }

  @override
  String get messageStartAConversationTokensHint =>
      'Empieza una conversación para ver tu consumo de tokens aquí.';

  @override
  String messageDailyTokensDays(int days) {
    return 'Tokens diarios ($days días)';
  }

  @override
  String get titleByConversation => 'Conversaciones destacadas';

  @override
  String get labelTotalTokens => 'Tokens totales';

  @override
  String get labelGenerated => 'Generados';

  @override
  String get messageUntitled => 'Sin título';

  @override
  String messageModelBreakdown(String prompt, String generated, int count) {
    return '$prompt in · $generated out · $count msgs';
  }

  @override
  String messagePromptGeneratedInOut(String prompt, String generated) {
    return '$prompt in · $generated out';
  }

  @override
  String get tooltipOpenConversations => 'Abrir conversaciones';

  @override
  String get tooltipSearchConversations => 'Buscar conversaciones';

  @override
  String get labelMicroApp => 'Micro-app';

  @override
  String get tooltipReopenMicroAppPanel => 'Reabrir el panel de la micro-app';

  @override
  String tooltipReopenApp(String name) {
    return 'Reabrir $name';
  }

  @override
  String messageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count mensajes',
      one: '$count mensaje',
    );
    return '$_temp0';
  }

  @override
  String get hintSystemPromptExample =>
      'p. ej. Eres un asistente conciso y directo. Da respuestas breves y fácticas con ejemplos.';

  @override
  String get messageCityLevelOnlyHint =>
      'Comparte tu zona a nivel de barrio, para que las preguntas \"cerca de mí\" (como restaurantes cercanos) funcionen. Tus coordenadas exactas nunca se guardan.';

  @override
  String get messageNotifyAssistantBackground =>
      'Notificar cuando el asistente responde con la app en segundo plano';

  @override
  String get messageUpdatesCheckedAtStart =>
      'Las actualizaciones se comprueban al iniciar la app';

  @override
  String get messageUpToDate => 'Estás actualizado';

  @override
  String get messageInstallAppRestart => 'Instalando — la app se reiniciará';

  @override
  String get messageUpdateCheckFailed =>
      'La comprobación de actualizaciones falló';

  @override
  String get messageNoBuildForPlatform => 'Sin build para esta plataforma';

  @override
  String get tooltipRedetectLocation =>
      'Redetectar desde la ubicación del dispositivo';

  @override
  String get hintTypeAMessage => 'Escribe un mensaje…';

  @override
  String get messageRoomEmptyHint =>
      'Escribe un mensaje para empezar. Usa @AgentName para llamar a un agente, o @all para mencionar a todos.';

  @override
  String get titleMyMcpServers => 'Mis servidores MCP';

  @override
  String get messagePersonalMcpServersHint =>
      'Conecta tus propios servidores de herramientas. Solo tú puedes verlos y usarlos; los administradores gestionan los servidores compartidos para todos.';

  @override
  String get labelAddServer => 'Añadir servidor';
}
