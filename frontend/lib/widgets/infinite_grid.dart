import 'package:flutter/material.dart';

import '../api/models.dart';
import '../design/tokens.dart';
import 'poster_grid.dart';
import 'states.dart';

/// A poster grid that lazily loads more results as you scroll (offset paging).
/// `fetchPage(offset, limit)` returns the next chunk; an empty result ends paging.
/// Changing [resetKey] (e.g. when filters change) reloads from the first page.
class InfiniteGrid extends StatefulWidget {
  const InfiniteGrid({
    super.key,
    required this.resetKey,
    required this.fetchPage,
    required this.itemBuilder,
    required this.empty,
    this.pageSize = 60,
  });

  final Object resetKey;
  final Future<List<SearchResult>> Function(int offset, int limit) fetchPage;
  final Widget Function(BuildContext context, SearchResult result) itemBuilder;
  final Widget empty;
  final int pageSize;

  @override
  State<InfiniteGrid> createState() => _InfiniteGridState();
}

class _InfiniteGridState extends State<InfiniteGrid> {
  final _scroll = ScrollController();
  final _items = <SearchResult>[];
  int _offset = 0;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _reset();
  }

  @override
  void didUpdateWidget(InfiniteGrid old) {
    super.didUpdateWidget(old);
    if (old.resetKey != widget.resetKey) _reset();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _reset() {
    setState(() {
      _items.clear();
      _offset = 0;
      _hasMore = true;
      _error = null;
    });
    _loadMore();
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 600) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.fetchPage(_offset, widget.pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _offset += widget.pageSize;
        if (page.isEmpty) _hasMore = false;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // First-page states.
    if (_items.isEmpty) {
      if (_loading) return const _Scroll(child: LoadingView());
      if (_error != null) return _Scroll(child: ErrorView(message: '$_error', onRetry: _reset));
      return _Scroll(child: widget.empty);
    }

    return RefreshIndicator(
      onRefresh: () async => _reset(),
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, Insets.sm),
            sliver: SliverGrid(
              gridDelegate: posterGridDelegate(context),
              delegate: SliverChildBuilderDelegate(
                (context, i) => widget.itemBuilder(context, _items[i]),
                childCount: _items.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.xxl),
              child: Center(
                child: _loading
                    ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                    : (_error != null
                        ? TextButton(onPressed: _loadMore, child: Text('$_error'))
                        : const SizedBox.shrink()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Scroll extends StatelessWidget {
  const _Scroll({required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [SizedBox(height: MediaQuery.sizeOf(context).height * 0.28), child],
      );
}
