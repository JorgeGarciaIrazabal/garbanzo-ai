import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:garbanzo_ai/core/auth_service.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Opt-in location sharing (settings → Profile).
///
/// Off by default: sharing is on exactly when the server has a stored
/// location string. Enabling tries device geolocation (Android / web /
/// GeoClue on Linux) and sends the coordinates once to the backend, which
/// stores only the reverse-geocoded "Neighbourhood, City, Country" — precise
/// coordinates never persist anywhere. Wherever geolocation is unavailable or
/// denied, the flow falls back to typing a location manually, which doubles as
/// the edit affordance once sharing is on.
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
            title: Text(AppLocalizations.of(context)!.titleShareCoarseLocation),
            subtitle: Text(
              _sharing
                  ? AppLocalizations.of(
                      context,
                    )!.messageAssistantKnowsLocation('$location')
                  : AppLocalizations.of(context)!.messageCityLevelOnlyHint,
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
              subtitle: Text(
                AppLocalizations.of(context)!.titleTapToUpdateOrCorrect,
              ),
              trailing: IconButton(
                key: const ValueKey('location_refresh_button'),
                tooltip: AppLocalizations.of(context)!.tooltipRedetectLocation,
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
        _showError(
          result.error ??
              AppLocalizations.of(context)!.messageCouldNotResolveLocation,
        );
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
        _showError(
          result.error ??
              AppLocalizations.of(context)!.messageFailedToResolveLocation,
        );
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
      // Neighbourhood-level is the goal (precise enough for "restaurants near
      // me"), so ask for a medium fix — low is too coarse to resolve a suburb.
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
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
        title: Text(AppLocalizations.of(context)!.titleSetYourLocation),
        content: TextField(
          key: const ValueKey('location_manual_field'),
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.labelCity,
            hintText: AppLocalizations.of(context)!.hintEGMadridSpain,
          ),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(AppLocalizations.of(context)!.save),
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
