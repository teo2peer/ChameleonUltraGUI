import 'package:chameleonultragui/helpers/definitions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:chameleonultragui/main.dart';

class SlotChanger extends StatefulWidget {
  const SlotChanger({super.key});

  @override
  SlotChangerState createState() => SlotChangerState();
}

class SlotChangerState extends State<SlotChanger> {
  var selectedSlot = 1;
  Future<List<Icon>>? _slotFuture;
  Object? _communicator;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final communicator = context.watch<ChameleonGUIState>().communicator;
    if (!identical(_communicator, communicator)) {
      _communicator = communicator;
      if (communicator != null) {
        _slotFuture = getFutureData();
      }
    }
  }

  Future<List<Icon>> getFutureData() async {
    var appState = context.read<ChameleonGUIState>();
    final usedSlots = await appState.communicator!.getSlotTagTypes();
    return await getSlotIcons(usedSlots);
  }

  Future<List<Icon>> getSlotIcons(List<SlotTypes> usedSlots) async {
    var appState = context.read<ChameleonGUIState>();
    List<Icon> icons = [];

    selectedSlot = await appState.communicator!.getActiveSlot() + 1;

    for (int i = 0; i < 8; i++) {
      if (i == selectedSlot - 1) {
        icons.add(const Icon(Icons.circle_outlined, color: Colors.red));
      } else if (usedSlots[i].notMatch()) {
        icons.add(const Icon(Icons.circle));
      } else {
        icons.add(const Icon(Icons.circle_outlined));
      }
    }
    return icons;
  }

  List<Icon> presold = [
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
    const Icon(Icons.circle_outlined),
  ];

  void reload() {
    if (!mounted) return;
    setState(() => _slotFuture = getFutureData());
  }

  Future<void> activateSlot(int slot) async {
    if (_busy) return;
    final appState = context.read<ChameleonGUIState>();
    setState(() => _busy = true);
    try {
      await appState.runSlotOperation(
        () => appState.communicator!.activateSlot(slot),
      );
      appState.changesMade();
    } catch (error, stackTrace) {
      appState.log?.w(
        'Could not activate slot ${slot + 1}',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.maybeOf(
          context,
        )?.showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _slotFuture = getFutureData();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Icon>>(
      future: _slotFuture,
      builder: (BuildContext context, AsyncSnapshot<List<Icon>> snapshot) {
        if (snapshot.connectionState == ConnectionState.none ||
            snapshot.connectionState == ConnectionState.waiting) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(onPressed: null, icon: const Icon(Icons.arrow_back)),
              ...presold,
              IconButton(
                onPressed: null,
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          );
        } else if (snapshot.hasError) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Tooltip(
                message: snapshot.error.toString(),
                child: const Icon(Icons.warning),
              ),
              IconButton(onPressed: reload, icon: const Icon(Icons.refresh)),
            ],
          );
        } else {
          final slotIcons = snapshot.data ?? presold;
          presold = slotIcons;

          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (selectedSlot > 1) {
                          await activateSlot(selectedSlot - 2);
                        }
                      },
                icon: const Icon(Icons.arrow_back),
              ),
              ...slotIcons,
              IconButton(
                onPressed: _busy
                    ? null
                    : () async {
                        if (selectedSlot < 8) {
                          await activateSlot(selectedSlot);
                        }
                      },
                icon: const Icon(Icons.arrow_forward),
              ),
            ],
          );
        }
      },
    );
  }
}
