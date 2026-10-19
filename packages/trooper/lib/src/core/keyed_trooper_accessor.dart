import 'dart:async';

import 'package:trooper/src/core/accessor.dart';
import 'package:trooper/src/core/keyed_accessor.dart';
import 'package:trooper/src/state/data_metadata.dart';
import 'package:trooper/src/state/stateful_data.dart';
import 'package:trooper/src/stream/keyed_stateful_stream.dart';
import 'package:trooper/src/stream/stateful_stream.dart';
import 'package:trooper/types/parameter.dart';

/// Concrete, unmodifiable implementation of [KeyedAccessor].
final class KeyedTrooperAccessor<K extends Object, T, P extends Parameter>
    implements KeyedAccessor<K, T, P> {
  /// Creates a [KeyedTrooperAccessor] delegating to the underlying [stream] and accessor callbacks.
  KeyedTrooperAccessor({
    required this.accessorFactory,
    required KeyedStatefulStream<K, T> stream,
    required this.onInvalidate,
    this.onInvalidateKey,
    this.onRead,
    this.onRefresh,
  }) : _keyedStream = stream;

  /// Factory resolving a single-key [Accessor].
  final Accessor<T, P> Function(K key) accessorFactory;

  /// Underlying keyed stream managing per-key state.
  final KeyedStatefulStream<K, T> _keyedStream;

  /// Callback to invalidate the collection.
  final void Function() onInvalidate;

  /// Optional callback to invalidate a single key across all parameters.
  final void Function(K key)? onInvalidateKey;

  /// Optional custom get handler for the entire map.
  final Future<Map<K, T>> Function()? onRead;

  /// Optional custom refresh handler for the entire map.
  final Future<Map<K, T>> Function()? onRefresh;

  @override
  Accessor<T, P> operator [](K key) => accessorFactory(key);

  @override
  void invalidateKey(K key) => onInvalidateKey?.call(key);

  @override
  void invalidateKeys(Iterable<K> keys) {
    for (final k in keys) {
      invalidateKey(k);
    }
  }

  @override
  Future<Map<K, T>> getAll(
    Iterable<K> keys,
    P parameter, {
    bool forceRefresh = false,
  }) async {
    final keyList = keys.toList();
    final results = await Future.wait(
      keyList.map((k) => this[k].get(parameter, forceRefresh: forceRefresh)),
    );
    return Map<K, T>.fromIterables(keyList, results);
  }

  @override
  Future<Map<K, T>> refreshKeys(Iterable<K> keys, P parameter) async {
    final keyList = keys.toList();
    final results = await Future.wait(
      keyList.map((k) => this[k].refresh(parameter)),
    );
    return Map<K, T>.fromIterables(keyList, results);
  }

  @override
  void triggerKeys(Iterable<K> keys, P parameter, {bool forceRefresh = false}) {
    for (final k in keys) {
      this[k].trigger(parameter, forceRefresh: forceRefresh);
    }
  }

  @override
  Map<K, T> get currentDataMap => _keyedStream.currentDataMap;

  @override
  Map<K, StatefulData<T>> get currentStates => _keyedStream.currentStates;

  @override
  Set<K> get activeKeys => _keyedStream.activeKeys;

  @override
  int get count => _keyedStream.count;

  @override
  Stream<Map<K, StatefulData<T>>> watchAll() => _keyedStream.watchAll();

  @override
  Stream<Set<K>> watchKeys() => _keyedStream.watchKeys();

  @override
  StatefulStream<Map<K, T>> get stream => StatefulStream<Map<K, T>>(
    _keyedStream.watchAll().map((_) => current()),
    currentStateProvider: () => current(),
  );

  @override
  StatefulStream<Map<K, T>> watch({()? initialParameter, bool eager = false}) =>
      stream;

  @override
  Future<Map<K, T>> get(() parameter, {bool forceRefresh = false}) async {
    if (forceRefresh && onRefresh != null) {
      return await onRefresh!();
    }
    if (onRead != null) {
      return await onRead!();
    }
    return currentDataMap;
  }

  @override
  Future<Map<K, T>> refresh(() parameter) async {
    if (onRefresh != null) {
      return await onRefresh!();
    }
    onInvalidate();
    return currentDataMap;
  }

  @override
  void trigger(() parameter, {bool forceRefresh = false}) {
    get(parameter, forceRefresh: forceRefresh).ignore();
  }

  @override
  StatefulData<Map<K, T>> current() {
    final data = currentDataMap;
    if (data.isEmpty) {
      return const DataInitial();
    }
    return DataLoaded(
      data,
      metadata: DataMetadata.now(source: DataSource.local),
    );
  }

  @override
  Map<K, T>? currentData() {
    final data = currentDataMap;
    return data.isEmpty ? null : data;
  }

  @override
  void invalidate() => onInvalidate();
}
