import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:garbanzo_ai/core/auth_service.dart';

/// Opt-in coarse location sharing (settings → Profile).
///
/// Off by default: sharing is on exactly when the server has a stored
/// location string. Enabling tries device geolocation (Android / web /
/// GeoClue on Linux) and sends the coordinates once to the backend, which
/// stores only the reverse-geocoded "City, Country" — precise coordinates
/// never persist anywhere. Wherever geolocation is unavailable or denied,
/// the flow falls back to typing a city manually, which doubles as the
/// edit affordance once sharing is on.
class LocationSection extends StatefulWidget {
  const LocationSection({
    super.key,
    required this.user,
    required this.onUserChanged,
  });

  final UserInfo? user;
  final VoidCallback onUserChanged;

  @override
  State<LocationSection> createState() => _LocationSectionState();
}

class _LocationSectionState extends State<LocationSection> {
  bool _busy = false;

  bool get _sharing => widget.user?.location != null;

  @override
  Widget build(BuildContext context) {
    final location = widget.user?.location;

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            key: const ValueKey('location_sharing_switch'),
            secondary: _busy
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.location_on_outlined),
            title: const Text('Share coarse location'),
            subtitle: Text(
              _sharing
                  ? 'The assistant knows you are near $location'
                  : 'City-level only, so "near me" questions work. '
                        'Precise coordinates are never stored.',
            ),
            value: _sharing,
            onChanged: _busy ? null : (on) => on ? _enable() : _disable(),
          ),
          if (_sharing) ...[
            const Divider(height: 1),
            ListTile(
              key: const ValueKey('location_edit_tile'),
              leading: const Icon(Icons.edit_location_alt_outlined),
              title: Text(location ?? ''),
              subtitle: const Text('Tap to update or correct'),
              trailing: IconButton(
                key: const ValueKey('location_refresh_button'),
                tooltip: 'Re-detect from device location',
                icon: const Icon(Icons.my_location),
                onPressed: _busy ? null : _enable,
              ),
              onTap: _busy ? null : _enterManually,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    try {
      final position = await _devicePosition();
      if (position == null) {
        // Geolocation unavailable (unsupported, off, or denied): fall back
        // to manual entry rather than dead-ending the toggle.
        if (mounted) await _enterManually();
        return;
      }
      final result = await AuthService.instance.setLocationFromCoordinates(
        latitude: position.latitude,
        longitude: position.longitude,
      );
      if (!mounted) return;
      if (result.success) {
        widget.onUserChanged();
      } else {
        _showError(result.error ?? 'Could not resolve your location');
        await _enterManually();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _disable() async {
    setState(() => _busy = true);
    try {
      final result = await AuthService.instance.setManualLocation(null);
      if (!mounted) return;
      if (result.success) {
        widget.onUserChanged();
      } else {
        _showError(result.error ?? 'Failed to update location');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Low-accuracy device position, or null when any step of the permission /
  /// service dance fails — callers treat null as "use manual entry".
  Future<Position?> _devicePosition() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      // City-level is the goal, so ask for the cheapest fix the platform has.
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _enterManually() async {
    final controller = TextEditingController(text: widget.user?.location ?? '');
    final city = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Set your location'),
        content: TextField(
          key: const ValueKey('location_manual_field'),
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'City',
            hintText: 'e.g. Madrid, Spain',
          ),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (city == null || city.trim().isEmpty || !mounted) return;
    final result = await AuthService.instance.setManualLocation(city);
    if (!mounted) return;
    if (result.success) {
      widget.onUserChanged();
    } else {
      _showError(result.error ?? 'Failed to update location');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
