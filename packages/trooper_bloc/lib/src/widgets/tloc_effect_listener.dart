import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:trooper_bloc/src/effects/effects.dart';

/// Signature for effect listener callbacks.
typedef EffectWidgetListener<F> = void Function(BuildContext context, F effect);

/// Flutter widget that listens to one-off presentation [effects] emitted by a [Tloc] or [Tubit].
///
/// Executes [onEffect] in response to each emitted effect without causing widget rebuilds.
///
/// ### Example:
/// ```dart
/// TlocEffectListener<ProfileTloc, ProfileEffect>(
///   onEffect: (context, effect) => switch (effect) {
///     ShowToastEffect(:final message) => ScaffoldMessenger.of(context).showSnackBar(
///       SnackBar(content: Text(message)),
///     ),
///   },
///   child: const ProfileScreen(),
/// )
/// ```
class TlocEffectListener<B extends Effects<F>, F> extends StatefulWidget {
  /// Creates a [TlocEffectListener].
  const TlocEffectListener({
    required this.onEffect,
    required this.child,
    this.bloc,
    this.listenWhen,
    super.key,
  });

  /// Callback executed whenever an effect of type [F] is emitted.
  final EffectWidgetListener<F> onEffect;

  /// Optional condition callback to determine if [onEffect] should be called.
  final bool Function(F effect)? listenWhen;

  /// Optional explicit instance of [B]. If omitted, resolves [B] from the widget tree via [context.read].
  final B? bloc;

  /// The widget below this widget in the tree.
  final Widget child;

  @override
  State<TlocEffectListener<B, F>> createState() =>
      _TlocEffectListenerState<B, F>();
}

class _TlocEffectListenerState<B extends Effects<F>, F>
    extends State<TlocEffectListener<B, F>> {
  StreamSubscription<F>? _subscription;
  B? _resolvedBloc;

  @override
  void initState() {
    super.initState();
    _resolvedBloc = widget.bloc;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bloc = widget.bloc ?? context.read<B>();
    if (!identical(bloc, _resolvedBloc)) {
      _resolvedBloc = bloc;
      _subscribe();
    } else if (_subscription == null) {
      _subscribe();
    }
  }

  @override
  void didUpdateWidget(TlocEffectListener<B, F> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.bloc, oldWidget.bloc)) {
      _resolvedBloc = widget.bloc ?? context.read<B>();
      _subscribe();
    }
  }

  void _subscribe() {
    _subscription?.cancel();
    _subscription = _resolvedBloc?.effects.listen((effect) {
      if (mounted) {
        if (widget.listenWhen == null || widget.listenWhen!(effect)) {
          widget.onEffect(context, effect);
        }
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
