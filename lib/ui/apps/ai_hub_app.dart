import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../services/linux_runtime.dart';
import '../../services/settings_store.dart';
import 'terminal_app.dart';

/// OpenCode, running inside the guest with the developer toolchain and the
/// stored GitHub credentials.
class AiHubApp extends StatelessWidget {
  const AiHubApp({super.key, required this.runtime, required this.settings});

  final LinuxRuntime runtime;
  final SettingsStore settings;

  static String _command(String theme) => '''
export PATH="/root/.opencode/bin:/root/.local/bin:\$PATH"
if command -v opencode >/dev/null 2>&1; then
  mkdir -p /root/.config/opencode
  printf '{"\$schema":"https://opencode.ai/config.json","theme":"$theme"}' > /root/.config/opencode/opencode.json
  exec opencode
fi
printf '\n\033[1mOpenCode is not installed in this guest yet.\033[0m\n'
printf 'Open Settings -> Runtime and run the toolchain install.\n\n'
exec bash -l
''';

  @override
  Widget build(BuildContext context) {
    const theme = 'github';
    return Container(
      color: const Color(0xFF0B0E14),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF141822),
            child: Row(
              children: const [
                Icon(Icons.auto_awesome, size: 13, color: MicroColors.green),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'OpenCode · GitHub PAT is for GitHub only · use /connect for an AI provider',
                    style: TextStyle(color: MicroColors.subtle, fontSize: 10),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: TerminalTabsApp(
              runtime: runtime,
              settings: settings,
              argv: <String>['/bin/bash', '-lc', _command(theme)],
            ),
          ),
        ],
      ),
    );
  }
}
