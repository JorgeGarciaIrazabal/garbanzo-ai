import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:garbanzo_ai/features/rooms/models/room_models.dart';
import 'package:garbanzo_ai/features/rooms/providers/room_provider.dart';
import 'package:garbanzo_ai/features/rooms/services/room_service.dart';
import 'package:garbanzo_ai/features/rooms/widgets/mute_room_sheet.dart';
import 'package:garbanzo_ai/features/rooms/widgets/rooms_list_view.dart';

class _MockRoomService extends Mock implements RoomService {}

final _now = DateTime.utc(2026, 7, 11);

/// The far-future value the backend stores for "muted forever"
/// (`room_service.MUTE_FOREVER`).
final _foreverSentinel = DateTime.utc(9999, 12, 31, 23, 59, 59);

RoomMember _member({DateTime? mutedUntil}) => RoomMember(
      roomId: 'r1',
      userId: 'me@x.com',
      role: 'member',
      joinedAt: _now,
      mutedUntil: mutedUntil,
    );

Room _room({String id = 'r1', String name = 'Room One', DateTime? mutedUntil}) =>
    Room(
      id: id,
      name: name,
      ownerId: 'owner@x.com',
      isPublic: false,
      maxAgentTurnDepth: 3,
      mode: 'chat',
      createdAt: _now,
      updatedAt: _now,
      memberCount: 1,
      agentCount: 0,
      mutedUntil: mutedUntil,
    );

void main() {
  group('mute state', () {
    test('a null muted_until is not muted', () {
      expect(_member().isMuted, isFalse);
      expect(isMuteActive(null), isFalse);
    });

    test('an expired muted_until is not muted', () {
      final past = DateTime.now().subtract(const Duration(hours: 1));
      expect(_member(mutedUntil: past).isMuted, isFalse);
    });

    test('a future muted_until is muted', () {
      final future = DateTime.now().add(const Duration(hours: 8));
      expect(_member(mutedUntil: future).isMuted, isTrue);
    });

    test('the year-9999 sentinel is muted, and muted forever', () {
      final m = _member(mutedUntil: _foreverSentinel);
      expect(m.isMuted, isTrue);
      expect(m.isMutedForever, isTrue);
    });

    test('a timed mute is not a forever mute', () {
      final m = _member(mutedUntil: DateTime.now().add(const Duration(days: 7)));
      expect(m.isMuted, isTrue);
      expect(m.isMutedForever, isFalse);
    });

    test('fromJson maps muted_until, tolerating its absence', () {
      RoomMember parse(Map<String, dynamic> extra) => RoomMember.fromJson({
            'room_id': 'r1',
            'user_id': 'me@x.com',
            'role': 'member',
            'joined_at': _now.toIso8601String(),
            ...extra,
          });

      expect(parse(const {}).mutedUntil, isNull);
      expect(parse(const {'muted_until': null}).mutedUntil, isNull);
      expect(
        parse({'muted_until': _foreverSentinel.toIso8601String()}).isMutedForever,
        isTrue,
      );
    });

    test('the forever sentinel never renders as a literal year-9999 date', () {
      final label = muteStatusLabel(_foreverSentinel);
      expect(label, 'Muted always');
      expect(label, isNot(contains('9999')));
    });

    test('a same-day mute renders wall-clock time only', () {
      // `now` is pinned: a real clock near midnight would roll the expiry into
      // the next day and flip the label to the dated form.
      final now = DateTime(2026, 7, 15, 9, 0);
      final until = DateTime(2026, 7, 15, 14, 30);
      expect(muteStatusLabel(until, now: now), 'Muted until 14:30');
    });

    test('a mute landing on another day gets a date prefix', () {
      final now = DateTime(2026, 7, 15, 22, 0);
      final until = DateTime(2026, 7, 22, 6, 5);
      expect(muteStatusLabel(until, now: now), 'Muted until Jul 22, 06:05');
    });

    test('an expired mute reports not muted', () {
      final now = DateTime(2026, 7, 15, 9, 0);
      expect(muteStatusLabel(DateTime(2026, 7, 14), now: now), 'Not muted');
      expect(muteStatusLabel(null, now: now), 'Not muted');
    });

    test('Room.memberFor finds the local user, else null', () {
      final room = Room(
        id: 'r1',
        name: 'Room One',
        ownerId: 'owner@x.com',
        isPublic: false,
        maxAgentTurnDepth: 3,
        mode: 'chat',
        createdAt: _now,
        updatedAt: _now,
        memberCount: 1,
        agentCount: 0,
        members: [_member(mutedUntil: _foreverSentinel)],
      );
      expect(room.memberFor('me@x.com')?.isMuted, isTrue);
      expect(room.memberFor('someone@else.com'), isNull);
      expect(room.memberFor(null), isNull);
    });

    test('Room.isMuted reads the top-level muted_until from the list payload',
        () {
      expect(_room().isMuted, isFalse, reason: 'defaults to null/unmuted');
      expect(_room(mutedUntil: _foreverSentinel).isMuted, isTrue);
      expect(
        _room(mutedUntil: DateTime.now().subtract(const Duration(days: 1)))
            .isMuted,
        isFalse,
        reason: 'expired',
      );
      expect(
        _room(mutedUntil: DateTime.now().add(const Duration(hours: 8)))
            .isMuted,
        isTrue,
      );
    });

    test(
        'Room.fromJson maps the list payload\'s muted_until independently of '
        'members', () {
      final room = Room.fromJson({
        'id': 'r1',
        'name': 'Room One',
        'owner_id': 'owner@x.com',
        'is_public': false,
        'max_agent_turn_depth': 3,
        'mode': 'chat',
        'created_at': _now.toIso8601String(),
        'updated_at': _now.toIso8601String(),
        'member_count': 1,
        'agent_count': 0,
        'muted_until': _foreverSentinel.toIso8601String(),
      });
      expect(room.isMuted, isTrue);
      expect(room.members, isEmpty, reason: 'RoomOut carries no members');
    });

    test(
        'withViewerMutedUntil updates the top-level field and the matching '
        'member without touching others', () {
      final other = RoomMember(
        roomId: 'r1',
        userId: 'other@x.com',
        role: 'member',
        joinedAt: _now,
      );
      final room = Room(
        id: 'r1',
        name: 'Room One',
        ownerId: 'owner@x.com',
        isPublic: false,
        maxAgentTurnDepth: 3,
        mode: 'chat',
        createdAt: _now,
        updatedAt: _now,
        memberCount: 2,
        agentCount: 0,
        members: [_member(), other],
      );

      final updated = room.withViewerMutedUntil(
        'me@x.com',
        _foreverSentinel,
      );

      expect(updated.isMuted, isTrue);
      expect(updated.memberFor('me@x.com')?.isMuted, isTrue);
      expect(
        updated.memberFor('other@x.com')?.mutedUntil,
        isNull,
        reason: 'unrelated members are left alone',
      );
    });
  });

  group('RoomProvider.setMute', () {
    test(
        'adopts the server-returned expiry and updates the listed Room '
        'rather than guessing it', () async {
      final service = _MockRoomService();
      final serverExpiry = DateTime.now().toUtc().add(const Duration(hours: 8));
      when(() => service.listRooms()).thenAnswer((_) async => [_room()]);
      when(() => service.setMute(any(), any()))
          .thenAnswer((_) async => _member(mutedUntil: serverExpiry));

      final provider = RoomProvider(service: service);
      await provider.loadRooms();
      expect(
        provider.rooms.single.isMuted,
        isFalse,
        reason: 'list payload starts unmuted',
      );

      var notified = 0;
      provider.addListener(() => notified++);
      await provider.setMute('r1', muteDuration8h);

      verify(() => service.setMute('r1', '8h')).called(1);
      expect(provider.rooms.single.isMuted, isTrue);
      expect(provider.rooms.single.mutedUntil, serverExpiry);
      expect(notified, greaterThan(0));

      provider.dispose();
    });

    test('unmute clears the listed Room state', () async {
      final service = _MockRoomService();
      when(() => service.listRooms()).thenAnswer((_) async => [_room()]);
      when(() => service.setMute(any(), 'forever'))
          .thenAnswer((_) async => _member(mutedUntil: _foreverSentinel));
      when(() => service.setMute(any(), 'unmute'))
          .thenAnswer((_) async => _member());

      final provider = RoomProvider(service: service);
      await provider.loadRooms();
      await provider.setMute('r1', muteDurationForever);
      expect(provider.rooms.single.isMuted, isTrue);

      await provider.setMute('r1', muteDurationUnmute);
      expect(provider.rooms.single.isMuted, isFalse);
      expect(provider.rooms.single.mutedUntil, isNull);

      provider.dispose();
    });

    test(
        'a failing request surfaces the error and leaves the listed Room '
        'untouched', () async {
      final service = _MockRoomService();
      when(() => service.listRooms()).thenAnswer((_) async => [_room()]);
      when(() => service.setMute(any(), any())).thenThrow(Exception('boom'));

      final provider = RoomProvider(service: service);
      await provider.loadRooms();
      await provider.setMute('r1', muteDuration8h);

      expect(provider.error, contains('boom'));
      expect(provider.rooms.single.isMuted, isFalse);

      provider.dispose();
    });
  });

  group('mute sheet', () {
    Widget host(
      List<Room> rooms, {
      void Function(Room, String)? onMute,
    }) =>
        MaterialApp(
          home: Scaffold(
            body: RoomsListView(
              rooms: rooms,
              onSelect: (_) {},
              onDelete: (_) {},
              onMute: onMute,
            ),
          ),
        );

    testWidgets('long-press opens the sheet and the choice calls back',
        (tester) async {
      final calls = <(String, String)>[];
      await tester.pumpWidget(host(
        [_room()],
        onMute: (room, duration) => calls.add((room.id, duration)),
      ));

      await tester.longPress(find.text('Room One'));
      await tester.pumpAndSettle();

      // Not muted yet, so unmute isn't offered.
      expect(find.text('8 hours'), findsOneWidget);
      expect(find.text('1 week'), findsOneWidget);
      expect(find.text('Always'), findsOneWidget);
      expect(find.text('Unmute'), findsNothing);

      await tester.tap(find.text('8 hours'));
      await tester.pumpAndSettle();

      expect(calls, [('r1', '8h')]);
    });

    testWidgets('a muted room offers unmute and shows its status', (tester) async {
      final calls = <(String, String)>[];
      await tester.pumpWidget(host(
        [_room(mutedUntil: _foreverSentinel)],
        onMute: (room, duration) => calls.add((room.id, duration)),
      ));

      // The list entry carries the muted-bell glyph.
      expect(find.byKey(const ValueKey('room_muted_glyph')), findsOneWidget);

      await tester.longPress(find.text('Room One'));
      await tester.pumpAndSettle();

      expect(find.text('Muted always'), findsOneWidget);
      expect(find.textContaining('9999'), findsNothing);
      expect(find.text('Unmute'), findsOneWidget);

      await tester.tap(find.text('Unmute'));
      await tester.pumpAndSettle();

      expect(calls, [('r1', 'unmute')]);
    });

    testWidgets('an unmuted room shows no bell glyph', (tester) async {
      await tester.pumpWidget(host([_room()]));
      expect(find.byKey(const ValueKey('room_muted_glyph')), findsNothing);
    });

    testWidgets('an expired mute shows no bell glyph', (tester) async {
      await tester.pumpWidget(host(
        [_room(mutedUntil: DateTime.now().subtract(const Duration(days: 1)))],
      ));
      expect(find.byKey(const ValueKey('room_muted_glyph')), findsNothing);
    });

    testWidgets('dismissing the sheet applies nothing', (tester) async {
      final calls = <(String, String)>[];
      await tester.pumpWidget(host(
        [_room()],
        onMute: (room, duration) => calls.add((room.id, duration)),
      ));

      await tester.longPress(find.text('Room One'));
      await tester.pumpAndSettle();
      expect(find.text('8 hours'), findsOneWidget);

      await tester.tapAt(const Offset(400, 50)); // barrier
      await tester.pumpAndSettle();

      expect(calls, isEmpty);
    });

    testWidgets('without onMute, long-press does nothing', (tester) async {
      await tester.pumpWidget(host([_room()]));

      await tester.longPress(find.text('Room One'));
      await tester.pumpAndSettle();

      expect(find.text('8 hours'), findsNothing);
    });
  });
}
