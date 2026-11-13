import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../core/theme.dart';
import '../services/linux_runtime.dart';

/// Native-feeling first-run installer for the pre-baked Linux workstation.
class InstallScreen extends StatelessWidget {
  const InstallScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final runtime = AppScope.of(context).runtime;

    return ListenableBuilder(
      listenable: runtime,
      builder: (context, _) {
        final failed = runtime.status == RuntimeStatus.failed;
        final busy = runtime.isBusy;
        final progress = runtime.progress.clamp(0.0, 1.0);
        final percent = (progress * 100).round();

        return Material(
          color: const Color(0xFF17181C),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(28, 34, 28, 28),
                    decoration: BoxDecoration(
                      color: const Color(0xFF222328),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x55000000),
                          blurRadius: 44,
                          offset: Offset(0, 18),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 76,
                          height: 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF34363D), Color(0xFF17181D)],
                            ),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: const Icon(
                            Icons.desktop_mac_rounded,
                            size: 38,
                            color: Color(0xFFE8EAF0),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'MicroOS',
                          style: TextStyle(
                            fontFamily: 'Inter',
                            color: Colors.white,
                            fontSize: 25,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          failed
                              ? 'The workstation could not be unpacked.'
                              : busy
                                  ? 'Preparing your Linux workstation'
                                  : 'A desktop experience, ready when you are.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            color: Color(0xFFAAADB7),
                            fontSize: 13,
                            height: 1.5,
                          ),
                        ),
                        if (busy || failed) ...[
                          const SizedBox(height: 34),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Installing',
                                style: TextStyle(
                                  color: Color(0xFFD9DBE2),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                '$percent%',
                                style: TextStyle(
                                  color: failed ? MicroColors.red : Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            height: 13,
                            decoration: BoxDecoration(
                              color: const Color(0xFF101115),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white10),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: progress,
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color: failed ? MicroColors.red : MicroColors.accent,
                                          borderRadius: BorderRadius.circular(20),
                                          boxShadow: [
                                            BoxShadow(
                                              color: (failed ? MicroColors.red : MicroColors.accent)
                                                  .withValues(alpha: 0.65),
                                              blurRadius: 12,
                                              spreadRadius: 1,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            failed ? 'Installation stopped' : progress >= 0.92 ? 'Finishing up…' : runtime.stage,
                            style: const TextStyle(
                              color: Color(0xFF858995),
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (failed && runtime.error != null) ...[
                          const SizedBox(height: 18),
                          Text(
                            runtime.error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFFFF817A),
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ],
                        if (!busy) ...[
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: failed ? runtime.reinstall : runtime.install,
                              child: Text(failed ? 'Retry' : 'Install MicroOS'),
                            ),
                          ),
                        ],
                        if (runtime.logLines.isNotEmpty && failed) ...[
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 100,
                            child: ListView.builder(
                              itemCount: runtime.logLines.length,
                              itemBuilder: (_, index) => Text(
                                runtime.logLines[index],
                                style: const TextStyle(
                                  color: Color(0xFF858995),
                                  fontSize: 10,
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
            ),
          ),
        );
      },
    );
  }
}
