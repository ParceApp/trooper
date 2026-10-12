import 'dart:async';
import 'package:trooper/trooper.dart';

/// Simple immutable data model representing a post.
class Post {
  const Post({
    required this.id,
    required this.title,
    required this.views,
  });

  final int id;
  final String title;
  final int views;

  @override
  String toString() => 'Post(id: $id, title: "$title", views: $views)';
}

/// Simulated remote API client with artificial latency and call tracking.
class MockBlogApi {
  int networkHits = 0;

  final List<Post> _database = [
    const Post(id: 1, title: 'Introduction to Trooper Architecture', views: 420),
    const Post(id: 2, title: 'Zero-Flicker SWR in Production', views: 890),
    const Post(id: 3, title: 'Request Deduplication Deep Dive', views: 230),
  ];

  Future<List<Post>> fetchFeed() async {
    networkHits++;
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return List<Post>.from(_database);
  }

  Future<Post> fetchPost(int id) async {
    networkHits++;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return _database.firstWhere(
      (p) => p.id == id,
      orElse: () => Post(id: id, title: 'Post #$id', views: 0),
    );
  }

  Future<Post> createPost(String title) async {
    networkHits++;
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final newPost = Post(
      id: _database.length + 1,
      title: title,
      views: 0,
    );
    _database.add(newPost);
    return newPost;
  }
}

/// Feature controller orchestrating queries, cache lifecycles, and mutations.
class BlogController extends TrooperController {
  BlogController(this._api);

  final MockBlogApi _api;

  // 1. Single cached query with 5-minute TTL, SWR revalidation, and retry policy
  late final feed = query<List<Post>, ()>(
    namespace: 'blog_feed',
    fetch: (_) => _api.fetchFeed(),
    config: const TrooperConfig(
      timeToLive: Duration(minutes: 5),
      retryPolicy: RetryPolicy.exponential(maxRetries: 3),
      timeout: Duration(seconds: 10),
    ),
  );

  // 2. Keyed query partitioned by post ID
  late final postDetails = keyedQuery<int, Post, ()>(
    namespace: 'post_details',
    fetch: (id, _) => _api.fetchPost(id),
    config: const TrooperConfig(timeToLive: Duration(hours: 1)),
  );

  // 3. In-memory local state tracking selected post ID
  late final selectedPostId = local<int?, ()>(
    namespace: 'selected_post_id',
    initialValue: null,
  );

  // 4. Command mutation that automatically invalidates the feed upon success
  late final publish = mutation<Post, ({String title})>(
    namespace: 'publish_post',
    action: (param) => _api.createPost(param.title),
    invalidateOnSuccess: [this],
  );
}

void main() async {
  print('====================================================');
  print('          TROOPER STATE-OF-THE-ART EXAMPLE          ');
  print('====================================================\n');

  final api = MockBlogApi();
  final controller = BlogController(api);

  // Step 0: Initialize controller lifecycle
  await controller.initialize();
  print('1. Controller initialized.\n');

  // Step 1: Subscribe to reactive stream via modern pattern matching
  final subscription = controller.feed.watch().listen((state) {
    switch (state) {
      case DataInitial():
        print('   [Stream Event] State: Idle (DataInitial)');
      case DataLoading():
        print('   [Stream Event] State: Initial fetch in-flight (DataLoading)');
      case DataRefreshing(:final data):
        print('   [Stream Event] State: SWR background refresh (DataRefreshing, ${data.length} items)');
      case DataLoaded(:final data):
        print('   [Stream Event] State: Data ready (DataLoaded, ${data.length} items)');
      case DataError(:final error):
        print('   [Stream Event] State: Error occurred ($error)');
    }
  });

  // Small delay to allow subscription to register
  await Future<void>.delayed(const Duration(milliseconds: 20));

  // Step 2: First read (Cold Start: Cache Miss -> Fetches from network)
  print('2. Requesting feed (Cold Read)...');
  final initialFeed = await controller.feed.get(const ());
  print('   Result: Loaded ${initialFeed.length} posts.');
  print('   Total Network Hits: ${api.networkHits}\n');

  // Step 3: Second read (Warm Read: Instant L1 Cache Hit in 0ms)
  print('3. Requesting feed again immediately (Warm Read)...');
  final stopwatch = Stopwatch()..start();
  final cachedFeed = await controller.feed.get(const ());
  stopwatch.stop();
  print('   Result: Served ${cachedFeed.length} posts from L1 cache in ${stopwatch.elapsedMicroseconds} µs.');
  print('   Total Network Hits: ${api.networkHits} (0 additional network calls!)\n');

  // Step 4: Keyed Query partitioned by entity ID
  print('4. Requesting keyed post details for ID 2...');
  final post2 = await controller.postDetails[2].get(const ());
  print('   Result: $post2');
  print('   Total Network Hits: ${api.networkHits}\n');

  // Step 5: Update local state
  print('5. Setting selected post ID in local state...');
  controller.selectedPostId.set(2, const ());
  print('   Selected Post ID: ${controller.selectedPostId.currentData()}\n');

  // Step 6: Execute a Mutation with automatic cache invalidation
  print('6. Publishing new post via mutation...');
  final newPost = await controller.publish((title: 'Reactive Micro-Frontends with Dart'));
  print('   Mutation succeeded: Created ${newPost.title} (ID: ${newPost.id})');
  print('   Notice: "feed" cache was invalidated automatically!\n');

  // Step 7: Read feed again after invalidation (Refetches fresh data)
  print('7. Requesting feed after mutation invalidation...');
  final refreshedFeed = await controller.feed.get(const ());
  print('   Result: Feed now contains ${refreshedFeed.length} posts.');
  print('   Total Network Hits: ${api.networkHits}\n');

  // Cleanup: Cancel subscription and dispose controller
  await subscription.cancel();
  await controller.dispose();
  print('8. Controller disposed cleanly. All resources freed.');
  print('====================================================');
}
