import 'package:flutter/material.dart';
import '../l10n/l10n.dart';
import '../screens/account_screen.dart';
import '../screens/buddy_screen.dart';
import '../screens/depot_screen.dart';
import '../screens/overview_screen.dart';
import 'brand.dart';
import 'buddy_chart.dart';
import 'buddy_orb.dart';

// Ahead on a screen: the orb, the one thing it has to say about what is
// shown here, and a real field to write to it. Sending an empty field asks
// [question], so the answer starts from this screen. Small on Konto and Depot;
// [card] is the large "Ahead sagt" on Überblick with a second line.
class AgentBar extends StatefulWidget {
  // what Ahead says here (**fett** allowed); only numbers the screen itself shows
  final String line;
  // the card's second, quieter line
  final String? detail;
  // the suggested question: the field's hint, sent when nothing was typed
  final String question;
  final bool card;
  const AgentBar({super.key, required this.line, required this.question, this.detail, this.card = false});

  @override
  State<AgentBar> createState() => _AgentBarState();
}

class _AgentBarState extends State<AgentBar> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  // the screen this bar sits on: the answer starts with that screen's chart
  AskPlace? get _place {
    if (context.findAncestorWidgetOfExactType<DepotScreen>() != null) return AskPlace.depot;
    if (context.findAncestorWidgetOfExactType<AccountScreen>() != null) return AskPlace.account;
    if (context.findAncestorWidgetOfExactType<OverviewScreen>() != null) return AskPlace.overview;
    return null;
  }

  void _send() {
    final typed = _text.text.trim();
    _text.clear();
    FocusManager.instance.primaryFocus?.unfocus();
    BuddyScreen.open(context, typed.isEmpty ? widget.question : typed, _place);
  }

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(widget.card ? 24 : 20),
        // Ahead speaks from copper light, like on the landing page
        child: CopperLight(
          child: Padding(
            padding: widget.card ? const EdgeInsets.fromLTRB(16, 16, 16, 14) : const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (widget.card) ...[
                Row(children: [
                  const BuddyOrb(size: 22),
                  const SizedBox(width: 8),
                  Text(tr('Ahead sagt'),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xCCFFFFFF))),
                ]),
                const SizedBox(height: 10),
                RichMarkdown(widget.line, glossary: false, fontSize: 18, color: Colors.white),
                if (widget.detail != null) ...[
                  const SizedBox(height: 6),
                  Text(widget.detail!, style: const TextStyle(color: Color(0xD9FFF7F0), fontSize: 14, height: 1.4)),
                ],
                const SizedBox(height: 14),
              ] else ...[
                Row(children: [
                  const BuddyOrb(size: 26),
                  const SizedBox(width: 10),
                  Expanded(child: RichMarkdown(widget.line, glossary: false, fontSize: 14.5, color: Colors.white)),
                ]),
                const SizedBox(height: 10),
              ],
              _field(),
            ]),
          ),
        ),
      );

  // the same input as in the chat: write to Ahead from wherever you are
  Widget _field() => Container(
        height: 44,
        padding: const EdgeInsets.fromLTRB(14, 0, 4, 0),
        decoration: BoxDecoration(
          color: const Color(0x29FFFFFF),
          border: Border.all(color: const Color(0x38FFFFFF)),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              key: const Key('agent-bar-field'),
              controller: _text,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              cursorColor: Colors.white,
              // 16 px keeps mobile browsers from zooming into the field
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: widget.question,
                hintMaxLines: 1,
                hintStyle: const TextStyle(color: Color(0xB3FFFFFF), fontSize: 15),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: tr('Frag Ahead'),
            child: InkResponse(
              key: const Key('agent-bar-send'),
              onTap: _send,
              radius: 24,
              child: Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: const Icon(Icons.arrow_upward_rounded, color: Color(0xFF17120E), size: 19),
              ),
            ),
          ),
        ]),
      );
}
