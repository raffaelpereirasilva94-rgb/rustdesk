import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/desktop/pages/desktop_home_page.dart';
import 'package:flutter_hbb/desktop/pages/desktop_setting_page.dart';
import 'package:flutter_hbb/desktop/widgets/mr_client_panel.dart';
import 'package:flutter_hbb/desktop/widgets/mr_technician_panel.dart';
import 'package:flutter_hbb/desktop/widgets/tabbar_widget.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/state_model.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';
// import 'package:flutter/services.dart';

import '../../common/shared_state.dart';

class DesktopTabPage extends StatefulWidget {
  const DesktopTabPage({Key? key}) : super(key: key);

  @override
  State<DesktopTabPage> createState() => _DesktopTabPageState();

  static bool get usesMrClientWindow => useMrClientLayout;

  // Called before the native main window is shown, after restoring its position.
  // Do not let the generic desktop startup re-enable resizing afterwards.
  static Future<void> prepareMrClientWindow() async {
    if (useMrTechnicianLayout) {
      await windowManager.setResizable(true);
      await windowManager.setMaximizable(true);
      if (!await windowManager.isMaximized()) {
        final size = await windowManager.getSize();
        // The shared native profile may remember the compact client window.
        if (size.width < 900 || size.height < 560) {
          await windowManager.setSize(const Size(1100, 650));
        }
      }
      return;
    }
    if (!usesMrClientWindow) return;
    await applyMrClientWindowMode(home: true);
  }

  static Future<void> applyMrClientWindowMode({required bool home}) async {
    if (home) {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      }
      await windowManager.setMaximizable(false);
      await windowManager.setResizable(false);
      await windowManager.setSize(mrClientWindowSize);
    } else {
      await windowManager.setResizable(true);
      await windowManager.setMaximizable(true);
      await windowManager.setSize(getIncomingOnlySettingsSize());
    }
  }

  static void onAddSetting(
      {SettingsTabKey initialPage = SettingsTabKey.general}) {
    try {
      DesktopTabController tabController = Get.find<DesktopTabController>();
      tabController.add(TabInfo(
          key: kTabLabelSettingPage,
          label: kTabLabelSettingPage,
          selectedIcon: Icons.build_sharp,
          unselectedIcon: Icons.build_outlined,
          page: DesktopSettingPage(
            key: const ValueKey(kTabLabelSettingPage),
            initialTabkey: initialPage,
          )));
      // add() suppresses onSelected for unrestricted desktop builds.
      // The internal client preview still needs the same expanded window.
      if (usesMrClientWindow && !bind.isIncomingOnly()) {
        tabController.onSelected?.call(kTabLabelSettingPage);
      }
    } catch (e) {
      debugPrintStack(label: '$e');
    }
  }
}

class _DesktopTabPageState extends State<DesktopTabPage> {
  final tabController = DesktopTabController(tabType: DesktopTabType.main);

  _DesktopTabPageState() {
    RemoteCountState.init();
    Get.put<DesktopTabController>(tabController);
    tabController.add(TabInfo(
        key: kTabLabelHomePage,
        label: kTabLabelHomePage,
        selectedIcon: Icons.home_sharp,
        unselectedIcon: Icons.home_outlined,
        closable: false,
        page: DesktopHomePage(
          key: const ValueKey(kTabLabelHomePage),
        )));
    if (useMrClientLayout) {
      tabController.onSelected = (_) => _queueMrClientWindowMode();
    } else if (bind.isIncomingOnly()) {
      tabController.onSelected = (key) {
        if (key == kTabLabelHomePage) {
          windowManager.setSize(getIncomingOnlyHomeSize());
          setResizable(false);
        } else {
          windowManager.setSize(getIncomingOnlySettingsSize());
          setResizable(true);
        }
      };
    }
  }

  Future<void> _windowModeQueue = Future<void>.value();

  // Serialize native operations so rapid tab switches cannot leave the
  // compact window with the expanded tab's resize/maximize permissions.
  void _queueMrClientWindowMode() {
    _windowModeQueue = _windowModeQueue.then((_) async {
      if (!mounted || !useMrClientLayout) return;
      await DesktopTabPage.applyMrClientWindowMode(home: isInHomePage());
    }).catchError((Object error, StackTrace stack) {
      debugPrint('MR Client window mode: $error');
    });
  }

  /*
  bool _handleKeyEvent(KeyEvent event) {
    if (!mouseIn && event is KeyDownEvent) {
      print('key down: ${event.logicalKey}');
      shouldBeBlocked(_block, canBeBlocked);
    }
    return false; // allow it to propagate
  }
  */

  @override
  void dispose() {
    // HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    Get.delete<DesktopTabController>();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tabWidget = Container(
        child: Scaffold(
            backgroundColor: Theme.of(context).colorScheme.background,
            body: DesktopTab(
              controller: tabController,
              mainHomeHeader: useMrClientLayout
                  ? MrClientHeader(
                      onSettings: bind.isDisableSettings()
                          ? null
                          : () => DesktopTabPage.onAddSetting(),
                    )
                  : useMrTechnicianLayout
                      ? const SizedBox.shrink()
                      : null,
              tail: Offstage(
                offstage: bind.isIncomingOnly() || bind.isDisableSettings(),
                child: ActionIcon(
                  message: 'Settings',
                  icon: IconFont.menu,
                  onTap: DesktopTabPage.onAddSetting,
                  isClose: false,
                ),
              ),
            )));
    return isMacOS || kUseCompatibleUiMode
        ? tabWidget
        : Obx(
            () => DragToResizeArea(
              resizeEdgeSize: useMrClientLayout && isInHomePage()
                  ? 0.0
                  : stateGlobal.resizeEdgeSize.value,
              enableResizeEdges: useMrClientLayout && isInHomePage()
                  ? const <ResizeEdge>[]
                  : windowManagerEnableResizeEdges,
              child: tabWidget,
            ),
          );
  }
}
