import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'board_list.dart';

typedef void OnDropItem(int? listIndex, int? itemIndex, int? oldListIndex,
    int? oldItemIndex, BoardItemState state);
typedef void OnTapItem(int listIndex, int itemIndex, BoardItemState state);
typedef void OnStartDragItem(
    int? listIndex, int? itemIndex, BoardItemState state);
typedef void OnDragItem(int oldListIndex, int oldItemIndex, int newListIndex,
    int newItemIndex, BoardItemState state);

class BoardItem extends StatefulWidget {
  final BoardListState? boardList;
  final Widget? item;
  final int? index;
  final OnDropItem? onDropItem;
  final OnTapItem? onTapItem;
  final OnStartDragItem? onStartDragItem;
  final OnDragItem? onDragItem;
  final bool draggable;

  const BoardItem(
      {Key? key,
      this.boardList,
      this.item,
      this.index,
      this.onDropItem,
      this.onTapItem,
      this.onStartDragItem,
      this.draggable = true,
      this.onDragItem})
      : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return BoardItemState();
  }
}

class BoardItemState extends State<BoardItem>
    with AutomaticKeepAliveClientMixin {
  late double height;
  double? width;

  @override
  bool get wantKeepAlive => true;

  void onDropItem(int? listIndex, int? itemIndex) {
    if (widget.onDropItem != null) {
      // check if itemIndex == items.length
      // log everything
      widget.onDropItem!(
          listIndex,
          itemIndex,
          widget.boardList!.widget.boardView!.startListIndex,
          widget.boardList!.widget.boardView!.startItemIndex,
          this);
    }
    widget.boardList!.widget.boardView!.draggedItemIndex = null;
    widget.boardList!.widget.boardView!.draggedListIndex = null;
    if (widget.boardList!.widget.boardView!.listStates[listIndex!].mounted) {
      widget.boardList!.widget.boardView!.listStates[listIndex].setState(() {});
    }
  }

  void _startDrag(Widget item, BuildContext context) {
    if (widget.boardList!.widget.boardView != null) {
      widget.boardList!.widget.boardView!.onDropItem = onDropItem;
      if (widget.boardList!.mounted) {
        widget.boardList!.setState(() {});
      }
      widget.boardList!.widget.boardView!.draggedItemIndex = widget.index;
      widget.boardList!.widget.boardView!.height = context.size!.height;
      widget.boardList!.widget.boardView!.draggedListIndex =
          widget.boardList!.widget.index;
      widget.boardList!.widget.boardView!.startListIndex =
          widget.boardList!.widget.index;
      widget.boardList!.widget.boardView!.startItemIndex = widget.index;
      widget.boardList!.widget.boardView!.draggedItem = item;
      if (widget.onStartDragItem != null) {
        widget.onStartDragItem!(
            widget.boardList!.widget.index, widget.index, this);
      }
      widget.boardList!.widget.boardView!.run();
      if (widget.boardList!.widget.boardView!.mounted) {
        widget.boardList!.widget.boardView!.setState(() {});
      }
    }
  }

  void afterFirstLayout(BuildContext context) {
    try {
      height = context.size!.height;
      width = context.size!.width;
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance!
        .addPostFrameCallback((_) => afterFirstLayout(context));
    if (widget.boardList!.itemStates.length > widget.index!) {
      widget.boardList!.itemStates.removeAt(widget.index!);
    }
    widget.boardList!.itemStates.insert(widget.index!, this);
    return GestureDetector(
      onTapDown: (otd) {
        if (widget.draggable) {
          RenderBox object = context.findRenderObject() as RenderBox;
          Offset pos = object.localToGlobal(Offset.zero);
          RenderBox box =
              widget.boardList!.context.findRenderObject() as RenderBox;
          Offset listPos = box.localToGlobal(Offset.zero);
          widget.boardList!.widget.boardView!.leftListX = listPos.dx;
          widget.boardList!.widget.boardView!.topListY = listPos.dy;
          widget.boardList!.widget.boardView!.topItemY = pos.dy;
          widget.boardList!.widget.boardView!.bottomItemY =
              pos.dy + object.size.height;
          widget.boardList!.widget.boardView!.bottomListY =
              listPos.dy + box.size.height;
          widget.boardList!.widget.boardView!.rightListX =
              listPos.dx + box.size.width;

          widget.boardList!.widget.boardView!.initialX = pos.dx;
          widget.boardList!.widget.boardView!.initialY = pos.dy;
        }
      },
      onTapCancel: () {},
      onTap: () {
        if (widget.onTapItem != null) {
          if (widget.boardList != null &&
              widget.boardList!.widget.index != null &&
              widget.index != null) {
            widget.onTapItem!(
                widget.boardList!.widget.index!, widget.index!, this);
          } else {}
        }
      },
      onLongPress: () {
        if (!widget.boardList!.widget.boardView!.widget.isSelecting &&
            widget.draggable) {
          _startDrag(widget, context);
        }
      },
      child: widget.item,
    );
  }
}
