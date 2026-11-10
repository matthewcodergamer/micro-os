import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../services/linux_runtime.dart';

/// First-run screen. Shown until the guest is unpacked and provisioned.
class InstallScreen extends StatelessWidget {
  const InstallScreen({super.key, required this.runtime});

  final LinuxRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: runtime,
      builder: (context, _) {
        final failed = runtime.status == RuntimeStatus.failed;
        final lines = runtime.logLines;
        final tail = lines.sublist(math.max(0, lines.length - 8));

        return Container(
          color: const Color(0xE605070B),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: MicroColors.panelSolid,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: MicroColors.border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x99000000),
                    blurRadius: 40,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF4F8CFF), Color(0xFF7C4DFF)],
                          ),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: const Icon(Icons.laptop_mac,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MicroOS',
                            style: TextStyle(
                              color: MicroColors.text,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Linux workstation for Android',
                            style: TextStyle(
                              color: MicroColors.subtle,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text(
                    runtime.stage,
                    style: const TextStyle(
                      color: MicroColors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: runtime.progress == 0 ? null : runtime.progress,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (failed && runtime.error != null)
                    Text(
                      runtime.error!,
                      style: const TextStyle(
                        color: MicroColors.red,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    )
                  else
                    const Text(
                      'Unpacks a bundled Ubuntu rootfs, then installs Python, '
                      'Node, Rust, git, GitHub CLI, Chromium/Falkon, OpenCode and '
                      'the X11 stack. Roughly 1 GB — use Wi-Fi.',
                      style: TextStyle(
                        color: MicroColors.subtle,
                        fontSize: 11,
                        height: 1.5,
                      ),
                    ),
                  if (tail.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      height: 96,
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B0E14),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: Text(
                          tail.join('\n'),
                          style: const TextStyle(
                            color: Color(0xFF9FB0C7),
                            fontSize: 9,
                            fontFamily: 'monospace',
                            height: 1.45,
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: runtime.isBusy
                              ? null
                              : () => failed
                                  ? runtime.reinstall()
                                  : runtime.install(),
                          child: Text(
                            runtime.isBusy
                                ? 'Installing…'
                                : failed
                                    ? 'Retry installation'
                                    : 'Install Linux',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
