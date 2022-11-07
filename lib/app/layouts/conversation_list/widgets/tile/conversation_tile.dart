import 'dart:async';

import 'package:bluebubbles/helpers/types/constants.dart';
import 'package:bluebubbles/helpers/types/helpers/message_helper.dart';
import 'package:bluebubbles/helpers/ui/ui_helpers.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/app/layouts/conversation_list/pages/conversation_list.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/cupertino_conversation_tile.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/material_conversation_tile.dart';
import 'package:bluebubbles/app/layouts/conversation_list/widgets/tile/samsung_conversation_tile.dart';
import 'package:bluebubbles/app/layouts/conversation_view/pages/conversation_view.dart';
import 'package:bluebubbles/app/widgets/avatars/contact_avatar_group_widget.dart';
import 'package:bluebubbles/app/widgets/message_widget/typing_indicator.dart';
import 'package:bluebubbles/app/widgets/theme_switcher/theme_switcher.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/main.dart';
import 'package:bluebubbles/services/ui/chat/chat_lifecycle_manager.dart';
import 'package:bluebubbles/services/ui/chat/chat_manager.dart';
import 'package:bluebubbles/services/backend_ui_interop/event_dispatcher.dart';
import 'package:bluebubbles/models/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:universal_html/html.dart' as html;

class ConversationTileController extends StatefulController {
  final RxBool shouldHighlight = false.obs;
  final RxBool shouldPartialHighlight = false.obs;
  final RxBool hoverHighlight = false.obs;
  final Chat chat;
  final ConversationListController listController;
  final Function(bool)? onSelect;
  final bool inSelectMode;
  final Widget? subtitle;

  bool get isSelected => listController.selectedChats
      .firstWhereOrNull((e) => e.guid == chat.guid) != null;

  ConversationTileController({
    Key? key,
    required this.chat,
    required this.listController,
    this.onSelect,
    this.inSelectMode = false,
    this.subtitle,
  });

  void onTap(BuildContext context) {
    if ((inSelectMode || listController.selectedChats.isNotEmpty) && onSelect != null) {
      onLongPress();
    } else {
      ns.pushAndRemoveUntil(
        context,
        ConversationView(
          chat: chat,
        ),
        (route) => route.isFirst,
      );
    }
  }

  Future<void> onSecondaryTap(BuildContext context, TapUpDetails details) async {
    if (kIsWeb) {
      (await html.document.onContextMenu.first).preventDefault();
    }
    shouldPartialHighlight.value = true;
    await showConversationTileMenu(
      context,
      this,
      chat,
      details.globalPosition,
      context.textTheme,
    );
    shouldPartialHighlight.value = false;
  }

  void onLongPress() {
    onSelected();
    HapticFeedback.lightImpact();
  }
  
  void onSelected() {
    if (ss.settings.skin.value == Skins.Material) {
      updateWidgetFunctions[MaterialConversationTile]?.call(null);
    }
    if (ss.settings.skin.value == Skins.Samsung) {
      updateWidgetFunctions[SamsungConversationTile]?.call(null);
    }
    onSelect!.call(!isSelected);
  }
}

class ConversationTile extends CustomStateful<ConversationTileController> {
  ConversationTile({
    Key? key,
    required Chat chat,
    required ConversationListController controller,
    Function(bool)? onSelect,
    bool inSelectMode = false,
    Widget? subtitle,
  }) : super(key: key, parentController: Get.isRegistered<ConversationTileController>(tag: chat.guid)
      ? Get.find<ConversationTileController>(tag: chat.guid)
      : Get.put(ConversationTileController(
        chat: chat,
        listController: controller,
        onSelect: onSelect,
        inSelectMode: inSelectMode,
        subtitle: subtitle,
      ), tag: inSelectMode ? randomString(8) : chat.guid)
  );

  @override
  State<ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends CustomState<ConversationTile, void, ConversationTileController> with AutomaticKeepAliveClientMixin {
  ConversationListController get listController => controller.listController;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    tag = controller.chat.guid;
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;

    if (kIsDesktop || kIsWeb) {
      controller.shouldHighlight.value =
          cm.activeChat?.chat.guid == controller.chat.guid;
    }

    eventDispatcher.stream.listen((event) {
      if (event.item1 == 'update-highlight' && mounted) {
        if ((kIsDesktop || kIsWeb) && event.item2 == controller.chat.guid) {
          controller.shouldHighlight.value = true;
        } else if (controller.shouldHighlight.value = true) {
          controller.shouldHighlight.value = false;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return MouseRegion(
      onEnter: (event) => controller.hoverHighlight.value = true,
      onExit: (event) => controller.hoverHighlight.value = false,
      cursor: SystemMouseCursors.click,
      child: ThemeSwitcher(
        iOSSkin: CupertinoConversationTile(
          parentController: controller,
        ),
        materialSkin: MaterialConversationTile(
          parentController: controller,
        ),
        samsungSkin: SamsungConversationTile(
          parentController: controller,
        ),
      ),
    );
  }
}

class ChatTitle extends CustomStateful<ConversationTileController> {
  const ChatTitle({Key? key, required super.parentController, required this.style});

  final TextStyle style;

  @override
  State<StatefulWidget> createState() => _ChatTitleState();
}

class _ChatTitleState extends CustomState<ChatTitle, void, ConversationTileController> {
  String title = "Unknown";
  late final StreamSubscription<Query<Chat>> sub;
  String? cachedDisplayName = "";
  List<Handle> cachedParticipants = [];

  @override
  void initState() {
    super.initState();
    tag = controller.chat.guid;
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;
    cachedDisplayName = controller.chat.displayName;
    cachedParticipants = controller.chat.handles;
    title = controller.chat.getTitle() ?? title;
    // run query after render has completed
    updateObx(() {
      final titleQuery = chatBox.query(Chat_.guid.equals(controller.chat.guid))
          .watch();
      sub = titleQuery.listen((Query<Chat> query) {
        final chat = query.findFirst()!;
        // check if we really need to update this widget
        if (chat.displayName != cachedDisplayName
            || chat.handles.length != cachedParticipants.length) {
          final newTitle = chat.getTitle();
          if (newTitle != title) {
            setState(() {
              title = newTitle;
            });
          }
        }
        cachedDisplayName = chat.displayName;
        cachedParticipants = chat.handles;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hideInfo = ss.settings.redactedMode.value
          && ss.settings.hideContactInfo.value;
      final generateNames = ss.settings.redactedMode.value
          && ss.settings.generateFakeContactNames.value;

      if (hideInfo) return const SizedBox.shrink();

      String _title = title;
      if (generateNames) {
        _title = controller.chat.participants.length > 1 ? "Group Chat" : controller.chat.participants[0].fakeName;
      }

      return RichText(
        text: TextSpan(
          children: MessageHelper.buildEmojiText(
            _title,
            widget.style,
          ),
        ),
        overflow: TextOverflow.ellipsis,
      );
    });
  }
}

class ChatSubtitle extends CustomStateful<ConversationTileController> {
  const ChatSubtitle({Key? key, required super.parentController, required this.style});

  final TextStyle style;

  @override
  State<StatefulWidget> createState() => _ChatSubtitleState();
}

class _ChatSubtitleState extends CustomState<ChatSubtitle, void, ConversationTileController> {
  String subtitle = "Unknown";
  late final StreamSubscription<Query<Message>> sub;
  String? cachedLatestMessageGuid = "";

  @override
  void initState() {
    super.initState();
    tag = controller.chat.guid;
    // keep controller in memory since the widget is part of a list
    // (it will be disposed when scrolled out of view)
    forceDelete = false;
    subtitle = controller.chat.latestMessageGetter != null
        ? MessageHelper.getNotificationText(controller.chat.latestMessageGetter!)
        : controller.chat.latestMessageText ?? "";
    // run query after render has completed
    updateObx(() {
      final latestMessageQuery = (messageBox.query(Message_.dateDeleted.isNull())
        ..link(Message_.chat, Chat_.guid.equals(controller.chat.guid))
        ..order(Message_.dateCreated, flags: Order.descending))
          .watch();

      sub = latestMessageQuery.listen((Query<Message> query) {
        final message = query.findFirst();
        // check if we really need to update this widget
        if (message?.guid != cachedLatestMessageGuid) {
          message?.handle = message.getHandle();
          String newSubtitle = controller.chat.latestMessageText ?? "";
          if (message != null) {
            newSubtitle = MessageHelper.getNotificationText(message);
          }
          if (newSubtitle != subtitle) {
            setState(() {
              subtitle = newSubtitle;
            });
          }
        }
        cachedLatestMessageGuid = message?.guid;
      });
    });
  }

  @override
  void dispose() {
    sub.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final hideContent = ss.settings.redactedMode.value
          && ss.settings.hideMessageContent.value;
      final generateContent = ss.settings.redactedMode.value
          && ss.settings.generateFakeMessageContent.value;

      if (hideContent) return const SizedBox.shrink();

      String _subtitle = subtitle;
      if (generateContent) {
        _subtitle = controller.chat.fakeLatestMessageText ?? "";
      }

      return RichText(
        text: TextSpan(
          children: MessageHelper.buildEmojiText(
            _subtitle,
            widget.style,
          ),
        ),
        overflow: TextOverflow.ellipsis,
        maxLines: ss.settings.skin.value == Skins.Material
            ? 3 : 2,
      );
    });
  }
}

class ChatLeading extends StatelessWidget {
  final ConversationTileController controller;
  final Widget? unreadIcon;

  ChatLeading({required this.controller, this.unreadIcon});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (unreadIcon != null && ss.settings.skin.value == Skins.iOS)
          unreadIcon!,
        Obx(() {
          final showTypingIndicator = cvc(controller.chat).showTypingIndicator.value;
          double height = Theme.of(context).textTheme.labelLarge!.fontSize! * 1.25;
          return Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 2),
                child: controller.isSelected ? Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(30),
                    color: context.theme.colorScheme.primary,
                  ),
                  width: 40,
                  height: 40,
                  child: Center(
                    child: Icon(
                      Icons.check,
                      color: context.theme.colorScheme.onPrimary,
                      size: 20,
                    ),
                  ),
                ) : ContactAvatarGroupWidget(
                  chat: controller.chat,
                  size: 40,
                  editable: false,
                  onTap: () => controller.onTap(context),
                ),
              ),
              if (showTypingIndicator)
                Positioned(
                  top: 30,
                  left: 20,
                  height: height,
                  child: const FittedBox(
                    alignment: Alignment.centerLeft,
                    child: TypingIndicator(
                      chatList: true,
                      visible: true,
                    ),
                  ),
                ),
              if (unreadIcon != null && ss.settings.skin.value == Skins.Samsung)
                Positioned(
                  top: 30,
                  right: 20,
                  height: height,
                  child: FittedBox(
                    alignment: Alignment.centerRight,
                    child: unreadIcon,
                  ),
                ),
            ],
          );
        })
      ],
    );
  }
}