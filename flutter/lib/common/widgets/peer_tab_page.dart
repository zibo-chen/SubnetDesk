import 'package:flutter/material.dart';
import 'package:flutter_hbb/common/widgets/peers_view.dart';
import 'package:flutter_hbb/models/peer_tab_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:provider/provider.dart';

/// Local-only peer history and discovery. Cloud address books and groups are
/// intentionally not constructed in the LAN-only product.
class PeerTabPage extends StatelessWidget {
  const PeerTabPage({
    Key? key,
    this.selectedIndex,
    this.showTabs = true,
  }) : super(key: key);

  final int? selectedIndex;
  final bool showTabs;

  @override
  Widget build(BuildContext context) {
    final model = Provider.of<PeerTabModel>(context, listen: false);
    final currentIndex = (selectedIndex ?? model.currentTab).clamp(0, 2);
    if (!showTabs) {
      return switch (currentIndex) {
        0 => RecentPeersView(),
        1 => FavoritePeersView(),
        _ => DiscoveredPeersView(),
      };
    }
    return DefaultTabController(
      length: 3,
      initialIndex: currentIndex,
      child: Column(
        children: [
          TabBar(
            tabs: const [
              Tab(icon: Icon(Icons.access_time_filled)),
              Tab(icon: Icon(Icons.star)),
              Tab(icon: Icon(Icons.explore)),
            ],
            onTap: (index) async {
              model.setCurrentTab(index);
              switch (index) {
                case 0:
                  bind.mainLoadRecentPeers();
                  break;
                case 1:
                  bind.mainLoadFavPeers();
                  break;
                case 2:
                  bind.mainLoadLanPeers();
                  break;
              }
            },
          ),
          Expanded(
            child: TabBarView(
              children: [
                RecentPeersView(),
                FavoritePeersView(),
                DiscoveredPeersView(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
