# Trooper Examples

This directory contains executable, runnable examples demonstrating the Trooper reactive data-flow and state management framework.

---

## Available Examples

| Example | Path | Focus Area | Description |
|---|---|---|---|
| **State of the Art** | [`main.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/example/main.dart) | Production Feature Controller | Full-fledged feature controller with queries, SWR revalidation, instant L1 cache hits, keyed collections, mutations with cache invalidation, and stream pattern matching. |
| **Simple Counter** | [`counter/main.dart`](file:///Users/hannes/Developer/trooper/packages/trooper/example/counter/main.dart) | Local State Management | Minimalist counter demonstrating `local` state, synchronous functional updates (`update`), resets, and reactive stream subscriptions. |

---

## 1. State of the Art Example (`main.dart`)

Demonstrates an end-to-end production blog architecture:

- **Queries with SWR & Retries**: `feed` query with 5-minute TTL, exponential backoff, and 10-second timeouts.
- **Instant L1 Cache Hits**: Subsequent calls return in microseconds without network traffic.
- **Keyed Collections**: `postDetails` partitioned by post ID via subscript syntax (`postDetails[id]`).
- **Command Mutations with Invalidation**: `publish` creates a post and automatically invalidates the `feed` query cache.
- **Pattern Matching**: Consuming `StatefulData` transitions (`DataInitial`, `DataLoading`, `DataLoaded`, `DataRefreshing`, `DataError`).

### Running the Example

From the package directory:

```bash
dart run example/main.dart
```

### Code Snippet

```dart
import 'package:trooper/trooper.dart';

class BlogController extends TrooperController {
  BlogController(this._api);
  final ApiService _api;

  // Cached query with SWR
  late final feed = query<List<Post>, ()>(
    namespace: 'blog_feed',
    fetch: (_) => _api.fetchFeed(),
    config: const TrooperConfig(timeToLive: Duration(minutes: 5)),
  );

  // Keyed query partitioned by post ID
  late final postDetails = keyedQuery<int, Post, ()>(
    namespace: 'post_details',
    fetch: (id, _) => _api.fetchPost(id),
  );

  // Mutation with automatic cache invalidation
  late final publish = mutation<Post, ({String title})>(
    namespace: 'publish_post',
    action: (param) => _api.createPost(param.title),
    invalidateOnSuccess: [this],
  );
}

void main() async {
  final controller = BlogController(api);
  await controller.initialize();

  // 1. Cold Read: Fetches from network
  final posts = await controller.feed.get(const ());

  // 2. Warm Read: Instant 0ms memory cache hit
  final cached = await controller.feed.get(const ());

  // 3. Keyed lookup
  final post = await controller.postDetails[1].get(const ());

  // 4. Mutation that auto-invalidates feed cache
  await controller.publish((title: 'Building scalable apps with Trooper'));

  await controller.dispose();
}
```

---

## 2. Simple Counter Example (`counter/main.dart`)

Demonstrates pure in-memory reactive state using `LocalTrooper`:

### Running the Example

```bash
dart run example/counter/main.dart
```

### Code Snippet

```dart
import 'package:trooper/trooper.dart';

class CounterController extends TrooperController {
  // Local state container initialized to 0
  late final count = local<int, ()>(
    namespace: 'counter_value',
    initialValue: 0,
  );

  void increment() => count.update((val) => val + 1, const ());
  void decrement() => count.update((val) => val - 1, const ());
  void reset() => count.reset(const ());
}

void main() async {
  final controller = CounterController();
  await controller.initialize();

  // Watch state changes
  controller.count.watch(initialParameter: ()).listen((state) {
    if (state case DataLoaded(:final data)) {
      print('Current count: $data');
    }
  });

  controller.increment(); // 1
  controller.increment(); // 2
  controller.decrement(); // 1
  controller.reset();     // 0

  await controller.dispose();
}
```
