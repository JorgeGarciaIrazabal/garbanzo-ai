/// Reasoning depth for thinking-capable models.
///
/// Mirrors the backend's `ThinkingLevel` literal (`off|low|medium|high`).
/// A `null` level everywhere means "provider default": thinking auto-enables
/// for models that advertise the capability. The UI labels that state "Auto".
enum ThinkingLevel { off, low, medium, high }

extension ThinkingLevelLabel on ThinkingLevel {
  /// Short human label for chips and the segmented control.
  String get label => switch (this) {
    ThinkingLevel.off => 'Off',
    ThinkingLevel.low => 'Low',
    ThinkingLevel.medium => 'Medium',
    ThinkingLevel.high => 'High',
  };
}
