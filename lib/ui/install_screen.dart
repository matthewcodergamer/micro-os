import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/theme.dart';
import '../services/linux_runtime.dart';

/// First-run Setup Assistant shown when the Linux rootfs is not yet ready.
class InstallScreen extends StatelessWidget {
  const InstallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final runtime = scope.runtime;

    return ListenableBuilder(
      listenable: runtime,
      builder: (context, _) {
        final failed = runtime.status == RuntimeStatus.failed;
        final lines = runtime.logLines;

        return Material(
          color: Colors.transparent,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: MicroColors.panelSolid,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: MicroColors.border),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x66000000),
                      blurRadius: 40,
                      offset: Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.auto_awesome_rounded,
                        color: MicroColors.accent, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      runtime.isBusy ? runtime.stage : 'Golden Gate',
                      style: const TextStyle(
                        color: MicroColors.text,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      runtime.isBusy
                          ? 'Unpacking the Linux workstation…'
                          : 'Set up your MicroOS Linux environment.',
                      style: const TextStyle(
                        color: MicroColors.subtle,
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (runtime.isBusy || failed) ...[
                      const SizedBox(height: 20),
                      LinearProgressIndicator(
                        value: runtime.progress == 0 ? null : runtime.progress,
                        backgroundColor: const Color(0x22FFFFFF),
                        color: failed ? MicroColors.red : MicroColors.accent,
                      ),
                      if (failed && runtime.error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          runtime.error!,
                          style: const TextStyle(
                            color: MicroColors.red,
                            fontSize: 13,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                    if (runtime.canContinueManually) ...[
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () {
                          if (runtime.continueToDesktop()) {
                            // Desktop will take over.
                          }
                        },
                        child: const Text('Continue to Desktop'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: runtime.isBusy
                            ? null
                            : () => failed
                                ? runtime.reinstall()
                                : runtime.install(),
                        child: Text(
                          failed ? 'Retry Install' : 'Install Workstation',
                        ),
                      ),
                    ),
                    if (lines.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 120,
                        child: ListView.builder(
                          itemCount: lines.length,
                          itemBuilder: (_, i) => Text(
                            lines[i],
                            style: const TextStyle(
                              color: MicroColors.subtle,
                              fontSize: 11,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
