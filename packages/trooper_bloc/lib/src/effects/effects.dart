import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

/// Mixin adding one-off presentation effect capabilities (snackbars, dialogs, navigation)
/// to a `Tloc` or `Tubit`.
///
/// Eliminates the need for external presentation packages or boilerplate `NoActions` types.
///
/// ### Example:
/// ```dart
/// sealed class ProfileEffect {
///   const ProfileEffect();
/// }
///
/// class ShowToastEffect extends ProfileEffect {
///   const ShowToastEffect(this.message);
///   final String message;
/// }
///
/// class ProfileTloc extends Tloc<ProfileEvent, ProfileState> with Effects<ProfileEffect> {
///   ...
///   void onUserSave() {
///     emitEffect(const ShowToastEffect('Profile updated!'));
///   }
/// }
/// ```
mixin Effects<F> {
  StreamController<F>? _effectsController;

  /// Reactive stream of one-off presentation effects.
  Stream<F> get effects {
    _effectsController ??= StreamController<F>.broadcast();
    return _effectsController!.stream;
  }

  /// Emits a one-off presentation [effect] to active listeners.
  ///
  /// Ignored if the host component is already closed.
  @protected
  void emitEffect(F effect) {
    if (_isHostClosed) return;
    _effectsController ??= StreamController<F>.broadcast();
    _effectsController!.add(effect);
  }

  bool get _isHostClosed {
    final dynamic self = this;
    if (self is BlocBase) {
      return self.isClosed;
    }
    return false;
  }

  /// Closes the internal effects stream controller.
  @mustCallSuper
  Future<void> close() async {
    await _effectsController?.close();
    _effectsController = null;
  }
}
