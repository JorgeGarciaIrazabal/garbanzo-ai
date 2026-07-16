// Shared notification-mute semantics for rooms and conversations.
//
// Mirrors the backend's `app.services.mute_util`: NULL means "not muted",
// anything in the past has expired, and "muted forever" is encoded as a
// far-future sentinel timestamp (`MUTE_FOREVER`, `9999-12-31T23:59:59Z`)
// rather than a separate bool, so every reader only ever needs one
// comparison. Keep mute checks going through here so the sentinel never
// leaks into UI code as a literal date.

/// Mute durations understood by the backend mute endpoints (`PATCH
/// /rooms/{id}/members/me/mute`, `PATCH /chat/conversations/{id}/mute`).
const muteDuration8h = '8h';
const muteDuration1w = '1w';
const muteDurationForever = 'forever';
const muteDurationUnmute = 'unmute';

/// Whether a `muted_until` value is still in effect.
bool isMuteActive(DateTime? mutedUntil, {DateTime? now}) =>
    mutedUntil != null && mutedUntil.isAfter(now ?? DateTime.now());

/// Whether [mutedUntil] is the "muted forever" sentinel rather than a real
/// expiry the UI should print.
///
/// Compares on year alone so tz normalization or sub-second drift on the wire
/// can't turn "Always" into a literal year-9999 date.
bool isMuteForever(DateTime? mutedUntil) =>
    mutedUntil != null && mutedUntil.toUtc().year >= 9999;

/// Human-readable mute status, e.g. "Muted until 14:30" / "Muted always".
///
/// Never prints the forever-sentinel's literal year-9999 date. [now] is
/// injectable so tests can pin the "is it today?" decision.
String muteStatusLabel(DateTime? mutedUntil, {DateTime? now}) {
  if (!isMuteActive(mutedUntil, now: now)) return 'Not muted';
  if (isMuteForever(mutedUntil)) return 'Muted always';
  return 'Muted until ${_formatUntil(mutedUntil!, now ?? DateTime.now())}';
}

/// Local-time formatting consistent with `room_message_bubble._formatTime`;
/// a date prefix is added once the expiry is off today (an "8h" mute can land
/// tomorrow, a "1w" one always does).
String _formatUntil(DateTime until, DateTime now) {
  final local = until.toLocal();
  final time = '${_two(local.hour)}:${_two(local.minute)}';
  final sameDay =
      local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  if (sameDay) return time;
  return '${_months[local.month - 1]} ${local.day}, $time';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');
